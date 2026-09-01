//! words — spindrift's operators, registered into rill's registry like
//! every other word.
//!
//! Three in beat 1 and one in beat 2 (campaign §3.3, §3.4, ruled
//! 2026-09-01), each a row word:
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
