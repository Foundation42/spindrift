//! emitter — knobs, the three-phase tick, and P0's stand-in kernel.
//!
//! **The stand-in.** P0's kernel is `spawn` / `gravity` / `perish` as Zig
//! functions over the population — NOT rill text. Recon R-a §7 found the
//! `row` routing cannot land inside P0 honestly (a parser form that needs
//! a read-aloud, a registry column that needs a ruling, an evaluator that
//! does not exist), and the brief allows a Zig-native stand-in on exactly
//! that finding. It is recorded in the ledger as a stand-in P1 deletes,
//! trigger: P1 itself. It does not grow a second word.
//!
//! **The tick is three phases and only the middle one is parallel** (recon
//! R-b §3). Spawn pops the freelist in a fixed order — serial. The kernel
//! is row-local (every row reads and writes its own fields, nothing else,
//! no inter-particle anything by the campaign's fence) — chunked over
//! `common/jobs.zig`, and chunk boundaries cannot reach the result. Perish
//! walks ascending ids and pushes the dead — serial, because push ORDER is
//! what the next spawn's ids are a function of. G0 is what forces this
//! shape: perish inside the parallel phase makes the freelist a race, and
//! two runs then differ in which slot a spawn lands.
//!
//! **Time is fed.** `tick(now)` carries `{frame, time_ns}` like rill's, dt
//! is the fed delta and nothing else, and a regression is a loud error,
//! never a clamp. No float enters the loop: every product is `fixed.mul`.

const std = @import("std");
const rill = @import("rill");
const common = @import("common");
const jobs = common.jobs;
const fixed = @import("fixed.zig");
const world_mod = @import("world.zig");
const Population = @import("population.zig").Population;

const Fixed = fixed.Fixed;
const Vec = fixed.Vec;

pub const Now = rill.Now;
pub const World = world_mod.World;

pub const TickError = error{TimeRegression} || std.mem.Allocator.Error;

/// The instance knobs (campaign §3.2), every one lane-capable later. Units
/// are the row's: cells and seconds in Q16.16. `life` is a duration on the
/// knob and a tick count in the row (R-b fork 3) — conversion happens at
/// spawn, by the fed dt, so a row never carries a unit.
pub const Knobs = struct {
    /// Rows per second.
    rate: Fixed = 0,
    /// Cells per second along `aim`.
    speed: Fixed = 0,
    /// ± cells per second of per-axis jitter, from the row's seed.
    spread: Fixed = 0,
    /// How long a row lives, fed nanoseconds.
    life_ns: u64 = std.time.ns_per_s,
    /// Cells per second², added to vel.y each tick. Negative is down.
    gravity: Fixed = 0,
};

/// What one tick did — the numbers `drift-run` prints and G6 will read.
pub const Stats = struct {
    spawned: u32 = 0,
    died: u32 = 0,
    /// Spawns refused because the population was at capacity.
    throttled: u32 = 0,
    /// Rows the kernel evaluated — the budget unit (§3.6), counted from
    /// tick one so the number exists before anything enforces it. Counted
    /// BY the kernel, per chunk, not assumed from the live count: a kernel
    /// that quietly evaluated every dead row too survived the whole suite
    /// while this was `= pop.live` (mutation M11, ledger), because nothing
    /// watched the work — only the result, which dead rows never reach.
    row_steps: u32 = 0,
};

/// Rows per job. ≈ 69 bytes of row across the sixteen arrays, so a chunk
/// streams ≈ 70 KB — inside L2 with room for scratch. Not measured; a
/// constant until the first customer scene moves it (R-b §3).
pub const DEFAULT_CHUNK: u32 = 1024;

