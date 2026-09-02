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

test "spawn: at capacity the spray says refused and never grows" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 2, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(5), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("spawn\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 2), b.spray.last.spawned);
    try testing.expectEqual(@as(u32, 3), b.spray.last.refused);
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

test "perish: a kernel without it has immortal rows, and a full spray says refused" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .life_ns = std.time.ns_per_ms };
    try b.mount("spawn\n");
    var t: u64 = 0;
    while (t <= 6) : (t += 1) try b.tick(t, t * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
    try testing.expect(b.spray.last.refused > 0);
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
    try words.registerTracer(&reg);
    for (words.WORDS ++ words.TRACER) |w| {
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
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    for (words.WORDS ++ words.TRACER) |w| {
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
    try testing.expectEqual(words.WORDS.len + words.TRACER.len, rows);
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

// ---------------------------------------------------------------------------
// Beat 2 — fields, both ways. The harness: a mock field store shared by a
// caster rill (through a cast door) and the spray (as its Fields), with the
// mock's receiver-side sum standing in for an ear.
// ---------------------------------------------------------------------------

const smoke = @embedFile("smoke.rill");

const FieldBench = struct {
    reg: rill.Registry,
    mock: rill.MockPlane,
    fields: spindrift.MockFields,
    door: spindrift.MockFields.CastDoor,
    nowhere: spindrift.Nowhere = .{},
    spray: Spray,
    caster: ?struct { prog: rill.Program, rt: rill.Runtime } = null,

    fn init(gpa: std.mem.Allocator, capacity: u32, seed: u32) !*FieldBench {
        const b = try gpa.create(FieldBench);
        errdefer gpa.destroy(b);
        b.* = .{ .reg = try registry(gpa), .mock = rill.MockPlane.init(gpa), .fields = spindrift.MockFields.init(gpa), .door = undefined, .spray = undefined };
        b.door = .{ .inner = b.mock.asPlane(), .fields = &b.fields, .owner = "caster" };
        b.spray = try Spray.init(gpa, capacity, seed, b.nowhere.asWorld());
        b.spray.fields = b.fields.asFields();
        return b;
    }

    fn deinit(b: *FieldBench, gpa: std.mem.Allocator) void {
        b.unmountCaster();
        b.spray.deinit();
        b.fields.deinit();
        b.mock.deinit();
        b.reg.deinit();
        gpa.destroy(b);
    }

    fn mount(b: *FieldBench, kernel: []const u8) !void {
        var diag = rill.registry.Detail{};
        b.spray.mountKernel(&b.reg, "k", kernel, &diag) catch |err| {
            std.debug.print("kernel refused: {s}\n", .{diag.text()});
            return err;
        };
    }

    /// A caster rill on the same store, through the door: `cast` lands in
    /// the mock under the owner "caster", everything else on the mock plane.
    fn mountCaster(b: *FieldBench, gpa: std.mem.Allocator, src: []const u8) !void {
        var diag = rill.Diag{};
        var prog = try rill.parse(gpa, &b.reg, "caster", src, &diag);
        errdefer prog.deinit();
        b.caster = .{ .prog = prog, .rt = undefined };
        b.caster.?.rt = try rill.Runtime.mount(gpa, &b.caster.?.prog, b.door.asPlane(), .{});
    }

    fn unmountCaster(b: *FieldBench) void {
        const c = &(b.caster orelse return);
        c.rt.deinit();
        c.prog.deinit();
        b.caster = null;
    }

    /// One fed tick for everything: the store's clock, the caster, the spray.
    fn tick(b: *FieldBench, frame: u64, time_ns: u64) !void {
        b.fields.tick(time_ns);
        if (b.caster) |*c| try c.rt.tick(.{ .frame = frame, .time_ns = time_ns });
        try b.spray.tick(.{ .frame = frame, .time_ns = time_ns }, null, b.mock.asPlane());
    }
};

test "lattice: a deposit rasterises to the engine's kernel at the grid points, quantised once" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    try b.fields.declare(.{ .name = "$t", .default_decay_ns = 0 });
    b.spray.samples = &.{.{ .channel = "$t", .cell = fixed.ONE }};
    try b.fields.deposit("caster", "$t", .{ 0, 0, 0 }, 2, 4, null, "");
    try b.tick(0, 0);
    const l = b.spray.lattice("$t").?;
    try testing.expect(l.live);
    // No rows: the box is the spawn point padded by a cell — three points an axis.
    try testing.expectEqual([3]u32{ 3, 3, 3 }, l.dims);
    try testing.expectEqual(fixed.Vec{ -fixed.ONE, -fixed.ONE, -fixed.ONE }, l.origin);
    // At the caster, k = 1 ⇒ 2.0; one cell out, q = 1 − 1/16 ⇒ 2·q² = 1.7578125, exact in Q16.16.
    try testing.expectEqual(fixed.fromInt(2), l.at(1, 1, 1));
    try testing.expectEqual(@as(Fixed, 115200), l.at(2, 1, 1));
    try testing.expectEqual(@as(Fixed, 115200), l.at(1, 0, 1));
    try testing.expectEqual(fixed.fromInt(2), l.sampleAt(.{ 0, 0, 0 }));
    // The gradient at the caster is zero; one cell out it points back.
    try testing.expectEqual(fixed.Vec{ 0, 0, 0 }, l.gradientAt(.{ 0, 0, 0 }));
    try testing.expect(l.gradientAt(.{ fixed.ONE, 0, 0 })[0] < 0);
    try testing.expectEqual(@as(u32, 0), b.spray.last.bags_missing);
}

test "hear: a kernel reads the value and the gradient of the spray's lattice at the row" {
    // Mutation: `hear` answers zero; every assertion below fails.
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    try b.fields.declare(.{ .name = "$t", .default_decay_ns = 0 });
    b.spray.samples = &.{.{ .channel = "$t", .cell = fixed.ONE }};
    try b.fields.deposit("caster", "$t", .{ 1, 0, 0 }, 2, 4, null, "");
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("$t at row.pos | write row.u0\n$t grad at row.pos | .x | write row.u1\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // one row, at the spray's origin, one cell from the caster
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    try testing.expectEqual(@as(Fixed, 115200), b.spray.pop.userOf(0)[0]);
    try testing.expect(b.spray.pop.userOf(0)[1] > 0); // uphill is +x, toward the caster
}

test "hear: refused at mount for a channel the spray does not sample, or a spray with no fields; bare $chan is a parse error" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    var diag = rill.registry.Detail{};
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "$fog at row.pos | write row.u0", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "does not sample $fog") != null);
    try testing.expect(std.mem.indexOf(u8, diag.text(), "samples $fog cell") != null);
    try testing.expectError(error.Parse, b.spray.mountKernel(&b.reg, "k", "$fog | write row.u0", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "'$fog at row.pos'") != null);
    b.spray.fields = null;
    b.spray.samples = &.{.{ .channel = "$fog", .cell = fixed.ONE }};
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "$fog at row.pos | write row.u0", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "no field store") != null);
}

