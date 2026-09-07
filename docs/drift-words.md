# The drift words

Spindrift's operators, registered into rill's registry through the same
`Registry.register` as every core word — so the reserved-name rule, the
tail rule and the argument-spelling rule bind them at registration. Every
word here is a **row word**: it means something on a spray and nothing on
the world plane. Piped into a plane program, it refuses at mount by name.

A kernel is a rill program whose plane is the row (`rill-spec.md` §3.16).
Row fields are `row.pos`, `row.vel`, `row.age`, `row.life`, `row.seed`,
`row.size`, `row.colour`, `row.kind`, `row.stuck`, `row.normal` (the
contact, once `stick` landed the row; zero otherwise), `row.alpha` (the
row's opacity in [0, 1], born 1 — the appearance's hit test takes it as a
factor on the disc's coverage; a landed value outside [0, 1] is refused
on the write node and lands nothing, beat 6), `row.u0`–`row.u3`;
the spray's knobs
are `plane.drift.@self.<knob>`, broadcast to every row.

**A user channel carrying a manifold coordinate must stay in range, and
nothing here will tell you if it does not.** `row.alpha` carries bounds so
a bad curve refuses on the write node rather than looking plausible
(campaign 2, ruling 3); `row.u0`–`u3` cannot, because a user channel is
whatever a kernel means by it. When one of them is an appearance
coordinate the cost of leaving [0, 1] is not a clamp — the reader MIRRORS.
loam's `Set.fold` reflects a query point back into the cube on every axis
(`loam/src/rbf.zig:145-155`), so a `cooled` of 1.2 reads at 0.8 and an
over-cooled row comes back looking HOT. Spell every state line as an
approach that saturates — `relax` toward the target, never a bare add —
and the range holds by construction rather than by care.

```rill
// embers.rill
spawn
gravity plane.drift.@self.gravity
perish
```

```rill
// smoke.rill — leans away from the wind's source, and (declared on the
// ^spray, not here) casts $dankness where it drifts
spawn
gravity plane.drift.@self.gravity
$wind grad at row.pos | mul plane.drift.@self.lean | write row.vel add
perish
```

| word | reads | writes | what |
|---|---|---|---|
| `spawn` | the spray's aim, speed, spread; the row's seed | `row.vel` | On a row's birth tick, launch it: `vel ← aim × speed`, plus a per-axis draw in ±spread from the seed. Nothing on later ticks. A kernel without it has rows that sit where they were born. |
| `gravity <g>` | `g` — a literal, or a broadcast knob | `row.vel.y`, add mode | `vel.y += g · dt`, cells per second², negative is down. |
| `perish` | `row.age`, `row.life` | retires the row | On the first tick the row's age has reached its life, mark it; the spray reaps in its serial phase. A kernel without it has immortal rows, and a full population says `throttled`. |
| `relax <target> <rate>` | `in` (piped), `target`, `rate` — literals or broadcast knobs | — (emits the step) | The step toward `target` at `rate` per second: `(target − in) · rate · dt`. It emits the STEP, not the arrival, so influences COMPOSE — `row.u0 \| relax 1 0.9 \| write row.u0 add` cools a row, and a second line `row.u0 \| relax 1 8 \| mul row.stuck \| write row.u0 add` cools a landed one faster still; the queued adds land on the live field in turn and sum the way forces do. A word that returned the new value could only ever be the last word to speak. The rate is PER SECOND because the word eats the fed dt, and that is the reason it is a word at all: `(1 − x) · rate` is spellable with core rill (`\| mul -1 \| add 1 \| mul <rate>`) but only per TICK, and `fire.rill` spelled it that way for a beat before this one. A NEGATIVE rate refuses by name — that is divergence, not a slow relax; so does one whose step closes more than the whole gap (`rate · dt > 1`), which would carry the value past the target and, past two, further away every tick. A clamp there would leave a kernel oscillating while the picture looked plausible (campaign 2, ruling 3). Read-aloud: "u0, relax toward 1 at nine tenths a second." |
| `collide` | `row.pos`, `row.vel`, the spray's `World` | — (emits: hit point, normal, `t`, material) | The host's word (campaign §7.7): the row's move this tick, `pos → pos + vel · dt`, against the world through the CPU twin tracer; on a hit the hit point pipes on and normal, `t`, material ride the other ports — a downstream word takes them by NAME (`stick`'s `normal` port; rill's rule, beat 5); no hit, the flow ends quietly. Exact at the row — the host does its float query once and answers in fixed point. **The segment is the kernel-start move** (ruling 20): every word in a row's sweep reads the tick's snapshot, so `collide` tests `pos → pos + vel·dt` with the velocity the row HAD when the kernel began, while the integrate moves it with the velocity the kernel LEFT. They differ by the tick's acceleration × dt²: 0.0007 cells at 60 Hz under −2.5, 0.1 cells on a 100 ms headless tick. A host that finds a row inside a solid places it on the face it came through. `material` is an opaque host handle (ruling 23): 0 is nothing; compare it only against a value the host publishes, never against an engine table index, never arithmetic. A kernel naming it on a host with no World is refused at mount as an unknown word. |
| `ground` | `row.pos`, the spray's `World` | — (emits: signed distance, normal) | The host's word: the nearest surface below the row. |
| `slide <at> <normal>` | the hit point, piped; the normal, by name from `collide`; the row's velocity | `row.pos`, `row.normal`, `row.vel` (add) | Take the contact's normal OUT of the velocity and put the row on the surface: `vel −= (n · vel) n`, `pos ← at`. What is left is the tangent, so the row RUNS ALONG what it hit instead of stopping on it — rain down a window, an ember down a sloped hearth, and a soot streak where `stick` alone leaves a dot. It SUBTRACTS rather than replacing, for the reason `relax` emits a step: as an add it composes. A replace lands the snapshot's tangent over everything else the tick had to say, and a row on a slope then gains speed in STAIR-STEPS — holding a velocity for several ticks and jumping on the one where it has sunk far enough for a real crossing rather than a resume — so its acceleration is a function of the tick rate and the geometry. As an add the gain is the tangential gravity times dt, every tick, by construction. As an add it composes: gravity pulls, the wind pushes, `slide` removes the part of the result that would go through the wall. The correction is computed from the tick's snapshot, so it lags one tick exactly as `collide`'s segment does (ruling 20) — the row ends each tick a `g · dt²` sliver INSIDE the surface and the world's resume puts it back next tick. Without that resume `slide` cannot work at all: the row sinks on its first contact and a mock that says "already through" abandons it there. The normal is taken to be UNIT, as every `World` answers it; a longer one over-corrects by \|n\|², which is the host's bug and would cost a square root per row to catch. `collide \| slide \| stick`. |
| `stick <at> <normal>` | the hit point, piped; the normal, by name from `collide` | `row.pos`, `row.normal`, `row.stuck` | Land the row: position the CONTACT point, `row.normal` the contact normal, `row.stuck` set. The resting offset is the appearance's (ruling 27b): a disc or a light is drawn at `pos + normal · size`, tangent to the surface, one rule for every row — so a landed row that shrinks stays on the surface by construction, and `hear` still samples at the contact. A stuck row has no velocity — the sweep drops whatever the kernel added, every tick, which is what `stuck` means — so it stays where it landed; it still ages and still reads its curves. `collide \| stick` is the ember on the plate and the spark on the trim in one breath. |
| `hear $chan [grad] at <pos>` | the spray's lattice for `$chan`, at `pos` | — (a value) | The field read. Spelled `$wind at row.pos` (value) or `$wind grad at row.pos` (gradient, toward the caster) — the parser desugars to `hear`. The spray must declare `samples $wind cell <c>` or the kernel is refused at mount; the lattice is rasterised from the host's bag once per tick and the row trilinear-samples it, integer-exact. Coupled deposits (`to #tag`) reach a spray only while it carries the tag. |

