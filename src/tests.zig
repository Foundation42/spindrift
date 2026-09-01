//! The gates. Each names the mutation that must bite (campaign §2): a gate
//! that passes under its mutation is a finding about the gate, not a pass.
//! Mutations were applied by hand and their outcomes are in the ledger
//! (`docs/implementation-notes.md`).

const std = @import("std");
const testing = std.testing;
const rill = @import("rill");
const common = @import("common");
const jobs = common.jobs;
const spindrift = @import("spindrift.zig");
const fixed = spindrift.fixed;
const dump = spindrift.dump;
const words = spindrift.words;
const Spray = spindrift.Spray;
const Knobs = spindrift.Knobs;
const Fixed = fixed.Fixed;

const embers = @embedFile("embers.rill");

/// A registry with the core and the drift words — what every host builds.
fn registry(gpa: std.mem.Allocator) !rill.Registry {
    var reg = try rill.Registry.init(gpa);
    errdefer reg.deinit();
    try rill.registerCore(&reg);
    try words.register(&reg);
    return reg;
}

const Script = struct {
    capacity: u32 = 64,
    seed: u32 = 7,
    knobs: Knobs = .{ .rate = fixed.fromInt(4), .speed = fixed.fromInt(3), .spread = fixed.ONE, .life_ns = 2 * std.time.ns_per_s },
    gravity: []const u8 = "-10",
    dt_ns: u64 = std.time.ns_per_s / 2,
    ticks: u32 = 20,
    chunk: u32 = spindrift.spray.DEFAULT_CHUNK,
    kernel: []const u8 = "spawn\ngravity plane.drift.@self.gravity\nperish\n",
};

/// Mount a spray with the script's kernel on a mock plane (gravity seeded
/// as its knob), run it, and return its dump. The script is the whole
/// input: same script, same bytes, or G0 is broken.
fn run(gpa: std.mem.Allocator, s: Script, js: ?*jobs.JobSystem) ![]u8 {
    var reg = try registry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    // The knob crosses the plane as a number in cells — a float, at the one
    // boundary. (Seeded as the raw fixed integer, it read as −655360 cells,
    // out of range, and every G0 run was gravity-free while green.)
    try mock.putValue("plane.drift.@em.gravity", fixed.toF64(try fixed.parseDecimal(s.gravity)));
    var floor = spindrift.Floor{};
    var spray = try Spray.init(gpa, s.capacity, s.seed, floor.asWorld());
    defer spray.deinit();
    spray.knobs = s.knobs;
    spray.chunk = s.chunk;
    var diag = rill.registry.Detail{};
    spray.mountKernel(&reg, "k", s.kernel, &diag) catch |err| {
        std.debug.print("kernel refused: {s}\n", .{diag.text()});
        return err;
    };
    var t: u32 = 0;
    while (t <= s.ticks) : (t += 1) {
        try spray.tick(.{ .frame = t, .time_ns = @as(u64, t) * s.dt_ns }, js, mock.asPlane());
    }
    // A population that never moved is a harness defect, not a run: the
    // first draft of beat 1 had every kernel write refused (a queue sized
    // to `write` nodes alone) and G0 passed on identical bytes of nothing.
    // Determinism of stillness is not the claim.
    if (spray.last.refusals > 0) {
        std.debug.print("kernel refused {d} rows: {s}\n", .{ spray.last.refusals, spray.last_refusal.text() });
        return error.KernelRefused;
    }
    var moved = false;
    var fell = false;
    var id: u32 = 0;
    while (id < spray.pop.capacity) : (id += 1) {
        if (!spray.pop.alive[id]) continue;
        if (spray.pop.pos[1][id] != 0) moved = true;
        if (spray.pop.vel[1][id] < 0) fell = true;
    }
    if (!moved) return error.PopulationNeverMoved;
    if (!fell) return error.GravityNeverReached;
    return dump.write(gpa, &spray.pop, spray.ticks);
}

