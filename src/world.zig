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
//!
//! **A row is a SPHERE of `row.size`** (ruled 2026-09-08). `collide` takes
//! a radius and answers the centre's position at contact; `ground` does
//! not, because it measures where `collide` places. A radius of 0 is the
//! point test that was here before, bit for bit.

const std = @import("std");
const fixed = @import("fixed.zig");
const Fixed = fixed.Fixed;
const Vec = fixed.Vec;

/// What `ground` answers: signed distance above the surface under `pos`
/// (negative = below it) and the surface normal there.
pub const Ground = struct { distance: Fixed, normal: Vec };

/// What `collide` answers when the row's SPHERE crosses a surface: `t` in
/// [0, 1] along the segment, the sphere's CENTRE at contact, the SURFACE
/// normal at the crossing, and the material the host names there (0 = the
/// host said nothing; the mock floor is 0).
///
/// **`at` is the CENTRE, never the point on the surface** (ruled
/// 2026-09-08, with the radius). `stick` and `slide` both write
/// `pos ← at`, so if `at` were the surface point they would put the row's
/// centre ON the wall and the next tick's sweep would start already
/// interpenetrating — which is the bug the radius exists to fix, wearing a
/// different hat. A landed row's centre therefore rests one radius off the
/// surface along the normal, and `normal` is still the SURFACE's. At
/// radius 0 the two coincide, which is why every gate written before this
/// still reads the same numbers.
///
/// Fixed point across the boundary: the host does its float query once and
/// answers in the row's number, as the lattice does. The point is the
/// host's, not `from + (to − from)·t` at the row: that product floors twice
/// and landed a row one Q16.16 ulp above the floor (beat 4's first gate
/// run) — the floor answers the contact height exactly.
pub const Hit = struct { t: Fixed, at: Vec, normal: Vec, material: u32 = 0 };