pub const Emitter = struct {
    pop: Population,
    /// The emitter's decorrelator: every row's seed derives from this and
    /// the row's spawn ordinal, and nothing else.
    seed: u32,
    pos: Vec = fixed.zero_vec,
    /// Direction × 1.0; spawn velocity is `aim × speed`. Not normalised
    /// here — an aim of (0, 2, 0) is twice the speed, and saying so is
    /// cheaper than a square root in fixed point.
    aim: Vec = .{ 0, fixed.ONE, 0 },
    knobs: Knobs = .{},
    world: World,
    chunk: u32 = DEFAULT_CHUNK,

    /// Rows owed by `rate`, in units of (rows · 2¹⁶ · ns) — `rate` is Q16.16
    /// rows/s and dt is fed nanoseconds, so their product is exact here and
    /// a whole row is `ONE × ns_per_s` of it. The accumulator is what makes
    /// 3/s at dt = 0.5 s spawn 1, 2, 1, 2 rather than 1, 1, 1 forever; the
    /// nanosecond unit is what makes 40/s at dt = 50 ms spawn exactly 2 per
    /// tick rather than 1.9995 — the Q16.16 dt the kernel uses truncates
    /// 50 ms to 49.99 ms, which is fine for motion and wrong for a count
    /// that G1 will threshold on.
    spawn_acc: i128 = 0,
    /// Spawn ordinal: the row seed's other half. Never reset.
    spawned: u32 = 0,
    now: Now = .{},
    started: bool = false,
    ticks: u64 = 0,
    last: Stats = .{},
    /// One row-step count per chunk, written by the chunk's own job and
    /// summed serially after the join — a per-chunk slot instead of an
    /// atomic, so the count is exact and the sum is in one order.
    gpa: std.mem.Allocator,
    chunk_steps: []u32 = &.{},

    pub fn init(gpa: std.mem.Allocator, capacity: u32, seed: u32, world: World) !Emitter {
        return .{
            .pop = try Population.init(gpa, capacity),
            .seed = seed,
            .world = world,
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.pop.deinit();
        self.gpa.free(self.chunk_steps);
    }

    /// One fed tick. The first call sets the epoch (dt = 0: nothing spawns,
    /// nothing moves); every later call advances by the fed delta. `js` null
    /// runs the kernel inline on the caller — the same arithmetic, one
    /// thread — which is how a gate proves the chunking cannot reach the
    /// result.
    pub fn tick(self: *Emitter, now: Now, js: ?*jobs.JobSystem) TickError!void {
        if (self.started and (now.time_ns < self.now.time_ns or now.frame < self.now.frame)) {
            return error.TimeRegression;
        }
        const dt_ns: u64 = if (self.started) now.time_ns - self.now.time_ns else 0;
        self.now = now;
        self.started = true;
        const dt = fixed.fromNs(dt_ns);

        var stats = Stats{};
        self.spawnPhase(dt_ns, &stats);
        stats.row_steps = try self.kernelPhase(dt, js);
        self.perishPhase(&stats);
        self.last = stats;
        self.ticks += 1;
    }

    // -- phase 1: spawn (serial) -------------------------------------------

    fn spawnPhase(self: *Emitter, dt_ns: u64, stats: *Stats) void {
        if (dt_ns == 0) return;
        const one_row: i128 = @as(i128, fixed.ONE) * std.time.ns_per_s;
        self.spawn_acc += @as(i128, self.knobs.rate) * dt_ns;
        if (self.spawn_acc < 0) self.spawn_acc = 0; // a negative rate owes nothing, and owes nothing later
        var owed: u32 = @intCast(@divFloor(self.spawn_acc, one_row));
        self.spawn_acc -= @as(i128, owed) * one_row;
        // A life shorter than one tick is one tick: a row that could never
        // be seen is a row that was never there, and zero would let `age >=
        // life` retire it before the kernel moved it once.
        const life_ticks: u32 = @intCast(@max(self.knobs.life_ns / dt_ns, 1));
        while (owed > 0) : (owed -= 1) {
            const id = self.pop.spawn() orelse {
                stats.throttled += owed;
                return;
            };
            const row_seed = mix(self.seed, self.spawned);
            self.spawned +%= 1;
            const p = &self.pop;
            p.seed[id] = row_seed;
            p.life[id] = life_ticks;
            p.size[id] = fixed.ONE;
            p.colour[0][id] = fixed.ONE;
            inline for (0..3) |a| {
                p.pos[a][id] = self.pos[a];
                p.vel[a][id] = fixed.mul(self.aim[a], self.knobs.speed) + jitter(row_seed, a, self.knobs.spread);
            }
            stats.spawned += 1;
        }
    }

    // -- phase 2: the kernel (chunked) -------------------------------------

    const KernelCtx = struct { em: *Emitter, dt: Fixed };

    /// Returns the row-steps the kernel spent — one per live row it touched.
    fn kernelPhase(self: *Emitter, dt: Fixed, js: ?*jobs.JobSystem) !u32 {
        const n_chunks: usize = (self.pop.capacity + self.chunk - 1) / self.chunk;
        if (self.chunk_steps.len != n_chunks) {
            self.gpa.free(self.chunk_steps);
            self.chunk_steps = try self.gpa.alloc(u32, n_chunks);
        }
        @memset(self.chunk_steps, 0);
        var ctx = KernelCtx{ .em = self, .dt = dt };
        if (js) |sys| {
            var counter = jobs.Counter.init(0);
            sys.parallelFor(self.pop.capacity, self.chunk, kernelJob, &ctx, &counter);
            sys.waitFor(&counter);
        } else {
            var start: u32 = 0;
            while (start < self.pop.capacity) : (start += self.chunk) {
                kernelRows(&ctx, start, @min(start + self.chunk, self.pop.capacity));
            }
        }
        var steps: u32 = 0;
        for (self.chunk_steps) |c| steps += c;
        return steps;
    }

    fn kernelJob(job: *jobs.Job) void {
        const range = job.getData(jobs.BatchRange);
        const ctx: *const KernelCtx = @ptrCast(@alignCast(range.context));
        kernelRows(ctx, range.start, range.end);
    }

    /// The stand-in kernel, per row: `gravity`, then the integration every
    /// kernel ends with, then age. Row-local by construction — the only
    /// indices touched are `id`'s own, plus this chunk's own step slot.
    fn kernelRows(ctx: *const KernelCtx, start: u32, end: u32) void {
        const p = &ctx.em.pop;
        const dt = ctx.dt;
        const g_dt = fixed.mul(ctx.em.knobs.gravity, dt);
        var steps: u32 = 0;
        var id = start;
        while (id < end) : (id += 1) {
            if (!p.alive[id]) continue;
            // gravity
            p.vel[1][id] += g_dt;
            // integrate
            inline for (0..3) |a| p.pos[a][id] += fixed.mul(p.vel[a][id], dt);
            // age
            p.age[id] += 1;
            steps += 1;
        }
        ctx.em.chunk_steps[start / ctx.em.chunk] = steps;
    }

    // -- phase 3: perish (serial, ascending) -------------------------------

    fn perishPhase(self: *Emitter, stats: *Stats) void {
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            if (self.pop.age[id] >= self.pop.life[id]) {
                self.pop.kill(id);
                stats.died += 1;
            }
        }
    }
};

/// A 32-bit mix (murmur3's finaliser over a keyed input). Every row seed
/// and every jitter draw comes from this, so the whole population is a
/// pure function of the emitter seed and fed history.
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
fn jitter(row_seed: u32, axis: usize, spread: Fixed) Fixed {
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
