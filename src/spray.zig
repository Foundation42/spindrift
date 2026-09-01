//! spray — a population with a kernel mounted on it, ticked by fed time.
//!
//! The `@<name>` instance of the tenant (campaign §3.2, ruled `spray`
//! 2026-09-01): position, aim, knobs, and the rows. The kernel is a rill
//! program whose plane is the row (`rill/src/row.zig`); a spray mounts one
//! the way a host mounts a rill on the world, and evaluates it once per
//! live row per tick.
//!
//! **The tick is four phases and only the sweep is parallel** (recon R-b
//! §3, kept from P0 — and G0 is what forces the shape):
//!
//!   1. broadcasts — every `plane.…` the kernel reads is fetched once from
//!      the plane, `@self` resolved to this spray, converted once to a row
//!      value (the one float boundary), and handed to the runtime;
//!   2. spawn — serial: `rate × dt` rows, exact in nanoseconds, popped from
//!      the freelist in a fixed order, born at the spray's position with the
//!      spray's `life` and a seed from the spray's seed and the birth ordinal;
//!   3. the sweep — chunked over `common/jobs.zig`, row-local: the kernel
//!      once per live row (its writes land after its sweep of that row),
//!      then `pos += vel · dt` and `age += dt`. A kernel's `perish` marks;
//!      nothing here kills;
//!   4. reap — serial, ascending id: doomed rows go back on the freelist.
//!      Push ORDER is what the next spawn's ids are a function of.
//!
//! Then the spray says what it is on the plane: `plane.drift.@<name>.count`,
//! `.bounds` and `.digest`, change-only. On unmount it says zero — absence
//! is said, the S5 precedent.
//!
//! Integration is not a word: a velocity that did not move its position
//! would not be a velocity. Time is fed; dt is the fed delta; a regression
//! is loud. No float enters the loop.

const std = @import("std");
const rill = @import("rill");
const common = @import("common");
const struple = @import("struple");
const jobs = common.jobs;
const fixed = @import("fixed.zig");
const world_mod = @import("world.zig");
const population = @import("population.zig");
const Population = population.Population;

const Fixed = fixed.Fixed;
const Vec = fixed.Vec;
const Val = rill.row.Val;

pub const Now = rill.Now;
pub const World = world_mod.World;

pub const TickError = error{TimeRegression} || std.mem.Allocator.Error;
pub const MountError = error{ Parse, Mount } || std.mem.Allocator.Error;

/// The instance knobs (campaign §3.2). Units are the row's: cells and
/// seconds in Q16.16; `life` is nanoseconds on the knob and on the row
/// (the row reads it back in seconds). A knob written on the plane at
/// `plane.drift.@<name>.<knob>` wins over the field here — the host's
/// business (`drift-run` does it; the tenant's bridge will).
pub const Knobs = struct {
    /// Rows per second.
    rate: Fixed = 0,
    /// Cells per second along `aim` — `spawn`'s launch speed.
    speed: Fixed = 0,
    /// ± cells per second of per-axis jitter at launch, from the row's seed.
    spread: Fixed = 0,
    /// How long a row lives, fed nanoseconds; `perish` reaps at it.
    life_ns: u64 = std.time.ns_per_s,
};

/// What one tick did — the numbers `drift-run` prints and G6 will read.
pub const Stats = struct {
    spawned: u32 = 0,
    died: u32 = 0,
    /// Spawns refused because the population was at capacity.
    throttled: u32 = 0,
    /// Rows the sweep evaluated — the budget unit (§3.6), counted BY the
    /// sweep per chunk, never assumed from the live count (mutation M11,
    /// beat 0).
    row_steps: u32 = 0,
    /// Kernel refusals across every row this tick, merged after the join.
    refusals: u32 = 0,
};

/// Rows per job. ≈ 80 bytes of row across the arrays, so a chunk streams
/// ≈ 80 KB — inside L2 with room for scratch. A constant until the first
/// customer scene moves it (R-b §3).
pub const DEFAULT_CHUNK: u32 = 1024;

/// A mounted kernel: the parsed program, the row runtime over this spray's
/// population, and one evaluation scratch per chunk (chunk-indexed, so no
/// thread id is needed and the refusal merge is in one order).
const Kernel = struct {
    prog: rill.Program,
    rt: rill.row.Runtime,
    scratches: []rill.row.Scratch = &.{},
};

