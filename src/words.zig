//! words — spindrift's operators, registered into rill's registry like
//! every other word.
//!
//! Three in beat 1, one in beat 2, one in beat 3, three in beat 4 (campaign
//! §3.3, §3.4, §3.5, ruled 2026-09-01/02), each a row word. The beat-4
//! three are the TRACER words — `collide`, `ground`, `stick` — the host's
//! words (§7.7): registered by a host that has a `World` through
//! `registerTracer`, so a kernel naming one on a host without is refused at
//! mount as an unknown word. Their kernels are exact at the row because the
//! `World` answers in fixed point: the host does its float query once and
//! converts at the boundary, as the lattice does.
//! meaningful only on a spray, with an exact integer kernel and `row.only`
//! set. A plane program that names one is refused at PARSE by name — the
//! "refuse at mount" the campaign asked for, one door earlier. (The first
//! draft used `fails_mount`, and it leaked: it fires only if the node
//! evaluates at tick 0, and `plane.x | gravity` with an unfed `plane.x`
//! never did — spindrift's own G2 found it.) The plane `eval` below is a
//! truthful slot-filler nothing reaches through the parser.
//!
//! Every word walks `Registry.register`: the reserved-name check, the tail
//! rule, the argument-spelling rule (adjacent wordless optionals refused).
//! That is G2's structural half, and it binds this repo the way it binds
//! any host. The other half — every word is row-legal, exact, row-only,
//! and named in the manual — is `tests.zig`'s audit, both ways.

const std = @import("std");
const rill = @import("rill");
const row = rill.row;
const fixed = @import("fixed.zig");
const population = @import("population.zig");
const spray_mod = @import("spray.zig");

const Fixed = fixed.Fixed;
const Tag = rill.Tag;

/// A row word's plane eval: it never runs on the world plane, and says so.
fn planeRefuse(ctx: *rill.EvalCtx) rill.registry.EvalError!rill.Emit {
    return ctx.refuse("{s} is a row word — it means something on a spray, not on the plane; mount it in a kernel", .{ctx.op.name});
}

fn rowOnly(k: *const fn (ctx: *row.Ctx) row.Error!void) row.Row {
    return .{ .exact = true, .only = true, .eval = k };
}

fn sprayOf(ctx: *row.Ctx) row.Error!*spray_mod.Spray {
    const host = ctx.host orelse return ctx.refuse("{s}: no spray is hosting this row", .{ctx.op.name});
    return @ptrCast(@alignCast(host));
}

/// `spawn` — on a row's birth tick, launch it: `vel ← aim × speed`, plus a
/// per-axis draw in ±spread from the row's seed. Every later tick it does
/// nothing. A kernel without `spawn` has rows that sit where they were
/// born, which is a thing you can see.
fn kSpawn(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    if (p.age_ns[r] != 0) return;
    const seed = p.seed[r];
    var v: [3]Fixed = undefined;
    inline for (0..3) |a| {
        v[a] = fixed.mul(s.aim[a], s.knobs.speed) + spray_mod.jitter(seed, a, s.knobs.spread);
    }
    try ctx.write(.{ .field = population.F_VEL }, .replace, .{ .vec3 = v });
}

/// `gravity <g>` — `vel.y += g · dt`, g in cells per second². Negative is
/// down. Takes a literal or a broadcast (`gravity plane.drift.@self.gravity`).
fn kGravity(ctx: *row.Ctx) row.Error!void {
    const g = try ctx.scalar(0);
    try ctx.write(.{ .field = population.F_VEL, .axis = 1 }, .add, .{ .scalar = fixed.mul(g, ctx.dt) });
}

/// `perish` — retire the row on the first tick its age has reached its
/// life. Marks; the spray reaps in its serial phase. A kernel without
/// `perish` has immortal rows, and a full population says `throttled`.
fn kPerish(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const r = ctx.row_index;
    if (s.pop.age_ns[r] >= s.pop.life_ns[r]) ctx.retire();
}

/// `hear $chan [grad] at <pos>` — the field read, spelled `$wind at
/// row.pos` (the parser desugars to this). The spray's lattice for the
/// channel, rasterised once this tick from the host's bag, trilinear at
/// `pos`; `grad` gives the slope instead, toward the caster. A channel the
/// spray does not sample is refused at mount by the spray; a lattice the
/// host could not fill (an undeclared channel) refuses here, per row, by
/// name — never a quiet zero.
fn kHear(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const chan = ctx.statics[0].channel;
    const want_grad = ctx.statics[1].word.len != 0;
    const lat = s.lattice(chan) orelse return ctx.refuse("{s}: this spray does not sample {s}", .{ ctx.op.name, chan });
    if (!lat.live) return ctx.refuse("{s}: {s} has no lattice this tick — the host declares no such channel", .{ ctx.op.name, chan });
    const at = try ctx.vec3(0);
    ctx.out[0] = if (want_grad) .{ .vec3 = lat.gradientAt(at) } else .{ .scalar = lat.sampleAt(at) };
}

