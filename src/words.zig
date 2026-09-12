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
//!
//! **Every word says what it is FOR** (`TAGS` below, 2026-09-09). Fifteen
//! untagged words made a bad first palette — `rill ops --tag untagged` named
//! all fifteen the day tags landed — and G22 is the audit that keeps a
//! sixteenth from slipping through.

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

/// `gravity <pull>` — `vel.y += pull · dt`, in cells per second². Negative is
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


/// `relax <target> <rate>` — the STEP that carries a value toward
/// `target` at `rate` per second: `(target − in) · rate · dt`.
///
/// It emits the step, not the arrival, and that is the whole design. A
/// row's state is pushed by several things at once — it cools on its own,
/// faster against something cold, faster once the air gets at it — and a
/// word that returned the new value could only ever be the LAST word to
/// speak. A step composes: `write row.u0 add` lands each one on the live
/// field in turn, so the influences sum the way forces do. `gravity` is
/// the same shape, one field down.
///
/// `dt` is why it is a word at all. `(1 − x) · rate` can be spelled with
/// core rill — `| mul -1 | add 1 | mul <rate>` — and `fire.rill` spelled
/// it that way for a beat, but the rate is then PER TICK and the kernel is
/// correct at one dt only. A kernel cannot say dt: `ctx.dt` is Zig's,
/// there is no `row.dt`, and every stateful core op that would relax
/// (`ease`, `ramp`) is not row-legal. So the word eats the fed delta and
/// the knob is per second, like `gravity`'s cells per second².
///
/// Two refusals, both loud, because each is a rate that does the opposite
/// of what the word says. A NEGATIVE rate walks away from the target —
/// that is not a slow relax, it is divergence. A rate whose step exceeds
/// the whole gap (`rate · dt > 1`) steps PAST the target and, past two,
/// further away every tick; clamping it would leave a kernel oscillating
/// while the picture looked plausible, which is campaign 2's ruling 3 the
/// row-fields already answer with bounds. The dt in the test is the fed
/// one, so a kernel tuned at 16 ms says so on the tick that is not.
///
/// Read-aloud: "u0, relax toward 1 at nine tenths a second." Rejected:
/// `decay` (only ever toward zero, and half these lines climb); `approach`
/// (reads as motion in space, and this is a scalar); `cool` (names one
/// customer, not the operation); `toward` (wants a preposition it has not
/// got); `ease` and `ramp` are rill's plane words and stateful — a
/// different thing wearing a near name.
fn kRelax(ctx: *row.Ctx) row.Error!void {
    const x = try ctx.scalar(0);
    const target = try ctx.scalar(1);
    const rate = try ctx.scalar(2);
    var nb: [24]u8 = undefined;
    if (rate < 0) return ctx.refuse("{s}: rate {s} is negative — that walks away from the target, not toward it", .{ ctx.op.name, fixed.format(rate, &nb) });
    // The fraction of the gap this tick closes. Formed FIRST so the guard
    // reads the number it guards, and so the product that reaches the
    // subtraction is the small one.
    const k = fixed.mul(rate, ctx.dt);
    if (k > fixed.ONE) {
        var db: [24]u8 = undefined;
        return ctx.refuse("{s}: rate {s} over a {s}s tick closes more than the whole gap — it would step past the target", .{ ctx.op.name, fixed.format(rate, &nb), fixed.format(ctx.dt, &db) });
    }
    ctx.out[0] = .{ .scalar = fixed.mul(target -% x, k) };
}

// `over` was spindrift's fifth word from beat 3 until rill took it into its
// core (rill `23ac55c`, beat 5): the same spelling, `row.age | over row.life
// [1, 0.7, 0]`, the same bits — clamped divide, segment by shift, fraction
// by mask, `lerpVal` — and now on the plane as well as the row, with a zero
// span refused by name. One word, one home; the kernel that lived here is
// deleted rather than kept beside it (a duplicate name refuses at register).

/// `collide` — the row's move this tick, `pos → pos + vel · dt`, against
/// the world, as a SPHERE of the row's own `size`. A hit emits the contact
/// point (port 0), the normal (1), `t` (2) and the material (3); no hit
/// emits nothing and the row's flow ends quietly there. A stuck row moves
/// nothing and so hits nothing.
///
/// **A row IS a sphere of `row.size`** (ruled 2026-09-08), so the radius is
/// authored nowhere: the field the appearance already draws with, and that
/// `deposit` already marks with, is the one collision uses. Nothing else
/// would be honest — a row with two widths would be two rows.
///
/// It was a zero-width POINT until then, and that was measured as a bug and
/// not a simplification: in matryoshka's playground, particles walking a
/// floor passed straight through a sphere and a box resting on it at
/// 1.1–1.3× the density of a control annulus — no blocking at all — because
/// the rows rest at y = 0 exactly and both props' cross-section AT y = 0 is
/// a tangent point and a coplanar face. A point through the one height
/// where a prop has no cross-section hits nothing, and no nudge to the
/// props' heights fixes the class of that bug.
///
/// The point it emits is the sphere's CENTRE at contact, one radius off the
/// surface along the normal, never the surface point — `stick` and `slide`
/// both write `pos ← at`, and a centre placed ON the surface starts the
/// next tick interpenetrating, which is the same bug wearing a hat. The
/// normal is still the SURFACE's.
///
/// The size is read from the row's SNAPSHOT, like everything else in the
/// sweep (ruling 20): a kernel that writes `row.size` this tick collides at
/// the width it had when the kernel began, and shrinks into the next one.
///
/// A NEGATIVE `row.size` refuses by name. Nothing clamps it: a negative
/// radius moves the surface the wrong way, so the row would tunnel further
/// than a point would, and it would do it quietly while the picture looked
/// almost right — campaign 2's ruling 3, at the seam.
fn kCollide(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    const radius = p.size[r];
    if (radius < 0) {
        var nb: [24]u8 = undefined;
        return ctx.refuse("{s}: row.size {s} is negative — a row IS a sphere of its size, and a negative radius is a surface that moves the wrong way", .{ ctx.op.name, fixed.format(radius, &nb) });
    }
    const from: fixed.Vec = .{ p.pos[0][r], p.pos[1][r], p.pos[2][r] };
    const to: fixed.Vec = .{ from[0] +% fixed.mul(p.vel[0][r], ctx.dt), from[1] +% fixed.mul(p.vel[1][r], ctx.dt), from[2] +% fixed.mul(p.vel[2][r], ctx.dt) };
    const hit = s.world.collide(from, to, radius) orelse return;
    ctx.out[0] = .{ .vec3 = hit.at };
    ctx.out[1] = .{ .vec3 = hit.normal };
    ctx.out[2] = .{ .scalar = hit.t };
    ctx.out[3] = .{ .scalar = fixed.fromInt(@intCast(@min(hit.material, 32767))) };
}