pub const Spray = struct {
    gpa: std.mem.Allocator,
    pop: Population,
    /// The `@name` on the plane — `plane.drift.@<name>.…` is where the
    /// knobs are read and the count is said.
    name: []const u8 = "em",
    /// The spray's decorrelator: every row's seed derives from this and the
    /// row's birth ordinal, and nothing else.
    seed: u32,
    pos: Vec = fixed.zero_vec,
    /// Direction × 1.0; `spawn` launches along `aim × speed`. Not
    /// normalised — an aim of (0, 2, 0) is twice the speed, and saying so
    /// is cheaper than a square root in fixed point.
    aim: Vec = .{ 0, fixed.ONE, 0 },
    knobs: Knobs = .{},
    world: World,
    chunk: u32 = DEFAULT_CHUNK,

    /// Rows owed by `rate`, in (rows · 2¹⁶ · ns): `rate` is Q16.16 rows/s
    /// and dt is fed nanoseconds, so the product is exact and a whole row is
    /// `ONE × ns_per_s` of it. 40/s at 50 ms spawns exactly 2 a tick.
    spawn_acc: i128 = 0,
    /// Birth ordinal, the row seed's other half. Never reset.
    spawned: u32 = 0,
    now: Now = .{},
    started: bool = false,
    ticks: u64 = 0,
    last: Stats = .{},
    /// The first refusal's words from the last tick, for the host's log.
    last_refusal: rill.registry.Detail = .{},
    chunk_steps: []u32 = &.{},
    kernel: ?Kernel = null,

    /// What was last said on the plane, so a tick that changes nothing says
    /// nothing (change-only: a sensor precondition, and a quiet log).
    said_count: ?u32 = null,
    said_digest: ?u64 = null,
    said_bounds: ?[6]Fixed = null,

    pub fn init(gpa: std.mem.Allocator, capacity: u32, seed: u32, world: World) !Spray {
        return .{
            .gpa = gpa,
            .pop = try Population.init(gpa, capacity),
            .seed = seed,
            .world = world,
        };
    }

    pub fn deinit(self: *Spray) void {
        self.unmountKernel();
        self.pop.deinit();
        self.gpa.free(self.chunk_steps);
    }

    // -- the kernel ----------------------------------------------------------

    /// Parse `source` with `reg` and mount it on this spray's rows. A
    /// refusal — parse or mount — lands in `diag` in words, and the error
    /// names which. `reg` must outlive the spray: the program borrows it.
    /// A spray with a kernel mounted must not be moved: the runtime holds a
    /// pointer to the program inside it.
    pub fn mountKernel(self: *Spray, reg: *rill.Registry, kernel_name: []const u8, source: []const u8, diag: *rill.registry.Detail) MountError!void {
        self.unmountKernel();
        var pdiag = rill.Diag{};
        var prog = rill.parseKernel(self.gpa, reg, kernel_name, source, &pdiag) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                diag.set("{s}:{d}:{d}: {s}", .{ kernel_name, pdiag.line, pdiag.col, pdiag.msg() });
                return error.Parse;
            },
        };
        errdefer prog.deinit();
        // `mount` borrows a pointer to the program; the Kernel owns both, so
        // build the kernel in place and mount against its own field.
        self.kernel = .{ .prog = prog, .rt = undefined };
        const k = &self.kernel.?;
        k.rt = rill.row.Runtime.mount(self.gpa, &k.prog, self.pop.asRowPlane(), diag) catch |err| switch (err) {
            error.OutOfMemory => {
                self.kernel = null;
                return error.OutOfMemory;
            },
            else => {
                self.kernel = null;
                return error.Mount;
            },
        };
    }

    pub fn unmountKernel(self: *Spray) void {
        const k = &(self.kernel orelse return);
        for (k.scratches) |*s| s.deinit();
        self.gpa.free(k.scratches);
        k.rt.deinit();
        k.prog.deinit();
        self.kernel = null;
    }

    pub fn hasKernel(self: *const Spray) bool {
        return self.kernel != null;
    }

    // -- the tick ------------------------------------------------------------

    /// One fed tick. The first call sets the epoch (dt = 0: nothing spawns,
    /// nothing moves); every later call advances by the fed delta. `js` null
    /// runs the sweep inline on the caller. `plane` is where broadcasts are
    /// read from and the count is said to; null is a spray with no world to
    /// talk to (the kernel's `plane.…` reads then stay quiet).
    pub fn tick(self: *Spray, now: Now, js: ?*jobs.JobSystem, plane: ?rill.Plane) TickError!void {
        if (self.started and (now.time_ns < self.now.time_ns or now.frame < self.now.frame)) {
            return error.TimeRegression;
        }
        const dt_ns: u64 = if (self.started) now.time_ns - self.now.time_ns else 0;
        self.now = now;
        self.started = true;
        const dt = fixed.fromNs(dt_ns);

        var stats = Stats{};
        try self.broadcastPhase(plane);
        self.spawnPhase(dt_ns, &stats);
        try self.sweepPhase(dt, dt_ns, js, &stats);
        self.reapPhase(&stats);
        self.last = stats;
        self.ticks += 1;
        if (plane) |p| try self.say(p);
    }

    // -- phase 1: broadcasts ---------------------------------------------------

    fn broadcastPhase(self: *Spray, plane: ?rill.Plane) !void {
        const k = &(self.kernel orelse return);
        const p = plane orelse return;
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [512]u8 = undefined;
        for (k.prog.subs.items, 0..) |s, i| {
            if (!k.rt.isBroadcast(i)) continue;
            const path = self.resolveSelf(&path_buf, s.path);
            pk.reset();
            p.read(path, &pk) catch {
                k.rt.setBroadcast(i, null);
                continue;
            };
            k.rt.setBroadcast(i, rill.row.fromStruple(self.gpa, pk.bytes()));
        }
    }

    /// `plane.drift.@self.rate` → `plane.drift.@<name>.rate`. Elsewhere the
    /// path is itself.
    fn resolveSelf(self: *const Spray, buf: []u8, path: []const u8) []const u8 {
        const at = std.mem.indexOf(u8, path, "@self") orelse return path;
        return std.fmt.bufPrint(buf, "{s}@{s}{s}", .{ path[0..at], self.name, path[at + "@self".len ..] }) catch path;
    }

    // -- phase 2: spawn (serial) -----------------------------------------------

    fn spawnPhase(self: *Spray, dt_ns: u64, stats: *Stats) void {
        if (dt_ns == 0) return;
        const one_row: i128 = @as(i128, fixed.ONE) * std.time.ns_per_s;
        self.spawn_acc += @as(i128, self.knobs.rate) * dt_ns;
        if (self.spawn_acc < 0) self.spawn_acc = 0; // a negative rate owes nothing, and owes nothing later
        var owed: u32 = @intCast(@divFloor(self.spawn_acc, one_row));
        self.spawn_acc -= @as(i128, owed) * one_row;
        while (owed > 0) : (owed -= 1) {
            const id = self.pop.spawn() orelse {
                stats.throttled += owed;
                return;
            };
            const p = &self.pop;
            p.seed[id] = mix(self.seed, self.spawned);
            self.spawned +%= 1;
            p.life_ns[id] = self.knobs.life_ns;
            p.size[id] = fixed.ONE;
            p.colour[0][id] = fixed.ONE;
            inline for (0..3) |a| p.pos[a][id] = self.pos[a];
            stats.spawned += 1;
        }
    }

    // -- phase 3: the sweep (chunked) ------------------------------------------

    const SweepCtx = struct { spray: *Spray, dt: Fixed, dt_ns: u64 };

    fn sweepPhase(self: *Spray, dt: Fixed, dt_ns: u64, js: ?*jobs.JobSystem, stats: *Stats) !void {
        const n_chunks: usize = (self.pop.capacity + self.chunk - 1) / self.chunk;
        if (self.chunk_steps.len != n_chunks) {
            self.gpa.free(self.chunk_steps);
            self.chunk_steps = try self.gpa.alloc(u32, n_chunks);
        }
        @memset(self.chunk_steps, 0);
        if (self.kernel) |*k| {
            if (k.scratches.len != n_chunks) {
                for (k.scratches) |*s| s.deinit();
                self.gpa.free(k.scratches);
                k.scratches = try self.gpa.alloc(rill.row.Scratch, n_chunks);
                var made: usize = 0;
                errdefer {
                    for (k.scratches[0..made]) |*s| s.deinit();
                    self.gpa.free(k.scratches);
                    k.scratches = &.{};
                }
                for (k.scratches) |*s| {
                    s.* = try k.rt.newScratch(self.gpa);
                    made += 1;
                }
            }
            for (k.scratches) |*s| {
                s.refusals = 0;
                s.first_node = null;
            }
        }

        var ctx = SweepCtx{ .spray = self, .dt = dt, .dt_ns = dt_ns };
        if (js) |sys| {
            var counter = jobs.Counter.init(0);
            sys.parallelFor(self.pop.capacity, self.chunk, sweepJob, &ctx, &counter);
            sys.waitFor(&counter);
        } else {
            var start: u32 = 0;
            while (start < self.pop.capacity) : (start += self.chunk) {
                sweepRows(&ctx, start, @min(start + self.chunk, self.pop.capacity));
            }
        }

        var steps: u32 = 0;
        for (self.chunk_steps) |c| steps += c;
        stats.row_steps = steps;
        // Merge refusals in chunk order — exact, no atomics, one order.
        if (self.kernel) |*k| {
            self.last_refusal.clear();
            for (k.scratches) |*s| {
                stats.refusals += @intCast(s.refusals);
                if (s.first_node != null and self.last_refusal.len == 0) {
                    self.last_refusal.set("{s}", .{s.first.text()});
                }
            }
        }
    }

    fn sweepJob(job: *jobs.Job) void {
        const range = job.getData(jobs.BatchRange);
        const ctx: *const SweepCtx = @ptrCast(@alignCast(range.context));
        sweepRows(ctx, range.start, range.end);
    }

    /// Per row: the kernel, then integration, then age. Row-local by
    /// construction — the only indices touched are `id`'s own, plus this
    /// chunk's own step slot and scratch.
    fn sweepRows(ctx: *const SweepCtx, start: u32, end: u32) void {
        const s = ctx.spray;
        const p = &s.pop;
        const chunk_index = start / s.chunk;
        const dt = ctx.dt;
        var steps: u32 = 0;
        var id = start;
        while (id < end) : (id += 1) {
            if (!p.alive[id]) continue;
            if (s.kernel) |*k| k.rt.evalRow(&k.scratches[chunk_index], id, dt, s);
            // integrate — a velocity moves its position; not a word
            inline for (0..3) |a| p.pos[a][id] += fixed.mul(p.vel[a][id], dt);
            // age — fed nanoseconds, exact
            p.age_ns[id] += ctx.dt_ns;
            steps += 1;
        }
        s.chunk_steps[chunk_index] = steps;
    }

    // -- phase 4: reap (serial, ascending) -------------------------------------

    fn reapPhase(self: *Spray, stats: *Stats) void {
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (self.pop.alive[id] and self.pop.doomed[id]) {
                self.pop.kill(id);
                stats.died += 1;
            }
        }
    }

    // -- the plane -------------------------------------------------------------

    /// Say what the population is: `count`, `bounds` and `digest`, each
    /// written only when it changed. The population itself never leaves
    /// memory except through a dump (campaign §3.1).
    pub fn say(self: *Spray, plane: rill.Plane) !void {
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [256]u8 = undefined;

        const count = self.pop.live;
        if (self.said_count != count) {
            pk.reset();
            try pk.appendInt(count);
            try self.write(plane, &path_buf, "count", pk.bytes());
            self.said_count = count;
        }

        const now_digest = self.digest();
        if (self.said_digest != now_digest) {
            pk.reset();
            try pk.appendInt(@bitCast(now_digest));
            try self.write(plane, &path_buf, "digest", pk.bytes());
            self.said_digest = now_digest;
        }

        const now_bounds = self.bounds();
        const same = if (self.said_bounds) |b| std.mem.eql(Fixed, &b, &now_bounds) else false;
        if (!same) {
            pk.reset();
            try packBounds(self.gpa, &pk, now_bounds);
            try self.write(plane, &path_buf, "bounds", pk.bytes());
            self.said_bounds = now_bounds;
        }
    }

    /// Absence, said: `count` is zero, and the kernel is gone. The other
    /// two leaves keep their last value — a bound of nothing is not a box.
    pub fn unmount(self: *Spray, plane: rill.Plane) !void {
        self.unmountKernel();
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [256]u8 = undefined;
        try pk.appendInt(0);
        try self.write(plane, &path_buf, "count", pk.bytes());
        self.said_count = 0;
    }

    fn write(self: *const Spray, plane: rill.Plane, buf: []u8, leaf: []const u8, bytes: []const u8) !void {
        const path = std.fmt.bufPrint(buf, "plane.drift.@{s}.{s}", .{ self.name, leaf }) catch return error.OutOfMemory;
        plane.write(path, bytes, .value, .base, 0) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => {}, // a plane that refuses the say is a host matter; the sim is unchanged
        };
    }

    /// A cheap change detector over the live rows, in id order: positions,
    /// velocities and ages. Not the dump's digest (that is over the dump's
    /// bytes, and building a dump every tick to hash it is a dump every
    /// tick); a sensor that wants "did anything move" wants this.
    pub fn digest(self: *const Spray) u64 {
        var h = std.hash.Wyhash.init(0);
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            h.update(std.mem.asBytes(&id));
            inline for (0..3) |a| {
                h.update(std.mem.asBytes(&self.pop.pos[a][id]));
                h.update(std.mem.asBytes(&self.pop.vel[a][id]));
            }
            h.update(std.mem.asBytes(&self.pop.age_ns[id]));
        }
        return h.final();
    }

    /// min xyz, max xyz over live rows; all zero when there are none.
    pub fn bounds(self: *const Spray) [6]Fixed {
        var out = [6]Fixed{ 0, 0, 0, 0, 0, 0 };
        var any = false;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                const v = self.pop.pos[a][id];
                if (!any or v < out[a]) out[a] = v;
                if (!any or v > out[3 + a]) out[3 + a] = v;
            }
            any = true;
        }
        return out;
    }
};