test "hear: a channel the host never declared leaves the lattice dead, and the read refuses per row by name" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.samples = &.{.{ .channel = "$ghost", .cell = fixed.ONE }};
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 100 * std.time.ns_per_s };
    try b.mount("$ghost at row.pos | write row.u0\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 1), b.spray.last.bags_missing);
    try testing.expectEqual(@as(u32, 1), b.spray.last.refusals);
    try testing.expect(std.mem.indexOf(u8, b.spray.last_refusal.text(), "no such channel") != null);
}

test "coupling: a deposit `to #tag` reaches a spray only while it carries the tag" {
    // Mutation: drop the `hears` filter at rasterisation; the uncoupled spray reads the field too.
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    try b.fields.declare(.{ .name = "$alarm", .default_decay_ns = 0 });
    b.spray.samples = &.{.{ .channel = "$alarm", .cell = fixed.ONE }};
    try b.fields.deposit("caster", "$alarm", .{ 0, 0, 0 }, 1, 4, null, "#garrison");
    try b.tick(0, 0);
    try testing.expectEqual(@as(Fixed, 0), b.spray.lattice("$alarm").?.sampleAt(.{ 0, 0, 0 }));
    b.spray.carried = &.{"#garrison"};
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(fixed.ONE, b.spray.lattice("$alarm").?.sampleAt(.{ 0, 0, 0 }));
    b.spray.carried = &.{"#raiders"};
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(Fixed, 0), b.spray.lattice("$alarm").?.sampleAt(.{ 0, 0, 0 }));
}

// ---------------------------------------------------------------------------
// G3 — fields in. A spray that samples `$wind` bends; unmount the caster and
// the trail straightens within the deposit's decay. Mutation: disable
// sampling in the kernel; the trail is straight from tick 0 and the gate
// fails.
// ---------------------------------------------------------------------------

test "G3: the smoke leans away from the wind's source, and straightens once the caster is gone and its deposit has decayed" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 256, 9);
    defer b.deinit(gpa);
    // ε = 0.01, τ = 1 s: a deposit of 8 is culled at ln(800) ≈ 6.68 s.
    try b.fields.declare(.{ .name = "$wind", .epsilon = 0.01, .default_decay_ns = std.time.ns_per_s });
    b.spray.samples = &.{.{ .channel = "$wind", .cell = fixed.HALF }};
    b.spray.knobs = .{ .rate = fixed.fromInt(4), .speed = fixed.fromInt(1), .spread = 0, .life_ns = 30 * std.time.ns_per_s };
    // Rows rise straight up at 1 cell/s; the wind blows from x = −3.
    try b.mount("spawn\n$wind grad at row.pos | mul -1 | write row.vel add\nperish\n");
    try b.mountCaster(gpa, "every 1f | cast $wind 8 radius 6 at {x: -3, y: 0, z: 0}");

    var t: u64 = 0;
    while (t <= 4) : (t += 1) try b.tick(t, t * std.time.ns_per_s / 4);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    // Every row born under the wind leans downwind: +x velocity, all of them.
    var leaning: u32 = 0;
    var id: u32 = 0;
    while (id < b.spray.pop.capacity) : (id += 1) {
        if (!b.spray.pop.alive[id]) continue;
        try testing.expect(b.spray.pop.vel[0][id] > 0);
        leaning += 1;
    }
    try testing.expect(leaning >= 3);
    const born_under_wind = b.spray.spawned;

    // The caster is unmounted at 1 s. Its deposit decays from there and is
    // culled at 1 + ln(800) ≈ 7.68 s. Between those a row born under the
    // dying wind still leans by a hair (168/65536 of a cell per second was
    // the first draft's finding — a real lean from a nearly dead deposit,
    // not a bug), so "straight" means born after the cull: age ≤ 2 s at 10 s
    // (a row ages on its birth tick, so eight rows, ticks 33–40).
    b.unmountCaster();
    while (t <= 40) : (t += 1) try b.tick(t, t * std.time.ns_per_s / 4);
    try testing.expectEqual(@as(usize, 0), b.fields.depositCount("$wind"));
    // Rows born after the cull go straight up: vel.x is exactly zero.
    var straight: u32 = 0;
    var bent: u32 = 0;
    id = 0;
    while (id < b.spray.pop.capacity) : (id += 1) {
        if (!b.spray.pop.alive[id]) continue;
        if (b.spray.pop.age_ns[id] <= 2 * std.time.ns_per_s) {
            try testing.expectEqual(@as(Fixed, 0), b.spray.pop.vel[0][id]);
            straight += 1;
        } else if (b.spray.pop.vel[0][id] > 0) bent += 1;
    }
    try testing.expect(straight >= 8);
    try testing.expect(bent >= 3); // the old rows keep the lean they got
    try testing.expect(b.spray.spawned > born_under_wind);
}