/// `ground` — the nearest surface below the row: signed distance (port 0)
/// and its normal (1). A world with no ground says nothing.
///
/// **No radius, decided 2026-09-08 when `collide` got one.** `collide` had
/// to take one because its answer is a POSITION the row adopts, and a
/// position that ignores the radius is a position inside the wall. `ground`
/// answers a distance and a normal; the row does not move to them, and
/// nothing here places anything. Every number a `World` hands back is
/// therefore about the row's CENTRE — one convention rather than two, where
/// a `ground` that quietly subtracted the radius would answer clearance
/// while `collide` answered centres and a kernel reading both would have to
/// know which was which. The clearance under the BODY is already spellable
/// at the row, exactly, with no word: `ground | sub row.size`. And it costs
/// a host nothing — `groundFn` is unchanged, so matryoshka's compiles as it
/// stands.
///
/// Recorded, with its trigger: the first word that PLACES a row from
/// `ground`'s answer — a `settle` or a `hover` that rests a row on what is
/// under it without a segment to sweep — is placement, not measurement, and
/// wants the radius the way `collide` does. One customer, not a hunch.
fn kGround(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    const g = s.world.ground(.{ p.pos[0][r], p.pos[1][r], p.pos[2][r] }) orelse return;
    ctx.out[0] = .{ .scalar = g.distance };
    ctx.out[1] = .{ .vec3 = g.normal };
}

/// `stick` — land the row where it hit: position the contact point, velocity
/// zero, `row.stuck` set. A stuck row still ages and still reads its
/// curves. Read-aloud: `collide | stick` is the ember on the plate and the
/// spark on the trim in one breath; `land` fit the plate and not the wall,
/// `settle`/`rest` read as easing, not a stop.
fn kStick(ctx: *row.Ctx) row.Error!void {
    const at = try ctx.vec3(0);
    const normal = try ctx.vec3(1);
    // The row's position is the contact — and since 2026-09-08 the contact
    // is the sphere's CENTRE there, one radius off the surface, because
    // `collide` sweeps the row's `size` and answers where the centre is
    // when the body touches. `stick` itself learned nothing: it writes the
    // point it was handed, which is the test that rule 2 is in the right
    // place. A row that shrinks after landing keeps its landing centre and
    // its body lifts off the surface — see the trigger recorded on
    // `spray.zig`'s `Appearance`; the appearance's own re-rest is
    // matryoshka's beat.
    //
    // **Ruling 27b is now a double count and must move.** It says the
    // resting offset is the APPEARANCE's — a disc or a light drawn at
    // `pos + normal · size`, one rule for every row with no stuck branch.
    // The sim now holds the row a radius off the surface itself, so a
    // renderer that still adds `normal · size` draws a landed row TWO radii
    // up. One rule, in the sim, is the answer; the renderer's line comes
    // out in matryoshka's beat, not here.
    //
    // The first draft offset `pos` here (ruling 24 as first ruled) and a
    // shrinking ember kept its landing height. `hear` samples at `pos`, the
    // centre. The normal rides the pipe from `collide` by name.
    try ctx.write(.{ .field = population.F_POS }, .replace, .{ .vec3 = at });
    try ctx.write(.{ .field = population.F_NORMAL }, .replace, .{ .vec3 = normal });
    // No velocity write here: the sweep drops a stuck row's velocity every
    // tick (spray.zig), which is what `stuck` MEANS. The first draft zeroed
    // it here too; the mutation that deleted this line survived every gate,
    // so one rule in two places became one rule (beat 4).
    try ctx.write(.{ .field = population.F_STUCK }, .replace, .{ .scalar = fixed.ONE });
    // The landing tick, said on the slate. `row.stuck` is the STATE that
    // follows; this is the EVENT, and a kernel that wants the moment rather
    // than the condition cannot get it from the field — `stuck` is already 1
    // on every tick after, and a stuck row stops colliding, so `stick` never
    // runs twice for one landing.
    ctx.publish(0, .{ .scalar = fixed.ONE });
}