// ---------------------------------------------------------------------------
// G0 — determinism. Same script ⇒ byte-identical dump, two runs.
// Mutation: perturb the seed; the dumps differ. (`repro-input` precedent.)
// ---------------------------------------------------------------------------

test "G0: the same script twice is the same bytes" {
    const gpa = testing.allocator;
    const a = try run(gpa, .{}, null);
    defer gpa.free(a);
    const b = try run(gpa, .{}, null);
    defer gpa.free(b);
    try testing.expectEqualSlices(u8, a, b);
    // The gate must be able to fail: this is not a dump of nothing.
    const s = try dump.readSummary(gpa, a);
    defer gpa.free(s.ids);
    try testing.expect(s.live > 0);
    try testing.expectEqual(@as(u64, 21), s.tick);
}

test "G0 mutation: a perturbed seed is a different population" {
    const gpa = testing.allocator;
    const a = try run(gpa, .{ .seed = 7 }, null);
    defer gpa.free(a);
    const b = try run(gpa, .{ .seed = 8 }, null);
    defer gpa.free(b);
    try testing.expect(!std.mem.eql(u8, a, b));
    // …and the difference is in the rows, not the counts: same rate, same
    // life, same number alive — only where they went.
    const sa = try dump.readSummary(gpa, a);
    defer gpa.free(sa.ids);
    const sb = try dump.readSummary(gpa, b);
    defer gpa.free(sb.ids);
    try testing.expectEqual(sa.live, sb.live);
    try testing.expectEqualSlices(u32, sa.ids, sb.ids);
}

test "G0: chunking over the job system cannot reach the result" {
    // Four workers, 4096 rows in chunks of 64 — sixty-four jobs a tick with
    // a thousand spawns and a thousand deaths each — and the bytes must
    // match the single-threaded run exactly, five runs over. This is the
    // gate that forces the reap to be serial (R-b §3): a freelist pushed
    // from inside the parallel sweep makes the NEXT tick's ids a race.
    //
    // The scale is load-bearing. At 64 rows in chunks of 8 this gate passed
    // under exactly that mutation (M2, beat 0): the jobs were too small for
    // the steal order to ever differ. A gate that watches for a race must
    // run where the race can happen.
    const gpa = testing.allocator;
    const js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    const s = Script{ .capacity = 4096, .chunk = 64, .ticks = 12, .knobs = .{ .rate = fixed.fromInt(2000), .speed = fixed.fromInt(3), .spread = fixed.ONE, .life_ns = 2 * std.time.ns_per_s } };
    const serial = try run(gpa, s, null);
    defer gpa.free(serial);
    var round: u32 = 0;
    while (round < 5) : (round += 1) {
        const parallel = try run(gpa, s, js);
        defer gpa.free(parallel);
        try testing.expectEqualSlices(u8, serial, parallel);
    }
}

// ---------------------------------------------------------------------------
// The three words, each against an exact expectation. dt is a power of two
// of a second so every fixed product is exact.
// ---------------------------------------------------------------------------

const Bench = struct {
    reg: rill.Registry,
    mock: rill.MockPlane,
    nowhere: spindrift.Nowhere = .{},
    spray: Spray,

    fn init(gpa: std.mem.Allocator, capacity: u32, seed: u32) !*Bench {
        const b = try gpa.create(Bench);
        errdefer gpa.destroy(b);
        b.* = .{ .reg = try registry(gpa), .mock = rill.MockPlane.init(gpa), .spray = undefined };
        b.spray = try Spray.init(gpa, capacity, seed, b.nowhere.asWorld());
        return b;
    }

    fn deinit(b: *Bench, gpa: std.mem.Allocator) void {
        b.spray.deinit();
        b.mock.deinit();
        b.reg.deinit();
        gpa.destroy(b);
    }

    fn mount(b: *Bench, kernel: []const u8) !void {
        var diag = rill.registry.Detail{};
        b.spray.mountKernel(&b.reg, "k", kernel, &diag) catch |err| {
            std.debug.print("kernel refused: {s}\n", .{diag.text()});
            return err;
        };
    }

    fn tick(b: *Bench, frame: u64, time_ns: u64) !void {
        try b.spray.tick(.{ .frame = frame, .time_ns = time_ns }, null, b.mock.asPlane());
    }
};

