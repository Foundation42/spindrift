//! spray — a population with a kernel mounted on it, ticked by fed time.
//!
//! The `@<name>` instance of the tenant (campaign §3.2, ruled `spray`
//! 2026-09-01): position, aim, knobs, and the rows. The kernel is a rill
//! program whose plane is the row (`rill/src/row.zig`); a spray mounts one
//! the way a host mounts a rill on the world, and evaluates it once per
//! live row per tick.
//!
//! **The tick is six phases and only the sweep is parallel** (recon R-b
//! §3, kept from P0 — and G0 is what forces the shape):
//!
//!   1. broadcasts — every `plane.…` the kernel reads is fetched once from
//!      the plane, `@self` resolved to this spray, converted once to a row
//!      value (the one float boundary), and handed to the runtime;
//!   2. materialise — every channel the archetype `samples` is rasterised
//!      from the host's live bag onto a lattice over the spray's bounds,
//!      once, so `hear` is a trilinear read of integers (beat 2, §3.4);
//!   3. spawn — serial: `rate × dt` rows, exact in nanoseconds, popped from
//!      the freelist in a fixed order, born at the spray's position with the
//!      spray's `life` and a seed from the spray's seed and the birth ordinal;
//!   4. the sweep — chunked over `common/jobs.zig`, row-local: the kernel
//!      once per live row (its writes land after its sweep of that row),
//!      then `pos += vel · dt` and `age += dt`. A kernel's `perish` marks;
//!      nothing here kills;
//!   5. reap — serial, ascending id: doomed rows go back on the freelist.
//!      Push ORDER is what the next spawn's ids are a function of;
//!   6. cast — every channel the archetype `casts` gets ONE aggregate
//!      deposit: centre of mass, amplitude ∝ live count × per-row amplitude,
//!      radius from bounds; the host replaces last tick's (§3.4).
//!
//! Then the spray says what it is on the plane: `plane.drift.@<name>.count`,
//! `.bounds` and `.digest`, change-only. On unmount it says zero and
//! withdraws its casts — absence is said, and ownership is the ceiling.
//!
//! Integration is not a word: a velocity that did not move its position
//! would not be a velocity. Time is fed; dt is the fed delta; a regression
//! is loud. No float enters the loop: the lattice and the cast are the
//! boundaries, crossed once per tick.

const std = @import("std");
const rill = @import("rill");
const common = @import("common");
const struple = @import("struple");
const jobs = common.jobs;
const fixed = @import("fixed.zig");
const world_mod = @import("world.zig");
const fields_mod = @import("fields.zig");
const population = @import("population.zig");
const Population = population.Population;

const Fixed = fixed.Fixed;
const Vec = fixed.Vec;
const Val = rill.row.Val;

pub const Now = rill.Now;
pub const World = world_mod.World;
pub const Fields = fields_mod.Fields;

pub const TickError = error{TimeRegression} || std.mem.Allocator.Error;
pub const MountError = error{ Parse, Mount } || std.mem.Allocator.Error;

/// The instance knobs (campaign §3.2). Units are the row's: cells and
/// seconds in Q16.16; `life` is nanoseconds on the knob and on the row
/// (the row reads it back in seconds). A knob written on the plane at
/// `plane.drift.@<name>.<knob>` wins over the field here — the host's
/// business (`drift-run` does it; the tenant's bridge does).
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

/// `samples $wind cell 0.5` on the archetype: a channel the kernel may
/// `hear`, and the lattice's declared cell size in cells.
pub const Sampled = struct {
    channel: []const u8,
    cell: Fixed,
};

pub const RadiusPolicy = union(enum) {
    /// Half the bounds' diagonal, floored at one cell so a lone row casts.
    bounds,
    fixed: f32,
};

/// `casts $dankness amp 0.01 radius bounds [to #tag]` on the archetype.
pub const Casting = struct {
    channel: []const u8,
    /// Amplitude per live row; the aggregate's is this × the live count.
    per_row_amplitude: f32,
    radius: RadiusPolicy = .bounds,
    /// Null = the channel's default.
    decay_ns: ?u64 = null,
    /// Coupling, sigil included; empty = uncoupled.
    to: []const u8 = "",
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
    /// Sampled channels the host does not declare — the lattice stays
    /// dead and `hear` refuses, said here rather than guessed.
    bags_missing: u32 = 0,
    /// Lattices whose cell was doubled to fit the cap this tick.
    coarsened: u32 = 0,
    /// Aggregate casts the host refused (an undeclared channel, no store).
    cast_refusals: u32 = 0,
};