/// `slide` — take the contact's normal OUT of the row's velocity, and put
/// the row on the surface: `vel −= (n · vel) n`, `pos ← at`. What is left
/// is the tangent, so the row runs along what it hit instead of stopping
/// on it. `collide | slide | stick` is the whole life of an ember on a
/// sloped hearth in one breath.
///
/// "On the surface" is the sphere's centre one radius off it since
/// 2026-09-08, for the same reason `stick`'s is and by the same route: `at`
/// comes from `collide`, and `slide` writes whatever it was handed. So a
/// sliding row RIDES the surface at its own radius instead of dragging its
/// centre along it, and the streak it leaves is where the body was.
///
/// It SUBTRACTS rather than replacing, and that is the same choice `relax`
/// made an hour earlier for the same reason: as an add it composes, so
/// gravity pulls, the wind pushes, and `slide` removes only the part of
/// the RESULT that would go through the wall.
///
/// The first draft of this comment said a replace would lose `gravity`'s
/// add — queued from an earlier node — and that a row on a slope would
/// therefore never accelerate. Running the mutation says otherwise, and
/// the truth is more interesting: a replaced row DOES gain speed, in
/// STAIR-STEPS — it holds a velocity for several ticks and jumps on the
/// one where it has sunk far enough for a real crossing rather than a
/// resume (−1.44, −1.44, −1.44, −1.44, −1.68, −1.68 against a clean
/// −1.44, −1.68, −1.92, …). So the acceleration under a replace is a
/// function of the tick rate and the geometry; under an add it is
/// 0.24 cells/s per tick, which is the tangential gravity times dt, every
/// tick and by construction. The gate had to be sharpened to say that —
/// three samples straddled a step and the mutation survived them.
///
/// The correction is computed from the tick's snapshot, so it lags a tick
/// exactly as `collide`'s segment does (ruling 20) — one rule, already
/// written down. The row therefore ends each tick a sliver INSIDE the
/// surface, by that same `g · dt²`, and is put back on it next tick by the
/// world's resume. Without that resume `slide` cannot work at all: the
/// row sinks on its first contact and the old mock abandoned it there.
///
/// The normal is taken to be UNIT, as every `World` answers it. Nothing
/// here checks that: a host that returns a longer one scales the
/// correction by |n|² and over-corrects, which is the host's bug and would
/// cost a square root at every row to catch.
///
/// Read-aloud: "collide, slide, stick." Rejected: `slip` (reads as a
/// failure, not a motion); `skid` (promises a friction this does not
/// model — a frictionless slide on a flat floor runs for ever, and that is
/// a thing you can see); `graze` (a near miss, the opposite); `tangent`
/// (names the plane, not the act); `deflect` (says bounce, and nothing
/// here reflects).
fn kSlide(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const p = &s.pop;
    const r = ctx.row_index;
    const at = try ctx.vec3(0);
    const n = try ctx.vec3(1);
    const v: fixed.Vec = .{ p.vel[0][r], p.vel[1][r], p.vel[2][r] };
    const vn = fixed.mul(n[0], v[0]) +% fixed.mul(n[1], v[1]) +% fixed.mul(n[2], v[2]);
    var back: fixed.Vec = undefined;
    inline for (0..3) |a| back[a] = -fixed.mul(n[a], vn);
    try ctx.write(.{ .field = population.F_POS }, .replace, .{ .vec3 = at });
    try ctx.write(.{ .field = population.F_NORMAL }, .replace, .{ .vec3 = n });
    try ctx.write(.{ .field = population.F_VEL }, .add, .{ .vec3 = back });
    // And say so on the slate, for the lines below. A sliding row is against
    // the cold thing every tick and `row.stuck` is 0 the whole time, so
    // nothing in the row can carry this: a field written here is invisible
    // until the next tick (rill's writes land after the node loop) and would
    // then be state owing a dump. `slate.contact` is this tick's, this row's.
    ctx.publish(0, .{ .scalar = fixed.ONE });
}

/// `near <radius>` — how many live rows are within `radius`, and (on the
/// slate's HANDLE lane, under `crowd`) which ones.
///
/// The count is an ordinary number a kernel can use at once. The LIST is
/// the thing no `Val` can hold — the row plane's arrays are literal-only
/// and no operator emits one — so it goes on the slate as a native handle:
/// a pointer into the spray's per-chunk buffer, valid for exactly this
/// row's evaluation, which is the same lifetime the slate gives everything
/// and the reason a raw pointer is safe there at all.
///
/// The neighbourhood is a hash grid over the live rows, rebuilt once a tick
/// at the tail of the serial spawn — one snapshot of where everybody is,
/// which is what keeps `near` row-local in the parallel sweep. A radius
/// larger than the grid's cell is REFUSED rather than quietly missing the
/// rows a wider ring would have held.
///
/// Read-aloud: "near half a cell, push four". Rejected: `neighbours` (a
/// noun, and every other row word is a verb); `around` (reads as a
/// rotation); `within` is rill's already and means a point in a box; `flock`
/// names one customer of many.
fn kNear(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const radius = try ctx.scalar(0);
    var nb: [24]u8 = undefined;
    if (radius <= 0) return ctx.refuse("{s}: radius {s} is not positive — a neighbourhood with no width is a question with no answer", .{ ctx.op.name, fixed.format(radius, &nb) });
    // There is no upper guard, and there was one until 2026-09-08: the search
    // walked a fixed 3×3×3, so a radius wider than the cell would have MISSED
    // rows rather than found them, and refusing was the only honest answer.
    // The grid now derives the cell range from the radius itself, so a wide
    // radius costs more and answers correctly. The refusal went with the
    // constant that made it necessary.
    const buf = s.neighBuf(ctx.row_index);
    const got = s.gatherNear(ctx.row_index, radius, buf);
    if (got.crowded) s.crowded_rows += 1;
    ctx.publishHandle(0, .{ .ptr = @ptrCast(buf.ptr), .len = got.n });
    ctx.out[0] = .{ .scalar = fixed.fromInt(@intCast(got.n)) };
}