pub const World = struct {
    ctx: *anyopaque,
    /// The signed distance from the row's position — its CENTRE — to the
    /// surface under it. No radius: `ground` MEASURES where `collide`
    /// PLACES, and every number a `World` hands back is about the centre,
    /// one convention rather than two (ledger, 2026-09-08). A kernel that
    /// wants the clearance under the body spells `ground | sub row.size`.
    groundFn: *const fn (ctx: *anyopaque, pos: Vec) ?Ground,
    /// The row's move this tick as a SWEPT SPHERE: the centre travels
    /// `from → to` carrying `radius`, and the answer's `at` is where the
    /// centre is when the sphere first touches.
    ///
    /// `radius` is ≥ 0 — `collide` refuses a negative `row.size` by name
    /// before it reaches here — and **`radius = 0` is the old point test,
    /// bit for bit**. That is not a convenience: G0's byte-identity and the
    /// campaign's G7 bit-identity claim are only meaningful if a zero
    /// radius takes the same arithmetic it always did, so a host that
    /// implements this may not carry a "safety" epsilon into the r = 0
    /// path.
    collideFn: *const fn (ctx: *anyopaque, from: Vec, to: Vec, radius: Fixed) ?Hit,

    pub fn ground(self: World, pos: Vec) ?Ground {
        return self.groundFn(self.ctx, pos);
    }
    pub fn collide(self: World, from: Vec, to: Vec, radius: Fixed) ?Hit {
        return self.collideFn(self.ctx, from, to, radius);
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

    /// **The sweep against an infinite plane is one line of geometry.** A
    /// sphere of radius r touches y = `self.y` exactly when its CENTRE is at
    /// `self.y + r`, so the centre is tested against the surface raised by
    /// the radius and every convention below is the old one against THAT
    /// plane. At r = 0 the raised plane IS the surface and the arithmetic is
    /// the old arithmetic, bit for bit — no epsilon, no second branch.
    ///
    /// A crossing is the SPHERE going from clear-or-touching to
    /// overlapping. A segment whose sphere ends exactly TOUCHING does not
    /// collide: the point on the wall is on the wall (rill's
    /// `inside`/`within` keep the same convention), and a sphere resting on
    /// the floor is resting on the floor — a landed row asks again every
    /// tick and must not be answered "you are hitting me" for ever. It is
    /// also load-bearing rather than tasteful: a resting row's segment is
    /// `from == to`, and this test is the only thing between that and
    /// `fromRatio(0, 0)` below. Flipped to `>`, the gate that watches a
    /// landed row for ten ticks does not fail, it crashes.
    ///
    /// A segment that starts OVERLAPPING is a row already inside the solid,
    /// and its centre is pushed back out ALONG THE NORMAL until the sphere
    /// just touches, at t = 0 — the engine's own rule
    /// (`docs/drift-words.md`, `collide`), which the mock did not share
    /// until 2026-09-07. It said "already through, no crossing", and a row
    /// that got under the floor by any means fell for the rest of its life.
    /// It gets under by ruling 20's sliver: `collide` tests
    /// `pos → pos + vel_start · dt` while the integrate moves by
    /// `vel_end · dt`, which is `g · dt²` further, so a row that stops
    /// inside that gap passes the test and lands below — 2.57% of a fire's
    /// embers at 16 ms, and `slide` could not work at all, because a
    /// sliding row sinks by exactly that sliver every tick and was
    /// abandoned on the first one. Resuming from inside costs no frozen
    /// hash (spindrift freezes none; G0 compares two runs to each other)
    /// and it makes the mock agree with the engine, which is what a
    /// negative control is for.
    ///
    /// **What the radius did to ruling 20 (B)**, which is still open: the
    /// sliver is unchanged — it is `g · dt²` of the CENTRE, and the centre
    /// does not care how big the row is. What changes is what that sliver
    /// LOOKS like. At r = 0 a row inside the surface is a row under the
    /// floor; at r > 0 it is a sphere dented by `g · dt²` while its body is
    /// still mostly outside, and the resume presses the dent out every
    /// tick. So the radius shrinks the symptom by the ratio of the sliver
    /// to r and removes nothing: the fix is still to test the segment the
    /// integrate will actually take.
    fn collideThunk(ctx: *anyopaque, from: Vec, to: Vec, radius: Fixed) ?Hit {
        const self: *Floor = @ptrCast(@alignCast(ctx));
        const surface = self.y +% radius; // the plane the CENTRE travels against
        if (from[1] < surface) return .{ .t = 0, .at = .{ from[0], surface, from[2] }, .normal = .{ 0, fixed.ONE, 0 }, .material = 0 };
        if (to[1] >= surface) return null;
        const t = fixed.fromRatio(@as(i64, from[1]) - surface, @as(i64, from[1]) - to[1]);
        return .{
            .t = t,
            .at = .{ from[0] +% fixed.mul(to[0] -% from[0], t), surface, from[2] +% fixed.mul(to[2] -% from[2], t) },
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
    /// resume: a sphere starting OVERLAPPING is a row already inside, and
    /// its centre is put one radius off the surface along the normal at
    /// t = 0.
    ///
    /// The radius arrives the same way it does on the floor, spelled as the
    /// clearance instead of the height: a sphere touches when the centre's
    /// depth IS the radius, so every test is the old one over `depth − r`.
    /// r = 0 leaves the old arithmetic untouched, bit for bit.
    fn collideThunk(ctx: *anyopaque, from: Vec, to: Vec, radius: Fixed) ?Hit {
        const self: *Plane = @ptrCast(@alignCast(ctx));
        const d0 = self.depth(from) -% radius;
        const d1 = self.depth(to) -% radius;
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
        const off = self.depth(at) -% radius;
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
    fn collideThunk(_: *anyopaque, _: Vec, _: Vec, _: Fixed) ?Hit {
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

test "floor: a radius of zero is the point test, bit for bit — beat 4's numbers, unmoved" {
    // Rule 1 of the radius (ruled 2026-09-08): `r = 0` reproduces today
    // exactly — same `t`, `at`, `normal`, `material`. These are beat 4's own
    // literals, computed by the code that had no radius at all, and they are
    // the reference: G0's byte-identity and G7's bit-identity claim are only
    // worth anything if a zero radius takes the arithmetic it always took.
    //
    // Mutation: `surface` formed as `self.y +% radius +% 1` (an ulp of
    // "safety" against the seam) — every answer here moves by an ulp and the
    // equalities below fail at r = 0, where nothing should have changed.
    // The radius-ignored mutation SURVIVES this gate, and must: at r = 0
    // there is nothing to ignore. It is the two gates below that watch it,
    // which is why this one is only half the pair.
    var floor = Floor{};
    const w = floor.asWorld();
    // 4 above to 4 below: the crossing is at t = 0.5, exactly, and the whole
    // Hit is asserted — a point test that got the normal or the material
    // wrong would still land the row in the right place.
    const hit = w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }, 0).?;
    try std.testing.expectEqual(fixed.HALF, hit.t);
    try std.testing.expectEqual(Vec{ 0, 0, 0 }, hit.at);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, hit.normal);
    try std.testing.expectEqual(@as(u32, 0), hit.material);
    // A slanted crossing lands on the surface EXACTLY in y, wherever x went.
    const slant = w.collide(.{ 0, fixed.fromInt(5), 0 }, .{ fixed.fromInt(3), fixed.fromInt(-3), 0 }, 0).?;
    try std.testing.expectEqual(@as(Fixed, 0), slant.at[1]);
    try std.testing.expect(slant.at[0] > 0 and slant.at[0] < fixed.fromInt(3));
    // 1 above to 3 below: t = 0.25.
    try std.testing.expectEqual(fixed.ONE / 4, w.collide(.{ 0, fixed.fromInt(1), 0 }, .{ 0, fixed.fromInt(-3), 0 }, 0).?.t);
    // Both above: no crossing.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(2), 0 }, .{ 0, fixed.fromInt(1), 0 }, 0));
    // Both BELOW is a row already inside, and it comes back to the face it
    // came through at t = 0 — not null, which is what it used to say and
    // what left a tunnelled row falling for ever (ruling 20).
    // Mutation: restore the `from[1] < y` null; the fire's 2.57% returns
    // and the slope gate's row never gets a second contact.
    const inside = w.collide(.{ fixed.fromInt(3), -fixed.fromInt(1), fixed.fromInt(5) }, .{ 0, fixed.fromInt(-2), 0 }, 0).?;
    try std.testing.expectEqual(@as(Fixed, 0), inside.t);
    try std.testing.expectEqual(Vec{ fixed.fromInt(3), 0, fixed.fromInt(5) }, inside.at);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, inside.normal);
    // Ending on the surface is on the wall, not through it.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(2), 0 }, .{ 0, 0, 0 }, 0));
    // A raised floor moves the crossing with it.
    var high = Floor{ .y = fixed.fromInt(2) };
    const hw = high.asWorld();
    try std.testing.expectEqual(fixed.HALF, hw.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, 0, 0 }, 0).?.t);
}