/// One row, spawned on tick 1 and never another: rate 1/s at dt = 1 s
/// spawns exactly one, then the rate is dropped to zero.
fn oneRow(b: *Bench) !void {
    b.spray.knobs.rate = fixed.fromInt(1);
    try b.tick(0, 0); // epoch
    try b.tick(1, std.time.ns_per_s);
    b.spray.knobs.rate = 0;
    try testing.expectEqual(@as(u32, 1), b.spray.pop.live);
}

test "gravity: vel.y = -k and pos.y = -k(k+1)/2 cells after k ticks, exactly" {
    // Mutation: `gravity` writes with replace instead of add; vel.y stays -1.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("gravity -1\n");
    try oneRow(b);
    // The spawn tick already ran the kernel once on the new row.
    try testing.expectEqual(-fixed.fromInt(1), b.spray.pop.vel[1][0]);
    try testing.expectEqual(-fixed.fromInt(1), b.spray.pop.pos[1][0]);
    var k: u32 = 1;
    while (k < 10) : (k += 1) {
        try b.tick(k + 1, @as(u64, k + 1) * std.time.ns_per_s);
        const n: i32 = @intCast(k + 1);
        try testing.expectEqual(-fixed.fromInt(n), b.spray.pop.vel[1][0]);
        try testing.expectEqual(-fixed.fromInt(@divExact(n * (n + 1), 2)), b.spray.pop.pos[1][0]);
    }
    // x and z never moved: gravity is y's alone.
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.pos[0][0]);
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.pos[2][0]);
}

test "gravity: the knob is a broadcast — one write on the plane bends every row next tick" {
    // Mutation: `@self` not resolved to the spray's name; the knob is never
    // found and every row falls at zero.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.name = "sparks";
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("gravity plane.drift.@self.gravity\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // two rows, no knob yet: quiet, vel 0
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.vel[1][0]);
    try b.mock.putValue("plane.drift.@sparks.gravity", @as(i64, -2));
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(-fixed.fromInt(2), b.spray.pop.vel[1][0]);
    try testing.expectEqual(-fixed.fromInt(2), b.spray.pop.vel[1][3]);
    // A knob under another name is somebody else's.
    try b.mock.putValue("plane.drift.@em.gravity", @as(i64, -50));
    try b.tick(3, 3 * std.time.ns_per_s);
    try testing.expectEqual(-fixed.fromInt(4), b.spray.pop.vel[1][0]);
}

test "spawn: launches a newborn along aim × speed on its birth tick and never again" {
    // Mutation: drop the birth-tick check; every tick relaunches and the
    // row never accelerates.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.aim = .{ 0, fixed.fromInt(2), 0 };
    b.spray.knobs = .{ .speed = fixed.fromInt(3), .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\ngravity -1\n");
    try oneRow(b);
    // launched at 6 up, then gravity: 6 − 1 = 5, and moved 5 in the tick
    try testing.expectEqual(fixed.fromInt(5), b.spray.pop.vel[1][0]);
    try testing.expectEqual(fixed.fromInt(5), b.spray.pop.pos[1][0]);
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(fixed.fromInt(4), b.spray.pop.vel[1][0]); // not relaunched to 6
    try testing.expectEqual(fixed.fromInt(9), b.spray.pop.pos[1][0]);
}

test "spawn: spread is a per-row draw inside ±spread, different per row, the same per seed" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 64, 3);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(32), .speed = 0, .spread = fixed.ONE, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 32), b.spray.pop.live);
    var distinct: u32 = 0;
    var id: u32 = 0;
    while (id < 32) : (id += 1) {
        inline for (0..3) |a| {
            const v = b.spray.pop.vel[a][id];
            try testing.expect(v >= -fixed.ONE and v <= fixed.ONE);
        }
        if (id > 0 and b.spray.pop.vel[0][id] != b.spray.pop.vel[0][id - 1]) distinct += 1;
    }
    try testing.expect(distinct > 20);
}