/// `push <gain>` — separation: lean away from everything `near` found, at
/// `gain` cells per second per cell of offset.
/// `vel += Σ (pos − other) · gain · dt`.
///
/// It reads the list off the slate rather than asking again, which is the
/// whole point: the neighbourhood was already gathered this row, and a
/// second gather would be the same answer at twice the price.
///
/// The falloff is the neighbourhood's own edge and nothing softer — a row
/// just inside the radius pushes, one just outside does not, and the step
/// across is a discontinuity. Recorded rather than smoothed: a customer
/// that can see the seam is the trigger for a weight.
fn kPush(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const k = try ctx.scalar(0);
    const h = ctx.handle(0) orelse return; // `near` was quiet for this row
    const ids: [*]const u32 = @ptrCast(@alignCast(h.ptr orelse return));
    // The neighbourhood's SNAPSHOT positions, never the live store: the
    // sweep integrates a row the moment its kernel is done, so a live read
    // would lean away from where the earlier rows have already got to, and
    // the answer would depend on the order the chunks happened to run in.
    const mine = s.neighPos(ctx.row_index);
    var sum: fixed.Vec = .{ 0, 0, 0 };
    for (ids[0..h.len]) |other| {
        const theirs = s.neighPos(other);
        inline for (0..3) |a| sum[a] +%= mine[a] -% theirs[a];
    }
    const gain = fixed.mul(k, ctx.dt);
    var out: fixed.Vec = undefined;
    inline for (0..3) |a| out[a] = fixed.mul(sum[a], gain);
    try ctx.write(.{ .field = population.F_VEL }, .add, .{ .vec3 = out });
}

/// The signed way round: a phase difference in (−1, 1) brought into
/// [−0.5, 0.5), so two rows either side of the wrap pull toward each other
/// the SHORT way rather than sprinting the long way round.
fn wrapHalf(d: Fixed) Fixed {
    if (d > fixed.HALF) return d -% fixed.ONE;
    if (d < -fixed.HALF) return d +% fixed.ONE;
    return d;
}

/// `sync <row.uN> <drift> <couple>` — a phase oscillator that listens to
/// the rows `near` found. Each tick the phase advances by its own `drift`
/// and leans toward the average of its neighbours':
///
///     phase += (drift + couple · mean(wrap(other − phase))) · dt
///
/// and wraps into [0, 1). Give every row a slightly different `drift` (from
/// `row.seed`, say) and a local `couple`, and neighbours entrain while
/// distant ones do not — which is where travelling waves come from. Nothing
/// here makes a wave; the wave is what a field of these DOES.
///
/// The coupling is the phase difference itself, not its sine — the sawtooth
/// oscillator rather than Kuramoto proper. It entrains the same way, and it
/// is exact in Q16.16 where a sine would need a table and would put a
/// second definition of `sin` in the ecosystem.
///
/// Neighbours' phases are read from the neighbourhood's SNAPSHOT, never the
/// live store. A kernel's writes land at the end of that row's evaluation,
/// so a live read would have row 1 seeing row 0's new phase and row 0
/// seeing row 1's old one — Gauss-Seidel where the sweep promises Jacobi,
/// and an answer that depends on the order chunks happened to run in.
///
/// Only a user channel may be synchronised: a phase is the row's own state,
/// and the user channels are what the neighbourhood snapshots. Anything
/// else refuses by name rather than reading a stale field quietly.
///
/// Read-aloud: "sync row.u0, drifting at row.u1, coupled at 3." Rejected:
/// `entrain` (the right word and the obscure one — kept in the manual as
/// what this means); `phase` (a noun, where every row word is a verb);
/// `couple` (names the parameter, not the act); `chorus` (lovely, and says
/// nothing about what it does).
/// `infect row.uN <rate>` — a row CATCHES a channel from whoever `near`
/// found that has more of it. funideas §6: *"transfer a state variable
/// between neighbours. Now you've got spreading fire, bioluminescence,
/// chemical reactions, disease, magic, whatever."*
///
/// It reads the neighbours' MAXIMUM, not their mean. A mean is diffusion —
/// which is `relax` toward a neighbour average, and smears a peak into a
/// haze; a maximum is transmission, and it makes a FRONT. Watching a front
/// cross a cloud is the thing this word is for.
///
/// And it is MONOTONE: a row surrounded by cleaner rows does not get
/// cleaner. You catch it from somebody who has more. Recovery is a separate
/// fact with a separate rate, and `relax 0 <rate>` is already the word for
/// it — so an epidemic is two lines, and the balance between the two rates
/// is the threshold between a thing that spreads and a thing that dies out.
/// Writing that as one word with two rates would have hidden exactly the
/// number worth playing with.
///
/// Adds its step rather than replacing, unlike `sync`, so it composes with
/// the recovery line and with anything else the kernel does to the channel.
fn kInfect(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const wr = ctx.write_ref orelse return ctx.refuse("{s}: needs the field that spreads — `infect row.u0 <rate>`", .{ctx.op.name});
    if (wr.ref.field < population.F_U0 or wr.ref.field >= population.F_U0 + population.USER_CHANNELS) {
        return ctx.refuse("{s}: only a user channel can be caught (row.u0 … row.u3) — what spreads is the row's own state, and the user channels are what the neighbourhood snapshots", .{ctx.op.name});
    }
    const ch: u16 = wr.ref.field - population.F_U0;
    const rate = try ctx.scalar(0);
    var nb: [24]u8 = undefined;
    if (rate < 0) return ctx.refuse("{s}: rate {s} is negative — a row cannot catch LESS of a thing; recovery is `relax 0 <rate>`", .{ ctx.op.name, fixed.format(rate, &nb) });
    // `relax`'s guard, for `relax`'s reason: past one whole gap a row would
    // end the tick holding MORE than the neighbour it caught it from, and
    // the front would run away from its own source.
    if (fixed.mul(rate, ctx.dt) > fixed.ONE) {
        var db: [24]u8 = undefined;
        return ctx.refuse("{s}: rate {s} over a {s}s tick closes more than the whole gap — a row would end up holding more than the neighbour it caught it from", .{ ctx.op.name, fixed.format(rate, &nb), fixed.format(ctx.dt, &db) });
    }
    // From the snapshot, both sides — the row's own too. A kernel's writes
    // land after the whole node loop, so the live value and the snapshot are
    // the same number here; reading one place keeps it that way when a
    // kernel grows a line above this one.
    const mine = s.neighUser(ctx.row_index, ch);
    var best = mine;
    if (ctx.handle(0)) |h| {
        if (h.ptr) |ptr| if (h.len > 0) {
            const ids: [*]const u32 = @ptrCast(@alignCast(ptr));
            for (ids[0..h.len]) |other| {
                const v = s.neighUser(other, ch);
                if (v > best) best = v;
            }
        };
    }
    if (best <= mine) return; // nobody near has more: nothing to catch
    const step = fixed.mul(best -% mine, fixed.mul(rate, ctx.dt));
    try ctx.write(wr.ref, .add, .{ .scalar = step });
}