// ---------------------------------------------------------------------------
// G4 — fields out. A smoke spray casts `$dankness`; an ear downstream reads
// above zero; the spray unmounts and the ear reads zero (casts are owned by
// their caster — ownership is the ceiling). Mutation: remove the cast; the
// ear never rises.
// ---------------------------------------------------------------------------

test "G4: the smoke makes the room dank — one aggregate per tick, replaced, and withdrawn with the spray" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 64, 3);
    defer b.deinit(gpa);
    try b.fields.declare(.{ .name = "$dankness", .epsilon = 0.001, .default_decay_ns = 2 * std.time.ns_per_s });
    b.spray.name = "smoke";
    b.spray.casts = &.{.{ .channel = "$dankness", .per_row_amplitude = 0.05, .radius = .bounds }};
    b.spray.knobs = .{ .rate = fixed.fromInt(8), .speed = fixed.fromInt(1), .spread = fixed.HALF, .life_ns = 4 * std.time.ns_per_s };
    try b.mount("spawn\nperish\n");
    const ear = [3]f32{ 0, 1, 0 };
    try testing.expectEqual(@as(f32, 0), b.fields.sample("$dankness", ear, true, &.{}).?.value);
    var t: u64 = 0;
    while (t <= 12) : (t += 1) try b.tick(t, t * std.time.ns_per_s / 4);
    try testing.expectEqual(@as(u32, 0), b.spray.last.cast_refusals);
    // ONE deposit, whatever the rows did — the aggregate is replaced, never trailed.
    try testing.expectEqual(@as(usize, 1), b.fields.depositCount("$dankness"));
    const reading = b.fields.sample("$dankness", ear, true, &.{}).?;
    try testing.expect(reading.value > 0);
    // amplitude = per-row × live, exactly
    try testing.expectApproxEqAbs(@as(f32, 0.05) * @as(f32, @floatFromInt(b.spray.pop.live)), b.fields.deposits.items[0].amplitude, 1e-5);
    // Unmount: the bag goes with its owner, and the ear reads zero at once.
    try b.spray.unmount(b.mock.asPlane());
    try testing.expectEqual(@as(usize, 0), b.fields.depositCount("$dankness"));
    try testing.expectEqual(@as(f32, 0), b.fields.sample("$dankness", ear, true, &.{}).?.value);
}

test "G4: an undeclared channel refuses the cast, counted, and the sim is unchanged" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 8, 3);
    defer b.deinit(gpa);
    b.spray.casts = &.{.{ .channel = "$nothing", .per_row_amplitude = 1 }};
    b.spray.knobs = .{ .rate = fixed.fromInt(4), .life_ns = 10 * std.time.ns_per_s };
    try b.mount("spawn\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 1), b.spray.last.cast_refusals);
    try testing.expectEqual(@as(u32, 1), b.fields.refused);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
}

test "G0 with a field: same script, same wind, same bytes — the lattice is re-derived, not remembered" {
    const gpa = testing.allocator;
    var dumps: [2][]u8 = undefined;
    for (&dumps) |*d| {
        const b = try FieldBench.init(gpa, 128, 11);
        defer b.deinit(gpa);
        try b.fields.declare(.{ .name = "$wind", .default_decay_ns = std.time.ns_per_s });
        b.spray.samples = &.{.{ .channel = "$wind", .cell = fixed.HALF }};
        b.spray.knobs = .{ .rate = fixed.fromInt(6), .speed = fixed.fromInt(1), .spread = fixed.HALF, .life_ns = 3 * std.time.ns_per_s };
        try b.mount("spawn\n$wind grad at row.pos | mul -2 | write row.vel add\nperish\n");
        try b.mountCaster(gpa, "every 1f | cast $wind 5 radius 4 at {x: -2, y: 1, z: 0}");
        var t: u64 = 0;
        while (t <= 24) : (t += 1) try b.tick(t, t * std.time.ns_per_s / 8);
        try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
        d.* = try dump.write(gpa, &b.spray.pop, b.spray.ticks);
    }
    defer for (dumps) |d| gpa.free(d);
    try testing.expectEqualSlices(u8, dumps[0], dumps[1]);
}

test "smoke.rill: the shipped kernel parses and mounts on a spray that samples $wind" {
    const gpa = testing.allocator;
    const b = try FieldBench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    try b.fields.declare(.{ .name = "$wind" });
    b.spray.samples = &.{.{ .channel = "$wind", .cell = fixed.HALF }};
    try b.mount(smoke);
    try testing.expectEqual(@as(usize, 6), b.spray.kernel.?.prog.nodeCount());
}