/// `over <life> <curve>` — a value over normalised life: `t = age / life`
/// clamped to [0, 1], then piecewise linear over the curve's knots, evenly
/// spaced. Numbers or vec3s (a colour curve in Oklab lerps the same way).
/// Exact by lerp. The curve is the first stateless array on the row — a
/// literal converted once at mount, or a broadcast (`plane.drift.@self.
/// size_curve`, the Spray applet's `:::curve`) converted once per change
/// and shared. A life of zero refuses: "over nothing" is a question, not
/// a value.
fn kOver(ctx: *row.Ctx) row.Error!void {
    const age = try ctx.scalar(0);
    const life = try ctx.scalar(1);
    const knots = try ctx.array(2);
    if (life <= 0) return ctx.refuse("{s}: life is {d} — a value over nothing is not a value", .{ ctx.op.name, life });
    if (age <= 0) {
        ctx.out[0] = knots[0];
        return;
    }
    // t = age / life in Q16.16, clamped; then (n − 1) segments over [0, 1].
    var t: i64 = @divFloor(@as(i64, age) << fixed.FRAC_BITS, life);
    if (t >= fixed.ONE) {
        ctx.out[0] = knots[knots.len - 1];
        return;
    }
    if (knots.len == 1) {
        ctx.out[0] = knots[0];
        return;
    }
    t *= @as(i64, @intCast(knots.len - 1));
    const seg: usize = @intCast(t >> fixed.FRAC_BITS);
    const frac: Fixed = @intCast(t & (fixed.ONE - 1));
    ctx.out[0] = try row.kernels.lerpVal(ctx, frac, knots[seg], knots[seg + 1]);
}

/// `collide` — the row's move this tick, `pos → pos + vel · dt`, against
/// the world. A hit emits the hit point (port 0), the normal (1), `t` (2)
/// and the material (3); no hit emits nothing and the row's flow ends
/// quietly there. A stuck row moves nothing and so hits nothing.
fn kCollide(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    const from: fixed.Vec = .{ p.pos[0][r], p.pos[1][r], p.pos[2][r] };
    const to: fixed.Vec = .{ from[0] +% fixed.mul(p.vel[0][r], ctx.dt), from[1] +% fixed.mul(p.vel[1][r], ctx.dt), from[2] +% fixed.mul(p.vel[2][r], ctx.dt) };
    const hit = s.world.collide(from, to) orelse return;
    ctx.out[0] = .{ .vec3 = hit.at };
    ctx.out[1] = .{ .vec3 = hit.normal };
    ctx.out[2] = .{ .scalar = hit.t };
    ctx.out[3] = .{ .scalar = fixed.fromInt(@intCast(@min(hit.material, 32767))) };
}

/// `ground` — the nearest surface below the row: signed distance (port 0)
/// and its normal (1). A world with no ground says nothing.
fn kGround(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    const g = s.world.ground(.{ p.pos[0][r], p.pos[1][r], p.pos[2][r] }) orelse return;
    ctx.out[0] = .{ .scalar = g.distance };
    ctx.out[1] = .{ .vec3 = g.normal };
}

/// `stick` — land the row where it hit: position the hit point, velocity
/// zero, `row.stuck` set. A stuck row still ages and still reads its
/// curves. Read-aloud: `collide | stick` is the ember on the plate and the
/// spark on the trim in one breath; `land` fit the plate and not the wall,
/// `settle`/`rest` read as easing, not a stop.
fn kStick(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const at = try ctx.vec3(0);
    const normal = try ctx.vec3(1);
    // The resting offset (ruling 24, re-ruled on the plate capture): a disc
    // of radius `row.size` centred ON the hit point sits half inside the
    // surface — half-discs on the grass, and a light row 6 µm inside the
    // plate lit its underside. The row rests at `at + normal · size`,
    // tangent to the surface; light rows inherit it. The normal rides the
    // pipe from `collide` by name (rill: a producer's other outputs bind to
    // the consumer's like-named open ports).
    const size = s.pop.size[ctx.row_index];
    var rest: fixed.Vec = undefined;
    inline for (0..3) |a| rest[a] = at[a] +% fixed.mul(normal[a], size);
    try ctx.write(.{ .field = population.F_POS }, .replace, .{ .vec3 = rest });
    // No velocity write here: the sweep drops a stuck row's velocity every
    // tick (spray.zig), which is what `stuck` MEANS. The first draft zeroed
    // it here too; the mutation that deleted this line survived every gate,
    // so one rule in two places became one rule (beat 4).
    try ctx.write(.{ .field = population.F_STUCK }, .replace, .{ .scalar = fixed.ONE });
}