test "floor: a sphere stops a radius short, and its centre rests a radius off — the surface point is not the answer" {
    // Rule 2 (ruled 2026-09-08): `at` is the sphere's CENTRE at contact, not
    // the point on the surface. If it were the surface point, `stick` would
    // put the centre ON the floor and the next tick would start already
    // interpenetrating — the roaches bug in a new hat.
    //
    // Mutation: the radius ignored in the crossing test (`surface = self.y`)
    // — the sphere is buried to its centre and `t` is the point's 0.5.
    // Mutation: `at[1]` answered as `self.y` (the surface point) instead of
    // `surface` — the centre lands on the floor with the body under it.
    var floor = Floor{};
    const w = floor.asWorld();
    const r = fixed.ONE;
    // 4 above to 4 below with r = 1: the sphere touches when the centre is
    // at 1, so t = 3/8 where the point's was 1/2, and the centre stops there.
    const hit = w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }, r).?;
    try std.testing.expectEqual(fixed.fromRatio(3, 8), hit.t);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, hit.at);
    try std.testing.expectEqual(Vec{ 0, fixed.ONE, 0 }, hit.normal);
    // A sphere whose centre stops exactly one radius up is TOUCHING, and
    // touching is not overlapping — otherwise a landed row would be told it
    // is hitting the floor on every tick it rests there for ever.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, r, 0 }, r));
    // And a sphere found overlapping is pressed back out to touching, not
    // down onto the surface. Mutation: the resume answers `self.y` — the row
    // rests buried and is overlapping again on the very next tick, for ever.
    const dented = w.collide(.{ fixed.fromInt(3), fixed.HALF, fixed.fromInt(5) }, .{ fixed.fromInt(3), fixed.HALF, fixed.fromInt(5) }, r).?;
    try std.testing.expectEqual(@as(Fixed, 0), dented.t);
    try std.testing.expectEqual(Vec{ fixed.fromInt(3), r, fixed.fromInt(5) }, dented.at);
}