test "dirty chunks: a chunk is dirty on every tick a live row was swept in it — born, moving, or dying — and quiet otherwise" {
    // Mutation: the sweep's mark dropped; nothing is ever dirty and the
    // renderer never uploads. The tick that reaps a chunk's last row must
    // be dirty (the ghost) and the next quiet (the upload that never ends).
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 64, 1);
    defer b.deinit(gpa);
    b.spray.chunk = 16; // four chunks
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .life_ns = std.time.ns_per_s };
    try b.mount("perish\n");
    try b.tick(0, 0);
    try testing.expectEqualSlices(bool, &.{ false, false, false, false }, b.spray.dirtyChunks());
    try b.tick(1, std.time.ns_per_s / 2); // row 0 born in chunk 0
    try testing.expectEqualSlices(bool, &.{ true, false, false, false }, b.spray.dirtyChunks());
    b.spray.knobs.rate = 0;
    try b.tick(2, std.time.ns_per_s); // swept
    try testing.expectEqualSlices(bool, &.{ true, false, false, false }, b.spray.dirtyChunks());
    try b.tick(3, 3 * std.time.ns_per_s / 2); // reaped at age 1 s — swept then killed: still dirty
    try testing.expectEqual(@as(u32, 1), b.spray.last.died);
    try testing.expectEqualSlices(bool, &.{ true, false, false, false }, b.spray.dirtyChunks());
    try b.tick(4, 2 * std.time.ns_per_s); // nothing left: quiet
    try testing.expectEqualSlices(bool, &.{ false, false, false, false }, b.spray.dirtyChunks());
}

// ---------------------------------------------------------------------------
// Beat 3 — `over`, and `coarsened` on the plane.
// ---------------------------------------------------------------------------

test "over: a value over normalised life is piecewise linear over the knots, exact, numbers and Oklab colours alike" {
    // Mutation: the segment index never advances (always knots[0..1]); the
    // second half of life reads the first segment.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 4 * std.time.ns_per_s };
    try b.mount(
        \\row.age | over row.life [1, 0.5, 0] | write row.size
        \\row.age | over row.life [{l: 1, a: 0, b: 0}, {l: 0, a: 0.5, b: -0.5}] | write row.colour
    );
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // born: age 0 at the sweep
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    try testing.expectEqual(fixed.ONE, b.spray.pop.size[0]);
    try testing.expectEqual([3]Fixed{ fixed.ONE, 0, 0 }, .{ b.spray.pop.colour[0][0], b.spray.pop.colour[1][0], b.spray.pop.colour[2][0] });
    b.spray.knobs.rate = 0;
    try b.tick(2, 2 * std.time.ns_per_s); // age 1 s of 4: t = 0.25 → first segment, halfway: 0.75
    try testing.expectEqual(fixed.ONE / 4 * 3, b.spray.pop.size[0]);
    try b.tick(3, 3 * std.time.ns_per_s); // t = 0.5 → the middle knot exactly
    try testing.expectEqual(fixed.HALF, b.spray.pop.size[0]);
    try testing.expectEqual([3]Fixed{ fixed.HALF, fixed.ONE / 4, -fixed.ONE / 4 }, .{ b.spray.pop.colour[0][0], b.spray.pop.colour[1][0], b.spray.pop.colour[2][0] });
    try b.tick(4, 4 * std.time.ns_per_s); // t = 0.75 → second segment, halfway: 0.25
    try testing.expectEqual(fixed.ONE / 4, b.spray.pop.size[0]);
    try b.tick(5, 5 * std.time.ns_per_s); // t = 1 → the last knot; past life it stays there
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.size[0]);
    try b.tick(6, 6 * std.time.ns_per_s);
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.size[0]);
}

test "over: refuses a life of zero by name, and a live element in the curve at mount" {
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    var diag = rill.registry.Detail{};
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "row.age | over row.life [row.size, 1] | write row.size", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "an array on the row is a literal") != null);
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 0 };
    try b.mount("row.age | over row.life [1, 0] | write row.size\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 1), b.spray.last.refusals);
    // rill's `over` (core since 23ac55c) refuses a zero span by port name.
    try testing.expect(std.mem.indexOf(u8, b.spray.last_refusal.text(), "is zero") != null);
}

