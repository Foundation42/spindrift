//! population — the struct-of-arrays row store, fixed capacity, freelist,
//! and the row plane a kernel is mounted on.
//!
//! Field-major on purpose (campaign §3.1, recon R-b §1): `common/jobs.zig`
//! hands a batch an index range, and a range over parallel arrays is
//! straight streaming reads with no gather. Capacity is the only
//! allocation — everything a kernel touches exists before mount, and
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
//!
//! **The population is a `rill.row.Plane`** (beat 1, ruled 2026-09-01: a
//! kernel is a rill whose plane is the row). `asRowPlane` hands rill the
//! schema and four thunks; the fields a kernel sees are below. Age and life
//! are nanoseconds in the store and seconds (Q16.16) on the row — a unit
//! conversion at the read, never a unit in the row.

const std = @import("std");
const rill = @import("rill");
const fixed = @import("fixed.zig");
const Fixed = fixed.Fixed;
const Val = rill.row.Val;

pub const Handle = struct { id: u32, gen: u16 };

pub const USER_CHANNELS: u32 = 4;

/// The row a kernel sees. Index order is the plane's field index.
pub const schema = [_]rill.row.Field{
    .{ .name = "pos", .kind = .vec3 },
    .{ .name = "vel", .kind = .vec3 },
    .{ .name = "age", .kind = .scalar, .writable = false },
    .{ .name = "life", .kind = .scalar, .writable = false },
    .{ .name = "seed", .kind = .scalar, .writable = false },
    .{ .name = "size", .kind = .scalar },
    .{ .name = "colour", .kind = .vec3 },
    .{ .name = "kind", .kind = .scalar, .writable = false },
    // 1 once `stick` landed the row; 0 otherwise. A stuck row still ages
    // and reads its curves (beat 4, ruled); the renderer may read it too.
    .{ .name = "stuck", .kind = .scalar },
    // The contact normal `stick` stored; zero for every unstuck row. The
    // resting offset is the APPEARANCE's (ruling 27b): a disc or a light is
    // drawn at `pos + normal · size`, one rule for every row, so a landed
    // row that shrinks stays on the surface by construction. `hear` samples
    // at `pos`, the contact.
    .{ .name = "normal", .kind = .vec3 },
    .{ .name = "u0", .kind = .scalar },
    .{ .name = "u1", .kind = .scalar },
    .{ .name = "u2", .kind = .scalar },
    .{ .name = "u3", .kind = .scalar },
};

pub const F_POS: u16 = 0;
pub const F_VEL: u16 = 1;
pub const F_AGE: u16 = 2;
pub const F_LIFE: u16 = 3;
pub const F_SEED: u16 = 4;
pub const F_SIZE: u16 = 5;
pub const F_COLOUR: u16 = 6;
pub const F_KIND: u16 = 7;
pub const F_STUCK: u16 = 8;
pub const F_NORMAL: u16 = 9;
pub const F_U0: u16 = 10;