/// Rows per job. ≈ 80 bytes of row across the arrays, so a chunk streams
/// ≈ 80 KB — inside L2 with room for scratch. A constant until the first
/// customer scene moves it (R-b §3).
pub const DEFAULT_CHUNK: u32 = 1024;

/// Grid points per axis a lattice may have. 33³ Q16.16 values is 144 KB
/// per channel; a spray whose bounds want more gets a coarser cell and
/// says `coarsened`, never a bigger allocation — capacity is the only one.
pub const MAX_SAMPLES: u32 = 33;

/// A sampled channel's field, rasterised onto grid points over the
/// spray's bounds. Values are Q16.16 amplitudes at the points; `sampleAt`
/// is trilinear and `gradientAt` is central differences, both integer.
pub const Lattice = struct {
    channel: []const u8,
    declared_cell: Fixed,
    /// The cell in use — the declared one, doubled until the bounds fit.
    cell: Fixed = 0,
    origin: Vec = fixed.zero_vec,
    /// Grid points per axis, each ≥ 2 once materialised.
    dims: [3]u32 = .{ 0, 0, 0 },
    values: []Fixed,
    /// False until the host has answered for this channel this tick —
    /// an unknown channel leaves the lattice dead, and `hear` refuses.
    live: bool = false,
    coarsened: u8 = 0,

    pub fn index(self: *const Lattice, i: u32, j: u32, k: u32) usize {
        return (@as(usize, k) * self.dims[1] + j) * self.dims[0] + i;
    }

    pub fn at(self: *const Lattice, i: u32, j: u32, k: u32) Fixed {
        return self.values[self.index(i, j, k)];
    }

    /// `p − origin` in grid units, Q16.16, clamped to the grid: integer part
    /// is the point, fraction is the position between it and the next.
    fn local(self: *const Lattice, p: Vec, axis: usize) Fixed {
        const hi: i64 = @as(i64, @intCast(self.dims[axis] - 1)) << fixed.FRAC_BITS;
        const off: i64 = @as(i64, p[axis]) - self.origin[axis];
        const q: i64 = @divFloor(off << fixed.FRAC_BITS, self.cell);
        return @intCast(@min(@max(q, 0), hi));
    }

    /// Trilinear, exact: eight point reads and seven fixed lerps.
    pub fn sampleAt(self: *const Lattice, p: Vec) Fixed {
        var i: [3]u32 = undefined;
        var t: [3]Fixed = undefined;
        inline for (0..3) |a| {
            const l = self.local(p, a);
            var cellidx: u32 = @intCast(l >> fixed.FRAC_BITS);
            var frac: Fixed = l & (fixed.ONE - 1);
            if (cellidx >= self.dims[a] - 1) {
                cellidx = self.dims[a] - 2;
                frac = fixed.ONE;
            }
            i[a] = cellidx;
            t[a] = frac;
        }
        const c000 = self.at(i[0], i[1], i[2]);
        const c100 = self.at(i[0] + 1, i[1], i[2]);
        const c010 = self.at(i[0], i[1] + 1, i[2]);
        const c110 = self.at(i[0] + 1, i[1] + 1, i[2]);
        const c001 = self.at(i[0], i[1], i[2] + 1);
        const c101 = self.at(i[0] + 1, i[1], i[2] + 1);
        const c011 = self.at(i[0], i[1] + 1, i[2] + 1);
        const c111 = self.at(i[0] + 1, i[1] + 1, i[2] + 1);
        const c00 = lerp(c000, c100, t[0]);
        const c10 = lerp(c010, c110, t[0]);
        const c01 = lerp(c001, c101, t[0]);
        const c11 = lerp(c011, c111, t[0]);
        const c0 = lerp(c00, c10, t[1]);
        const c1 = lerp(c01, c11, t[1]);
        return lerp(c0, c1, t[2]);
    }

    /// Central differences at the nearest grid point, one-sided at the
    /// edges; amplitude per cell, so a row reads the same slope whatever
    /// the cell the lattice settled on.
    pub fn gradientAt(self: *const Lattice, p: Vec) Vec {
        var n: [3]u32 = undefined;
        inline for (0..3) |a| {
            const l = self.local(p, a);
            const nearest: u32 = @intCast((l + fixed.HALF) >> fixed.FRAC_BITS);
            n[a] = @min(nearest, self.dims[a] - 1);
        }
        var g: Vec = undefined;
        inline for (0..3) |a| {
            const lo: u32 = if (n[a] > 0) n[a] - 1 else n[a];
            const hi: u32 = if (n[a] + 1 < self.dims[a]) n[a] + 1 else n[a];
            var lo_i = n;
            var hi_i = n;
            lo_i[a] = lo;
            hi_i[a] = hi;
            const span: i64 = @as(i64, @intCast(hi - lo)) * self.cell;
            g[a] = if (span == 0) 0 else @intCast(@divFloor(@as(i64, self.at(hi_i[0], hi_i[1], hi_i[2]) - self.at(lo_i[0], lo_i[1], lo_i[2])) << fixed.FRAC_BITS, span));
        }
        return g;
    }

    fn lerp(a: Fixed, b: Fixed, t: Fixed) Fixed {
        return a +% fixed.mul(b -% a, t);
    }
};

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
    /// knobs are read and the count is said; also the cast owner's name.
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
    /// The host's field store; null = a spray with no fields (a kernel
    /// that `hear`s refuses at mount, and casts are dropped, counted).
    fields: ?Fields = null,
    /// `samples …` and `casts …` from the archetype.
    samples: []const Sampled = &.{},
    casts: []const Casting = &.{},
    /// Tags this spray carries, for coupled deposits (`to #tag`) — the
    /// spray's authored ear hears a coupled deposit only while it carries
    /// the tag, exactly as an entity-bound ear does. Set by the host.
    carried: []const []const u8 = &.{},
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
    /// Per chunk: was a live row swept in it this tick? That is the whole
    /// rule — the renderer uploads dirty chunks and nothing else (campaign
    /// §3.7). A row born this tick is swept this tick; a row reaped this
    /// tick was swept this tick (`perish` marks during the sweep, the reap
    /// kills after), so the chunk it leaves is dirty now and quiet next
    /// tick. The first draft also marked at spawn and at reap; mutations
    /// dropping either survived every gate, because the sweep's mark had
    /// already said it — two decorations, deleted (ledger, beat 3).
    chunk_dirty: []bool = &.{},
    kernel: ?Kernel = null,
    /// One per `samples` entry, allocated on the first tick that sees them.
    lattices: []Lattice = &.{},
    bag_scratch: std.ArrayListUnmanaged(fields_mod.Deposit) = .empty,

    /// What was last said on the plane, so a tick that changes nothing says
    /// nothing (change-only: a sensor precondition, and a quiet log).
    said_count: ?u32 = null,
    said_digest: ?u64 = null,
    said_bounds: ?[6]Fixed = null,
    said_coarsened: ?u32 = null,

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
        self.gpa.free(self.chunk_dirty);
        for (self.lattices) |l| self.gpa.free(l.values);
        self.gpa.free(self.lattices);
        self.bag_scratch.deinit(self.gpa);
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
        // The spray's own refusals, before rill's: a `hear` of a channel the
        // archetype does not sample has no lattice to read, and the answer
        // is the archetype's declaration, not a zero.
        for (prog.nodes.items) |*n| {
            const def = reg.get(n.op);
            if (!std.mem.eql(u8, def.name, "hear")) continue;
            const chan = n.statics[0].channel;
            if (self.fields == null) {
                diag.set("{s}: '{s} at …' — this spray has no field store to hear; the host mounted it without fields", .{ n.name, chan });
                return error.Mount;
            }
            const declared = for (self.samples) |s| {
                if (std.mem.eql(u8, s.channel, chan)) break true;
            } else false;
            if (!declared) {
                diag.set("{s}: '{s} at …' — this spray does not sample {s}; declare `samples {s} cell <c>` on its ^spray", .{ n.name, chan, chan, chan });
                return error.Mount;
            }
        }
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

    /// Which chunks changed this tick, for a renderer's upload. Valid after
    /// `tick`; one entry per chunk of `chunk` rows.
    pub fn dirtyChunks(self: *const Spray) []const bool {
        return self.chunk_dirty;
    }

    /// The lattice for a sampled channel, for `hear`. Null = not sampled.
    pub fn lattice(self: *const Spray, channel: []const u8) ?*const Lattice {
        for (self.lattices) |*l| {
            if (std.mem.eql(u8, l.channel, channel)) return l;
        }
        return null;
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
        try self.sizeChunks();
        @memset(self.chunk_dirty, false);
        try self.broadcastPhase(plane);
        try self.materialisePhase(&stats);
        self.spawnPhase(dt_ns, &stats);
        try self.sweepPhase(dt, dt_ns, js, &stats);
        self.reapPhase(&stats);
        self.castPhase(&stats);
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

    // -- phase 2: materialise --------------------------------------------------

    /// Rasterise every sampled channel's bag onto its lattice over the
    /// spray's bounds. The bounds are last tick's rows plus the spawn
    /// point, padded by a cell; the cell doubles until the grid fits the
    /// cap. Every grid point sums the engine's kernel over the deposits
    /// this spray hears, is clamped by the channel, and lands as Q16.16 —
    /// the field enters the sim here, once per point per tick.
    fn materialisePhase(self: *Spray, stats: *Stats) !void {
        if (self.samples.len == 0) return;
        if (self.lattices.len != self.samples.len) {
            for (self.lattices) |l| self.gpa.free(l.values);
            self.gpa.free(self.lattices);
            self.lattices = try self.gpa.alloc(Lattice, self.samples.len);
            var made: usize = 0;
            errdefer {
                for (self.lattices[0..made]) |l| self.gpa.free(l.values);
                self.gpa.free(self.lattices);
                self.lattices = &.{};
            }
            for (self.samples, self.lattices) |s, *l| {
                l.* = .{ .channel = s.channel, .declared_cell = s.cell, .values = try self.gpa.alloc(Fixed, MAX_SAMPLES * MAX_SAMPLES * MAX_SAMPLES) };
                made += 1;
            }
        }
        const host = self.fields orelse {
            for (self.lattices) |*l| l.live = false;
            stats.bags_missing += @intCast(self.samples.len);
            return;
        };

        // The box: live rows and the spawn point, padded by one cell.
        var lo = self.pos;
        var hi = self.pos;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                lo[a] = @min(lo[a], self.pop.pos[a][id]);
                hi[a] = @max(hi[a], self.pop.pos[a][id]);
            }
        }

        for (self.lattices) |*l| {
            self.bag_scratch.clearRetainingCapacity();
            const maybe_bag = host.bag(l.channel, self.now.time_ns, self.gpa, &self.bag_scratch) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null, // a refusal is an undeclared channel by another name
            };
            const bag = maybe_bag orelse {
                l.live = false;
                stats.bags_missing += 1;
                continue;
            };
            // Fit: cell doubles until every axis has ≤ MAX_SAMPLES points.
            var cell = l.declared_cell;
            var doublings: u8 = 0;
            var dims: [3]u32 = undefined;
            while (true) {
                var fits = true;
                inline for (0..3) |a| {
                    const extent: i64 = @as(i64, hi[a]) - lo[a] + 2 * @as(i64, cell);
                    const n: i64 = @divFloor(extent + cell - 1, cell) + 1;
                    dims[a] = @intCast(@max(n, 2));
                    if (dims[a] > MAX_SAMPLES) fits = false;
                }
                if (fits or cell >= std.math.maxInt(Fixed) / 2) break;
                cell *= 2;
                doublings += 1;
            }
            inline for (0..3) |a| dims[a] = @min(dims[a], MAX_SAMPLES);
            l.cell = cell;
            l.dims = dims;
            l.coarsened = doublings;
            inline for (0..3) |a| l.origin[a] = lo[a] - cell;
            if (doublings > 0) stats.coarsened += 1;

            // Rasterise.
            var k: u32 = 0;
            while (k < dims[2]) : (k += 1) {
                var j: u32 = 0;
                while (j < dims[1]) : (j += 1) {
                    var i: u32 = 0;
                    while (i < dims[0]) : (i += 1) {
                        const at = [3]f32{
                            fixed.toF32(l.origin[0] +% @as(Fixed, @intCast(i)) * cell),
                            fixed.toF32(l.origin[1] +% @as(Fixed, @intCast(j)) * cell),
                            fixed.toF32(l.origin[2] +% @as(Fixed, @intCast(k)) * cell),
                        };
                        var value: f32 = 0;
                        for (bag.deposits) |d| {
                            if (!fields_mod.hears(d, self.carried)) continue;
                            const kv = fields_mod.kernelAt(d, at) orelse continue;
                            value += kv.value;
                        }
                        l.values[l.index(i, j, k)] = fixed.fromF32Saturating(std.math.clamp(value, bag.clamp_lo, bag.clamp_hi));
                    }
                }
            }
            l.live = true;
        }
    }

    // -- phase 3: spawn (serial) -----------------------------------------------

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

    // -- phase 4: the sweep (chunked) ------------------------------------------

    const SweepCtx = struct { spray: *Spray, dt: Fixed, dt_ns: u64 };

    /// The per-chunk arrays follow `chunk`, which a host may set after init.
    fn sizeChunks(self: *Spray) !void {
        const n_chunks: usize = (self.pop.capacity + self.chunk - 1) / self.chunk;
        if (self.chunk_steps.len != n_chunks) {
            self.gpa.free(self.chunk_steps);
            self.chunk_steps = try self.gpa.alloc(u32, n_chunks);
        }
        if (self.chunk_dirty.len != n_chunks) {
            self.gpa.free(self.chunk_dirty);
            self.chunk_dirty = try self.gpa.alloc(bool, n_chunks);
            @memset(self.chunk_dirty, false);
        }
    }

    fn sweepPhase(self: *Spray, dt: Fixed, dt_ns: u64, js: ?*jobs.JobSystem, stats: *Stats) !void {
        const n_chunks: usize = self.chunk_steps.len;
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
        for (self.chunk_steps, self.chunk_dirty) |c, *d| {
            steps += c;
            if (c > 0) d.* = true;
        }
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
    /// chunk's own step slot and scratch. The lattices are read-only here.
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

    // -- phase 5: reap (serial, ascending) -------------------------------------

    fn reapPhase(self: *Spray, stats: *Stats) void {
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (self.pop.alive[id] and self.pop.doomed[id]) {
                self.pop.kill(id);
                stats.died += 1;
            }
        }
    }

    // -- phase 6: cast ----------------------------------------------------------

    /// One aggregate per declared channel: the centre of mass of the live
    /// rows (an exact integer mean, then one conversion), amplitude = per-row
    /// × live, radius from the bounds. The host replaces last tick's. No
    /// live rows, no cast — the previous one decays on its own; unmount
    /// withdraws it.
    fn castPhase(self: *Spray, stats: *Stats) void {
        if (self.casts.len == 0 or self.pop.live == 0) return;
        const host = self.fields orelse {
            stats.cast_refusals += @intCast(self.casts.len);
            return;
        };
        var sum: [3]i64 = .{ 0, 0, 0 };
        var lo: Vec = undefined;
        var hi: Vec = undefined;
        var any = false;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                const v = self.pop.pos[a][id];
                sum[a] += v;
                if (!any or v < lo[a]) lo[a] = v;
                if (!any or v > hi[a]) hi[a] = v;
            }
            any = true;
        }
        const n: i64 = self.pop.live;
        const centre = [3]f32{
            fixed.toF32(@intCast(@divFloor(sum[0], n))),
            fixed.toF32(@intCast(@divFloor(sum[1], n))),
            fixed.toF32(@intCast(@divFloor(sum[2], n))),
        };
        var half_diag: f32 = 0;
        inline for (0..3) |a| {
            const e = fixed.toF32(hi[a] -% lo[a]) / 2;
            half_diag += e * e;
        }
        half_diag = @sqrt(half_diag);
        for (self.casts) |c| {
            const radius: f32 = switch (c.radius) {
                .bounds => @max(half_diag, 1.0),
                .fixed => |r| r,
            };
            host.cast(self.name, self.now.time_ns, .{
                .channel = c.channel,
                .pos = centre,
                .amplitude = c.per_row_amplitude * @as(f32, @floatFromInt(self.pop.live)),
                .radius = radius,
                .decay_ns = c.decay_ns,
                .to = c.to,
            }) catch {
                stats.cast_refusals += 1;
            };
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

        // `coarsened` (ruled, beat 2 accepted): how many times the declared
        // cell was doubled to fit the cap, the largest over the sampled
        // channels; zero when the declared cell held. Change-only, so a
        // sentry can watch it and not only the Spray applet. A function of
        // the bounds and the declared cell alone — fed inputs — so a
        // coarsened run replays byte-identical (gated).
        const now_coarsened = self.coarsened();
        if (self.said_coarsened != now_coarsened) {
            pk.reset();
            try pk.appendInt(now_coarsened);
            try self.write(plane, &path_buf, "coarsened", pk.bytes());
            self.said_coarsened = now_coarsened;
        }
    }

    /// The largest doubling any sampled channel's lattice took this tick.
    pub fn coarsened(self: *const Spray) u32 {
        var worst: u32 = 0;
        for (self.lattices) |l| {
            if (l.live) worst = @max(worst, l.coarsened);
        }
        return worst;
    }

    /// Absence, said: `count` is zero, the kernel is gone, and the spray's
    /// casts are withdrawn — ownership is the ceiling. The other two leaves
    /// keep their last value (a bound of nothing is not a box).
    pub fn unmount(self: *Spray, plane: rill.Plane) !void {
        self.unmountKernel();
        if (self.fields) |f| f.withdraw(self.name);
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

test "lattice: trilinear is exact on the grid and between it on every axis, and the gradient is the slope in amplitude per cell" {
    const gpa = std.testing.allocator;
    var l = Lattice{ .channel = "$t", .declared_cell = fixed.ONE, .cell = fixed.ONE, .origin = .{ 0, 0, 0 }, .dims = .{ 3, 3, 3 }, .values = try gpa.alloc(Fixed, 27), .live = true };
    defer gpa.free(l.values);
    // f = 2x + 3y + 5z: linear, so trilinear reproduces it EXACTLY anywhere,
    // and every axis contributes — a field constant in y and z let a
    // mutation that dropped the y and z lerps survive the first draft of
    // this gate (Q11, ledger): A equalled B on the axes it broke.
    var k: u32 = 0;
    while (k < 3) : (k += 1) {
        var j: u32 = 0;
        while (j < 3) : (j += 1) {
            var i: u32 = 0;
            while (i < 3) : (i += 1) l.values[l.index(i, j, k)] = fixed.fromInt(@intCast(2 * i + 3 * j + 5 * k));
        }
    }
    try std.testing.expectEqual(fixed.fromInt(0), l.sampleAt(.{ 0, 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(2), l.sampleAt(.{ fixed.ONE, 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(10), l.sampleAt(.{ fixed.ONE, fixed.ONE, fixed.ONE }));
    try std.testing.expectEqual(fixed.fromInt(5), l.sampleAt(.{ fixed.HALF, fixed.HALF, fixed.HALF })); // 1 + 1.5 + 2.5
    try std.testing.expectEqual(fixed.fromInt(4), l.sampleAt(.{ 0, fixed.HALF, fixed.HALF })); // 0 + 1.5 + 2.5
    try std.testing.expectEqual(fixed.fromInt(3), l.sampleAt(.{ fixed.ONE + fixed.HALF, 0, 0 }));
    // Past the grid clamps to the edge.
    try std.testing.expectEqual(fixed.fromInt(4), l.sampleAt(.{ fixed.fromInt(9), 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(0), l.sampleAt(.{ -fixed.fromInt(9), 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(20), l.sampleAt(.{ fixed.fromInt(9), fixed.fromInt(9), fixed.fromInt(9) }));
    // Gradient: (2, 3, 5) per cell everywhere — middle and edges alike.
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ fixed.ONE, fixed.ONE, fixed.ONE }));
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ 0, 0, 0 }));
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ fixed.fromInt(2), fixed.fromInt(2), fixed.fromInt(2) }));
    // A coarser cell halves the per-cell slope of the same field.
    l.cell = 2 * fixed.ONE;
    try std.testing.expectEqual(Vec{ fixed.fromInt(1), @divExact(fixed.fromInt(3), 2), @divExact(fixed.fromInt(5), 2) }, l.gradientAt(.{ 2 * fixed.ONE, 2 * fixed.ONE, 2 * fixed.ONE }));
}