/// The tracer words — a host with a `World` registers these beside the
/// core; a host without leaves a kernel that names one to refuse at mount.
pub const TRACER = [_]rill.OpDef{
    .{
        .name = "collide",
        .outputs = &.{
            .{ .name = "at", .ty = Tag.any },
            .{ .name = "normal", .ty = Tag.any },
            .{ .name = "t", .ty = Tag.number },
            .{ .name = "material", .ty = Tag.number },
        },
        .help = "Row word (host): the row's move this tick against the world. On a hit, the hit point (piped on), then normal, t, material; no hit, nothing — `collide | stick`.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kCollide),
        .eval = planeRefuse,
    },
    .{
        .name = "ground",
        .outputs = &.{
            .{ .name = "distance", .ty = Tag.number },
            .{ .name = "normal", .ty = Tag.any },
        },
        .help = "Row word (host): the nearest surface below the row — signed distance (piped on) and its normal.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kGround),
        .eval = planeRefuse,
    },
    .{
        .name = "stick",
        .inputs = &.{ .{ .name = "at", .ty = Tag.any }, .{ .name = "normal", .ty = Tag.any } },
        .help = "Row word: land the row at `at` + `normal` × row.size — resting tangent to the surface, row.stuck set; the sweep holds it. A stuck row still ages and reads its curves. `collide | stick` (the normal rides the pipe by name).",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kStick),
        .eval = planeRefuse,
    },
};

/// Register the tracer words. A host calls this when it has a `World` to
/// answer them — matryoshka on its CPU twin tracer, `drift-run` on the mock
/// floor. Call after `register`.
pub fn registerTracer(reg: *rill.Registry) !void {
    for (TRACER) |def| _ = try reg.register(def);
}

pub const WORDS = [_]rill.OpDef{
    .{
        .name = "spawn",
        .help = "Row word: on a row's birth tick, launch it — vel ← the spray's aim × speed, ± spread per axis from the row's seed. Does nothing on later ticks.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kSpawn),
        .eval = planeRefuse,
    },
    .{
        .name = "gravity",
        .inputs = &.{.{ .name = "g", .ty = Tag.number }},
        .help = "Row word: vel.y += g · dt, g in cells/s², negative down — `gravity -9.8`, or `gravity plane.drift.@self.gravity` from a knob.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kGravity),
        .eval = planeRefuse,
    },
    .{
        .name = "perish",
        .help = "Row word: retire the row on the first tick its age has reached its life. A kernel without it has immortal rows.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kPerish),
        .eval = planeRefuse,
    },
    .{
        .name = "over",
        .inputs = &.{
            .{ .name = "age", .ty = Tag.number },
            .{ .name = "life", .ty = Tag.number },
            .{ .name = "curve", .ty = Tag.array },
        },
        .outputs = &.{.{ .name = "out", .ty = Tag.any }},
        .help = "Row word: a value over normalised life — `row.age | over row.life [1.0, 0.7, 0.0]` is 1.0 at birth, 0.7 halfway, 0.0 at the end, piecewise linear over evenly spaced knots. Numbers, or Oklab colours `[{l, a, b}, …]`; the curve may be a literal or a broadcast (`plane.drift.@self.size_curve`).",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kOver),
        .eval = planeRefuse,
    },
    .{
        .name = "hear",
        .statics = &.{
            .{ .name = "channel", .kind = .channel },
            .{ .name = "grad", .kind = .word, .flag = true, .optional = true },
        },
        .inputs = &.{.{ .name = "at", .ty = Tag.any, .kw = true }},
        .outputs = &.{.{ .name = "out", .ty = Tag.any }},
        .help = "Row word: the field read — `$wind at row.pos` is the value of the spray's $wind lattice there, `$wind grad at row.pos` the slope toward the caster. The ^spray must `samples $wind cell <c>`.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kHear),
        .eval = planeRefuse,
    },
};

/// Register every spindrift word. Call after `rill.registerCore`.
pub fn register(reg: *rill.Registry) !void {
    for (WORDS) |def| _ = try reg.register(def);
}

test "words: every spindrift word registers through rill's one door" {
    var reg = try rill.Registry.init(std.testing.allocator);
    defer reg.deinit();
    try rill.registerCore(&reg);
    try register(&reg);
    for (WORDS) |w| {
        const def = reg.get(reg.find(w.name).?);
        try std.testing.expect(def.row.legal());
        try std.testing.expect(def.row.exact);
        try std.testing.expect(def.row.only);
    }
}