test "coarsened: said on the plane, change-only, the worst over the sampled channels, zero when the declared cell held, and a coarsened run replays byte-identical" {
    // Mutation: publish every tick — the change-only assertion fails.
    // Mutation: publish the LAST lattice's doublings, not the worst — with
    // the fine channel first and a coarse one that holds second, "last"
    // says zero. (The first draft had one channel, so last and worst were
    // the same lattice and the mutation survived: A equalled B.)
    const gpa = testing.allocator;
    var dumps: [2][]u8 = undefined;
    for (&dumps) |*d| {
        const b = try FieldBench.init(gpa, 256, 5);
        defer b.deinit(gpa);
        try b.fields.declare(.{ .name = "$wind", .default_decay_ns = 0 });
        try b.fields.declare(.{ .name = "$fog", .default_decay_ns = 0 });
        // A cell of 1/16: thirty-three points cover two cells, and a spray
        // spreading four cells wide must double the cell — twice. The fog's
        // cell of 4 holds whatever the spray does.
        b.spray.samples = &.{ .{ .channel = "$wind", .cell = fixed.ONE / 16 }, .{ .channel = "$fog", .cell = fixed.fromInt(4) } };
        b.spray.knobs = .{ .rate = fixed.fromInt(16), .speed = fixed.fromInt(2), .spread = fixed.fromInt(2), .life_ns = 4 * std.time.ns_per_s };
        try b.fields.deposit("caster", "$wind", .{ 0, 0, 0 }, 1, 8, null, "");
        try b.mount("spawn\n$wind at row.pos | write row.u0\nperish\n");
        try b.tick(0, 0);
        try testing.expectEqual(@as(f64, 0), rill.types.asNumber(b.mock.store.get("plane.drift.@em.coarsened").?).?); // nothing spread yet: held
        var t: u64 = 1;
        while (t <= 8) : (t += 1) try b.tick(t, t * std.time.ns_per_s / 4);
        try testing.expect(b.spray.coarsened() >= 2);
        try testing.expectEqual(@as(u8, 0), b.spray.lattice("$fog").?.coarsened); // the coarse one held…
        try testing.expect(b.spray.lattice("$wind").?.coarsened >= 2); // …the fine one doubled, and the plane says the worst
        try testing.expectEqual(@as(f64, @floatFromInt(b.spray.coarsened())), rill.types.asNumber(b.mock.store.get("plane.drift.@em.coarsened").?).?);
        // Change-only: two quiet ticks at the same coarsening write nothing more.
        var writes: usize = 0;
        for (b.mock.writes.items) |w| {
            if (std.mem.eql(u8, w.path, "plane.drift.@em.coarsened")) writes += 1;
        }
        try testing.expect(writes >= 2 and writes <= 4);
        d.* = try dump.write(gpa, &b.spray.pop, b.spray.ticks);
    }
    defer for (dumps) |d| gpa.free(d);
    try testing.expectEqualSlices(u8, dumps[0], dumps[1]);
}

test "over: the curve may be a broadcast the applet edits — converted once per change, followed next tick, a scalar refused by name" {
    // Mutation: the array cast is not re-converted when the bytes change;
    // the second curve is never seen.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 2 * std.time.ns_per_s };
    try b.mock.putValue("plane.drift.@em.size_curve", [_]f64{ 1, 0 });
    try b.mount("row.age | over row.life plane.drift.@self.size_curve | write row.size\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // born, t = 0
    b.spray.knobs.rate = 0;
    try b.tick(2, 2 * std.time.ns_per_s); // t = 0.5 on [1, 0] → 0.5
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    try testing.expectEqual(fixed.HALF, b.spray.pop.size[0]);
    try testing.expectEqual(@as(usize, 1), b.spray.array_casts.items.len);
    // The applet drags the curve: [1, 0] → [1, 1] — halfway is now 1.
    try b.mock.putValue("plane.drift.@em.size_curve", [_]f64{ 1, 1 });
    b.spray.pop.age_ns[0] = std.time.ns_per_s; // hold t at 0.5 for the read
    try b.tick(3, 3 * std.time.ns_per_s);
    try testing.expectEqual(fixed.ONE, b.spray.pop.size[0]);
    try testing.expectEqual(@as(usize, 1), b.spray.array_casts.items.len); // replaced, not accumulated
    // A number where a curve should be: the row refuses, by name.
    try b.mock.putValue("plane.drift.@em.size_curve", @as(f64, 3));
    try b.tick(4, 4 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 1), b.spray.last.refusals);
    try testing.expect(std.mem.indexOf(u8, b.spray.last_refusal.text(), "wants an array, got a number") != null);
}

// ---------------------------------------------------------------------------
// Beat 4 — the tracer words, and the budget. `collide`/`ground`/`stick` are
// the host's words: `registerTracer` is what a host with a World calls.
// ---------------------------------------------------------------------------

/// A registry with the core, the drift words AND the tracer words — a host
/// that has a World, as drift-run and the engine do.
fn tracerRegistry(gpa: std.mem.Allocator) !rill.Registry {
    var reg = try registry(gpa);
    errdefer reg.deinit();
    try words.registerTracer(&reg);
    return reg;
}

