//! population — the struct-of-arrays row store, fixed capacity, freelist.
//!
//! Field-major on purpose (campaign §3.1, recon R-b §1): `common/jobs.zig`
//! hands a batch an index range, and a range over sixteen parallel arrays
//! is sixteen straight streaming reads with no gather. Capacity is the
//! only allocation — everything a kernel touches exists before mount, and
//! nothing grows at runtime (an unbounded population is a corpse that
//! rides every dump).
//!
//! A row's id is its index, and a row keeps it for its whole life: the
//! store never compacts and never moves a row, the freelist holds DEAD ids
//! only, and a live id is in neither list. Stable identity is a sensor
//! precondition — something will want to watch a particle — and it holds
//! here by construction rather than by policy. A `gen` counter beside the
//! alive mask is bumped on every spawn, so a handle `(id, gen)` held across
//! a death is refusable instead of silently re-pointed at a stranger.

const std = @import("std");
const fixed = @import("fixed.zig");
const Fixed = fixed.Fixed;

pub const Handle = struct { id: u32, gen: u16 };

pub const Population = struct {
    gpa: std.mem.Allocator,
    capacity: u32,
    live: u32 = 0,

    alive: []bool,
    gen: []u16,
    pos: [3][]Fixed,
    vel: [3][]Fixed,
    age: []u32,
    life: []u32,
    seed: []u32,
    size: []Fixed,
    colour: [3][]Fixed,
    kind: []u8,
    user: [4][]Fixed,

    /// Dead ids, a stack: `spawn` pops the top, `kill` pushes. Seeded in
    /// descending order so a fresh population hands out 0, 1, 2, … — which
    /// is what makes a first-run dump readable, and costs nothing.
    free: []u32,
    free_len: u32,

    pub fn init(gpa: std.mem.Allocator, capacity: u32) !Population {
        std.debug.assert(capacity > 0);
        var p: Population = undefined;
        p.gpa = gpa;
        p.capacity = capacity;
        p.live = 0;
        p.alive = try gpa.alloc(bool, capacity);
        errdefer gpa.free(p.alive);
        @memset(p.alive, false);
        p.gen = try gpa.alloc(u16, capacity);
        errdefer gpa.free(p.gen);
        @memset(p.gen, 0);
        p.age = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.age);
        p.life = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.life);
        p.seed = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.seed);
        p.size = try gpa.alloc(Fixed, capacity);
        errdefer gpa.free(p.size);
        p.kind = try gpa.alloc(u8, capacity);
        errdefer gpa.free(p.kind);
        p.free = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.free);
        inline for (0..3) |a| {
            p.pos[a] = try gpa.alloc(Fixed, capacity);
            p.vel[a] = try gpa.alloc(Fixed, capacity);
            p.colour[a] = try gpa.alloc(Fixed, capacity);
        }
        inline for (0..4) |u| p.user[u] = try gpa.alloc(Fixed, capacity);
        // Scratch is zeroed once so a dump of a fresh population is a
        // function of capacity alone; every spawn re-zeroes its own row.
        p.clearRow(null);
        for (p.free, 0..) |*f, i| f.* = @intCast(capacity - 1 - i);
        p.free_len = capacity;
        return p;
    }

    pub fn deinit(self: *Population) void {
        const gpa = self.gpa;
        gpa.free(self.alive);
        gpa.free(self.gen);
        gpa.free(self.age);
        gpa.free(self.life);
        gpa.free(self.seed);
        gpa.free(self.size);
        gpa.free(self.kind);
        gpa.free(self.free);
        inline for (0..3) |a| {
            gpa.free(self.pos[a]);
            gpa.free(self.vel[a]);
            gpa.free(self.colour[a]);
        }
        inline for (0..4) |u| gpa.free(self.user[u]);
    }

    /// Zero one row's fields, or every row's when `which` is null.
    fn clearRow(self: *Population, which: ?u32) void {
        if (which) |id| {
            self.age[id] = 0;
            self.life[id] = 0;
            self.seed[id] = 0;
            self.size[id] = 0;
            self.kind[id] = 0;
            inline for (0..3) |a| {
                self.pos[a][id] = 0;
                self.vel[a][id] = 0;
                self.colour[a][id] = 0;
            }
            inline for (0..4) |u| self.user[u][id] = 0;
        } else {
            @memset(self.age, 0);
            @memset(self.life, 0);
            @memset(self.seed, 0);
            @memset(self.size, 0);
            @memset(self.kind, 0);
            inline for (0..3) |a| {
                @memset(self.pos[a], 0);
                @memset(self.vel[a], 0);
                @memset(self.colour[a], 0);
            }
            inline for (0..4) |u| @memset(self.user[u], 0);
        }
    }

    /// Claim a dead row: the id comes back zeroed, alive, one generation
    /// on. Null when the population is at capacity — the caller says
    /// `throttled`; the store never grows.
    pub fn spawn(self: *Population) ?u32 {
        if (self.free_len == 0) return null;
        self.free_len -= 1;
        const id = self.free[self.free_len];
        std.debug.assert(!self.alive[id]);
        self.clearRow(id);
        self.alive[id] = true;
        self.gen[id] +%= 1;
        self.live += 1;
        return id;
    }

    /// Retire a live row. Its fields are left as they were — they are
    /// scratch now and the next spawn zeroes them — and its id goes on the
    /// freelist to be handed out again.
    pub fn kill(self: *Population, id: u32) void {
        std.debug.assert(self.alive[id]);
        self.alive[id] = false;
        self.free[self.free_len] = id;
        self.free_len += 1;
        self.live -= 1;
    }

    pub fn handle(self: *const Population, id: u32) Handle {
        return .{ .id = id, .gen = self.gen[id] };
    }

    /// A handle is live only while the row it named is the row it named.
    pub fn isLive(self: *const Population, h: Handle) bool {
        return h.id < self.capacity and self.alive[h.id] and self.gen[h.id] == h.gen;
    }
};