test "spawn: rate × dt rows per tick, with the fraction carried, not dropped" {
    // Mutation: reset `spawn_acc` to zero each tick; 3/s at dt = 0.5 s
    // spawns 1, 1, 1, 1 instead of 1, 2, 1, 2.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 64, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(3), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\n");
    try b.tick(0, 0);
    const expect_per_tick = [_]u32{ 1, 2, 1, 2, 1, 2 };
    var total: u32 = 0;
    for (expect_per_tick, 1..) |want, t| {
        try b.tick(t, @as(u64, t) * std.time.ns_per_s / 2);
        try testing.expectEqual(want, b.spray.last.spawned);
        total += want;
        try testing.expectEqual(total, b.spray.pop.live);
        // The sweep spent exactly one row-step per live row — counted by
        // the sweep, so a sweep that walked the dead too would say so
        // (mutation M11, beat 0, survived while this number was assumed).
        try testing.expectEqual(total, b.spray.last.row_steps);
    }
}

test "spawn: the first tick is the epoch and spawns nothing" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(100) };
    try b.mount("spawn\n");
    try b.tick(5, 5 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.pop.live);
    try testing.expectEqual(@as(u32, 0), b.spray.last.spawned);
}

test "spawn: at capacity the spray says throttled and never grows" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 2, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(5), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 2), b.spray.last.spawned);
    try testing.expectEqual(@as(u32, 3), b.spray.last.throttled);
    try testing.expectEqual(@as(u32, 2), b.spray.pop.live);
}

test "perish: a row is reaped on the first tick its age has reached its life, and its id is reused" {
    // Mutation: `age > life` instead of `>=`; the row lives one tick long.
    // Mutation: the reap inside the sweep; the id is reused a tick early
    // and the chunking gate races.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    // life 1 s at dt 0.5 s: born at age 0, seen at 0.5, reaped at 1.0.
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .life_ns = std.time.ns_per_s };
    try b.mount("perish\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s / 2); // row 0 born (age 0 → 0.5)
    try testing.expectEqual(@as(u32, 1), b.spray.pop.live);
    try testing.expectEqual(@as(u32, 0), b.spray.last.died);
    try b.tick(2, std.time.ns_per_s); // row 1 born; row 0 at 0.5 → 1.0, still here
    try testing.expectEqual(@as(u32, 0), b.spray.last.died);
    try testing.expectEqual(@as(u32, 2), b.spray.pop.live);
    try b.tick(3, 3 * std.time.ns_per_s / 2); // row 0 at 1.0 ≥ 1.0 ⇒ reaped; row 2 born on id 2
    try testing.expectEqual(@as(u32, 1), b.spray.last.died);
    try testing.expectEqual(@as(u32, 2), b.spray.pop.live);
    try testing.expect(!b.spray.pop.alive[0]);
    try testing.expect(b.spray.pop.alive[1]);
    try testing.expect(b.spray.pop.alive[2]);
    try b.tick(4, 2 * std.time.ns_per_s); // row 1 reaped; the newborn takes id 0 back
    try testing.expect(b.spray.pop.alive[0]);
    try testing.expect(!b.spray.pop.alive[1]);
    try testing.expectEqual(@as(u16, 2), b.spray.pop.gen[0]);
}

test "perish: a kernel without it has immortal rows, and a full spray says throttled" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .life_ns = std.time.ns_per_ms };
    try b.mount("spawn\n");
    var t: u64 = 0;
    while (t <= 6) : (t += 1) try b.tick(t, t * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
    try testing.expect(b.spray.last.throttled > 0);
}

