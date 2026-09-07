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

    /// A crossing is from ON-OR-ABOVE to BELOW. A segment ending exactly on
    /// the surface does not collide: the point on the wall is on the wall
    /// (rill's `inside`/`within` keep the same convention).
    ///
    /// A segment that starts BELOW is a row already inside the solid, and
    /// it is placed on the face it came through, at t = 0 — the engine's
    /// own rule (`docs/drift-words.md`, `collide`), which the mock did not
    /// share until 2026-09-07. It said "already through, no crossing", and
    /// a row that got under the floor by any means fell for the rest of its
    /// life. It gets under by ruling 20's sliver: `collide` tests
    /// `pos → pos + vel_start · dt` while the integrate moves by
    /// `vel_end · dt`, which is `g · dt²` further, so a row that stops
    /// inside that gap passes the test and lands below — 2.57% of a fire's
    /// embers at 16 ms, and `slide` could not work at all, because a
    /// sliding row sinks by exactly that sliver every tick and was
    /// abandoned on the first one. Resuming from inside costs no frozen
    /// hash (spindrift freezes none; G0 compares two runs to each other)
    /// and it makes the mock agree with the engine, which is what a
    /// negative control is for.
    fn collideThunk(ctx: *anyopaque, from: Vec, to: Vec) ?Hit {
        const self: *Floor = @ptrCast(@alignCast(ctx));
        if (from[1] < self.y) return .{ .t = 0, .at = .{ from[0], self.y, from[2] }, .normal = .{ 0, fixed.ONE, 0 }, .material = 0 };
        if (to[1] >= self.y) return null;
        const t = fixed.fromRatio(@as(i64, from[1]) - self.y, @as(i64, from[1]) - to[1]);
        return .{
            .t = t,
            .at = .{ from[0] +% fixed.mul(to[0] -% from[0], t), self.y, from[2] +% fixed.mul(to[2] -% from[2], t) },
            .normal = .{ 0, fixed.ONE, 0 },
            .material = 0,
        };
    }
};

/// The second mock: an infinite plane through `n · p = d`, `n` a UNIT
/// normal. `Floor` is this with n = (0, 1, 0) and d = its y, and is kept
/// beside it rather than folded into it — every beat-4 gate is written
/// against `Floor`'s exact answers, and a mock rewritten under its own
/// gates is a mock nobody checked.
///
/// It exists because `slide` cannot be gated on a floor. On a flat floor
/// gravity is entirely normal, so the tangential velocity a slide leaves
/// is the one the row already had: the word's whole effect is invisible
/// there, and a gate over it would pass against a kernel that did nothing.
/// A WALL — n = (1, 0, 0) — is exact in Q16.16 and separates them: a row
/// thrown at it keeps falling and stops advancing.
pub const Plane = struct {
    n: Vec = .{ 0, fixed.ONE, 0 },
    d: Fixed = 0,

    pub fn asWorld(self: *Plane) World {
        return .{ .ctx = self, .groundFn = groundThunk, .collideFn = collideThunk };
    }

    /// `n · p`, in Q16.16. A unit `n` makes this the signed distance.
    fn depth(self: *const Plane, p: Vec) Fixed {
        return fixed.mul(self.n[0], p[0]) +% fixed.mul(self.n[1], p[1]) +% fixed.mul(self.n[2], p[2]) -% self.d;
    }

    fn groundThunk(ctx: *anyopaque, pos: Vec) ?Ground {
        const self: *Plane = @ptrCast(@alignCast(ctx));
        return .{ .distance = self.depth(pos), .normal = self.n };
    }

    /// The same crossing rule as `Floor`, one dimension up — including its
    /// resume: a segment starting BELOW is a row already inside, and it is
    /// put back on the surface along the normal at t = 0.
    fn collideThunk(ctx: *anyopaque, from: Vec, to: Vec) ?Hit {
        const self: *Plane = @ptrCast(@alignCast(ctx));
        const d0 = self.depth(from);
        const d1 = self.depth(to);
        if (d0 < 0) {
            var back: Vec = undefined;
            inline for (0..3) |a| back[a] = from[a] -% fixed.mul(self.n[a], d0);
            return .{ .t = 0, .at = back, .normal = self.n, .material = 0 };
        }
        if (d1 >= 0) return null;
        const t = fixed.fromRatio(d0, @as(i64, d0) - @as(i64, d1));
        // The point is the plane's own, as `Floor`'s is: the row is put back
        // ON the surface along the normal rather than interpolated to it, so
        // no product floors twice and leaves it an ulp off.
        var at: Vec = undefined;
        inline for (0..3) |a| at[a] = from[a] +% fixed.mul(to[a] -% from[a], t);
        const off = self.depth(at);
        inline for (0..3) |a| at[a] -%= fixed.mul(self.n[a], off);
        return .{ .t = t, .at = at, .normal = self.n, .material = 0 };
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
    // Both above: no crossing.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(2), 0 }, .{ 0, fixed.fromInt(1), 0 }));
    // Both BELOW is a row already inside, and it comes back to the face it
    // came through at t = 0 — not null, which is what it used to say and
    // what left a tunnelled row falling for ever (ruling 20).
    // Mutation: restore the `from[1] < y` null; the fire's 2.57% returns
    // and the slope gate's row never gets a second contact.
    const inside = w.collide(.{ fixed.fromInt(3), -fixed.fromInt(1), fixed.fromInt(5) }, .{ 0, fixed.fromInt(-2), 0 }).?;
    try std.testing.expectEqual(@as(Fixed, 0), inside.t);
    try std.testing.expectEqual(Vec{ fixed.fromInt(3), 0, fixed.fromInt(5) }, inside.at);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, inside.normal);
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