test "floor: a row whose CENTRE misses the surface but whose BODY does not now hits — the roaches bug, in miniature" {
    // The bug this was paid for, measured in matryoshka's playground on
    // 2026-09-08: particles walking the floor passed straight through a
    // sphere and a box resting on it, at 1.1–1.3× the density of a control
    // annulus — no blocking at all. The cause is geometric and certain: the
    // rows rest at y = 0 exactly, the props' cross-section at y = 0 is a
    // tangent point and a coplanar face, and a ZERO-WIDTH POINT travelling
    // through the one height where a prop has no cross-section misses it.
    //
    // The mock has no box, so the miniature is the same geometry against the
    // plane: a centre that passes ABOVE the surface the whole way while the
    // body crosses it. As a point this is "both above, no crossing" — the
    // exact answer that let the roaches through.
    //
    // Mutation: the radius dropped from the crossing test — this returns
    // null, which is the shipped bug, and nothing else in the file notices.
    var floor = Floor{};
    const w = floor.asWorld();
    const r = fixed.ONE;
    const from: Vec = .{ 0, fixed.fromRatio(15, 10), 0 };
    const to: Vec = .{ fixed.fromInt(4), fixed.HALF, 0 };
    // As a point: it never reaches y = 0, so nothing happens — twice over,
    // because the control is what makes the claim a claim.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(from, to, 0));
    // As a sphere of radius 1: the body touches half way along.
    const graze = w.collide(from, to, r).?;
    try std.testing.expectEqual(fixed.HALF, graze.t);
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), r, 0 }, graze.at);
}

test "plane: the second mock sweeps its sphere too — a wall stops a row a radius short of itself" {
    // Two mocks, two implementations of the same geometry, so a radius
    // dropped from one is invisible to the other's gate. `Plane` is the one
    // `slide` is gated on (a floor cannot show a tangent), so a radius that
    // reached only `Floor` would leave every sliding row half inside the
    // wall it was running along.
    //
    // Mutation: `radius` dropped from the `off` correction only — `t` is
    // right and the centre is put back ON the wall, half the row through it.
    //
    // Mutation: `radius` dropped from `d0`/`d1` — and what it does is worth
    // knowing, because it is not what you would guess. The crossing time
    // goes wrong (0.5 where the sphere's is 0.375) but `at` comes out RIGHT:
    // the `off` correction below — which exists to kill beat 4's
    // double-flooring ulp — projects the point onto the offset plane and
    // hides it. So this mutation is invisible to any gate that watches only
    // the position, and the slide wall gate in `tests.zig` is one: it
    // survives there and bites only here, on the `t` asserted above. A
    // contact point and a contact TIME can disagree, and the kernel reading
    // `t` off `collide`'s third port would have been the one to find out.
    var wall = Plane{ .n = .{ fixed.ONE, 0, 0 }, .d = 0 };
    const w = wall.asWorld();
    const r = fixed.HALF;
    const hit = w.collide(.{ fixed.fromInt(2), 0, 0 }, .{ -fixed.fromInt(2), 0, 0 }, r).?;
    try std.testing.expectEqual(fixed.fromRatio(3, 8), hit.t);
    try std.testing.expectEqual(Vec{ r, 0, 0 }, hit.at);
    try std.testing.expectEqual(Vec{ fixed.ONE, 0, 0 }, hit.normal);
    // r = 0 is the old answer, on this mock as on the floor.
    const point = w.collide(.{ fixed.fromInt(2), 0, 0 }, .{ -fixed.fromInt(2), 0, 0 }, 0).?;
    try std.testing.expectEqual(fixed.HALF, point.t);
    try std.testing.expectEqual(Vec{ 0, 0, 0 }, point.at);
    // The resume, one dimension up: a sphere overlapping the wall comes back
    // out along the normal to touching, not to the face.
    const dented = w.collide(.{ fixed.ONE / 4, fixed.fromInt(7), 0 }, .{ fixed.ONE / 4, fixed.fromInt(7), 0 }, r).?;
    try std.testing.expectEqual(@as(Fixed, 0), dented.t);
    try std.testing.expectEqual(Vec{ r, fixed.fromInt(7), 0 }, dented.at);
}

test "nowhere: the negative control answers nothing" {
    var nowhere = Nowhere{};
    const w = nowhere.asWorld();
    try std.testing.expectEqual(@as(?Ground, null), w.ground(.{ 0, 0, 0 }));
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }, 0));
    // A radius does not conjure a world: the negative control answers
    // nothing to a sphere as it does to a point.
    try std.testing.expectEqual(@as(?Hit, null), w.collide(.{ 0, fixed.fromInt(4), 0 }, .{ 0, fixed.fromInt(-4), 0 }, fixed.fromInt(2)));
}
