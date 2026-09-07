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
    const at = try ctx.vec3(0);
    const normal = try ctx.vec3(1);
    // The row's position is the CONTACT point, and the contact normal is
    // stored on the row (ruling 27b): the resting offset — a disc or a
    // light drawn at `pos + normal · size`, tangent to the surface — is the
    // appearance's, one rule for every row with no stuck branch, so a
    // landed row that shrinks stays on the surface by construction. The
    // first draft offset `pos` here (ruling 24 as first ruled) and a
    // shrinking ember kept its landing height. `hear` samples at the
    // contact. The normal rides the pipe from `collide` by name.
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

/// `push <k>` — separation: lean away from everything `near` found, at `k`
/// cells per second per cell of offset. `vel += Σ (pos − other) · k · dt`.
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
        .name = "slide",
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
        .publishes = &.{"contact"},
        .inputs = &.{ .{ .name = "at", .ty = Tag.any }, .{ .name = "normal", .ty = Tag.any } },
        .help = "Row word: land the row — position the contact point `at`, row.normal the contact normal, row.stuck set; the sweep holds it. The appearance draws a stuck row at pos + normal × size. A stuck row still ages and reads its curves. `collide | stick` (the normal rides the pipe by name).",
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
        .name = "relax",
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
        .inputs = &.{.{ .name = "k", .ty = Tag.number }},
        .help = "Row word: separation — lean away from everything `near` found, `vel += sum(pos - other) * k * dt`. Reads the list off the slate rather than gathering it again. Needs a `near` above it.",
        .class = .reads,
        .routes = .anywhere,
        .consumes = &.{"crowd"},
        .row = rowOnly(kPush),
        .eval = planeRefuse,
    },
    .{
        .name = "sync",
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
