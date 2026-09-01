//! The gates. Each names the mutation that must bite (campaign §2): a gate
//! that passes under its mutation is a finding about the gate, not a pass.
//! Mutations were applied by hand and their outcomes are in the ledger
//! (`docs/implementation-notes.md`, "P0 mutations").

const std = @import("std");
const testing = std.testing;
const common = @import("common");
const jobs = common.jobs;
const spindrift = @import("spindrift.zig");
const fixed = spindrift.fixed;
const dump = spindrift.dump;
const Emitter = spindrift.Emitter;
const Knobs = spindrift.Knobs;
const Fixed = fixed.Fixed;

const Script = struct {
    capacity: u32 = 64,
    seed: u32 = 7,
    knobs: Knobs = .{ .rate = fixed.fromInt(4), .speed = fixed.fromInt(3), .spread = fixed.ONE, .gravity = -fixed.fromInt(10), .life_ns = 2 * std.time.ns_per_s },
    dt_ns: u64 = std.time.ns_per_s / 2,
    ticks: u32 = 20,
    chunk: u32 = spindrift.emitter.DEFAULT_CHUNK,
};

/// Run one emitter over the script on a floor and return its dump. The
/// script is the whole input: same script, same bytes, or G0 is broken.
fn run(gpa: std.mem.Allocator, s: Script, js: ?*jobs.JobSystem) ![]u8 {
    var floor = spindrift.Floor{};
    var em = try Emitter.init(gpa, s.capacity, s.seed, floor.asWorld());
    defer em.deinit();
    em.knobs = s.knobs;
    em.chunk = s.chunk;
    var t: u32 = 0;
    while (t <= s.ticks) : (t += 1) {
        try em.tick(.{ .frame = t, .time_ns = @as(u64, t) * s.dt_ns }, js);
    }
    return dump.write(gpa, &em.pop, em.ticks);
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
    // gate that forces perish to be serial (R-b §3): a freelist pushed from
    // inside the parallel phase makes the NEXT tick's ids a race.
    //
    // The scale is load-bearing. At 64 rows in chunks of 8 this gate passed
    // under exactly that mutation (M2, ledger): the jobs were too small for
    // the steal order to ever differ, so the race never showed and two
    // OTHER gates caught it for the wrong reason. A gate that watches for a
    // race must run where the race can happen.
    const gpa = testing.allocator;
    const js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    const s = Script{ .capacity = 4096, .chunk = 64, .ticks = 12, .knobs = .{ .rate = fixed.fromInt(2000), .speed = fixed.fromInt(3), .spread = fixed.ONE, .gravity = -fixed.fromInt(10), .life_ns = 2 * std.time.ns_per_s } };
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
// The stand-in kernel's three words, each against an exact expectation.
// dt is a power of two of a second so every fixed product is exact.
// ---------------------------------------------------------------------------

/// One row, spawned on tick 1 and never another: rate 1/s at dt = 1 s
/// spawns exactly one, then the rate is dropped to zero.
fn oneRow(em: *Emitter) !void {
    em.knobs.rate = fixed.fromInt(1);
    try em.tick(.{ .frame = 0, .time_ns = 0 }, null); // epoch
    try em.tick(.{ .frame = 1, .time_ns = 1 * std.time.ns_per_s }, null);
    em.knobs.rate = 0;
    try testing.expectEqual(@as(u32, 1), em.pop.live);
}

test "gravity: vel.y = -k and pos.y = -k(k+1)/2 cells after k ticks, exactly" {
    // Mutation: drop the `vel.y += g·dt` line; pos.y stays at zero.
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 4, 1, nowhere.asWorld());
    defer em.deinit();
    em.knobs = .{ .speed = 0, .spread = 0, .gravity = -fixed.fromInt(1), .life_ns = 100 * std.time.ns_per_s };
    try oneRow(&em);
    // The spawn tick already ran the kernel once on the new row.
    try testing.expectEqual(-fixed.fromInt(1), em.pop.vel[1][0]);
    try testing.expectEqual(-fixed.fromInt(1), em.pop.pos[1][0]);
    var k: u32 = 1;
    while (k < 10) : (k += 1) {
        try em.tick(.{ .frame = k + 1, .time_ns = @as(u64, k + 1) * std.time.ns_per_s }, null);
        const n: i32 = @intCast(k + 1);
        try testing.expectEqual(-fixed.fromInt(n), em.pop.vel[1][0]);
        try testing.expectEqual(-fixed.fromInt(@divExact(n * (n + 1), 2)), em.pop.pos[1][0]);
    }
    // x and z never moved: gravity is y's alone.
    try testing.expectEqual(@as(Fixed, 0), em.pop.pos[0][0]);
    try testing.expectEqual(@as(Fixed, 0), em.pop.pos[2][0]);
}