// ---------------------------------------------------------------------------
// The freelist keeps ids stable for a row's life (R-b §4).
// ---------------------------------------------------------------------------

test "freelist: a live row keeps its id, its seed and its generation while others die around it" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 16, 3);
    defer b.deinit(gpa);
    // Two per tick at dt 1 s, life 2 s: born at 0, seen at 1, reaped at 2.
    // A rolling population of four: two aged 0, two aged 1.
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .speed = fixed.fromInt(1), .spread = fixed.ONE, .life_ns = 2 * std.time.ns_per_s };
    try b.mount(embers);
    try b.mock.putValue("plane.drift.@em.gravity", @as(i64, -1));
    var t: u64 = 0;
    while (t <= 4) : (t += 1) try b.tick(t, t * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
    var handles: [16]?spindrift.Handle = .{null} ** 16;
    var seeds: [16]u32 = undefined;
    var ages: [16]u64 = undefined;
    var id: u32 = 0;
    while (id < 16) : (id += 1) {
        if (!b.spray.pop.alive[id]) continue;
        handles[id] = b.spray.pop.handle(id);
        seeds[id] = b.spray.pop.seed[id];
        ages[id] = b.spray.pop.age_ns[id];
    }
    try b.tick(5, 5 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 2), b.spray.last.died);
    try testing.expectEqual(@as(u32, 2), b.spray.last.spawned);
    id = 0;
    var survivors: u32 = 0;
    while (id < 16) : (id += 1) {
        const h = handles[id] orelse continue;
        if (ages[id] >= 2 * std.time.ns_per_s) {
            try testing.expect(!b.spray.pop.isLive(h));
            continue;
        }
        survivors += 1;
        try testing.expect(b.spray.pop.isLive(h));
        try testing.expectEqual(seeds[id], b.spray.pop.seed[id]);
        try testing.expectEqual(ages[id] + std.time.ns_per_s, b.spray.pop.age_ns[id]);
    }
    try testing.expectEqual(@as(u32, 2), survivors);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
}

// ---------------------------------------------------------------------------
// Time is fed, and a regression is loud.
// ---------------------------------------------------------------------------

test "tick: fed time going backwards is refused, never clamped" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    try b.tick(0, 0);
    try b.tick(1, 100);
    try testing.expectError(error.TimeRegression, b.tick(2, 50));
    try testing.expectError(error.TimeRegression, b.tick(0, 200));
    // Equal is fine: a zero-clock script ticks at the same instant forever.
    try b.tick(1, 100);
}

// ---------------------------------------------------------------------------
// G1 — the population is plane-native. The spray publishes count (and
// bounds, and a change-only digest); a second rill reads count, pipes it
// through `above`, and writes a knob; the knob changes when the population
// crosses the threshold. Mutation: skip the zero on unmount; count stays at
// its last value, the knob never falls, and the gate fails.
// ---------------------------------------------------------------------------

