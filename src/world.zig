//! world — the query interface a host implements for the kernels.
//!
//! Spindrift declares it; Matryoshka implements it on `solver.zig`'s CPU
//! twin tracer (campaign §3.5); the mock here is a flat floor at y = 0. The
//! words that call it — `collide`, `stick`, `ground` — are P4's and need
//! their read-aloud first, so in P0 nothing calls this. The interface
//! exists now so P4 adds a caller and not a seam, and so the negative
//! control the ledger wants (an emitter that behaves identically with the
//! floor removed has no collision) has a floor to remove.
//!
//! Same fn-pointer discipline as rill's `Plane`: an opaque ctx and the
//! pointers are the whole contract. Everything crossing here is fixed
//! point, so a host answer is exact and a GPU twin can reproduce it.

const std = @import("std");
const fixed = @import("fixed.zig");
const Fixed = fixed.Fixed;
const Vec = fixed.Vec;

/// What `ground` answers: signed distance above the surface under `pos`
/// (negative = below it) and the surface normal there.
pub const Ground = struct { distance: Fixed, normal: Vec };

/// What `collide` answers when the segment from → to crosses a surface:
/// `t` in [0, 1] along the segment, the hit POINT, the normal at the
/// crossing, and the material the host names there (0 = the host said
/// nothing; the mock floor is 0). Fixed point across the boundary: the
/// host does its float query once and answers in the row's number, as the
/// lattice does. The point is the host's, not `from + (to − from)·t` at
/// the row: that product floors twice and landed a row one Q16.16 ulp
/// above the floor (beat 4's first gate run), and a landed row sits ON
/// the surface — the floor answers `y` exactly.
pub const Hit = struct { t: Fixed, at: Vec, normal: Vec, material: u32 = 0 };

pub const World = struct {
    ctx: *anyopaque,
    groundFn: *const fn (ctx: *anyopaque, pos: Vec) ?Ground,
    collideFn: *const fn (ctx: *anyopaque, from: Vec, to: Vec) ?Hit,

    pub fn ground(self: World, pos: Vec) ?Ground {
        return self.groundFn(self.ctx, pos);
    }
    pub fn collide(self: World, from: Vec, to: Vec) ?Hit {
        return self.collideFn(self.ctx, from, to);
    }
};

/// The mock: an infinite plane at `y`, normal up.
pub const Floor = struct {
    y: Fixed = 0,

    pub fn asWorld(self: *Floor) World {
        return .{ .ctx = self, .groundFn = groundThunk, .collideFn = collideThunk };
    }

    fn groundThunk(ctx: *anyopaque, pos: Vec) ?Ground {
        const self: *Floor = @ptrCast(@alignCast(ctx));
        return .{ .distance = pos[1] - self.y, .normal = .{ 0, fixed.ONE, 0 } };
    }

    /// A crossing is from ON-OR-ABOVE to BELOW. A segment that starts below
    /// the floor does not collide with it — it is already through, and
    /// `ground` says so with a negative distance. A segment ending exactly
    /// on the surface does not collide either: the point on the wall is on
    /// the wall (rill's `inside`/`within` keep the same convention).
    fn collideThunk(ctx: *anyopaque, from: Vec, to: Vec) ?Hit {
        const self: *Floor = @ptrCast(@alignCast(ctx));
        if (from[1] < self.y or to[1] >= self.y) return null;
        const t = fixed.fromRatio(@as(i64, from[1]) - self.y, @as(i64, from[1]) - to[1]);
        return .{
            .t = t,
            .at = .{ from[0] +% fixed.mul(to[0] -% from[0], t), self.y, from[2] +% fixed.mul(to[2] -% from[2], t) },
            .normal = .{ 0, fixed.ONE, 0 },
            .material = 0,
        };
    }
};

/// No world at all: every query answers null. This is the negative control
/// — an emitter whose dump is identical over `Nowhere` and over `Floor` is
/// an emitter that never asked.
pub const Nowhere = struct {
    pub fn asWorld(self: *Nowhere) World {
        return .{ .ctx = self, .groundFn = groundThunk, .collideFn = collideThunk };
    }
    fn groundThunk(_: *anyopaque, _: Vec) ?Ground {
        return null;
    }
    fn collideThunk(_: *anyopaque, _: Vec, _: Vec) ?Hit {
        return null;
    }
};

test "floor: ground is a signed distance with the normal up" {
    var floor = Floor{};
    const w = floor.asWorld();
    const above = w.ground(.{ 0, fixed.fromInt(3), 0 }).?;
    try std.testing.expectEqual(fixed.fromInt(3), above.distance);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, above.normal);
    const below = w.ground(.{ 0, fixed.fromInt(-2), 0 }).?;
    try std.testing.expectEqual(fixed.fromInt(-2), below.distance);
}

test "floor: collide answers t at the crossing, and only for a crossing" {
    var floor = Floor{};
    const w = floor.asWorld();
    // 4 above to 4 below: the crossing is at t = 0.5, exactly.
    const hit = w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }).?;
    try std.testing.expectEqual(fixed.HALF, hit.t);
    try std.testing.expectEqual(Vec{ 0, 0, 0 }, hit.at);
    // A slanted crossing lands on the surface EXACTLY in y, wherever x went.
    const slant = w.collide(.{ 0, fixed.fromInt(5), 0 }, .{ fixed.fromInt(3), fixed.fromInt(-3), 0 }).?;
    try std.testing.expectEqual(@as(Fixed, 0), slant.at[1]);
    try std.testing.expect(slant.at[0] > 0 and slant.at[0] < fixed.fromInt(3));
    // 1 above to 3 below: t = 0.25.
    try std.testing.expectEqual(fixed.ONE / 4, w.collide(.{ 0, fixed.fromInt(1), 0 }, .{ 0, fixed.fromInt(-3), 0 }).?.t);
    // Both above: no crossing. Both below: already through, no crossing.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(2), 0 }, .{ 0, fixed.fromInt(1), 0 }));
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(-1), 0 }, .{ 0, fixed.fromInt(-2), 0 }));
    // Ending on the surface is on the wall, not through it.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(2), 0 }, .{ 0, 0, 0 }));
    // A raised floor moves the crossing with it.
    var high = Floor{ .y = fixed.fromInt(2) };
    const hw = high.asWorld();
    try std.testing.expectEqual(fixed.HALF, hw.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, 0, 0 }).?.t);
}

test "nowhere: the negative control answers nothing" {
    var nowhere = Nowhere{};
    const w = nowhere.asWorld();
    try std.testing.expectEqual(@as(?Ground, null), w.ground(.{ 0, 0, 0 }));
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }));
}