/// `align <k>` — the third of the flocking trio: a row steers its velocity
/// toward the MEAN velocity of the rows `near` found, closing `k · dt` of the
/// difference. Separation is `push` with a positive gain and cohesion is the
/// same word with a negative one, so this is the only one of the three that
/// needed anything new — the neighbourhood had positions and user channels,
/// and a flock needs to know which way its neighbours are GOING.
///
/// The mean and not the maximum, which is the opposite of `infect`'s choice
/// and for the opposite reason: alignment is a consensus, and one fast row
/// should not drag the flock.
fn kAlign(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const k = try ctx.scalar(0);
    var nb: [24]u8 = undefined;
    if (k < 0) return ctx.refuse("{s}: gain {s} is negative — that steers a row AGAINST its neighbours, which is not a word yet", .{ ctx.op.name, fixed.format(k, &nb) });
    // `relax`'s guard, for `relax`'s reason: past one whole gap a row
    // overshoots the average it was steering toward, and past two it diverges
    // a little further every tick.
    if (fixed.mul(k, ctx.dt) > fixed.ONE) {
        var db: [24]u8 = undefined;
        return ctx.refuse("{s}: gain {s} over a {s}s tick closes more than the whole difference — a row would steer past the average it is joining", .{ ctx.op.name, fixed.format(k, &nb), fixed.format(ctx.dt, &db) });
    }
    const h = ctx.handle(0) orelse return; // `near` was quiet for this row
    const ids: [*]const u32 = @ptrCast(@alignCast(h.ptr orelse return));
    if (h.len == 0) return; // alone: nothing to agree with
    const mine = s.neighVel(ctx.row_index);
    var sum: fixed.Vec = .{ 0, 0, 0 };
    for (ids[0..h.len]) |other| {
        const theirs = s.neighVel(other);
        inline for (0..3) |a| sum[a] +%= theirs[a];
    }
    const gain = fixed.mul(k, ctx.dt);
    const n: Fixed = @intCast(h.len);
    var out: fixed.Vec = undefined;
    inline for (0..3) |a| out[a] = fixed.mul(@divTrunc(sum[a], n) -% mine[a], gain);
    try ctx.write(.{ .field = population.F_VEL }, .add, .{ .vec3 = out });
}

/// `deposit $chan <amount>` — the row leaves a MARK on a field channel, at
/// its own position, as wide as its own size. funideas §8: *"a particle
/// shouldn't necessarily disappear without consequence… particles become the
/// transport mechanism connecting simulations."*
///
/// The spray's `casts` is one standing aggregate the host REPLACES every
/// tick — where the cloud is, how much of it there is. This is the other
/// thing entirely: a mark that is added, decays on the channel's own clock,
/// and is never replaced. Rain leaves wetness; the wetness evaporates;
/// nobody wrote a "make this wall look wet" system.
///
/// The row only ASKS here. The mark is handed to the host serially in the
/// cast phase (`Spray.flushDeposits`), in row id order, because this runs in
/// the parallel sweep and a store is a store. A row leaves one mark a tick,
/// which is why the spray keeps one slot per row and mount refuses a second
/// `deposit`.
fn kDeposit(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const amount = try ctx.scalar(0);
    // Zero is not a mark. Negative is: a field sums its deposits, so a row
    // may take a thing away as readily as leave it — a raindrop landing on
    // hot stone is a negative deposit of heat.
    if (amount == 0) return;
    s.dep_amp[ctx.row_index] = amount;
}