Rejected at read-aloud (campaign §9): `die`/`kill` for `perish` — `perish`
reads as the row's own verb where `kill` reads as someone else's; `bend`
for the wind coupling is held for P2. For the fifth word: `across` ("age
across life") reads as a span, not a fraction; `curve` ("age curve life")
names the shape, not the operation. `over` reads as the division it is —
age over life — and the knots ride behind it. For the landing word: `land`
fit the plate and not the wall; `settle` and `rest` read as easing, not a
stop; `stick` is the ember on the plate and the spark on the trim. For the
tangent word: `slip` reads as a failure rather than a motion; `skid`
promises a friction this does not model (a frictionless slide on a flat
floor runs for ever, and that is a thing you can see); `graze` is a near
miss, the opposite; `tangent` names the plane, not the act; `deflect` says
bounce, and nothing here reflects. For the
step word: `decay` only ever goes toward zero and half of `fire.rill`'s
lines climb; `approach` reads as motion in space and this is a scalar;
`cool` names one customer, not the operation; `toward` wants a preposition
it has not got; `ease` and `ramp` are rill's own, on the plane and
stateful — a different thing wearing a near name.

## `over` — rill's word now

`row.age | over row.life [1.0, 0.7, 0.0]` — a value over normalised life,
piecewise linear over evenly spaced knots, numbers or Oklab colours, the
curve a literal or a broadcast (`plane.drift.@self.size_curve`) — was
spindrift's fifth word from beat 3. In beat 5 rill took it into its core
(rill `23ac55c`): the same spelling, the same bits (the clamped divide,
the segment by shift, the fraction by mask, `lerpVal`), on the plane as
well as the row, a zero span refused by name. Spindrift's kernel is
deleted rather than kept beside it; the gates here still run it through
`mountKernel` and still bite. It is not in the table above because the
table is the words THIS library registers (G2's parity gate counts them).

## Recorded, not built (beat 5)

| what | trigger |
|---|---|
| (B) integrate with the kernel-start velocity, so `collide`'s segment IS the move — explicit Euler where today is semi-implicit, costing stability as well as every hash | a tunnel at frame rate in a customer scene (ruling 20) |
| (C′) a second snapshot after an `integrate` line — statements below it read the post-move row, which is (C) without breaking the snapshot rule | the same trigger (ruling 20); (C) itself — one word reading the future — is refused |
