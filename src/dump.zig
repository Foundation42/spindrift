//! dump — a population as one canonical struple map.
//!
//! The dump is a gate artefact, not a transcript entry (campaign §3.1, §8):
//! the population is re-derived from fed time and the mounted program, and
//! `drift dump` is the only way rows leave memory. Two runs of the same
//! script must produce byte-identical dumps, so the format is fixed by the
//! content and by nothing else: struple's `appendMap` sorts keys, every
//! number is a struple int (fixed point rides raw, no float anywhere), and
//! only LIVE rows ride, in ascending id order — a dead row's fields are
//! stale scratch, and a dump that carried them would make two identical
//! populations differ by what died when (recon R-b §5).
//!
//! Field-major like memory; `age` and `life` ride as fed nanoseconds. The
//! struple Python port reads this with `struple.unpack` and no spindrift
//! code at all — `tools/read_dump.py`.

const std = @import("std");
const struple = @import("struple");
const fixed = @import("fixed.zig");
const Population = @import("population.zig").Population;

pub const FORMAT: i64 = 3; // 2: `stuck` rides (beat 4); 3: `normal`, the contact (beat 5, ruling 27b)

/// The scalar and array keys, in the order they are packed (the map sorts
/// them; this order is for the reader's eyes).
const array_keys = [_][]const u8{
    "ids", "gen",  "pos_x", "pos_y", "pos_z", "vel_x", "vel_y", "vel_z",
    "age", "life", "seed",  "size",  "col_l", "col_a", "col_b", "kind",
    "u0",  "u1",   "u2",    "u3", "stuck", "nrm_x", "nrm_y", "nrm_z",
};

fn rowValue(pop: *const Population, key_index: usize, id: u32) i64 {
    return switch (key_index) {
        0 => id,
        1 => pop.gen[id],
        2 => pop.pos[0][id],
        3 => pop.pos[1][id],
        4 => pop.pos[2][id],
        5 => pop.vel[0][id],
        6 => pop.vel[1][id],
        7 => pop.vel[2][id],
        8 => @intCast(pop.age_ns[id]),
        9 => @intCast(pop.life_ns[id]),
        10 => pop.seed[id],
        11 => pop.size[id],
        12 => pop.colour[0][id],
        13 => pop.colour[1][id],
        14 => pop.colour[2][id],
        15 => pop.kind[id],
        16 => pop.userOf(id)[0],
        17 => pop.userOf(id)[1],
        18 => pop.userOf(id)[2],
        19 => pop.userOf(id)[3],
        20 => pop.stuck[id],
        21 => pop.normal[0][id],
        22 => pop.normal[1][id],
        23 => pop.normal[2][id],
        else => unreachable,
    };
}

/// Encode the population. The caller owns the bytes.
pub fn write(gpa: std.mem.Allocator, pop: *const Population, tick: u64) ![]u8 {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();

    const n_scalars = 4;
    var entries: [n_scalars + array_keys.len][2][]const u8 = undefined;

    const scalar_keys = [_][]const u8{ "fmt", "tick", "capacity", "live" };
    const scalar_vals = [_]i64{ FORMAT, @intCast(tick), pop.capacity, pop.live };
    for (scalar_keys, scalar_vals, 0..) |k, v, i| {
        var kp = struple.Packer.init(a);
        try kp.appendString(k);
        var vp = struple.Packer.init(a);
        try vp.appendInt(v);
        entries[i] = .{ kp.bytes(), vp.bytes() };
    }

    for (array_keys, 0..) |k, ki| {
        var kp = struple.Packer.init(a);
        try kp.appendString(k);
        var inner = struple.Packer.init(a);
        var id: u32 = 0;
        while (id < pop.capacity) : (id += 1) {
            if (!pop.alive[id]) continue;
            try inner.appendInt(rowValue(pop, ki, id));
        }
        var vp = struple.Packer.init(a);
        try vp.appendArray(inner.bytes());
        entries[n_scalars + ki] = .{ kp.bytes(), vp.bytes() };
    }

    var out = struple.Packer.init(gpa);
    errdefer out.deinit();
    try out.appendMap(&entries);
    return out.toOwnedSlice();
}