fn kSync(ctx: *row.Ctx) row.Error!void {
    const s = try sprayOf(ctx);
    const wr = ctx.write_ref orelse return ctx.refuse("{s}: needs the field to synchronise — `sync row.u0 <drift> <couple>`", .{ctx.op.name});
    if (wr.ref.field < population.F_U0 or wr.ref.field >= population.F_U0 + population.USER_CHANNELS) {
        return ctx.refuse("{s}: only a user channel can be synchronised (row.u0 … row.u3) — a phase is the row's own state, and the user channels are what the neighbourhood snapshots", .{ctx.op.name});
    }
    const ch: u16 = wr.ref.field - population.F_U0;
    const drift = try ctx.scalar(0);
    const couple = try ctx.scalar(1);
    var nb: [24]u8 = undefined;
    if (couple < 0) return ctx.refuse("{s}: coupling {s} is negative — that drives neighbours APART, which is a different word", .{ ctx.op.name, fixed.format(couple, &nb) });
    // The same guard `relax` carries, for the same reason: the pull is at
    // most half a turn, so `couple · dt > 1` steps past the neighbours it
    // was leaning toward and, past two, further away every tick. A clamp
    // would leave a field of oscillators juddering while the picture moved.
    if (fixed.mul(couple, ctx.dt) > fixed.ONE) {
        var db: [24]u8 = undefined;
        return ctx.refuse("{s}: coupling {s} over a {s}s tick closes more than the whole gap — it would step past the neighbours it is leaning toward", .{ ctx.op.name, fixed.format(couple, &nb), fixed.format(ctx.dt, &db) });
    }
    // The row's own phase, from the snapshot too. This one is not a
    // correctness choice — nothing has written this row's phase yet when its
    // kernel runs, so the live value and the snapshot are the same number,
    // and the mutation that swaps them does not bite. It reads the snapshot
    // so that every phase in the expression comes from one place.
    const mine = s.neighUser(ctx.row_index, ch);
    var pull: Fixed = 0;
    if (ctx.handle(0)) |h| {
        if (h.ptr) |ptr| if (h.len > 0) {
            const ids: [*]const u32 = @ptrCast(@alignCast(ptr));
            var sum: i64 = 0;
            for (ids[0..h.len]) |other| sum += wrapHalf(s.neighUser(other, ch) -% mine);
            pull = @intCast(@divTrunc(sum, @as(i64, @intCast(h.len))));
        };
    }
    const step = fixed.mul(drift +% fixed.mul(couple, pull), ctx.dt);
    const next: Fixed = @intCast(@mod(@as(i64, mine) + @as(i64, step), @as(i64, fixed.ONE)));
    try ctx.write(wr.ref, .replace, .{ .scalar = next });
}

/// **The tags spindrift MINTS** — what a row word is FOR, in the vocabulary
/// rill's `OpDef.tags` opened (rill `8e044ec`, 2026-09-09). Five, because
/// five is what the row plane needed and rill's seventeen had no name for;
/// the six rill tags these words also carry are in `BORROWED` and their
/// sentences are NOT restated here. A second sentence for one tag is refused
/// at `describeTag`, and it is refused on evidence: Christian's own Blade3D
/// declares `Physics` twice with two descriptions, and `Constraints`
/// misspelled `Contraints`, unnoticed for years.
///
/// **The first tag is the home.** Declaration order, never alphabetical:
/// `push` is at home in `neighbourhood` and *found* under `motion`, and a
/// tidying sort of its list would file it beside `gravity`, away from the
/// `near` it cannot run without. G22 pins that with `push`, `align`,
/// `deposit` and `slide` — the four whose lists a sort would actually move.
///
/// **Nothing enforced is in here.** `row.only`, `publishes`/`consumes` and
/// which door registered a word all REFUSE programs; a tag is descriptive
/// and refuses nothing, so a tag restating one would be a label free to
/// drift from a real refusal. That is why the tracer four are not `world`:
/// `world` would say "registered through `registerTracer`", which the mount
/// already says by refusing an unknown word. `surface` says what they are
/// *for* instead. Same reason the neighbourhood tag is not `crowd` and the
/// tracer tag is not `contact` — both are SLATE lane names that mount
/// checks, and a tag wearing an enforced name invites exactly the confusion
/// the rule exists to prevent.
///
/// Read aloud, with what was rejected:
///
///   - `field` — rejected `lattice` (the implementation; a lattice is *how*
///     a field is sampled, and the language says `$chan`), `channel` (a
///     static KIND the registry already carries), `medium` (vague).
///   - `life` — rejected `lifecycle` (a compound; Christian's register is
///     single nouns — Blade3D reads `Logical`, `Curve`, `Noise`), `birth`
///     (half of it), `age` (a row field, and only `perish` reads it).
///   - `motion` — rejected `force` (it excludes `slide`, a projection, and
///     `spawn`, an initial condition: both motion, neither a force),
///     `velocity` (a row field name), `physics` (smears — `collide` is
///     physics too, and it is the group Blade3D declared twice).
///   - `neighbourhood` — rejected `crowd` (the slate lane, above), `flock`
///     and `swarm` (only three of the five flock; `sync` and `infect` do
///     not), `neighbour` (an operator is not a neighbour; the tag is the
///     subject), `social` (a phase oscillator is not sociable).
///   - `surface` — rejected `contact` (the slate lane), `world` (above),
///     `collision` (`ground` is a proximity query and collides with
///     nothing), `hit` (an event, not a subject).
///
/// Sorted, like rill's roster, because a listing prints tags sorted and a
/// reader comparing the two should not have to re-sort one.
pub const TAGS = [_]rill.registry.TagDoc{
    .{ .name = "field", .doc = "a quantity spread over space: read it where the row is, or leave a mark on it" },
    .{ .name = "life", .doc = "a row's beginning and its end: launched at birth, retired at death" },
    .{ .name = "motion", .doc = "what changes where a row is going: the launch, the forces on it, and what a surface takes away" },
    .{ .name = "neighbourhood", .doc = "the rows close by, and what they do to this one" },
    .{ .name = "surface", .doc = "solid geometry: what the row hit, where, and what it does about it" },
};