test "population: a fresh store hands out ascending ids and is empty" {
    var p = try Population.init(std.testing.allocator, 4);
    defer p.deinit();
    try std.testing.expectEqual(@as(u32, 0), p.live);
    try std.testing.expectEqual(@as(u32, 0), p.spawn().?);
    try std.testing.expectEqual(@as(u32, 1), p.spawn().?);
    try std.testing.expectEqual(@as(u32, 2), p.spawn().?);
    try std.testing.expectEqual(@as(u32, 3), p.spawn().?);
    try std.testing.expectEqual(@as(?u32, null), p.spawn()); // full: never grows
    try std.testing.expectEqual(@as(u32, 4), p.live);
}

test "population: a handle outlives nothing — a reused id is a different row" {
    var p = try Population.init(std.testing.allocator, 2);
    defer p.deinit();
    const a = p.spawn().?;
    const h = p.handle(a);
    try std.testing.expect(p.isLive(h));
    p.kill(a);
    try std.testing.expect(!p.isLive(h));
    const b = p.spawn().?;
    try std.testing.expectEqual(a, b); // the id came back…
    try std.testing.expect(!p.isLive(h)); // …but the handle did not
    try std.testing.expect(p.isLive(p.handle(b)));
}

test "population: a spawn re-zeroes its row, so no dead scratch leaks into a new life" {
    var p = try Population.init(std.testing.allocator, 1);
    defer p.deinit();
    const a = p.spawn().?;
    p.pos[1][a] = 12345;
    p.user[3][a] = -7;
    p.age[a] = 99;
    p.kill(a);
    const b = p.spawn().?;
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(@as(Fixed, 0), p.pos[1][b]);
    try std.testing.expectEqual(@as(Fixed, 0), p.user[3][b]);
    try std.testing.expectEqual(@as(u32, 0), p.age[b]);
}