test "G1: a second rill reads drift/@em/count through above and writes a knob; unmount says zero" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 64, 5);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(4), .speed = fixed.fromInt(1), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\nperish\n");

    // The watcher, mounted on the same plane.
    var diag = rill.Diag{};
    var prog = try rill.parse(gpa, &b.reg, "watch", "plane.drift.@em.count | above 10 5 | write plane.ui.alarm", &diag);
    defer prog.deinit();
    var rt = try rill.Runtime.mount(gpa, &prog, b.mock.asPlane(), .{});
    defer rt.deinit();

    // The harness is the engine's plane: everything the spray says is fed
    // to the watcher as a delta.
    var seen: usize = 0;
    var alarm_rose_at: ?u64 = null;
    var t: u64 = 0;
    while (t <= 5) : (t += 1) {
        try rt.tick(.{ .frame = t, .time_ns = t * std.time.ns_per_s });
        try b.tick(t, t * std.time.ns_per_s);
        for (b.mock.writes.items[seen..]) |w| try rt.feed(.{ .path = w.path, .value = w.value });
        seen = b.mock.writes.items.len;
        if (alarm_rose_at == null) {
            if (b.mock.store.get("plane.ui.alarm")) |v| {
                if (rill.types.asBool(v) == true) alarm_rose_at = t;
            }
        }
    }
    // 4 a second: 4, 8, 12 … the alarm rises once count is above 10, which
    // the watcher can only see on the tick AFTER the write (fed as a delta).
    try testing.expectEqual(@as(?u64, 4), alarm_rose_at);
    try testing.expectEqual(@as(u32, 20), b.spray.pop.live);
    try testing.expectEqual(@as(f64, 20), rill.types.asNumber(b.mock.store.get("plane.drift.@em.count").?).?);
    // Bounds and digest were said too, and change-only: the digest moved
    // every tick (rows aged), so it was written once per tick after tick 0.
    try testing.expect(b.mock.store.get("plane.drift.@em.bounds") != null);
    try testing.expect(b.mock.store.get("plane.drift.@em.digest") != null);

    // Unmount: absence is said. count is zero, the watcher falls below 5,
    // and the knob it wrote is still there — holding false, not gone.
    try b.spray.unmount(b.mock.asPlane());
    for (b.mock.writes.items[seen..]) |w| try rt.feed(.{ .path = w.path, .value = w.value });
    try rt.tick(.{ .frame = 6, .time_ns = 6 * std.time.ns_per_s });
    try testing.expectEqual(@as(f64, 0), rill.types.asNumber(b.mock.store.get("plane.drift.@em.count").?).?);
    try testing.expectEqual(false, rill.types.asBool(b.mock.store.get("plane.ui.alarm").?).?);
    try testing.expect(!b.spray.hasKernel());
}

test "G1: what the spray says is change-only — a quiet population says nothing" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    // No rate, no rows: after the first say, nothing changes and nothing is written.
    try b.tick(0, 0);
    const after_first = b.mock.writes.items.len;
    try testing.expect(after_first > 0);
    try b.tick(1, std.time.ns_per_s);
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(after_first, b.mock.writes.items.len);
}

// ---------------------------------------------------------------------------
// G2 — kernels are operators. Every spindrift word walks rill's register
// (reserved names, the tail rule, the argument-spelling rule), is
// row-legal, exact, row-only, refuses on the plane by name, and is named
// in the manual. Mutation: register a word with two adjacent wordless
// optionals; the registry refuses it at build.
// ---------------------------------------------------------------------------

test "G2: every drift word is row-legal, exact, row-only, and refuses the plane by name at mount" {
    const gpa = testing.allocator;
    var reg = try registry(gpa);
    defer reg.deinit();
    for (words.WORDS) |w| {
        const def = reg.get(reg.find(w.name).?);
        try testing.expect(def.row.legal());
        try testing.expect(def.row.only);
    }
    // On the world plane, a row word is refused at parse with its own
    // words — whatever is or is not fed. (A `fails_mount` refusal was the
    // first draft; `plane.x | gravity` with an unfed `plane.x` never
    // evaluated at tick 0, and mounted cleanly.)
    var diag = rill.Diag{};
    try testing.expectError(error.Parse, rill.parse(gpa, &reg, "p", "plane.x | gravity", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.msg(), "'gravity' is a row word") != null);
    try testing.expectError(error.Parse, rill.parse(gpa, &reg, "p", "spawn", &diag));
    try testing.expectError(error.Parse, rill.parse(gpa, &reg, "p", "every 1s | also { perish }", &diag));
}

test "G2 mutation: a word with two adjacent wordless optionals is refused at registration" {
    const gpa = testing.allocator;
    var reg = try registry(gpa);
    defer reg.deinit();
    const noop = struct {
        fn f(_: *rill.EvalCtx) rill.registry.EvalError!rill.Emit {
            return rill.Emit.none;
        }
    }.f;
    try testing.expectError(error.AmbiguousOptionals, reg.register(.{
        .name = "drag",
        .inputs = &.{ .{ .name = "in", .optional = true }, .{ .name = "k", .optional = true } },
        .help = "the shape a drag word must not have",
        .routes = .anywhere,
        .eval = noop,
    }));
    // …and the sigils are the store's, never a word's.
    try testing.expectError(error.ReservedName, reg.register(.{ .name = "$wind", .help = "", .routes = .anywhere, .eval = noop }));
}