/// Wyhash of the bytes, for the runner's log and a gate's eyeballing. Not
/// inside the map — a digest of the thing it lives in is a fixed-point
/// problem nobody needs.
pub fn digest(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

/// What a gate reads back. `ids` is owned by the caller.
pub const Summary = struct {
    fmt: i64,
    tick: u64,
    capacity: u32,
    live: u32,
    ids: []u32,
};

fn getInt(a: std.mem.Allocator, map: struple.MapView, key: []const u8) !i64 {
    var kp = struple.Packer.init(a);
    try kp.appendString(key);
    const v = (try map.get(kp.bytes())) orelse return error.MissingKey;
    var r = struple.reader(v);
    const e = (try r.next()) orelse return error.MissingKey;
    return switch (e) {
        .int => |i| @intCast(i),
        else => error.NotAnInt,
    };
}

pub fn readSummary(gpa: std.mem.Allocator, bytes: []const u8) !Summary {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    const v = struple.view(bytes);
    if (!v.isMap()) return error.NotAMap;
    const inner = (try v.containedItems(a)) orelse return error.NotAMap;
    const map = struple.MapView.init(inner);

    var kp = struple.Packer.init(a);
    try kp.appendString("ids");
    const ids_enc = (try map.get(kp.bytes())) orelse return error.MissingKey;
    const ids_inner = (try struple.view(ids_enc).containedItems(a)) orelse return error.NotAnArray;
    var ids: std.ArrayListUnmanaged(u32) = .empty;
    errdefer ids.deinit(gpa);
    var r = struple.reader(ids_inner);
    while (try r.next()) |e| {
        switch (e) {
            .int => |i| try ids.append(gpa, @intCast(i)),
            else => return error.NotAnInt,
        }
    }
    return .{
        .fmt = try getInt(a, map, "fmt"),
        .tick = @intCast(try getInt(a, map, "tick")),
        .capacity = @intCast(try getInt(a, map, "capacity")),
        .live = @intCast(try getInt(a, map, "live")),
        .ids = try ids.toOwnedSlice(gpa),
    };
}

/// One array column by key, as the reader sees it — a gate's way to check
/// a VALUE rode the dump, not just a key (a mutation that wrote zero for
/// `normal` survived a key-only check). Owned by the caller.
pub fn column(gpa: std.mem.Allocator, bytes: []const u8, key: []const u8) ![]i64 {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    const v = struple.view(bytes);
    if (!v.isMap()) return error.NotAMap;
    const inner = (try v.containedItems(a)) orelse return error.NotAMap;
    const map = struple.MapView.init(inner);
    var kp = struple.Packer.init(a);
    try kp.appendString(key);
    const enc = (try map.get(kp.bytes())) orelse return error.MissingKey;
    const items = (try struple.view(enc).containedItems(a)) orelse return error.NotAnArray;
    var out: std.ArrayListUnmanaged(i64) = .empty;
    errdefer out.deinit(gpa);
    var r = struple.reader(items);
    while (try r.next()) |e| {
        switch (e) {
            .int => |i| try out.append(gpa, @intCast(i)),
            else => return error.NotAnInt,
        }
    }
    return out.toOwnedSlice(gpa);
}

test "dump: an empty population is a fixed byte string, and reads back" {
    var p = try Population.init(std.testing.allocator, 8);
    defer p.deinit();
    const bytes = try write(std.testing.allocator, &p, 3);
    defer std.testing.allocator.free(bytes);
    const again = try write(std.testing.allocator, &p, 3);
    defer std.testing.allocator.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again);

    const s = try readSummary(std.testing.allocator, bytes);
    defer std.testing.allocator.free(s.ids);
    try std.testing.expectEqual(FORMAT, s.fmt);
    try std.testing.expectEqual(@as(u64, 3), s.tick);
    try std.testing.expectEqual(@as(u32, 8), s.capacity);
    try std.testing.expectEqual(@as(u32, 0), s.live);
    try std.testing.expectEqual(@as(usize, 0), s.ids.len);
}

test "dump: live rows ride in ascending id order, dead rows do not ride at all" {
    var p = try Population.init(std.testing.allocator, 4);
    defer p.deinit();
    _ = p.spawn().?; // 0
    _ = p.spawn().?; // 1
    _ = p.spawn().?; // 2
    p.pos[1][2] = fixed.fromInt(7);
    p.kill(1);
    const bytes = try write(std.testing.allocator, &p, 0);
    defer std.testing.allocator.free(bytes);
    const s = try readSummary(std.testing.allocator, bytes);
    defer std.testing.allocator.free(s.ids);
    try std.testing.expectEqual(@as(u32, 2), s.live);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2 }, s.ids);

    // The dead row's scratch is not in the bytes: poke it and nothing moves.
    p.pos[1][1] = fixed.fromInt(-99);
    const after = try write(std.testing.allocator, &p, 0);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, bytes, after);
}