test "collide | stick: a falling row lands on the floor — position the hit point, velocity zero, stuck set — and still ages and reads its curve" {
    // Mutation: `stick` leaves the velocity; the row falls through next tick.
    // Mutation: `collide` tests last tick's segment; the row lands one tick late, below the floor.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    var floor = spindrift.Floor{};
    var spray = try Spray.init(gpa, 4, 1, floor.asWorld());
    defer spray.deinit();
    // Born at y = 3, falling at 2 cells/s: the segment 3 → 1 misses, 1 → −1 hits at t = 0.5, y = 0.
    spray.pos = .{ 0, fixed.fromInt(3), 0 };
    spray.aim = .{ 0, -fixed.ONE, 0 };
    spray.knobs = .{ .rate = fixed.fromInt(1), .speed = fixed.fromInt(2), .life_ns = 10 * std.time.ns_per_s };
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k",
        \\spawn
        \\collide | stick
        \\row.age | over row.life [0.5, 0] | write row.size
        \\perish
    , &diag);
    try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
    try spray.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, mock.asPlane()); // born, launched down at 2, moved to y = 1
    spray.knobs.rate = 0;
    try testing.expectEqual(fixed.fromInt(1), spray.pop.pos[1][0]);
    try testing.expectEqual(@as(u8, 0), spray.pop.stuck[0]);
    // Ruling 27b: the row's position is the CONTACT point, and the contact
    // normal is stored on the row (zero until it lands); the resting offset
    // — drawn at pos + normal · size — is the appearance's, gated in the
    // engine. Mutation: `stick` stores no normal (up expected, zero found);
    // `stick` offsets pos by the radius (y = 0.5, not 0).
    try testing.expectEqual(fixed.Vec{ 0, 0, 0 }, fixed.Vec{ spray.pop.normal[0][0], spray.pop.normal[1][0], spray.pop.normal[2][0] });
    try spray.tick(.{ .frame = 2, .time_ns = 2 * std.time.ns_per_s }, null, mock.asPlane()); // 1 → −1 would cross: lands ON the floor
    try testing.expectEqual(@as(u32, 0), spray.last.refusals);
    try testing.expectEqual(@as(Fixed, 0), spray.pop.pos[1][0]);
    try testing.expectEqual(@as(Fixed, 0), spray.pop.vel[1][0]);
    try testing.expectEqual(@as(u8, 1), spray.pop.stuck[0]);
    try testing.expectEqual(fixed.Vec{ 0, fixed.ONE, 0 }, fixed.Vec{ spray.pop.normal[0][0], spray.pop.normal[1][0], spray.pop.normal[2][0] });
    // Stuck: it stays ON the surface as it shrinks — no re-rest anywhere;
    // the appearance keeps the shrinking disc tangent by construction.
    const size_at_landing = spray.pop.size[0];
    try spray.tick(.{ .frame = 3, .time_ns = 3 * std.time.ns_per_s }, null, mock.asPlane());
    try testing.expectEqual(@as(Fixed, 0), spray.pop.pos[1][0]);
    try testing.expectEqual(3 * std.time.ns_per_s, spray.pop.age_ns[0]);
    try testing.expect(spray.pop.size[0] < size_at_landing);
    try testing.expectEqual(fixed.fromInt(1), spray.pop.asRowPlane().read(0, spindrift.population.F_STUCK).scalar);
}

test "ground: the nearest surface below, distance and normal, and nothing over no world" {
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    var floor = spindrift.Floor{ .y = fixed.fromInt(1) };
    var spray = try Spray.init(gpa, 4, 1, floor.asWorld());
    defer spray.deinit();
    spray.pos = .{ 0, fixed.fromInt(4), 0 };
    spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 10 * std.time.ns_per_s };
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k", "ground | write row.u0\nground as d, n\nn | .y | write row.u1\n", &diag);
    try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, null);
    try spray.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, null);
    try testing.expectEqual(fixed.fromInt(3), spray.pop.userOf(0)[0]);
    try testing.expectEqual(fixed.ONE, spray.pop.userOf(0)[1]);
    // No world: the flow is quiet, not zero.
    var nowhere = spindrift.Nowhere{};
    var spray2 = try Spray.init(gpa, 4, 1, nowhere.asWorld());
    defer spray2.deinit();
    spray2.knobs = spray.knobs;
    try spray2.mountKernel(&reg, "k", "ground | write row.u0\n", &diag);
    spray2.pop.userOf(0)[0] = 7; // pre-set, so silence is distinguishable from a zero
    try spray2.tick(.{ .frame = 0, .time_ns = 0 }, null, null);
    try spray2.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, null);
    try testing.expectEqual(@as(u32, 0), spray2.last.refusals);
    try testing.expectEqual(@as(Fixed, 0), spray2.pop.userOf(0)[0]); // a spawn re-zeroes; the flow never wrote
}

test "the tracer words are the host's: a kernel naming one on a host without a World is refused at mount by name" {
    const gpa = testing.allocator;
    var reg = try registry(gpa); // core + drift words, no tracer
    defer reg.deinit();
    var nowhere = spindrift.Nowhere{};
    var spray = try Spray.init(gpa, 4, 1, nowhere.asWorld());
    defer spray.deinit();
    var diag = rill.registry.Detail{};
    try testing.expectError(error.Parse, spray.mountKernel(&reg, "k", "collide | stick\n", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "'collide'") != null);
}

test "negative control, flipped: with `collide | stick` the floor and no world now DISAGREE — the ledger's negative control has its caller" {
    const gpa = testing.allocator;
    var dumps: [2]?[]u8 = .{ null, null };
    defer for (dumps) |d| if (d) |bytes| gpa.free(bytes);
    const worlds = [_]bool{ true, false };
    for (worlds, &dumps) |with_floor, *d| {
        var reg = try tracerRegistry(gpa);
        defer reg.deinit();
        var floor = spindrift.Floor{};
        var nowhere = spindrift.Nowhere{};
        var spray = try Spray.init(gpa, 64, 7, if (with_floor) floor.asWorld() else nowhere.asWorld());
        defer spray.deinit();
        spray.pos = .{ 0, fixed.fromInt(2), 0 };
        spray.knobs = .{ .rate = fixed.fromInt(8), .speed = fixed.fromInt(1), .spread = fixed.HALF, .life_ns = 4 * std.time.ns_per_s };
        var diag = rill.registry.Detail{};
        try spray.mountKernel(&reg, "k", "spawn\ngravity -10\ncollide | stick\nperish\n", &diag);
        var t: u32 = 0;
        while (t <= 20) : (t += 1) try spray.tick(.{ .frame = t, .time_ns = @as(u64, t) * std.time.ns_per_s / 4 }, null, null);
        try testing.expectEqual(@as(u32, 0), spray.last.refusals);
        d.* = try dump.write(gpa, &spray.pop, spray.ticks);
        if (with_floor) {
            var stuck: u32 = 0;
            var id: u32 = 0;
            while (id < spray.pop.capacity) : (id += 1) {
                if (spray.pop.alive[id] and spray.pop.stuck[id] == 1) {
                    stuck += 1;
                    // Landed rows stay ON the floor — the first draft's
                    // gravity sank them 2.5 cells a tick after landing.
                    // ON the floor (ruling 27b: the contact is the position);
                    // the contact normal stored, up.
                    try testing.expectEqual(@as(Fixed, 0), spray.pop.pos[1][id]);
                    try testing.expectEqual(fixed.ONE, spray.pop.normal[1][id]);
                    try testing.expectEqual(@as(Fixed, 0), spray.pop.vel[1][id]);
                }
            }
            try testing.expect(stuck > 0);
        }
    }
    try testing.expect(!std.mem.eql(u8, dumps[0].?, dumps[1].?));
}

