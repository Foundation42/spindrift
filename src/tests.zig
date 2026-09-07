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
    kernel: []const u8 = "spawn\ngravity plane.drift.@self.k.gravity\nperish\n",
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
    try mock.putValue("plane.drift.@em.k.gravity", fixed.toF64(try fixed.parseDecimal(s.gravity)));
    var floor = spindrift.Floor{};
    var spray = try Spray.init(gpa, s.capacity, s.seed, floor.asWorld());
    defer spray.deinit();
    spray.knobs = s.knobs;
    spray.setChunk(s.chunk); // the gate's scale is load-bearing; say it, do not assign it
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
    try b.mount("gravity plane.drift.@self.k.gravity\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // two rows, no knob yet: quiet, vel 0
    try testing.expectEqual(@as(Fixed, 0), b.spray.pop.vel[1][0]);
    try b.mock.putValue("plane.drift.@sparks.k.gravity", @as(i64, -2));
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(-fixed.fromInt(2), b.spray.pop.vel[1][0]);
    try testing.expectEqual(-fixed.fromInt(2), b.spray.pop.vel[1][3]);
    // A knob under another name is somebody else's.
    try b.mock.putValue("plane.drift.@em.k.gravity", @as(i64, -50));
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
    try b.mock.putValue("plane.drift.@em.k.gravity", @as(i64, -1));
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
    try mock.putValue("plane.drift.@em.k.gravity", fixed.toF64(try fixed.parseDecimal(s.gravity)));
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
const fire = @embedFile("fire.rill");
const hearth = @embedFile("hearth.rill");

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




test "knob rooms: a kernel's own knob in the SPRAY's room is refused at mount by name, and the spray's own four are still readable" {
    // The bug this is paid for (2026-09-07): `plane.drift.@self.spread`
    // named as a kernel's own spreading rate silently retuned the launch
    // cone to 0.013 cells/s. Nothing was wrong with either party — the
    // spray re-reads its knobs from the plane every tick because that is
    // the host's documented interface (`write plane.drift.@sparks.rate`),
    // and a kernel reads broadcasts from the same room. One path, two
    // owners. The mount line printed the 1.6 the flag asked for and every
    // row went straight up in a pencil, green.
    //
    // Mutation: the guard dropped — the flat `@self.cool` mounts happily
    // and we are back to a kernel able to retune the spray by naming.
    // Mutation: `SPRAY_KNOBS` emptied — `@self.speed`, a legitimate read
    // of the spray's own knob, starts refusing.
    const gpa = testing.allocator;
    const cases = [_]struct { src: []const u8, mounts: bool }{
        // A kernel's own knob, in its own room.
        .{ .src = "gravity plane.drift.@self.k.gravity\n", .mounts = true },
        // The same knob flat: refused. `gravity` was never a SPRAY knob —
        // only a kernel one that drift-run seeded flat, which is the whole
        // confusion in miniature.
        .{ .src = "gravity plane.drift.@self.gravity\n", .mounts = false },
        // One of the spray's own four, read by a kernel: allowed, because
        // that is what they are for.
        .{ .src = "gravity plane.drift.@self.speed\n", .mounts = true },
        // The spray's own @name is the same room as @self.
        .{ .src = "gravity plane.drift.@em.cool\n", .mounts = false },
        // Somebody else's room is not ours to police.
        .{ .src = "gravity plane.drift.@other.cool\n", .mounts = true },
        // Nor is the rest of the plane.
        .{ .src = "gravity plane.ui.cool\n", .mounts = true },
    };
    for (cases) |c| {
        const b = try Bench.init(gpa, 4, 1);
        defer b.deinit(gpa);
        b.spray.name = "em";
        var diag = rill.registry.Detail{};
        const got = b.spray.mountKernel(&b.reg, "k", c.src, &diag);
        if (c.mounts) {
            got catch |err| {
                std.debug.print("'{s}' should mount, refused: {s}\n", .{ c.src, diag.text() });
                return err;
            };
        } else {
            try testing.expectError(error.Mount, got);
            // By NAME, and it says where to put it — a refusal that does not
            // name the path is a refusal nobody can act on.
            try testing.expect(std.mem.indexOf(u8, diag.text(), ".k.") != null);
        }
    }
}

test "slide: the contact's normal leaves the velocity — what is left is the tangent, and the row is on the surface" {
    // `slide` cannot be gated on a floor: there gravity is entirely normal,
    // so the tangent a slide leaves is the velocity the row already had and
    // a kernel that did NOTHING would pass. A wall separates them, and
    // n = (1, 0, 0) is exact in Q16.16, so this gate is equalities.
    //
    // Mutation: the correction added with the wrong sign — the normal
    // component doubles instead of leaving (vel.x −4, not 0).
    // Mutation: the whole velocity scaled instead of the normal part — the
    // tangent moves, and it is asserted here for exactly that reason.
    // Mutation: `pos ← at` dropped — the row is through the wall at −2.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    var wall = spindrift.Plane{ .n = .{ fixed.ONE, 0, 0 }, .d = 0 };
    var spray = try Spray.init(gpa, 4, 1, wall.asWorld());
    defer spray.deinit();
    // Thrown at the wall from x = 2 and falling: (−2, −1, 0) cells/s.
    spray.pos = .{ fixed.fromInt(2), fixed.fromInt(4), 0 };
    spray.aim = .{ -fixed.ONE, -fixed.HALF, 0 };
    spray.knobs = .{ .rate = fixed.fromInt(1), .speed = fixed.fromInt(2), .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k", "spawn\ncollide | slide\n", &diag);
    try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
    try spray.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, mock.asPlane());
    spray.knobs.rate = 0;
    // Born and launched; the move ends ON the plane, which is not a crossing.
    try testing.expectEqual(@as(Fixed, 0), spray.pop.pos[0][0]);
    try testing.expectEqual(-fixed.fromInt(2), spray.pop.vel[0][0]);
    try spray.tick(.{ .frame = 2, .time_ns = 2 * std.time.ns_per_s }, null, mock.asPlane());
    try testing.expectEqual(@as(u32, 0), spray.last.refusals);
    // The normal component is gone, EXACTLY, and the tangent is untouched.
    try testing.expectEqual(@as(Fixed, 0), spray.pop.vel[0][0]);
    try testing.expectEqual(-fixed.ONE, spray.pop.vel[1][0]);
    // And the row is on the wall, not through it.
    try testing.expectEqual(@as(Fixed, 0), spray.pop.pos[0][0]);
    try testing.expectEqual(fixed.Vec{ fixed.ONE, 0, 0 }, fixed.Vec{ spray.pop.normal[0][0], spray.pop.normal[1][0], spray.pop.normal[2][0] });
}

test "slide: it SUBTRACTS, so what it leaves still accelerates — a row on a slope gains speed and the same row on a floor does not" {
    // The add-versus-replace decision, which is the whole design and which
    // no equality gate can see. A replace would land the snapshot's tangent
    // over the top of `gravity`'s add — queued from an earlier node — and
    // the row would slide at a constant speed for ever.
    //
    // Mutation: `write row.vel` replace instead of add — the slope's row
    // stops gaining and the two worlds agree, which is the bug exactly.
    // Mutation: the correction dropped altogether — the row goes through
    // the slope and the floor's control gains speed too.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    // A 3-4-5 slope and a flat floor, run identically. The slope's normal
    // is unit to within a Q16.16 ulp, so this gate asserts ORDER, not
    // equalities — the claim is "gains speed", not "gains this much".
    var worlds = [2]spindrift.Plane{
        .{ .n = .{ -fixed.fromRatio(6, 10), fixed.fromRatio(8, 10), 0 }, .d = 0 },
        .{ .n = .{ 0, fixed.ONE, 0 }, .d = 0 },
    };
    var speeds: [2][6]Fixed = undefined;
    for (&worlds, 0..) |*w, i| {
        var mock = rill.MockPlane.init(gpa);
        defer mock.deinit();
        var spray = try Spray.init(gpa, 4, 1, w.asWorld());
        defer spray.deinit();
        spray.pos = .{ 0, fixed.fromInt(2), 0 };
        // Four a second at a quarter-second tick is exactly one row on tick
        // 1 — the rate is per SECOND and the tick is not, and the first cut
        // of this gate zeroed a 1/s rate before a quarter of a row had been
        // born. It asserted over a population of none and failed loudly,
        // which is the only reason it is not still doing that quietly.
        spray.knobs = .{ .rate = fixed.fromInt(4), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        var diag = rill.registry.Detail{};
        try spray.mountKernel(&reg, "k", "spawn\ngravity -2\ncollide | slide\n", &diag);
        try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
        var t: u64 = 1;
        while (t <= 14) : (t += 1) {
            try spray.tick(.{ .frame = t, .time_ns = t * std.time.ns_per_s / 4 }, null, mock.asPlane());
            if (t == 1) {
                try testing.expectEqual(@as(u32, 1), spray.pop.live);
                spray.knobs.rate = 0;
            }
            if (t >= 9) speeds[i][t - 9] = @intCast(@abs(spray.pop.vel[0][0])); // the ACROSS-slope speed
        }
        try testing.expectEqual(@as(u32, 1), spray.pop.live);
        try testing.expectEqual(@as(u32, 0), spray.last.refusals);
    }
    // On the slope the row runs downhill and gains on EVERY tick; on the
    // floor gravity is entirely normal and there is nothing left to
    // accelerate it. Every tick is the point, not the endpoints: the first
    // cut of this gate sampled three and the replace mutation SURVIVED it,
    // because a replace still gains — in stair-steps, on the ticks where
    // the row happens to sink far enough for a real crossing rather than a
    // resume (−1.44, −1.44, −1.44, −1.44, −1.68, −1.68 against a clean
    // −1.44, −1.68, −1.92, …). Three samples straddled a step and the gate
    // could not tell the two apart. Strict monotonicity over six can: a
    // plateau is exactly what a replace has and a subtraction has not.
    for (1..speeds[0].len) |k| try testing.expect(speeds[0][k - 1] < speeds[0][k]);
    // And it is not merely increasing, it is increasing BY THE SAME AMOUNT
    // — the tangential gravity times dt, once a tick, which is what "the
    // rest still accelerates" means. A stair-step fails this before it
    // fails monotonicity.
    // Within ONE ulp, not equal: the step is the tangential gravity times
    // dt = 0.24 cells/s, which is 15728.64 in Q16.16, so the rounding lands
    // 15729 once and 15728 after. One ulp is the honest tolerance and it
    // gives nothing away — a stair-step's plateau is a step of ZERO, which
    // is 15728 ulps out, and its jump is twice the step.
    const step = speeds[0][1] - speeds[0][0];
    for (1..speeds[0].len) |k| try testing.expect(@abs((speeds[0][k] - speeds[0][k - 1]) - step) <= 1);
    // The flat control never moves sideways at all.
    for (speeds[1]) |s| try testing.expectEqual(@as(Fixed, 0), s);
}

test "relax: the step is the FED delta's — double the tick, double the step, exactly" {
    // The reason `relax` is a word rather than three core ops. `(1 − x)·rate`
    // is spellable without it, but only PER TICK; this is the claim that the
    // rate is per SECOND, and it is exact in Q16.16 rather than approximate,
    // because the step is linear in dt even though the relaxation is not.
    //
    // Mutation: the `· dt` dropped from the step — both ticks move the same
    // and the word is per-tick again, which is the bug it was built to end.
    // Mutation: `k` formed as rate·rate, or the gap taken as `x − target` —
    // the halves stop being halves.
    const gpa = testing.allocator;
    var moved: [2]Fixed = undefined;
    // Both runs share tick 1 exactly; only the SECOND tick's fed delta
    // differs, so the difference in what moved is the difference in dt.
    for ([2]u64{ std.time.ns_per_s, std.time.ns_per_s / 2 }, 0..) |second_dt, i| {
        const b = try Bench.init(gpa, 4, 1);
        defer b.deinit(gpa);
        b.spray.knobs = .{ .rate = fixed.fromInt(1), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        try b.mount("row.u0 | relax 1 0.5 | write row.u0 add\n");
        try b.tick(0, 0);
        try b.tick(1, std.time.ns_per_s); // born; one second fed, so u0 = 0.5
        b.spray.knobs.rate = 0;
        const before = b.spray.pop.userOf(0)[0];
        try testing.expectEqual(fixed.HALF, before);
        try b.tick(2, std.time.ns_per_s + second_dt);
        try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
        moved[i] = b.spray.pop.userOf(0)[0] - before;
    }
    // Half the tick, half the step — and the numbers themselves, so a
    // mutation cannot pass by making both zero.
    try testing.expectEqual(fixed.ONE / 4, moved[0]);
    try testing.expectEqual(fixed.ONE / 8, moved[1]);
    try testing.expectEqual(moved[0], moved[1] * 2);
}

test "relax: a rate that walks away from the target, or that closes more than the whole gap in a tick, refuses by name" {
    // Loud, never a guess. Both are rates that do the OPPOSITE of the word:
    // a negative one diverges, and one past the gap steps over the target.
    // Mutation: either guard dropped — the refusal count stays 0 and the
    // channel sails past 1 (or away from it) with the picture still moving.
    const gpa = testing.allocator;
    const cases = [_]struct { src: []const u8, refuses: bool }{
        .{ .src = "row.u0 | relax 1 0.5 | write row.u0 add\n", .refuses = false }, // the control
        .{ .src = "row.u0 | relax 1 -0.5 | write row.u0 add\n", .refuses = true }, // away
        .{ .src = "row.u0 | relax 1 4 | write row.u0 add\n", .refuses = true }, // 4 · 1s = four gaps
    };
    for (cases) |c| {
        const b = try Bench.init(gpa, 4, 1);
        defer b.deinit(gpa);
        b.spray.knobs = .{ .rate = fixed.fromInt(1), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        try b.mount(c.src);
        try b.tick(0, 0);
        try b.tick(1, std.time.ns_per_s);
        if (c.refuses) {
            try testing.expect(b.spray.last.refusals > 0);
            try testing.expectEqual(@as(Fixed, 0), b.spray.pop.userOf(0)[0]); // and nothing landed
        } else {
            try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
        }
    }
    // The same rate that refuses at a one-second tick is fine at 16 ms:
    // the guard is on the STEP, which is the fed delta's business.
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("row.u0 | relax 1 4 | write row.u0 add\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s / 64);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
}




test "near/push: a row leans away from the rows around it, a row alone does not move, and the list rides the slate" {
    // The slate's HANDLE lane, and the customer that forced it: a list of
    // row ids is the one thing a row value cannot hold — the row plane's
    // arrays are literal-only and no operator emits one. So `near` says a
    // pointer into the spray's per-chunk buffer and `push` reads it, both
    // inside one row's evaluation, which is the only window in which that
    // pointer means anything.
    //
    // Mutation: `near` publishes no handle — `push` is quiet and nothing moves.
    // Mutation: `gatherNear` counts the row itself — the count is 2, not 1.
    // Mutation: the neighbourhood not rebuilt — every count is 0.
    // Mutation: `push` reads the row's own position twice (offset 0) — no push.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(3), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.9 | write row.u0\npush 5\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 3), b.spray.pop.live);
    b.spray.knobs.rate = 0;
    // Two within the radius, one well outside it. Set AFTER the spawn, so
    // the next tick's grid is built over exactly these.
    const p = &b.spray.pop;
    // 0.5 is exact in Q16.16; 0.4 is 26214.4 and floors, which made the first
    // cut of this gate expect a round number the arithmetic never produces.
    inline for (.{ 0, 1, 2 }, .{ 0, fixed.HALF, fixed.fromInt(5) }) |id, x| {
        p.pos[0][id] = x;
        p.pos[1][id] = 0;
        p.pos[2][id] = 0;
        inline for (0..3) |a| p.vel[a][id] = 0;
    }
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // Each of the near pair sees exactly ONE neighbour — itself excluded.
    try testing.expectEqual(fixed.ONE, p.userOf(0)[0]);
    try testing.expectEqual(fixed.ONE, p.userOf(1)[0]);
    try testing.expectEqual(@as(Fixed, 0), p.userOf(2)[0]);
    // And they lean apart, exactly: half a cell of offset, k = 5, dt = 1 s.
    try testing.expectEqual(-fixed.fromRatio(5, 2), p.vel[0][0]);
    try testing.expectEqual(fixed.fromRatio(5, 2), p.vel[0][1]);
    // The lone row is not pushed by anything, and `push` wrote nothing at all.
    try testing.expectEqual(@as(Fixed, 0), p.vel[0][2]);
}




test "near: the cap STOPS the scan, and the capped answer is the uncapped one's prefix" {
    // Paid for by the tick that made the cap worth thinking about: 2482 rows
    // sitting inside ONE cell cost 39 ms a tick, and 97.5% of that was
    // `gatherNear` walking the whole cell for every row to throw away
    // everything past the 64th. `near` hands on the first `MAX_NEIGHBOURS`
    // and reports the CAPPED count, so a row found past the cap was already
    // being discarded — stopping there is the same answer for a fortieth of
    // the work. This gate says "the same answer" out loud, because that claim
    // is the whole licence for the early-out.
    //
    // Three groups, because one crowd in one cell cannot tell these apart —
    // the first cut of this gate put all 100 rows on one spot and TWO of its
    // four mutations walked straight through it:
    //   ids  0– 9  x = 0.75, cell 0 — inside the visited cells, OUTSIDE the
    //              reach, and scanned FIRST, so a lost distance test shows
    //   ids 10–59  x = -0.25, cell -1 — a second populated cell, so the order
    //              the 27 are visited in decides which 64 survive the cap
    //   ids 60–99  x = 0, cell 0 — the crowd itself
    //
    // Mutation: the early-out fires one row early (`n + 1 >= out.len`) — the
    //   capped run returns 63 and stops being the uncapped run's prefix.
    // Mutation: the distance test dropped — ids 0–9 are 0.75 away with a
    //   reach of 0.5 and get counted, and they are scanned before the cap
    //   fills, so the count moves.
    // Mutation: `crowded` left false on the early-out — a truncated
    //   neighbourhood goes unsaid, which is the one thing a cap must not do.
    // Mutation: the 27 cells visited in the other order — still 64 rows, but
    //   no longer the SAME 64. Deliberate: which 64 a crowd hands on is a
    //   picture, not an implementation detail, and it may not drift in silence.
    const gpa = testing.allocator;
    const cap = spindrift.spray.MAX_NEIGHBOURS; // 64
    const b = try Bench.init(gpa, 128, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(100), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.5 | write row.u0\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 100), b.spray.pop.live);
    b.spray.knobs.rate = 0;

    // Every value exact in Q16.16 — 0.9 is not, and an inexact reach is how a
    // boundary gate ends up asserting a number the arithmetic never produces.
    const p = &b.spray.pop;
    var id: u32 = 0;
    while (id < 100) : (id += 1) {
        p.pos[0][id] = if (id < 10) fixed.fromRatio(3, 4) else if (id < 60) -fixed.fromRatio(1, 4) else 0;
        p.pos[1][id] = 0;
        p.pos[2][id] = 0;
        inline for (0..3) |a| p.vel[a][id] = 0;
    }
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // The far ten see only each other: nine, uncrowded, and NOT the ninety
    // rows a quarter- and three-quarter-cell away. The other ninety are over
    // the cap and report the cap, not their true size.
    id = 0;
    while (id < 100) : (id += 1) {
        const want: i32 = if (id < 10) 9 else @intCast(cap);
        try testing.expectEqual(fixed.fromInt(want), p.userOf(id)[0]);
    }
    // Ninety rows were truncated and the spray SAID so — once each.
    try testing.expectEqual(@as(u32, 90), b.spray.last.crowded);

    // And the claim itself: what a capped buffer returns is exactly what an
    // uncapped one returns, cut short. The same query twice over the same
    // snapshot, once with room for everybody. Row 60 sits in the crowd and
    // reaches into both populated cells, so its 64 are drawn from two.
    var big: [128]u32 = undefined;
    var small: [cap]u32 = undefined;
    const whole = b.spray.gatherNear(60, fixed.HALF, &big);
    const cut = b.spray.gatherNear(60, fixed.HALF, &small);
    try testing.expectEqual(@as(u32, 89), whole.n); // 50 in cell -1, 39 in cell 0, itself excluded
    try testing.expect(!whole.crowded);
    try testing.expectEqual(cap, cut.n);
    try testing.expect(cut.crowded);
    try testing.expectEqualSlices(u32, big[0..cap], small[0..cap]);

    // Which 64, exactly. The prefix check above is only self-consistent — run
    // the 27 cells in the other order and both halves move together, so it
    // sees nothing. This is the absolute claim, and it locks all three things
    // that decide the picture: the cells are walked -1 → +1 on each axis (so
    // cell -1's fifty are met before the home cell's), a bucket is scattered
    // in ascending row id, and the cap cuts the tail off. Row 60 skips itself
    // and the ten too far away, and stops fourteen into its own cell.
    var want: [cap]u32 = undefined;
    for (0..50) |i| want[i] = @intCast(10 + i); // cell -1, ids 10–59
    for (0..14) |i| want[50 + i] = @intCast(61 + i); // home cell, ids 61–74
    try testing.expectEqualSlices(u32, &want, small[0..cap]);
}




test "align: a row steers toward the MEAN velocity of its neighbours, and a row alone steers nowhere" {
    // The flocking trio completed. Separation was `push` and cohesion is the
    // same word with a negative gain (no sign guard, deliberately — the
    // arithmetic is the same and only the direction differs), so alignment is
    // the one that needed the neighbourhood to carry VELOCITY.
    //
    // Four rows on a line, `near 0.9`, three of them in reach of each other:
    //
    //     id 0        id 3        id 1                    id 2
    //     x = 0       x = 0.25    x = 0.5                 x = 5
    //     v = +1      v = +3      v = -1                  v = +1
    //
    // The numbers are chosen so the MEAN and the MAXIMUM disagree, as
    // `infect`'s are — but the other way round: row 1 sees +1 and +3, so a
    // mean steers it by (2 - -1)*0.25 = 0.75 and a maximum by 1. One fast row
    // must not drag the flock, which is why this word takes the mean and
    // `infect` does not.
    //
    // Mutation: the neighbours' MAXIMUM instead of their mean — row 1 lands
    //   on 0 rather than -0.25.
    // Mutation: the row's own velocity read from the population instead of
    //   the snapshot — the sweep has integrated the rows swept before this
    //   one, so the answer depends on chunk order; the symmetry below is what
    //   a half-updated world destroys.
    // Mutation: `mine` left out of the difference (steer toward the mean
    //   rather than by the gap) — row 0 moves when it should not.
    // Mutation: the empty-handle return dropped — the lone row divides by
    //   zero, or steers by the sum of nothing.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(4), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.9 | write row.u3\nalign 0.25\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
    b.spray.knobs.rate = 0;

    const p = &b.spray.pop;
    inline for (.{ 0, 3, 1, 2 }, .{ 0, fixed.fromRatio(1, 4), fixed.HALF, fixed.fromInt(5) }, .{ 1, 3, -1, 1 }) |id, x, vx| {
        p.pos[0][id] = x;
        p.pos[1][id] = 0;
        p.pos[2][id] = 0;
        p.vel[0][id] = fixed.fromInt(vx);
        p.vel[1][id] = 0;
        p.vel[2][id] = 0;
    }
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // Row 1 sees +1 and +3: mean 2, a quarter of the gap from -1 is +0.75.
    try testing.expectEqual(-fixed.fromRatio(1, 4), p.vel[0][1]);
    // Row 3 sees +1 and -1: mean 0, a quarter of the gap from +3 is -0.75.
    try testing.expectEqual(fixed.fromRatio(9, 4), p.vel[0][3]);
    // Row 0 sees +3 and -1: mean 1, which is what it already had. It is the
    // row that must NOT move, and the one a missing `- mine` moves.
    try testing.expectEqual(fixed.fromInt(1), p.vel[0][0]);
    // And the row out of reach agrees with nobody.
    try testing.expectEqual(fixed.fromInt(1), p.vel[0][2]);
    // Nothing steered off the line it was on.
    inline for (.{ 0, 1, 2, 3 }) |id| {
        try testing.expectEqual(@as(Fixed, 0), p.vel[1][id]);
        try testing.expectEqual(@as(Fixed, 0), p.vel[2][id]);
    }
}




test "align: refuses a negative gain and a gain that would steer past the average" {
    // `relax`'s two guards, and the first is the word's meaning: steering
    // AGAINST the neighbours is a different behaviour and has no word yet.
    // Mutation: either guard dropped — the matching case stops refusing.
    const gpa = testing.allocator;
    const cases = [_]struct { src: []const u8, want: []const u8 }{
        .{ .src = "near 0.9 | write row.u3\nalign -1\n", .want = "steers a row AGAINST" },
        .{ .src = "near 0.9 | write row.u3\nalign 4\n", .want = "more than the whole difference" },
    };
    for (cases) |c| {
        const b = try Bench.init(gpa, 4, 1);
        defer b.deinit(gpa);
        b.spray.knobs = .{ .rate = fixed.fromInt(1), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        try b.mount(c.src);
        try b.tick(0, 0);
        try b.tick(1, std.time.ns_per_s);
        try testing.expect(b.spray.last.refusals > 0);
        if (std.mem.indexOf(u8, b.spray.last_refusal.text(), c.want) == null) {
            std.debug.print("align refusal did not say '{s}': {s}\n", .{ c.want, b.spray.last_refusal.text() });
            return error.TestUnexpectedResult;
        }
    }
}




test "infect: a channel spreads from the neighbour that has MOST of it, and never the other way" {
    // funideas §6, the thirteenth word: "transfer a state variable between
    // neighbours. Now you've got spreading fire, bioluminescence, chemical
    // reactions, disease, magic, whatever."
    //
    // Four rows on a line, `near 0.9`, one of them alight:
    //
    //     id 0        id 3     id 1                    id 2
    //     x = 0       x = 0.25 x = 0.5                 x = 5
    //     u0 = 1      u0 = 0   u0 = 0                  u0 = 0
    //     <---------- in reach of each other --------> out of reach
    //
    // The numbers are chosen so the MEAN and the MAXIMUM disagree: row 1 sees
    // a 1 and a 0, so a mean would pull it to 0.25 in one tick at rate 0.5
    // and a maximum pulls it to 0.5. Diffusion and transmission are different
    // words, and this gate is the difference.
    //
    // Mutation: the neighbours' MEAN instead of their maximum — row 1 reads
    //   0.25, which is the smear this word exists not to be.
    // Mutation: the monotone rule dropped — the SOURCE catches its
    //   neighbours' zero and dims, and the front eats itself from behind.
    //   It takes BOTH halves to show it: `best` is seeded with the row's own
    //   value AND the write is skipped when nothing beats it, so either one
    //   alone still holds the line and neither alone is a mutation. Written
    //   down because a reader tidying one of them away would find the gate
    //   still green.
    // Mutation: `.replace` instead of `.add` — row 1 lands on the step
    //   itself, which is the same number on the first tick and 0.25 rather
    //   than 0.75 on the second. Two ticks are why this gate takes two.
    // Mutation: the row's own value read from the population instead of the
    //   snapshot — no bite, and recorded as no bite: nothing has written this
    //   row's channel when its kernel runs, so the two are the same number.
    //   It reads the snapshot so both sides of the comparison come from one
    //   place.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(4), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.9 | write row.u3\ninfect row.u0 0.5\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 4), b.spray.pop.live);
    b.spray.knobs.rate = 0;

    const p = &b.spray.pop;
    inline for (.{ 0, 3, 1, 2 }, .{ 0, fixed.fromRatio(1, 4), fixed.HALF, fixed.fromInt(5) }) |id, x| {
        p.pos[0][id] = x;
        p.pos[1][id] = 0;
        p.pos[2][id] = 0;
        inline for (0..3) |a| p.vel[a][id] = 0;
    }
    p.userOf(0)[0] = fixed.ONE; // the one alight
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // Half the gap to the MAXIMUM in reach, in one second at rate 0.5.
    try testing.expectEqual(fixed.HALF, p.userOf(1)[0]);
    try testing.expectEqual(fixed.HALF, p.userOf(3)[0]);
    // The source does not dim: nobody near it has more.
    try testing.expectEqual(fixed.ONE, p.userOf(0)[0]);
    // And nothing reaches the row out of reach.
    try testing.expectEqual(@as(Fixed, 0), p.userOf(2)[0]);

    // A second tick: half of what is LEFT, which is 0.75 — and 0.25 if the
    // step replaced the value instead of adding to it.
    try b.tick(3, 3 * std.time.ns_per_s);
    try testing.expectEqual(fixed.fromRatio(3, 4), p.userOf(1)[0]);
    try testing.expectEqual(fixed.ONE, p.userOf(0)[0]);
    try testing.expectEqual(@as(Fixed, 0), p.userOf(2)[0]);
}




test "infect: refuses a channel that is not the row's own, a negative rate, and a rate that would overshoot" {
    // The same three guards `relax` and `sync` carry, and the middle one is
    // the word's meaning rather than its arithmetic: a row cannot catch LESS
    // of a thing. Recovery is a separate fact with its own rate.
    //
    // Mutation: any of the three guards dropped — the matching case stops
    //   refusing, and the overshoot one leaves a row holding MORE than the
    //   neighbour it caught it from, which is a front outrunning its source.
    const gpa = testing.allocator;
    const cases = [_]struct { src: []const u8, want: []const u8 }{
        .{ .src = "near 0.9 | write row.u3\ninfect row.size 1\n", .want = "only a user channel" },
        .{ .src = "near 0.9 | write row.u3\ninfect row.u0 -1\n", .want = "recovery is `relax 0" },
        .{ .src = "near 0.9 | write row.u3\ninfect row.u0 4\n", .want = "more than the whole gap" },
    };
    for (cases) |c| {
        const b = try Bench.init(gpa, 4, 1);
        defer b.deinit(gpa);
        b.spray.knobs = .{ .rate = fixed.fromInt(1), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        try b.mount(c.src);
        try b.tick(0, 0);
        try b.tick(1, std.time.ns_per_s);
        try testing.expect(b.spray.last.refusals > 0);
        if (std.mem.indexOf(u8, b.spray.last_refusal.text(), c.want) == null) {
            std.debug.print("infect refusal did not say '{s}': {s}\n", .{ c.want, b.spray.last_refusal.text() });
            return error.TestUnexpectedResult;
        }
    }
}




test "appearance: a spray SAYS what its coordinate channels mean, once, and a channel it has not got is refused when set" {
    // The contract a host bridges (Christian, 2026-09-07: "Matryoshka can
    // provide the bridge as long as the contract is there"). Spindrift
    // declares the seam and evaluates NOTHING — `manifold` is a name the
    // host resolves, the way `World` and `Fields` are already filled by a
    // host and by a mock here. No dependency travels either way.
    //
    // Until this, what `row.u0`–`u2` MEANT lived in a comment, and that is
    // exactly how the fire manifold got authored upside down with every
    // number still in range.
    //
    // Mutation: `said_appearance` never set — the declaration is re-said on
    // every tick, so a host watching for changes sees a change that is not
    // one, every frame, for ever.
    // Mutation: `check` dropped — a coordinate naming a channel the
    // population has not got is accepted, and the host reads a number
    // nobody wrote.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);

    // Says nothing until there is something to say: a spray whose rows mean
    // nothing in particular must not publish a default a host could read as
    // a promise.
    try b.tick(0, 0);
    try testing.expect(b.mock.store.get("plane.drift.@em.appearance") == null);

    try b.spray.setAppearance(.{ .coord = .{ 0, 1, 2 }, .manifold = "fire" });
    try b.tick(1, std.time.ns_per_s);
    const said = b.mock.store.get("plane.drift.@em.appearance") orelse return error.TestUnexpectedResult;
    // The host reads a name and three channel indices; spindrift resolves
    // neither and evaluates neither.
    try testing.expect(std.mem.indexOf(u8, said, "fire") != null);
    try testing.expect(std.mem.indexOf(u8, said, "manifold") != null);

    // A DECLARATION changes when a host changes it and not otherwise. A
    // re-write would replace the stored bytes, so the same allocation still
    // being there is the claim — and it costs nothing, where clearing the
    // store to look leaks what the store owns (which is how this gate first
    // failed).
    try b.tick(2, 2 * std.time.ns_per_s);
    const again = b.mock.store.get("plane.drift.@em.appearance").?;
    try testing.expectEqual(said.ptr, again.ptr);

    // Setting it again IS a change, and is said again.
    try b.spray.setAppearance(.{ .coord = .{ 3, 1, 2 }, .manifold = "soot" });
    try b.tick(3, 3 * std.time.ns_per_s);
    const third = b.mock.store.get("plane.drift.@em.appearance").?;
    try testing.expect(std.mem.indexOf(u8, third, "soot") != null);

    // And a channel this population has not got is refused at the door.
    try testing.expectError(error.BadAppearance, b.spray.setAppearance(.{ .coord = .{ 0, 1, spindrift.population.USER_CHANNELS }, .manifold = "x" }));
}

test "sync: two coupled rows meet at their mean exactly, an uncoupled pair does not move, and the phase wraps" {
    // funideas §6's `synchronise`, and the thing a field of them does is
    // travelling waves. The claim gated here is the single step, because
    // that is what can be asserted exactly: half the coupling closes half
    // the gap, from both ends, so the pair lands on the MEAN.
    //
    // Mutation: neighbours' phases read live instead of from the snapshot —
    // row 0 moves first, row 1 then sees the moved one, and the pair no
    // longer meets. Symmetry is what a half-updated world destroys, and it
    // is the same bug `push` had.
    // Mutation: `wrapHalf` dropped — a pair either side of the wrap sprints
    // the long way round instead of meeting across it.
    // Mutation: the wrap into [0, 1) dropped — the phase walks off past 1.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(2), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.9 | write row.u3\nsync row.u0 row.u1 plane.drift.@self.k.couple\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 2), b.spray.pop.live);
    b.spray.knobs.rate = 0;
    const p = &b.spray.pop;

    // Half a cell apart, phases an eighth and three-eighths — both exact in
    // Q16.16, so the meeting point is exact too. No drift: coupling only.
    const setup = struct {
        fn go(pp: anytype) void {
            pp.pos[0][0] = 0;
            pp.pos[0][1] = fixed.HALF;
            inline for (.{ 1, 2 }) |a| {
                pp.pos[a][0] = 0;
                pp.pos[a][1] = 0;
            }
            pp.userOf(0)[0] = fixed.ONE / 8;
            pp.userOf(1)[0] = 3 * (fixed.ONE / 8);
            pp.userOf(0)[1] = 0;
            pp.userOf(1)[1] = 0;
        }
    }.go;

    setup(p);
    try b.mock.putValue("plane.drift.@em.k.couple", @as(f64, 0.5));
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    // Half the coupling closes half the gap, from both ends: the mean.
    try testing.expectEqual(fixed.ONE / 4, p.userOf(0)[0]);
    try testing.expectEqual(fixed.ONE / 4, p.userOf(1)[0]);

    // Uncoupled, they stay where they were put.
    setup(p);
    try b.mock.putValue("plane.drift.@em.k.couple", @as(f64, 0));
    try b.tick(3, 3 * std.time.ns_per_s);
    try testing.expectEqual(fixed.ONE / 8, p.userOf(0)[0]);
    try testing.expectEqual(3 * (fixed.ONE / 8), p.userOf(1)[0]);

    // Across the wrap, which is the whole reason `wrapHalf` exists: a
    // fifteen-sixteenths and a one-sixteenth are an EIGHTH apart the short
    // way and seven-eighths the long way. They meet at 0 — going forward and
    // backward respectively — and without the wrap they would both trudge to
    // 0.5 instead, which is the mutation.
    setup(p);
    p.userOf(0)[0] = 15 * (fixed.ONE / 16);
    p.userOf(1)[0] = fixed.ONE / 16;
    try b.mock.putValue("plane.drift.@em.k.couple", @as(f64, 0.5));
    // Consecutive ticks: the first cut skipped a frame here and the fed dt
    // was two seconds, so every step doubled and the pair sailed past each
    // other. `relax` and `sync` both scale by the FED delta, which is the
    // point of them, and a gate that changes it by accident is testing a
    // different program.
    try b.tick(4, 4 * std.time.ns_per_s);
    try testing.expectEqual(@as(Fixed, 0), p.userOf(0)[0]);
    try testing.expectEqual(@as(Fixed, 0), p.userOf(1)[0]);

    // And drift advances the phase and wraps it: 0.875 + 0.25 is 0.125.
    setup(p);
    p.userOf(0)[0] = 7 * (fixed.ONE / 8);
    p.userOf(0)[1] = fixed.ONE / 4;
    p.userOf(1)[1] = fixed.ONE / 4;
    try b.mock.putValue("plane.drift.@em.k.couple", @as(f64, 0));
    try b.tick(5, 5 * std.time.ns_per_s);
    try testing.expectEqual(fixed.ONE / 8, p.userOf(0)[0]);
}

test "the neighbourhood at scale: every count is what the geometry says, and the grid actually cuts the rows up" {
    // A 4x4x4 lattice at half-cell spacing. Two mutations survived a
    // three-row scene and needed this one, which is the chunking gate's rule
    // restated: a grid's bugs are invisible until there is a grid.
    //
    // It was a HASH grid until 2026-09-08 and the mutations it was paid for
    // were the hash's — a dropped cell-equality check counting a colliding
    // bucket's rows twice, and a mask of `buckets` instead of `buckets - 1`
    // putting every row in one of two buckets. Neither exists now; a dense
    // cell index cannot collide and there is no mask. What survives is the
    // half that was never about the hash: the COUNT is the geometry's, and
    // the grid has to be doing work for that to mean anything.
    //
    // Mutation: `sizeGrid` never refines (the first cell is kept) — one cell
    //   holds all 64 rows, every count is still right, and every query has
    //   become a scan of the whole population. That is what `cells` catches.
    // Mutation: the x-run ends at `hi[0]` instead of `hi[0] + 1` — the last
    //   cell of every run is missed and the total falls short.
    // Mutation: `cellOf` drops the z stride — rows pile onto the wrong cells
    //   and the total moves.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 128, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(64), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.mount("near 0.6 | write row.u0\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 64), b.spray.pop.live);
    b.spray.knobs.rate = 0;
    const p = &b.spray.pop;
    for (0..64) |i| {
        const id: u32 = @intCast(i);
        p.pos[0][id] = fixed.HALF * @as(Fixed, @intCast(i % 4));
        p.pos[1][id] = fixed.HALF * @as(Fixed, @intCast((i / 4) % 4));
        p.pos[2][id] = fixed.HALF * @as(Fixed, @intCast(i / 16));
    }
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // Neighbours at 0.5 are inside 0.6; the face diagonal at 0.707 is not.
    // A 4x4x4 lattice has 3 x (3 x 4 x 4) = 144 axis-adjacent pairs, and each
    // pair is counted from both ends.
    var total: i64 = 0;
    for (0..64) |i| total += p.userOf(@intCast(i))[0];
    try testing.expectEqual(@as(i64, 288) * fixed.ONE, total);

    // And the grid is doing its job. 64 rows over a 1.5 m lattice, one cell
    // per row allowed: the cell lands fine enough to give a cell per axis
    // step, so every row gets its own and a query walks a handful of them
    // rather than the population. Asserted as a floor, not the exact number,
    // because the exact number is the cell-stepping ratio's business and this
    // gate is about the grid existing.
    try testing.expect(b.spray.cellCount() >= 8);
    var used: u32 = 0;
    for (0..b.spray.cellCount()) |c| {
        if (b.spray.grid_starts[c + 1] > b.spray.grid_starts[c]) used += 1;
    }
    try testing.expect(used >= 8);
    // Nobody was lost or duplicated on the way in: the grid holds the live
    // population exactly once.
    try testing.expectEqual(@as(u32, 64), b.spray.grid_starts[b.spray.cellCount()]);
}

test "near/push: mount refuses a `push` with no `near` above it, and a WIDE radius is answered, not refused" {
    // Both are the slate's rules doing their job on a real pair: a consumer
    // of a name nobody says, and one that reads above the line that says it.
    // Mutation: the handle lane's mount checks dropped — `push` alone mounts
    // and is silently quiet on every row for ever.
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 8, 1);
    defer b.deinit(gpa);
    var diag = rill.registry.Detail{};
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "push 5\n", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "nothing in this program says") != null);
    try testing.expectError(error.Mount, b.spray.mountKernel(&b.reg, "k", "push 5\nnear 0.5 | write row.u0\n", &diag));
    try testing.expect(std.mem.indexOf(u8, diag.text(), "above the line that says it") != null);

    // A radius wider than the grid's cell REFUSED until 2026-09-08, and had
    // to: the search walked a fixed 3x3x3, so a wide radius would have missed
    // rows rather than found them. The range now comes from the radius, so
    // the honest answer is the answer. Three rows a cell and a half apart, a
    // reach of 4: the far one is found, and it is found because the range
    // spans the grid and not because the cell happens to be large.
    //
    // Mutation: the cell range hard-coded back to the row's own cell +/- 1 —
    //   the grid is three cells across, so row 0 misses row 2 and counts one.
    try b.spray.mountKernel(&b.reg, "k", "near 4 | write row.u0\n", &diag);
    b.spray.knobs = .{ .rate = fixed.fromInt(3), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 3), b.spray.pop.live);
    b.spray.knobs.rate = 0;
    const p = &b.spray.pop;
    inline for (.{ 0, 1, 2 }, .{ 0, fixed.fromRatio(3, 2), fixed.fromInt(3) }) |id, x| {
        p.pos[0][id] = x;
        p.pos[1][id] = 0;
        p.pos[2][id] = 0;
        inline for (0..3) |a| p.vel[a][id] = 0;
    }
    try b.tick(2, 2 * std.time.ns_per_s);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    try testing.expect(b.spray.grid_dims[0] >= 3); // the reach really does span cells
    inline for (.{ 0, 1, 2 }) |id| try testing.expectEqual(fixed.fromInt(2), p.userOf(id)[0]);
}

test "slate: `stick` says contact on the landing tick and on no other — the EVENT, where row.stuck is the state" {
    // Why both words say it, and why the two are not the same fact. A landed
    // row has `row.stuck` set for ever after; it made CONTACT once. A kernel
    // that wants the moment — a soot burst on impact, a sound, a spark —
    // cannot get it from the field, and a stuck row stops colliding, so
    // `stick` never runs a second time for one landing.
    //
    // Mutation: `stick`'s publish dropped — u3 stays 0 on the landing tick.
    // Mutation: the slate not blanked per row — u3 stays 1 for ever after,
    // which is `row.stuck` wearing the slate's name and says nothing new.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    var floor = spindrift.Floor{};
    var spray = try Spray.init(gpa, 4, 1, floor.asWorld());
    defer spray.deinit();
    spray.pos = .{ 0, fixed.fromInt(3), 0 };
    spray.aim = .{ 0, -fixed.ONE, 0 };
    spray.knobs = .{ .rate = fixed.fromInt(1), .speed = fixed.fromInt(2), .spread = 0, .life_ns = 100 * std.time.ns_per_s };
    var diag = rill.registry.Detail{};
    try spray.mountKernel(&reg, "k",
        \\spawn
        \\collide | stick
        \\slate.contact | write row.u3
    , &diag);
    try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
    try spray.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, mock.asPlane()); // born at 3, moves to 1
    spray.knobs.rate = 0;
    try testing.expectEqual(@as(Fixed, 0), spray.pop.userOf(0)[3]); // nothing touched yet
    try spray.tick(.{ .frame = 2, .time_ns = 2 * std.time.ns_per_s }, null, mock.asPlane()); // lands
    try testing.expectEqual(@as(u8, 1), spray.pop.stuck[0]);
    try testing.expectEqual(fixed.ONE, spray.pop.userOf(0)[3]); // said, on the tick it happened
    // And on every tick after: still stuck, never touching again. The write
    // is quiet because nothing said anything, so u3 keeps what it had — the
    // gate below clears it first so "quiet" is visible as itself.
    spray.pop.userOf(0)[3] = 0;
    try spray.tick(.{ .frame = 3, .time_ns = 3 * std.time.ns_per_s }, null, mock.asPlane());
    try testing.expectEqual(@as(u8, 1), spray.pop.stuck[0]);
    try testing.expectEqual(@as(Fixed, 0), spray.pop.userOf(0)[3]);
    try testing.expectEqual(@as(u32, 0), spray.last.refusals);
}

test "hearth.rill: a row running down a slope quenches, and row.stuck never once says so" {
    // The slate's customer scene. A sliding row is against the cold thing on
    // every tick and `row.stuck` is 0 the whole time — so the condition the
    // quench lines need exists nowhere in the row, and a field written by
    // `slide` would arrive a tick late and cross a boundary it has no business
    // crossing. `slate.contact` is this tick's and this row's.
    //
    // Same negative control as fire.rill's, one world apart: the SLOPE
    // against Nowhere, one kernel, one seed, one schedule.
    //
    // Mutation: `mul slate.contact` dropped from the plunge line — the quench
    // fires in mid-air too and the two worlds agree.
    // Mutation: `slide`'s `ctx.publish` dropped — nothing ever says contact,
    // the gated lines never fire, and the slope row cools like a falling one.
    // Mutation: the slate not blanked per row — a row that never touched
    // anything quenches on a neighbour's contact.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();
    const knobs = [_]struct { []const u8, f64 }{
        .{ "gravity", -2.0 }, .{ "cool", 0.05 }, .{ "plunge", 2.00 },
        .{ "smoke", 0.03 },   .{ "quench", 1.80 },
        .{ "thin", 0.06 },    .{ "settle", 0.50 },
        .{ "puff", 0.30 },    .{ "grain", 0.06 },
    };
    // A 3-4-5 slope, and no world at all.
    var slope = spindrift.Plane{ .n = .{ -fixed.fromRatio(6, 10), fixed.fromRatio(8, 10), 0 }, .d = 0 };
    var nowhere = spindrift.Nowhere{};
    var u: [2][3]Fixed = undefined;
    var ever_stuck = false;
    for (0..2) |w| {
        var mock = rill.MockPlane.init(gpa);
        defer mock.deinit();
        var buf: [64]u8 = undefined;
        for (knobs) |k| try mock.putValue(try std.fmt.bufPrint(&buf, "plane.drift.@em.k.{s}", .{k[0]}), k[1]);
        var spray = try Spray.init(gpa, 4, 1, if (w == 0) slope.asWorld() else nowhere.asWorld());
        defer spray.deinit();
        spray.pos = .{ 0, fixed.fromInt(2), 0 };
        spray.knobs = .{ .rate = fixed.fromInt(4), .speed = 0, .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        var diag = rill.registry.Detail{};
        spray.mountKernel(&reg, "k", hearth, &diag) catch |err| {
            std.debug.print("hearth.rill refused: {s}\n", .{diag.text()});
            return err;
        };
        try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
        var t: u64 = 1;
        while (t <= 16) : (t += 1) {
            try spray.tick(.{ .frame = t, .time_ns = t * std.time.ns_per_s / 4 }, null, mock.asPlane());
            if (t == 1) {
                try testing.expectEqual(@as(u32, 1), spray.pop.live);
                spray.knobs.rate = 0;
            }
            if (spray.pop.stuck[0] != 0) ever_stuck = true;
        }
        try testing.expectEqual(@as(u32, 0), spray.last.refusals);
        const ch = spray.pop.userOf(0);
        u[w] = .{ ch[0], ch[1], ch[2] };
    }
    const ran = u[0];
    const fell = u[1];

    // The whole point: it quenched hard, and it was never once STUCK.
    try testing.expect(!ever_stuck);
    try testing.expect(ran[0] > fixed.fromRatio(90, 100)); // cooled, against the slope
    try testing.expect(fell[0] < fixed.fromRatio(50, 100));
    try testing.expect(ran[1] > fixed.fromRatio(85, 100)); // sooted, quenched the whole way
    try testing.expect(fell[1] < fixed.fromRatio(40, 100));
    // And held dense, where the falling one blew thin.
    try testing.expect(ran[2] < fell[2]);
}

test "fire.rill: the appearance coordinate is the WORLD's, not the clock's — one kernel, one seed, one schedule, and only the floor differs" {
    // The manifold's customer scene (funideas §9, 2026-09-07). This kernel
    // writes NO colour: it writes a point in an appearance manifold, and
    // what moves that point is what happened to the row. So the claim is
    // not "the numbers change" — an age curve does that. The claim is that
    // the WORLD changes them, and the negative control is world.zig's own,
    // read the other way up: an emitter whose dump is identical over
    // Nowhere and over Floor never asked, so this one's two dumps must
    // DIFFER, and differ in the channels by name.
    //
    // Mutation: the `plunge` line dropped — a landed row cools no faster
    // than a falling one, and `cooled` agrees across the two worlds.
    // Mutation: the `settle` line dropped — `thinned` agrees across them.
    // Mutation: `mul row.stuck` dropped from either — the deflection fires
    // for every row and the two worlds agree again.
    const gpa = testing.allocator;
    var reg = try tracerRegistry(gpa);
    defer reg.deinit();

    // Punchier than the demo's knobs so ten ticks say it plainly; the
    // shapes are the kernel's, not these numbers'.
    const knobs = [_]struct { []const u8, f64 }{
        .{ "cool", 0.05 },  .{ "plunge", 0.40 }, .{ "chill", 0.02 },
        .{ "smoke", 0.03 }, .{ "quench", 0.30 },
        .{ "thin", 0.06 },  .{ "settle", 0.50 }, // a rate toward 0 now, not a negative multiplier
        .{ "puff", 0.30 },  .{ "grain", 0.06 },
    };

    var u: [2][3]Fixed = undefined;
    for (0..2) |w| {
        var mock = rill.MockPlane.init(gpa);
        defer mock.deinit();
        var buf: [64]u8 = undefined;
        for (knobs) |k| try mock.putValue(try std.fmt.bufPrint(&buf, "plane.drift.@em.k.{s}", .{k[0]}), k[1]);
        // The ONLY difference between the two runs.
        var floor = spindrift.Floor{};
        var nowhere = spindrift.Nowhere{};
        var spray = try Spray.init(gpa, 4, 1, if (w == 0) floor.asWorld() else nowhere.asWorld());
        defer spray.deinit();
        // Born at y = 3 heading down at 2 cells/s (the same drop the beat-4
        // `stick` gate uses, and for the same reason: at a one-second tick a
        // row starting at y = 1 is already through the floor before
        // `collide` gets a segment to test). Over the floor it lands on tick
        // 2 and stays; over Nowhere it falls for the whole run.
        spray.pos = .{ 0, fixed.fromInt(3), 0 };
        spray.aim = .{ 0, -fixed.ONE, 0 };
        spray.knobs = .{ .rate = fixed.fromInt(1), .speed = fixed.fromInt(2), .spread = 0, .life_ns = 100 * std.time.ns_per_s };
        var diag = rill.registry.Detail{};
        spray.mountKernel(&reg, "k", fire, &diag) catch |err| {
            std.debug.print("fire.rill refused: {s}\n", .{diag.text()});
            return err;
        };
        try spray.tick(.{ .frame = 0, .time_ns = 0 }, null, mock.asPlane());
        try spray.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null, mock.asPlane());
        spray.knobs.rate = 0; // exactly one row, and it is row 0
        var t: u64 = 2;
        while (t <= 12) : (t += 1) try spray.tick(.{ .frame = t, .time_ns = t * std.time.ns_per_s }, null, mock.asPlane());
        try testing.expectEqual(@as(u32, 0), spray.last.refusals);
        try testing.expectEqual(@as(u8, if (w == 0) 1 else 0), spray.pop.stuck[0]);
        const ch = spray.pop.userOf(0);
        u[w] = .{ ch[0], ch[1], ch[2] };
    }
    const landed = u[0];
    const falling = u[1];

    // Quenched on the plate: cold, black, and DENSE — the three of them,
    // and each for its own reason. A row that never touched anything is
    // still warm, still cleanish, and spreading.
    try testing.expect(landed[0] > fixed.fromRatio(95, 100)); // cooled, plunged
    try testing.expect(falling[0] < fixed.fromRatio(60, 100));
    try testing.expect(landed[1] > fixed.fromRatio(90, 100)); // sooted, quenched
    try testing.expect(falling[1] < fixed.fromRatio(40, 100));
    // `thinned` is the interesting one. The `thin` line is NOT gated on
    // being free — a stuck row keeps spreading and `settle` only BALANCES
    // it — so a landed row does not go to zero, it goes to the fixed point
    // of `u += thin·(1 − u) + settle·u`, which is thin/(thin + |settle|) =
    // 0.06/0.56 = 0.107. Pinning that balance is a stronger claim than
    // "small": the mutation that drops `settle` sends it to ~1 instead.
    // (Gating `thin` on free needs two saturating factors in one flow,
    // which the row cannot spell today — see the ledger.)
    try testing.expect(landed[2] > fixed.fromRatio(8, 100) and landed[2] < fixed.fromRatio(13, 100));
    try testing.expect(falling[2] > fixed.fromRatio(35, 100));

    // And the whole point, in one line: the same program, the same seed and
    // the same clock put the row in two different places in the manifold.
    try testing.expect(landed[0] > falling[0] and landed[1] > falling[1] and landed[2] < falling[2]);
}

test "the chunk is settled at INIT, from the capacity, and a host that says otherwise wins" {
    // The chunk is TWO things wearing one name — the sweep's work-division
    // unit and the dirty-upload unit a host reads — and until 2026-09-08 it
    // was a cache number, 1024, serving only the second. On the fireflies
    // scene that made 2482 rows into 2.4 chunks for THIRTY workers: a tenth
    // of the machine, and why the engine's tick was slower than drift-run's
    // single thread.
    //
    // It is cut from CAPACITY at init, and the "at init" is the load-bearing
    // half. The first cut derived it from the job system's worker count on
    // the FIRST TICK, which is a better number and arrives too late:
    // matryoshka sizes `run_n` from `spray.chunk` when it takes the spray and
    // then skips any spray whose chunk table has since changed length, so the
    // engine ran the sim and drew nothing at all, silently, for 420 frames.
    // A number a host builds on has to be final before the host can read it.
    //
    // Mutation: the lower clamp dropped — a small spray asks for
    //   capacity/256 = 0 rows a chunk and `sizeChunks` divides by it.
    // Mutation: the upper clamp dropped — a huge capacity asks for chunks
    //   bigger than the staging buffers a host sized from `DEFAULT_CHUNK`.
    // Mutation: the chunk left at `DEFAULT_CHUNK` — one chunk for anything up
    //   to 1024 rows, which is the whole bug this beat is about.
    // Mutation: `setChunk` ignored — G0's load-bearing scale evaporates.
    const gpa = testing.allocator;

    // Cut into `TARGET_CHUNKS`, before a single tick and before a host could
    // have read it: 8192/256 = 32 rows a chunk.
    {
        const b = try Bench.init(gpa, 8192, 1);
        defer b.deinit(gpa);
        try testing.expectEqual(@as(u32, 32), b.spray.chunk);
        try b.mount("gravity -1\n");
        try b.tick(0, 0);
        try testing.expectEqual(@as(u32, 32), b.spray.chunk); // and ticking never moves it
        try testing.expectEqual(@as(usize, 8192 / 32), b.spray.dirtyChunks().len);
    }

    // A small spray asks for capacity/256 = 0 rows a chunk and is floored,
    // because below `MIN_CHUNK` the dispatch is the work — and because
    // `sizeChunks` divides by the answer.
    {
        const b = try Bench.init(gpa, 128, 1);
        defer b.deinit(gpa);
        try testing.expectEqual(spindrift.spray.MIN_CHUNK, b.spray.chunk);
    }

    // A very large one is capped at `DEFAULT_CHUNK` — not for cache reasons
    // but because that is the number a host sized its staging buffers from
    // (matryoshka's `spray_bridge.zig` allocates that many `GpuParticle` and
    // asserts the chunk fits them). A bigger chunk runs off the end of them,
    // in the host.
    {
        const b = try Bench.init(gpa, 512 * 1024, 1);
        defer b.deinit(gpa);
        try testing.expectEqual(spindrift.spray.DEFAULT_CHUNK, b.spray.chunk);
    }

    // And a host that said so wins, and ticking does not take it back. This
    // is the door; G0's load-bearing scale depends on it.
    {
        const b = try Bench.init(gpa, 8192, 1);
        defer b.deinit(gpa);
        b.spray.setChunk(64);
        try b.mount("gravity -1\n");
        try b.tick(0, 0);
        try testing.expectEqual(@as(u32, 64), b.spray.chunk);
    }
}




test "dirty chunks: a chunk is dirty on every tick a live row was swept in it — born, moving, or dying — and quiet otherwise" {
    // Mutation: the sweep's mark dropped; nothing is ever dirty and the
    // renderer never uploads. The tick that reaps a chunk's last row must
    // be dirty (the ghost) and the next quiet (the upload that never ends).
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 64, 1);
    defer b.deinit(gpa);
    b.spray.setChunk(16); // four chunks
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
    try b.tick(5, 5 * std.time.ns_per_s);
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
    // rill's `over` (core since 23ac55c; a life ≤ 0 refused since 529e7d8,
    // spindrift's edge taken into core) refuses the span by port name.
    try testing.expect(std.mem.indexOf(u8, b.spray.last_refusal.text(), "a curve with no width") != null);
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
    try b.mock.putValue("plane.drift.@em.k.size_curve", [_]f64{ 1, 0 });
    try b.mount("row.age | over row.life plane.drift.@self.k.size_curve | write row.size\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // born, t = 0
    b.spray.knobs.rate = 0;
    try b.tick(2, 2 * std.time.ns_per_s); // t = 0.5 on [1, 0] → 0.5
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);
    try testing.expectEqual(fixed.HALF, b.spray.pop.size[0]);
    try testing.expectEqual(@as(usize, 1), b.spray.array_casts.items.len);
    // The applet drags the curve: [1, 0] → [1, 1] — halfway is now 1.
    try b.mock.putValue("plane.drift.@em.k.size_curve", [_]f64{ 1, 1 });
    b.spray.pop.age_ns[0] = std.time.ns_per_s; // hold t at 0.5 for the read
    try b.tick(3, 3 * std.time.ns_per_s);
    try testing.expectEqual(fixed.ONE, b.spray.pop.size[0]);
    try testing.expectEqual(@as(usize, 1), b.spray.array_casts.items.len); // replaced, not accumulated
    // A number where a curve should be: the row refuses, by name.
    try b.mock.putValue("plane.drift.@em.k.size_curve", @as(f64, 3));
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

test "dump: `stuck`, `normal` and `alpha` ride, format 4" {
    const gpa = testing.allocator;
    var p = try spindrift.Population.init(gpa, 2);
    defer p.deinit();
    _ = p.spawn().?;
    _ = p.spawn().?; // a second, unstuck row — the dump carries LIVE rows only
    p.stuck[0] = 1;
    p.normal[1][0] = fixed.ONE;
    p.alpha[0] = fixed.HALF;
    const bytes = try dump.write(gpa, &p, 0);
    defer gpa.free(bytes);
    const s = try dump.readSummary(gpa, bytes);
    defer gpa.free(s.ids);
    try testing.expectEqual(@as(i64, 4), s.fmt);
    // The VALUES, not the keys: a dump writing zero for `normal` kept the
    // key and survived a substring check.
    const stuck = try dump.column(gpa, bytes, "stuck");
    defer gpa.free(stuck);
    const nrm_y = try dump.column(gpa, bytes, "nrm_y");
    defer gpa.free(nrm_y);
    try testing.expectEqual(@as(i64, 1), stuck[0]);
    try testing.expectEqual(@as(i64, fixed.ONE), nrm_y[0]);
    try testing.expectEqual(@as(i64, 0), nrm_y[1]);
    // Beat 6: `alpha` rides as a value (a dump writing zero for it would keep
    // the key).
    const alpha = try dump.column(gpa, bytes, "alpha");
    defer gpa.free(alpha);
    try testing.expectEqual(@as(i64, fixed.HALF), alpha[0]);
    try testing.expectEqual(@as(i64, 0), alpha[1]);
}

// ---------------------------------------------------------------------------
// Beat 6 (campaign 2, G8's row half): `alpha` on the row — born opaque,
// faded by `over`, bounded by the field.
// ---------------------------------------------------------------------------

test "alpha: born 1, faded by `over`, and a landed value past 1 is refused on the write node, counted, the row unchanged" {
    // Mutations: the spawn leaving alpha 0 — the fade kernel hides it (its
    // first tick writes the first knot, 1), and the SECOND spray catches it:
    // 0 + 0.5 lands and the refusal count reads 0; the bounds dropped from
    // the schema (1.5 lands, and the count reads 0 again).
    const gpa = testing.allocator;
    const b = try Bench.init(gpa, 4, 1);
    defer b.deinit(gpa);
    b.spray.knobs = .{ .rate = fixed.fromInt(1), .life_ns = 4 * std.time.ns_per_s };
    try b.mount("row.age | over row.life [1, 1, 0] | write row.alpha\n");
    try b.tick(0, 0);
    try b.tick(1, std.time.ns_per_s); // born: age 0 → the first knot, 1
    b.spray.knobs.rate = 0;
    try testing.expectEqual(fixed.ONE, b.spray.pop.alpha[0]);
    try b.tick(2, 2 * std.time.ns_per_s); // t = 0.25 → still 1
    try b.tick(3, 3 * std.time.ns_per_s); // t = 0.5 → the middle knot, 1
    try testing.expectEqual(fixed.ONE, b.spray.pop.alpha[0]);
    try b.tick(4, 4 * std.time.ns_per_s); // t = 0.75 → halfway down, 0.5
    try testing.expectEqual(fixed.HALF, b.spray.pop.alpha[0]);
    try testing.expectEqual(@as(u32, 0), b.spray.last.refusals);

    // A second spray, born opaque: 1 + 0.5 lands nothing and says so; the
    // same row's other write lands.
    const c = try Bench.init(gpa, 4, 1);
    defer c.deinit(gpa);
    try c.mount(
        \\0.5 | write row.alpha add
        \\row.size | mul 2 | write row.size
    );
    try oneRow(c);
    try testing.expectEqual(@as(u32, 1), c.spray.last.refusals);
    try testing.expect(std.mem.indexOf(u8, c.spray.last_refusal.text(), "row.alpha = 1.5000 is outside [0.0000, 1.0000]") != null);
    try testing.expectEqual(fixed.ONE, c.spray.pop.alpha[0]);
    try testing.expectEqual(2 * fixed.ONE, c.spray.pop.size[0]);
}

test "G0 with a fade: same script, same bytes — and `alpha` rode the dump, between 0 and 1" {
    // Mutation: `alpha` left out of the dump (the column is missing), or the
    // kernel's write never reaching the row (no value between 0 and 1).
    const gpa = testing.allocator;
    const s = Script{ .kernel = "spawn\ngravity plane.drift.@self.k.gravity\nrow.age | over row.life [1, 1, 0] | write row.alpha\nperish\n" };
    const a = try run(gpa, s, null);
    defer gpa.free(a);
    const b = try run(gpa, s, null);
    defer gpa.free(b);
    try testing.expectEqualSlices(u8, a, b);
    const alpha = try dump.column(gpa, a, "alpha");
    defer gpa.free(alpha);
    var between: u32 = 0;
    for (alpha) |v| {
        try testing.expect(v >= 0 and v <= fixed.ONE);
        if (v > 0 and v < fixed.ONE) between += 1;
    }
    try testing.expect(between > 0);
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