/// **The rill tags a spindrift word carries**, and the argument for each.
/// Listed rather than described — rill owns their sentences — so that the
/// audit can close over the whole set both ways, and so a tag rill RETIRES
/// lands as a red gate here rather than as a palette filter that finds
/// nothing.
///
///   - `envelope` — `relax` IS rill's `ease` at the row: "a value in motion
///     over fed time: it chases". It emits the step rather than the arrival
///     so influences compose, which is a difference in the port, not in what
///     the word is for.
///   - `oscillator` — `sync` is a phase oscillator, the same family as
///     `wave` and `lfo`; the coupling is what is new, not the going round.
///   - `random` — `spawn`'s ±spread is a seeded draw off `row.seed`,
///     bit-identical on every machine, which is that sentence exactly.
///   - `sink` — `deposit` is `cast`'s row-plane sibling and `cast` is at
///     home there, so the two stay filed together. `class` is `.reads` and
///     not `.effect` (a row word may not write the plane), which is the
///     proof this tag restates nothing enforced.
///   - `space` — `near` is `within` asked of a whole population, and "what
///     is near what" is rill's own sentence for the tag.
///   - `time` — `perish`'s threshold is a duration and `relax`'s rate is per
///     second. Deliberately NOT on `gravity`, `push`, `align`, `sync` or
///     `infect`: their `dt` is a multiplier, not the subject, and a tag true
///     of eleven of fifteen words filters nothing.
///
/// Sorted, for `TAGS`'s reason.
pub const BORROWED = [_][]const u8{ "envelope", "oscillator", "random", "sink", "space", "time" };