test "spawn: rate × dt rows per tick, with the fraction carried, not dropped" {
    // Mutation: reset `spawn_acc` to zero each tick; 3/s at dt = 0.5 s
    // spawns 1, 1, 1, 1 instead of 1, 2, 1, 2.
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 64, 1, nowhere.asWorld());
    defer em.deinit();
    em.knobs = .{ .rate = fixed.fromInt(3), .life_ns = 100 * std.time.ns_per_s };
    try em.tick(.{ .frame = 0, .time_ns = 0 }, null);
    const expect_per_tick = [_]u32{ 1, 2, 1, 2, 1, 2 };
    var total: u32 = 0;
    for (expect_per_tick, 1..) |want, t| {
        try em.tick(.{ .frame = t, .time_ns = @as(u64, t) * std.time.ns_per_s / 2 }, null);
        try testing.expectEqual(want, em.last.spawned);
        total += want;
        try testing.expectEqual(total, em.pop.live);
        // The kernel spent exactly one row-step per live row — counted by
        // the kernel, so a kernel that walked the dead too would say so.
        // (Mutation M11 survived while this number was assumed.)
        try testing.expectEqual(total, em.last.row_steps);
    }
}

test "spawn: the first tick is the epoch and spawns nothing" {
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 8, 1, nowhere.asWorld());
    defer em.deinit();
    em.knobs = .{ .rate = fixed.fromInt(100) };
    try em.tick(.{ .frame = 5, .time_ns = 5 * std.time.ns_per_s }, null);
    try testing.expectEqual(@as(u32, 0), em.pop.live);
    try testing.expectEqual(@as(u32, 0), em.last.spawned);
}

test "spawn: at capacity the emitter says throttled and never grows" {
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 2, 1, nowhere.asWorld());
    defer em.deinit();
    em.knobs = .{ .rate = fixed.fromInt(5), .life_ns = 100 * std.time.ns_per_s };
    try em.tick(.{ .frame = 0, .time_ns = 0 }, null);
    try em.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s }, null);
    try testing.expectEqual(@as(u32, 2), em.last.spawned);
    try testing.expectEqual(@as(u32, 3), em.last.throttled);
    try testing.expectEqual(@as(u32, 2), em.pop.live);
}

test "perish: a row dies on the tick its age reaches its life, and its id is reused" {
    // Mutation: `age > life` instead of `>=`; the row lives one tick long.
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 8, 1, nowhere.asWorld());
    defer em.deinit();
    // life 1 s at dt 0.5 s is two ticks.
    em.knobs = .{ .rate = fixed.fromInt(2), .life_ns = std.time.ns_per_s };
    try em.tick(.{ .frame = 0, .time_ns = 0 }, null);
    try em.tick(.{ .frame = 1, .time_ns = std.time.ns_per_s / 2 }, null); // row 0 born, age 1
    try testing.expectEqual(@as(u32, 1), em.pop.live);
    try testing.expectEqual(@as(u32, 0), em.last.died);
    try testing.expectEqual(@as(u32, 2), em.pop.life[0]);
    try em.tick(.{ .frame = 2, .time_ns = std.time.ns_per_s }, null); // row 1 born; row 0 age 2 ⇒ dies
    try testing.expectEqual(@as(u32, 1), em.last.died);
    try testing.expectEqual(@as(u32, 1), em.pop.live);
    try testing.expect(!em.pop.alive[0]);
    try testing.expect(em.pop.alive[1]);
    try em.tick(.{ .frame = 3, .time_ns = 3 * std.time.ns_per_s / 2 }, null); // row 1 dies; the new row takes id 0 back
    try testing.expect(em.pop.alive[0]);
    try testing.expect(!em.pop.alive[1]);
    try testing.expectEqual(@as(u16, 2), em.pop.gen[0]);
}

// ---------------------------------------------------------------------------
// The freelist keeps ids stable for a row's life (R-b §4).
// ---------------------------------------------------------------------------