/// `{max: {x, y, z}, min: {x, y, z}}` in cells, as f64 — the plane is the
/// world's and the world reads floats; this is the boundary, once per tick.
fn packBounds(gpa: std.mem.Allocator, pk: *struple.Packer, b: [6]Fixed) !void {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    const axes = [_][]const u8{ "x", "y", "z" };
    var halves: [2][]const u8 = undefined;
    for (0..2) |h| {
        var entries: [3][2][]const u8 = undefined;
        for (axes, 0..) |name, i| {
            var kp = struple.Packer.init(a);
            try kp.appendString(name);
            var vp = struple.Packer.init(a);
            try vp.appendF64(fixed.toF64(b[h * 3 + i]));
            entries[i] = .{ kp.bytes(), vp.bytes() };
        }
        var mp = struple.Packer.init(a);
        try mp.appendMap(&entries);
        halves[h] = mp.bytes();
    }
    var kmin = struple.Packer.init(a);
    try kmin.appendString("min");
    var kmax = struple.Packer.init(a);
    try kmax.appendString("max");
    try pk.appendMap(&.{ .{ kmin.bytes(), halves[0] }, .{ kmax.bytes(), halves[1] } });
}

/// A 32-bit mix (murmur3's finaliser over a keyed input). Every row seed
/// and every jitter draw comes from this, so the whole population is a
/// pure function of the spray seed and fed history.
pub fn mix(key: u32, n: u32) u32 {
    var h = key ^ (n *% 0x9E3779B9);
    h ^= h >> 16;
    h *%= 0x85EBCA6B;
    h ^= h >> 13;
    h *%= 0xC2B2AE35;
    h ^= h >> 16;
    return h;
}

/// A per-axis draw in [−spread, spread], integer arithmetic only: the top
/// 32 bits of hash × (2·spread + 1) is a uniform index into that range.
pub fn jitter(row_seed: u32, axis: usize, spread: Fixed) Fixed {
    if (spread <= 0) return 0;
    const h = mix(row_seed, @intCast(axis + 1));
    const span: u64 = @as(u64, @intCast(spread)) * 2 + 1;
    const draw: i64 = @intCast((@as(u64, h) * span) >> 32);
    return @intCast(draw - spread);
}

test "mix: different ordinals under one key are different seeds, and the same is the same" {
    try std.testing.expectEqual(mix(7, 0), mix(7, 0));
    try std.testing.expect(mix(7, 0) != mix(7, 1));
    try std.testing.expect(mix(7, 0) != mix(8, 0));
}

test "jitter: stays inside ±spread and is zero at zero spread" {
    var n: u32 = 0;
    while (n < 1000) : (n += 1) {
        const j = jitter(mix(3, n), 0, fixed.ONE);
        try std.testing.expect(j >= -fixed.ONE and j <= fixed.ONE);
    }
    try std.testing.expectEqual(@as(Fixed, 0), jitter(mix(3, 1), 0, 0));
}