/// The tracer words — a host with a `World` registers these beside the
/// core; a host without leaves a kernel that names one to refuse at mount.
pub const TRACER = [_]rill.OpDef{
    .{
        .name = "collide",
        .tags = &.{"surface"},
        .outputs = &.{
            .{ .name = "at", .ty = Tag.any },
            .{ .name = "normal", .ty = Tag.any },
            .{ .name = "t", .ty = Tag.number },
            .{ .name = "material", .ty = Tag.number },
        },
        .help = "Row word (host): the row's move this tick against the world, swept as a SPHERE of row.size. On a hit, the contact point (piped on) — the row's CENTRE at contact, one radius off the surface — then the surface normal, t, material; no hit, nothing. A row with size 0 is the old point test exactly. A negative row.size refuses by name. `collide | stick`.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kCollide),
        .eval = planeRefuse,
    },
    .{
        .name = "ground",
        .tags = &.{"surface"},
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
        .name = "slide",
        .tags = &.{ "surface", "motion" },
        .publishes = &.{"contact"},
        .inputs = &.{ .{ .name = "at", .ty = Tag.any }, .{ .name = "normal", .ty = Tag.any } },
        .help = "Row word: take the contact's normal out of the row's velocity and put the row on the surface — vel -= (n * vel) n, pos <- at. What is left is the tangent, so the row runs along what it hit. Subtracts rather than replaces, so gravity and the wind still compose. `collide | slide | stick`.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kSlide),
        .eval = planeRefuse,
    },
    .{
        .name = "stick",
        .tags = &.{"surface"},
        .publishes = &.{"contact"},
        .inputs = &.{ .{ .name = "at", .ty = Tag.any }, .{ .name = "normal", .ty = Tag.any } },
        .help = "Row word: land the row — position the contact `at`, row.normal the contact normal, row.stuck set; the sweep holds it. `at` is the row's CENTRE at contact, one radius off the surface, because `collide` sweeps the row as a sphere of row.size — so the appearance draws a stuck row at `pos`, not at pos + normal × size. A stuck row still ages and reads its curves. `collide | stick` (the normal rides the pipe by name).",
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
        .tags = &.{ "life", "motion", "random" },
        .help = "Row word: on a row's birth tick, launch it — vel ← the spray's aim × speed, ± spread per axis from the row's seed. Does nothing on later ticks.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kSpawn),
        .eval = planeRefuse,
    },
    .{
        .name = "gravity",
        .tags = &.{"motion"},
        // **`pull`, and it was `g` until 2026-09-12** — the last one-letter
        // port in the set, renamed on the same pass and for the same reason as
        // `push`'s and `align`'s. `g` under a node called `gravity` is a
        // convention a reader completes without help, which is why it survived
        // the first pass; Christian's ruling was that a canvas should not ask
        // anyone to complete anything.
        //
        // `accel` was the accurate alternative and is rejected on the rule
        // that killed `:param` an hour earlier: an abbreviation is the same
        // crime one syllable longer. `force` is wrong — this is
        // mass-independent — and `down` inverts the sign a reader types.
        .inputs = &.{.{ .name = "pull", .ty = Tag.number }},
        .help = "Row word: vel.y += pull · dt, in cells/s², NEGATIVE is down — `gravity -9.8`, or `gravity plane.drift.@self.gravity` from a knob. A positive pull lifts, which is what `kernels/fireflies.rill` uses it for.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kGravity),
        .eval = planeRefuse,
    },
    .{
        .name = "perish",
        .tags = &.{ "life", "time" },
        .help = "Row word: retire the row on the first tick its age has reached its life. A kernel without it has immortal rows.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kPerish),
        .eval = planeRefuse,
    },
    .{
        .name = "relax",
        .tags = &.{ "envelope", "time" },
        .inputs = &.{
            .{ .name = "in", .ty = Tag.number },
            .{ .name = "target", .ty = Tag.number },
            .{ .name = "rate", .ty = Tag.number },
        },
        .outputs = &.{.{ .name = "step", .ty = Tag.number }},
        .help = "Row word: the STEP toward `target` at `rate` per second — (target - in) * rate * dt. It emits the step, not the arrival, so influences compose: `row.u0 | relax 1 0.9 | write row.u0 add`, and a second line adds another. A negative rate, or one that closes more than the gap in a tick, refuses by name.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kRelax),
        .eval = planeRefuse,
    },
    .{
        .name = "near",
        .tags = &.{ "neighbourhood", "space" },
        .inputs = &.{.{ .name = "radius", .ty = Tag.number }},
        .outputs = &.{.{ .name = "count", .ty = Tag.number }},
        .help = "Row word: how many live rows are within `radius` — and which ones, on the slate's handle lane under `crowd`, for `push` to read. Any positive radius is answerable; a wide one costs more cells, it does not miss rows.",
        .class = .reads,
        .routes = .anywhere,
        .publishes = &.{"crowd"},
        .row = rowOnly(kNear),
        .eval = planeRefuse,
    },
    .{
        .name = "push",
        .tags = &.{ "neighbourhood", "motion" },
        // **`gain`, and it was `k` until 2026-09-12.** Christian, looking at
        // the graph editor drawing three nodes with a pin labelled `k`:
        // *"people will ask, wtf is k."* They will. The node beside this one
        // has always spelled its ports `drift` and `couple`, so the house
        // style was never in doubt — these two were the holdouts, and a canvas
        // is what made them visible.
        //
        // Safe to rename because no port here is `kw`: a caller writes `push
        // :tuning.shove` positionally, so no file in the corpus spells the
        // name at all. It is the PIN that says it, to a reader.
        .inputs = &.{.{ .name = "gain", .ty = Tag.number }},
        .help = "Row word: separation — lean away from everything `near` found, `vel += sum(pos - other) * gain * dt`. A PER-NEIGHBOUR gain: the force grows with the crowd, so a wide ring wants a much smaller one than a tight ring. Reads the list off the slate rather than gathering it again. Needs a `near` above it.",
        .class = .reads,
        .routes = .anywhere,
        .consumes = &.{"crowd"},
        .row = rowOnly(kPush),
        .eval = planeRefuse,
    },
    .{
        .name = "align",
        .tags = &.{ "neighbourhood", "motion" },
        .inputs = &.{.{ .name = "gain", .ty = Tag.number }},
        .help = "Row word: alignment — steer toward the MEAN velocity of the rows `near` found, `vel += (mean(other.vel) - vel) * gain * dt`. The third of the flocking trio; separation is `push <gain>` and cohesion is `push` with a NEGATIVE gain, so a boid is `near` + those three. Neighbours' velocities come from the neighbourhood's snapshot. Needs a `near` above it.",
        .class = .reads,
        .routes = .anywhere,
        .consumes = &.{"crowd"},
        .row = rowOnly(kAlign),
        .eval = planeRefuse,
    },
    .{
        .name = "sync",
        .tags = &.{ "neighbourhood", "oscillator" },
        .statics = &.{.{ .name = "field", .kind = .path }},
        .inputs = &.{ .{ .name = "drift", .ty = Tag.number }, .{ .name = "couple", .ty = Tag.number } },
        .help = "Row word: a phase oscillator that listens to the rows `near` found — `phase += (drift + couple * mean(wrap(other - phase))) * dt`, wrapped into [0, 1). Only a user channel; neighbours' phases come from the neighbourhood's snapshot. Needs a `near` above it. `sync row.u0 row.u1 3`.",
        .class = .reads,
        .routes = .anywhere,
        .consumes = &.{"crowd"},
        .row = rowOnly(kSync),
        .eval = planeRefuse,
    },
    .{
        .name = "infect",
        .tags = &.{"neighbourhood"},
        .statics = &.{.{ .name = "field", .kind = .path }},
        .inputs = &.{.{ .name = "rate", .ty = Tag.number }},
        .help = "Row word: a channel SPREADS between neighbours — a row closes `rate * dt` of the gap to the highest value among the rows `near` found, and never goes down. The maximum and not the mean: a mean is diffusion and smears a peak, a maximum is transmission and makes a front. Recovery is `relax 0 <rate>` on the same channel, so an epidemic is two lines and the balance of the two rates is the threshold. Only a user channel; needs a `near` above it. `infect row.u0 3`.",
        .class = .reads,
        .routes = .anywhere,
        .consumes = &.{"crowd"},
        .row = rowOnly(kInfect),
        .eval = planeRefuse,
    },
    .{
        .name = "deposit",
        .tags = &.{ "sink", "field" },
        .statics = &.{.{ .name = "channel", .kind = .channel }},
        .inputs = &.{.{ .name = "amount", .ty = Tag.number }},
        .help = "Row word: leave a MARK on a field channel at this row's position, as wide as this row's size — `deposit $soot 0.4`. Added and left to decay, never replaced, which is what makes it different from the spray's `casts` aggregate. Handed to the host serially after the sweep, in row id order. A row leaves one mark a tick and mount refuses a second `deposit`; a host with nowhere to put marks refuses by name.",
        .class = .reads,
        .routes = .anywhere,
        .row = rowOnly(kDeposit),
        .eval = planeRefuse,
    },
    .{
        .name = "hear",
        .tags = &.{"field"},
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
///
/// The five minted sentences go in through the same door, and both TABLES
/// are described here rather than in `registerTracer` because `surface` is
/// carried only by the tracer words and a host with no `World` must still be
/// able to read what the tag means. A tag rill later adopts under one of
/// these five names refuses HERE, loudly, at startup — which is the answer
/// `describeTag` was built to give, and better than two sentences racing to
/// be the one a palette read last.
pub fn register(reg: *rill.Registry) !void {
    for (TAGS) |t| try reg.describeTag(t);
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