test "freelist: a live row keeps its id, its seed and its generation while others die around it" {
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 16, 3, nowhere.asWorld());
    defer em.deinit();
    // Two per tick, three ticks of life. A row born on tick t ages to 3 on
    // tick t+2 and dies there, so it is seen alive on two ticks and the
    // rolling population is four: two aged 1, two aged 2.
    em.knobs = .{ .rate = fixed.fromInt(2), .speed = fixed.fromInt(1), .spread = fixed.ONE, .life_ns = 3 * std.time.ns_per_s };
    var t: u32 = 0;
    while (t <= 4) : (t += 1) try em.tick(.{ .frame = t, .time_ns = @as(u64, t) * std.time.ns_per_s }, null);
    // Snapshot every live row's identity.
    var handles: [16]?spindrift.Handle = .{null} ** 16;
    var seeds: [16]u32 = undefined;
    var ages: [16]u32 = undefined;
    var id: u32 = 0;
    while (id < 16) : (id += 1) {
        if (!em.pop.alive[id]) continue;
        handles[id] = em.pop.handle(id);
        seeds[id] = em.pop.seed[id];
        ages[id] = em.pop.age[id];
    }
    try em.tick(.{ .frame = 5, .time_ns = 5 * std.time.ns_per_s }, null);
    try testing.expectEqual(@as(u32, 2), em.last.died);
    try testing.expectEqual(@as(u32, 2), em.last.spawned);
    id = 0;
    var survivors: u32 = 0;
    while (id < 16) : (id += 1) {
        const h = handles[id] orelse continue;
        if (ages[id] + 1 >= 3) {
            // Was due to die this tick: its handle must be dead now.
            try testing.expect(!em.pop.isLive(h));
            continue;
        }
        survivors += 1;
        try testing.expect(em.pop.isLive(h));
        try testing.expectEqual(seeds[id], em.pop.seed[id]);
        try testing.expectEqual(ages[id] + 1, em.pop.age[id]);
    }
    try testing.expectEqual(@as(u32, 2), survivors);
    // The two new rows took the two ids that died, and nobody else's.
    try testing.expectEqual(@as(u32, 4), em.pop.live);
}

// ---------------------------------------------------------------------------
// Time is fed, and a regression is loud.
// ---------------------------------------------------------------------------

test "tick: fed time going backwards is refused, never clamped" {
    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(testing.allocator, 4, 1, nowhere.asWorld());
    defer em.deinit();
    try em.tick(.{ .frame = 0, .time_ns = 0 }, null);
    try em.tick(.{ .frame = 1, .time_ns = 100 }, null);
    try testing.expectError(error.TimeRegression, em.tick(.{ .frame = 2, .time_ns = 50 }, null));
    try testing.expectError(error.TimeRegression, em.tick(.{ .frame = 0, .time_ns = 200 }, null));
    // Equal is fine: a zero-clock script ticks at the same instant forever.
    try em.tick(.{ .frame = 1, .time_ns = 100 }, null);
}

// ---------------------------------------------------------------------------
// The mock World is a negative control (campaign §8): an emitter that
// behaves identically with the floor removed has no collision. In P0 that
// is the TRUTH — no word calls the World — so this gate asserts equality.
// P4's `collide` must flip it to an inequality, and this comment is the
// pointer that says so.
// ---------------------------------------------------------------------------

test "negative control: P0 has no collision — the floor and no world at all agree byte for byte" {
    const gpa = testing.allocator;
    const s = Script{ .knobs = .{ .rate = fixed.fromInt(8), .speed = fixed.fromInt(2), .spread = fixed.ONE, .gravity = -fixed.fromInt(10), .life_ns = 4 * std.time.ns_per_s } };
    const on_floor = try run(gpa, s, null);
    defer gpa.free(on_floor);

    var nowhere = spindrift.Nowhere{};
    var em = try Emitter.init(gpa, s.capacity, s.seed, nowhere.asWorld());
    defer em.deinit();
    em.knobs = s.knobs;
    var t: u32 = 0;
    while (t <= s.ticks) : (t += 1) try em.tick(.{ .frame = t, .time_ns = @as(u64, t) * s.dt_ns }, null);
    const in_void = try dump.write(gpa, &em.pop, em.ticks);
    defer gpa.free(in_void);

    try testing.expectEqualSlices(u8, on_floor, in_void);
    // And the population did in fact fall through where a floor would be:
    // rows below y = 0 exist, so a collision word would have had work.
    var below: u32 = 0;
    var id: u32 = 0;
    while (id < em.pop.capacity) : (id += 1) {
        if (em.pop.alive[id] and em.pop.pos[1][id] < 0) below += 1;
    }
    try testing.expect(below > 0);
}