pub const Population = struct {
    gpa: std.mem.Allocator,
    capacity: u32,
    live: u32 = 0,

    alive: []bool,
    gen: []u16,
    /// Marked by a kernel's `perish` during the parallel sweep; reaped by
    /// the host's serial phase in ascending id. A kill inside the sweep is
    /// the freelist race G0 forbids.
    doomed: []bool,
    pos: [3][]Fixed,
    vel: [3][]Fixed,
    /// Fed nanoseconds since birth, and the birth's allotted span.
    age_ns: []u64,
    life_ns: []u64,
    seed: []u32,
    size: []Fixed,
    colour: [3][]Fixed,
    kind: []u8,
    /// `stick`'s bit: the row landed and stays. Read by the kernel as
    /// `row.stuck`, writable so a kernel may unstick.
    stuck: []u8,
    /// The contact normal (`row.normal`), stored by `stick`; zero otherwise.
    normal: [3][]Fixed,
    /// User channels, `USER_CHANNELS` per row, contiguous per row so a
    /// kernel's per-row state is one slice — the one field that is not
    /// field-major, for exactly that reason.
    user: []Fixed,

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
        p.doomed = try gpa.alloc(bool, capacity);
        errdefer gpa.free(p.doomed);
        @memset(p.doomed, false);
        p.age_ns = try gpa.alloc(u64, capacity);
        errdefer gpa.free(p.age_ns);
        p.life_ns = try gpa.alloc(u64, capacity);
        errdefer gpa.free(p.life_ns);
        p.seed = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.seed);
        p.size = try gpa.alloc(Fixed, capacity);
        errdefer gpa.free(p.size);
        p.kind = try gpa.alloc(u8, capacity);
        errdefer gpa.free(p.kind);
        p.stuck = try gpa.alloc(u8, capacity);
        errdefer gpa.free(p.stuck);
        p.user = try gpa.alloc(Fixed, capacity * USER_CHANNELS);
        errdefer gpa.free(p.user);
        p.free = try gpa.alloc(u32, capacity);
        errdefer gpa.free(p.free);
        inline for (0..3) |a| {
            p.pos[a] = try gpa.alloc(Fixed, capacity);
            p.vel[a] = try gpa.alloc(Fixed, capacity);
            p.colour[a] = try gpa.alloc(Fixed, capacity);
            p.normal[a] = try gpa.alloc(Fixed, capacity);
        }
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
        gpa.free(self.doomed);
        gpa.free(self.age_ns);
        gpa.free(self.life_ns);
        gpa.free(self.seed);
        gpa.free(self.size);
        gpa.free(self.kind);
        gpa.free(self.stuck);
        gpa.free(self.user);
        gpa.free(self.free);
        inline for (0..3) |a| {
            gpa.free(self.pos[a]);
            gpa.free(self.vel[a]);
            gpa.free(self.colour[a]);
            gpa.free(self.normal[a]);
        }
    }

    pub fn userOf(self: *const Population, id: u32) []Fixed {
        return self.user[id * USER_CHANNELS .. (id + 1) * USER_CHANNELS];
    }

    /// Zero one row's fields, or every row's when `which` is null.
    fn clearRow(self: *Population, which: ?u32) void {
        if (which) |id| {
            self.age_ns[id] = 0;
            self.life_ns[id] = 0;
            self.seed[id] = 0;
            self.size[id] = 0;
            self.kind[id] = 0;
            self.stuck[id] = 0;
            self.doomed[id] = false;
            inline for (0..3) |a| {
                self.pos[a][id] = 0;
                self.vel[a][id] = 0;
                self.colour[a][id] = 0;
                self.normal[a][id] = 0;
            }
            @memset(self.userOf(id), 0);
        } else {
            @memset(self.age_ns, 0);
            @memset(self.life_ns, 0);
            @memset(self.seed, 0);
            @memset(self.size, 0);
            @memset(self.kind, 0);
            @memset(self.stuck, 0);
            @memset(self.doomed, false);
            inline for (0..3) |a| {
                @memset(self.pos[a], 0);
                @memset(self.vel[a], 0);
                @memset(self.colour[a], 0);
                @memset(self.normal[a], 0);
            }
            @memset(self.user, 0);
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
        self.doomed[id] = false;
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

    // -- the row plane ------------------------------------------------------

    pub fn asRowPlane(self: *Population) rill.row.Plane {
        return .{ .ctx = self, .schema = &schema, .readFn = readThunk, .writeFn = writeThunk, .retireFn = retireThunk, .userFn = userThunk };
    }

    /// Nanoseconds → Q16.16 seconds, saturating at the format's top (a row
    /// nine hours old reads 32767 s, which is "old" in every kernel that
    /// asks). Truncation, like `fixed.fromNs`.
    fn secondsOf(ns: u64) Fixed {
        const scaled: u128 = (@as(u128, ns) << fixed.FRAC_BITS) / std.time.ns_per_s;
        if (scaled > std.math.maxInt(Fixed)) return std.math.maxInt(Fixed);
        return @intCast(scaled);
    }

    fn readThunk(ctx: *anyopaque, r: u32, field: u16) Val {
        const self: *Population = @ptrCast(@alignCast(ctx));
        return switch (field) {
            F_POS => .{ .vec3 = .{ self.pos[0][r], self.pos[1][r], self.pos[2][r] } },
            F_VEL => .{ .vec3 = .{ self.vel[0][r], self.vel[1][r], self.vel[2][r] } },
            F_AGE => .{ .scalar = secondsOf(self.age_ns[r]) },
            F_LIFE => .{ .scalar = secondsOf(self.life_ns[r]) },
            // The seed as a per-row uniform in [0, 1): its low 16 bits are the
            // fraction. `row.seed | mul 2` is a decorrelated 0..2 per row.
            F_SEED => .{ .scalar = @intCast(self.seed[r] & 0xFFFF) },
            F_SIZE => .{ .scalar = self.size[r] },
            F_COLOUR => .{ .vec3 = .{ self.colour[0][r], self.colour[1][r], self.colour[2][r] } },
            F_KIND => .{ .scalar = fixed.fromInt(self.kind[r]) },
            F_STUCK => .{ .scalar = fixed.fromInt(self.stuck[r]) },
            F_NORMAL => .{ .vec3 = .{ self.normal[0][r], self.normal[1][r], self.normal[2][r] } },
            else => .{ .scalar = self.userOf(r)[field - F_U0] },
        };
    }

    fn writeThunk(ctx: *anyopaque, r: u32, field: u16, val: Val) void {
        const self: *Population = @ptrCast(@alignCast(ctx));
        switch (field) {
            F_POS => if (val == .vec3) {
                inline for (0..3) |a| self.pos[a][r] = val.vec3[a];
            },
            F_VEL => if (val == .vec3) {
                inline for (0..3) |a| self.vel[a][r] = val.vec3[a];
            },
            F_SIZE => if (val == .scalar) {
                self.size[r] = val.scalar;
            },
            F_COLOUR => if (val == .vec3) {
                inline for (0..3) |a| self.colour[a][r] = val.vec3[a];
            },
            F_STUCK => if (val == .scalar) {
                self.stuck[r] = if (val.scalar > 0) 1 else 0;
            },
            F_NORMAL => if (val == .vec3) {
                inline for (0..3) |a| self.normal[a][r] = val.vec3[a];
            },
            F_AGE, F_LIFE, F_SEED, F_KIND => {}, // refused at mount; never reached
            else => if (val == .scalar) {
                self.userOf(r)[field - F_U0] = val.scalar;
            },
        }
    }

    fn retireThunk(ctx: *anyopaque, r: u32) void {
        const self: *Population = @ptrCast(@alignCast(ctx));
        self.doomed[r] = true;
    }

    fn userThunk(ctx: *anyopaque, r: u32) []Fixed {
        const self: *Population = @ptrCast(@alignCast(ctx));
        return self.userOf(r);
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
    p.userOf(a)[3] = -7;
    p.age_ns[a] = 99;
    p.doomed[a] = true;
    p.kill(a);
    const b = p.spawn().?;
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(@as(Fixed, 0), p.pos[1][b]);
    try std.testing.expectEqual(@as(Fixed, 0), p.userOf(b)[3]);
    try std.testing.expectEqual(@as(u64, 0), p.age_ns[b]);
    try std.testing.expect(!p.doomed[b]);
}

test "population: as a row plane, fields read in the row's units and read-only fields stay put" {
    var p = try Population.init(std.testing.allocator, 2);
    defer p.deinit();
    const r = p.spawn().?;
    p.age_ns[r] = std.time.ns_per_s / 2;
    p.life_ns[r] = 3 * std.time.ns_per_s;
    p.seed[r] = 0xABCD_8000;
    p.kind[r] = 3;
    p.vel[1][r] = 7;
    const plane = p.asRowPlane();
    try std.testing.expectEqual(fixed.HALF, plane.read(r, F_AGE).scalar);
    try std.testing.expectEqual(fixed.fromInt(3), plane.read(r, F_LIFE).scalar);
    try std.testing.expectEqual(@as(Fixed, 0x8000), plane.read(r, F_SEED).scalar); // 0.5, from the low 16 bits
    try std.testing.expectEqual(fixed.fromInt(3), plane.read(r, F_KIND).scalar);
    try std.testing.expectEqual([3]Fixed{ 0, 7, 0 }, plane.read(r, F_VEL).vec3);
    plane.write(r, F_VEL, .{ .vec3 = .{ 1, 2, 3 } });
    try std.testing.expectEqual(@as(Fixed, 3), p.vel[2][r]);
    plane.write(r, F_U0 + 2, .{ .scalar = 9 });
    try std.testing.expectEqual(@as(Fixed, 9), p.userOf(r)[2]);
    plane.user(r)[0] = 11;
    try std.testing.expectEqual(@as(Fixed, 11), plane.read(r, F_U0).scalar);
    try std.testing.expect(!p.doomed[r]);
    plane.retire(r);
    try std.testing.expect(p.doomed[r]);
    try std.testing.expect(p.alive[r]); // retire marks; the host reaps
}