// ---------------------------------------------------------------------------
// G6 — budget, not clock. Two sprays, one budget in row-steps read from
// the plane, the scheduler deciding by fed inputs; a burst over budget
// produces `throttled` as a mailbox occurrence, the tick replays
// byte-identically, and a coarsened-and-throttled run replays too.
// Mutation: a wall-clock read in the priority; two runs differ.
// ---------------------------------------------------------------------------

/// `said` hashes every write the two sprays made on the plane — path,
/// bytes, kind — in order. The replay gate compares it as well as the
/// dumps: a wall-clock read that leaked into the `throttled` payload
/// (staleness) survived the dump-only gate, because the order of the
/// ticks did not change, only what the sim SAID about them (beat 4).
const BudgetRun = struct { a: []u8, b: []u8, throttled_a: usize, throttled_b: usize, coarsened: u32, said: u64 };

fn budgetRun(gpa: std.mem.Allocator, budget: u32, with_field: bool) !BudgetRun {
    var reg = try registry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    try mock.putValue("plane.drift.budget.row_steps", @as(i64, budget));
    var store = spindrift.MockFields.init(gpa);
    defer store.deinit();
    try store.declare(.{ .name = "$wind", .default_decay_ns = 0 });
    try store.deposit("caster", "$wind", .{ 0, 0, 0 }, 1, 8, null, "");
    var nowhere = spindrift.Nowhere{};
    var a = try Spray.init(gpa, 512, 1, nowhere.asWorld());
    defer a.deinit();
    a.name = "a";
    a.knobs = .{ .rate = fixed.fromInt(200), .speed = fixed.fromInt(2), .spread = fixed.fromInt(2), .life_ns = 2 * std.time.ns_per_s };
    if (with_field) {
        a.fields = store.asFields();
        a.samples = &.{.{ .channel = "$wind", .cell = fixed.ONE / 16 }};
    }
    var b = try Spray.init(gpa, 64, 2, nowhere.asWorld());
    defer b.deinit();
    b.name = "b";
    b.knobs = .{ .rate = fixed.fromInt(8), .speed = fixed.ONE, .life_ns = 3 * std.time.ns_per_s };
    var diag = rill.registry.Detail{};
    try a.mountKernel(&reg, "k", if (with_field) "spawn\n$wind at row.pos | write row.u0\nperish\n" else "spawn\nperish\n", &diag);
    try b.mountKernel(&reg, "k", "spawn\nperish\n", &diag);

    const sprays = [_]*Spray{ &a, &b };
    var coarsened: u32 = 0;
    var t: u64 = 0;
    while (t <= 24) : (t += 1) {
        const now = rill.Now{ .frame = t, .time_ns = t * std.time.ns_per_s / 8 };
        // The knob, read once per tick — the only budget the sim knows.
        const knob: u32 = @intFromFloat(rill.types.asNumber(mock.store.get("plane.drift.budget.row_steps").?).?);
        var cands: [2]spindrift.scheduler.Candidate = undefined;
        for (sprays, 0..) |s, i| cands[i] = .{ .rows = s.pop.live, .priority = .{ .staleness = s.staleness } };
        var runs: [2]bool = undefined;
        var order: [2]u32 = undefined;
        _ = spindrift.scheduler.plan(&cands, knob, &runs, &order);
        for (sprays, runs) |s, go| {
            if (go) try s.tick(now, null, mock.asPlane()) else try s.carryOver(mock.asPlane());
        }
        coarsened = @max(coarsened, a.coarsened());
    }
    var ta: usize = 0;
    var tb: usize = 0;
    var said = std.hash.Wyhash.init(0);
    for (mock.writes.items) |w| {
        said.update(w.path);
        said.update(w.value);
        said.update(@tagName(w.kind));
        if (w.kind != .occurrence) continue;
        if (std.mem.eql(u8, w.path, "plane.drift.@a.throttled")) ta += 1;
        if (std.mem.eql(u8, w.path, "plane.drift.@b.throttled")) tb += 1;
    }
    return .{ .a = try dump.write(gpa, &a.pop, a.ticks), .b = try dump.write(gpa, &b.pop, b.ticks), .throttled_a = ta, .throttled_b = tb, .coarsened = coarsened, .said = said.final() };
}