test "G2: every drift word is named in the manual, and every word the manual names is registered" {
    const doc = @embedFile("drift-words.md");
    const gpa = testing.allocator;
    var reg = try registry(gpa);
    defer reg.deinit();
    for (words.WORDS) |w| {
        var buf: [64]u8 = undefined;
        const needle = try std.fmt.bufPrint(&buf, "| `{s}", .{w.name});
        if (std.mem.indexOf(u8, doc, needle) == null) {
            std.debug.print("'{s}' is registered and has no row in docs/drift-words.md\n", .{w.name});
            return error.TestUnexpectedResult;
        }
    }
    // The other way: every table row names a registered word.
    var lines = std.mem.splitScalar(u8, doc, '\n');
    var rows: usize = 0;
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "| `")) continue;
        const rest = line[3..];
        const end = std.mem.indexOfAny(u8, rest, " `") orelse continue;
        const name = rest[0..end];
        if (reg.find(name) == null) {
            std.debug.print("docs/drift-words.md names '{s}', which is not registered\n", .{name});
            return error.TestUnexpectedResult;
        }
        rows += 1;
    }
    try testing.expectEqual(words.WORDS.len, rows);
}

// ---------------------------------------------------------------------------
// A kernel that cannot be mounted says why, by name.
// ---------------------------------------------------------------------------

test "kernel: mount refusals name the op and the field" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    var diag = rill.registry.Detail{};
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "row.age | window 2s | write row.size", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "'window' is not row-legal") != null);
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "row.mass | write row.size", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "'row.mass' is not a row field") != null);
    try testing.expectError(error.Parse, b.spray.mountKernel(&b.reg, "k", "vel | write row.size", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "k:1:") != null);
    try testing.expect(!b.spray.hasKernel());
}

// ---------------------------------------------------------------------------
// The mock World is a negative control (campaign §8): an emitter that
// behaves identically with the floor removed has no collision. In P1 that
// is still the TRUTH — no word calls the World — so this gate asserts
// equality. P4's `collide` must flip it to an inequality.
// ---------------------------------------------------------------------------

test "negative control: P1 has no collision — the floor and no world at all agree byte for byte" {
    const gpa = testing.allocator;
    const s = Script{ .knobs = .{ .rate = fixed.fromInt(8), .speed = fixed.fromInt(2), .spread = fixed.ONE, .life_ns = 4 * std.time.ns_per_s } };
    const on_floor = try run(gpa, s, null);
    defer gpa.free(on_floor);

    var reg = try registry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    try mock.putValue("plane.drift.@em.gravity", fixed.toF64(try fixed.parseDecimal(s.gravity)));
    var nowhere = spindrift.Nowhere{};
    var spray = try Spray.init(gpa, s.capacity, s.seed, nowhere.asWorld());
    defer spray.deinit();
    spray.knobs = s.knobs;
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k", s.kernel, &diag);
    var t: u32 = 0;
    while (t <= s.ticks) : (t += 1) try spray.tick(.{ .frame = t, .time_ns = @as(u64, t) * s.dt_ns }, null, mock.asPlane());
    const in_void = try dump.write(gpa, &spray.pop, spray.ticks);
    defer gpa.free(in_void);

    try testing.expectEqualSlices(u8, on_floor, in_void);
    var below: u32 = 0;
    var id: u32 = 0;
    while (id < spray.pop.capacity) : (id += 1) {
        if (spray.pop.alive[id] and spray.pop.pos[1][id] < 0) below += 1;
    }
    try testing.expect(below > 0);
}