test "G6: a burst over the budget throttles, as a mailbox occurrence, and the tick replays byte-identically" {
    const gpa = testing.allocator;
    const r1 = try budgetRun(gpa, 40, false);
    defer gpa.free(r1.a);
    defer gpa.free(r1.b);
    const r2 = try budgetRun(gpa, 40, false);
    defer gpa.free(r2.a);
    defer gpa.free(r2.b);
    // 200 rows/s at 8 ticks/s is 25 rows a tick into `a`; `b` is small.
    // Once `a` is over the budget it is carried over and `b` runs, then
    // `a`'s staleness puts it first — both get ticks, both get throttled.
    try testing.expect(r1.throttled_a > 0);
    try testing.expect(r1.throttled_b > 0);
    try testing.expectEqualSlices(u8, r1.a, r2.a);
    try testing.expectEqualSlices(u8, r1.b, r2.b);
    try testing.expectEqual(r1.throttled_a, r2.throttled_a);
    try testing.expectEqual(r1.said, r2.said);
    // The gate can fail: a budget for everything throttles nobody and the
    // populations differ from the throttled run's.
    const r3 = try budgetRun(gpa, 100_000, false);
    defer gpa.free(r3.a);
    defer gpa.free(r3.b);
    try testing.expectEqual(@as(usize, 0), r3.throttled_a + r3.throttled_b);
    try testing.expect(!std.mem.eql(u8, r1.a, r3.a));
}

test "G6: a coarsened-and-throttled run replays too" {
    const gpa = testing.allocator;
    const r1 = try budgetRun(gpa, 40, true);
    defer gpa.free(r1.a);
    defer gpa.free(r1.b);
    const r2 = try budgetRun(gpa, 40, true);
    defer gpa.free(r2.a);
    defer gpa.free(r2.b);
    try testing.expect(r1.coarsened > 0);
    try testing.expect(r1.throttled_a > 0);
    try testing.expectEqualSlices(u8, r1.a, r2.a);
    try testing.expectEqualSlices(u8, r1.b, r2.b);
    try testing.expectEqual(r1.said, r2.said);
}

test "staleness is carry-overs since the spray last ran: the occurrence carries it, and a tick resets it" {
    // Mutation: `tick` does not reset staleness — survived G6, because a
    // spray that only ever grows staler still runs in the same order.
    const gpa = testing.allocator;
    var reg = try registry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    var nowhere = spindrift.Nowhere{};
    var spray = try Spray.init(gpa, 8, 1, nowhere.asWorld());
    defer spray.deinit();
    spray.name = "s";
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k", "spawn\nperish\n", &diag);
    try spray.carryOver(mock.asPlane());
    try spray.carryOver(mock.asPlane());
    try testing.expectEqual(@as(u64, 2), spray.staleness);
    try testing.expect(spray.last.carried_over);
    try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
    try testing.expectEqual(@as(u64, 0), spray.staleness);
    try testing.expect(!spray.last.carried_over);
    try spray.carryOver(mock.asPlane());
    try testing.expectEqual(@as(u64, 1), spray.staleness);
    // The three occurrences said 1, 2, 1 — the count since it last ran.
    var seen: [3]i64 = undefined;
    var n: usize = 0;
    for (mock.writes.items) |w| {
        if (w.kind != .occurrence or !std.mem.eql(u8, w.path, "plane.drift.@s.throttled")) continue;
        try testing.expect(n < 3);
        seen[n] = @intFromFloat(rill.types.asNumber(w.value).?);
        n += 1;
    }
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqual([3]i64{ 1, 2, 1 }, seen);
}

test "dump: `stuck` and `normal` ride, format 3" {
    const gpa = testing.allocator;
    var p = try spindrift.Population.init(gpa, 2);
    defer p.deinit();
    _ = p.spawn().?;
    _ = p.spawn().?; // a second, unstuck row — the dump carries LIVE rows only
    p.stuck[0] = 1;
    p.normal[1][0] = fixed.ONE;
    const bytes = try dump.write(gpa, &p, 0);
    defer gpa.free(bytes);
    const s = try dump.readSummary(gpa, bytes);
    defer gpa.free(s.ids);
    try testing.expectEqual(@as(i64, 3), s.fmt);
    // The VALUES, not the keys: a dump writing zero for `normal` kept the
    // key and survived a substring check.
    const stuck = try dump.column(gpa, bytes, "stuck");
    defer gpa.free(stuck);
    const nrm_y = try dump.column(gpa, bytes, "nrm_y");
    defer gpa.free(nrm_y);
    try testing.expectEqual(@as(i64, 1), stuck[0]);
    try testing.expectEqual(@as(i64, fixed.ONE), nrm_y[0]);
    try testing.expectEqual(@as(i64, 0), nrm_y[1]);
}

test "normal: zero on every unstuck row, and zero again on a reused slot" {
    // Mutation: `clearRow` leaves `normal` — a row born into a slot that had
    // landed carries the old contact normal, and the appearance would draw
    // it a radius off its position.
    var pop = try spindrift.population.Population.init(testing.allocator, 2);
    defer pop.deinit();
    const id = pop.spawn().?;
    pop.asRowPlane().write(id, spindrift.population.F_NORMAL, .{ .vec3 = .{ 0, fixed.ONE, 0 } });
    try testing.expectEqual(fixed.ONE, pop.normal[1][id]);
    pop.kill(id);
    const again = pop.spawn().?;
    try testing.expectEqual(id, again);
    try testing.expectEqual(@as(Fixed, 0), pop.normal[1][again]);
}
