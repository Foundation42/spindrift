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

**A kernel's own knobs live in their own room.** `rate`, `speed`, `spread`
and `life` under the spray's `@name` are the SPRAY's four — the host's
documented interface, driven from an ordinary rill (`write
plane.drift.@sparks.rate 2 mul`) and re-read by the host every tick. A
kernel may READ them; that is what they are for. Everything else a kernel
wants told to it goes under `.k.` — `plane.drift.@self.k.gravity`,
`@self.k.lean` — and a kernel naming any other knob flat under its own
`@name` is refused at MOUNT, by name, with where to put it instead.

The room exists because one path had two owners and neither was wrong.
`plane.drift.@self.spread`, meant as a kernel's own spreading rate, was
also the spray's launch cone: the host re-read it every tick and retuned
the cone to 0.013 cells/s while the mount line printed the 1.6 the flag
had asked for. Every row went straight up in a pencil, green. `gravity`
moved into `.k.` with the rest — it was never a spray knob at all, only a
kernel one that `drift-run` seeded on the flat path, which is the whole
confusion in miniature.

**The slate** (rill `docs/slate.md`) is the third path head, beside
`plane.` and `row.`: a named register file that lives for one row of one
tick. An operator says something on it and the lines BELOW read it —
`slide` and `stick` both say `contact`. It exists because a row field
cannot carry a within-tick fact: rill lands a row's writes only after the
whole node loop, so a field written at node 3 is invisible at node 7 and
arrives next tick, and a value that crosses a tick boundary is state owing
a dump. A `slate.<name>` nothing says, or one read above the line that says
it, is refused at mount by name.

**A spray SAYS what its coordinate channels mean.** `fire.rill` writes a
point in an appearance manifold to `row.u0`–`u2` and no colour at all;
`motes.rill` writes a phase to `row.u0`. What those channels MEAN is a
declaration, not a comment: a host sets `Spray.setAppearance(.{ .coord =
.{0, 1, 2}, .manifold = "fire" })` and the spray says it on the plane at
`plane.drift.@<name>.appearance`, once, change-only, beside its count and
bounds. A channel the population has not got is refused when it is set.

Spindrift resolves `manifold` and evaluates NOTHING against it. It is a
name the host resolves — matryoshka resolves it to a loam RBF set and reads
it in a shader — which is the same seam `World` and `Fields` already have:
spindrift declares it, a host fills it, the mock fills it for the gates,
and no dependency travels in either direction. Until this the meaning lived
in a comment, which is how the fire manifold got authored upside down with
every number still in range.

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
gravity plane.drift.@self.k.gravity
perish
```

```rill
// smoke.rill — leans away from the wind's source, and (declared on the
// ^spray, not here) casts $dankness where it drifts
spawn
gravity plane.drift.@self.k.gravity
$wind grad at row.pos | mul plane.drift.@self.k.lean | write row.vel add
perish
```

| word | reads | writes | what |
|---|---|---|---|
| `spawn` | the spray's aim, speed, spread; the row's seed | `row.vel` | On a row's birth tick, launch it: `vel ← aim × speed`, plus a per-axis draw in ±spread from the seed. Nothing on later ticks. A kernel without it has rows that sit where they were born. |
| `gravity <g>` | `g` — a literal, or a broadcast knob | `row.vel.y`, add mode | `vel.y += g · dt`, cells per second², negative is down. |
| `perish` | `row.age`, `row.life` | retires the row | On the first tick the row's age has reached its life, mark it; the spray reaps in its serial phase. A kernel without it has immortal rows, and a full population says `throttled`. |
| `relax <target> <rate>` | `in` (piped), `target`, `rate` — literals or broadcast knobs | — (emits the step) | The step toward `target` at `rate` per second: `(target − in) · rate · dt`. It emits the STEP, not the arrival, so influences COMPOSE — `row.u0 \| relax 1 0.9 \| write row.u0 add` cools a row, and a second line `row.u0 \| relax 1 8 \| mul row.stuck \| write row.u0 add` cools a landed one faster still; the queued adds land on the live field in turn and sum the way forces do. A word that returned the new value could only ever be the last word to speak. The rate is PER SECOND because the word eats the fed dt, and that is the reason it is a word at all: `(1 − x) · rate` is spellable with core rill (`\| mul -1 \| add 1 \| mul <rate>`) but only per TICK, and `fire.rill` spelled it that way for a beat before this one. A NEGATIVE rate refuses by name — that is divergence, not a slow relax; so does one whose step closes more than the whole gap (`rate · dt > 1`), which would carry the value past the target and, past two, further away every tick. A clamp there would leave a kernel oscillating while the picture looked plausible (campaign 2, ruling 3). Read-aloud: "u0, relax toward 1 at nine tenths a second." |
| `near <radius>` | the spray's neighbourhood — a dense grid over the live rows' bounds, rebuilt once a tick at the tail of the serial spawn | — (emits the count; SAYS the list on the slate's handle lane under `crowd`) | How many live rows are within `radius`, and which ones. The count is an ordinary number; the LIST is the thing no row value can hold — the row plane's arrays are literal-only and no operator emits one — so it rides the slate's HANDLE lane as a pointer into the spray's per-chunk buffer, valid for exactly this row's evaluation. That is the same lifetime the slate gives everything, and it is the whole reason a raw pointer is safe there. Only the cells the radius can actually reach are searched — the range is computed from the radius, not fixed at 3×3×3 — so any positive radius is answerable and a wide one costs more cells rather than missing rows. It DID refuse a radius wider than the cell until 2026-09-08, when the search walked a fixed 27 and refusing was the only honest answer. A row with more neighbours than `MAX_NEIGHBOURS` hands on a truncated list and the tick says `crowded`. |
| `push <k>` | the list `near` said, off the slate | `row.vel`, add mode | Separation: lean away from everything `near` found — `vel += sum(pos − other) · k · dt`. It reads the list rather than gathering it again, which is the point: the answer was already found this row and a second gather costs twice for the same result. Needs a `near` ABOVE it, and mount refuses it otherwise by name. The falloff is the neighbourhood's own edge and nothing softer — a row just inside pushes, one just outside does not; a customer that can see the seam is the trigger for a weight. |
| `align <k>` | the rows `near` said, and their velocities from the neighbourhood's snapshot | `row.vel`, add mode | Alignment: steer toward the MEAN velocity of everything `near` found — `vel += (mean(other.vel) - vel) * k * dt`. The third of the flocking trio, and the only one that needed anything new: separation is `push <k>`, cohesion is the same word with a NEGATIVE k, and a boid is `near` plus those three. Two `near` lines with different radii give the real thing — a tight separation ring inside a wide cohesion one — because a `push` or an `align` reads whichever `near` is nearest ABOVE it. The MEAN and not the maximum, which is `infect`'s choice inverted and for the inverse reason: alignment is a consensus, so one fast row must not drag the flock. Velocities come from the SNAPSHOT — a live read would have half the flock steering toward velocities the other half had not adopted yet. Needs a `near` above it. |
| `sync <row.uN> <drift> <couple>` | the field named, the rows `near` said, and their phases from the neighbourhood's snapshot | the named user channel, replace | A phase oscillator that listens to its neighbours — `phase += (drift + couple · mean(wrap(other − phase))) · dt`, wrapped into [0, 1). To ENTRAIN, which is the word for what it does. Give every row a slightly different `drift` (from `row.seed`, say) and neighbours lock together while distant ones do not; a field of them makes travelling waves, and nothing here makes a wave — the wave is what a field of these DOES. The coupling is the phase difference itself and not its sine: the sawtooth oscillator rather than Kuramoto proper, which entrains the same way and is exact in Q16.16 where a sine would want a table and a second definition of `sin` in the ecosystem. Neighbours' phases come from the SNAPSHOT — a live read would have row 1 seeing row 0's new phase and row 0 seeing row 1's old one, which is Gauss-Seidel where the sweep promises Jacobi. Only a user channel may be synchronised, and anything else refuses by name. Needs a `near` above it. |
| `infect <row.uN> <rate>` | the field named, the rows `near` said, and their values from the neighbourhood's snapshot | the named user channel, ADD mode | Transmission: a channel spreads between neighbours. A row closes `rate · dt` of the gap to the HIGHEST value among the rows `near` found, and never goes down. funideas §6 — *"transfer a state variable between neighbours; now you've got spreading fire, bioluminescence, chemical reactions, disease, magic, whatever."* The maximum and not the mean, deliberately: a mean is diffusion, which is `relax` toward a neighbour average and smears a peak into a haze; a maximum is transmission, and it makes a FRONT you can watch cross a cloud. MONOTONE for the same reason `infect` is the word — you catch it from somebody who has more, and a row among cleaner rows does not get cleaner. Recovery is a separate fact with its own rate, and `relax 0 <rate>` on the same channel already is it, so an epidemic is two lines and the balance between the two rates is the threshold between a thing that spreads and a thing that dies out; one word with two rates would have hidden the number worth playing with. Adds its step rather than replacing (unlike `sync`, whose phase wraps), so it composes with the recovery line. Only a user channel, and anything else refuses by name. Needs a `near` above it. |
| `collide` | `row.pos`, `row.vel`, `row.size`, the spray's `World` | — (emits: contact point, normal, `t`, material) | The host's word (campaign §7.7): the row's move this tick, `pos → pos + vel · dt`, against the world through the CPU twin tracer, swept as a SPHERE of `row.size`; on a hit the contact point pipes on and normal, `t`, material ride the other ports — a downstream word takes them by NAME (`stick`'s `normal` port; rill's rule, beat 5); no hit, the flow ends quietly. Exact at the row — the host does its float query once and answers in fixed point. **The segment is the kernel-start move** (ruling 20): every word in a row's sweep reads the tick's snapshot, so `collide` tests `pos → pos + vel·dt` with the velocity the row HAD when the kernel began, while the integrate moves it with the velocity the kernel LEFT. They differ by the tick's acceleration × dt²: 0.0007 cells at 60 Hz under −2.5, 0.1 cells on a 100 ms headless tick. A host that finds a row inside a solid places it on the face it came through. `material` is an opaque host handle (ruling 23): 0 is nothing; compare it only against a value the host publishes, never against an engine table index, never arithmetic. A kernel naming it on a host with no World is refused at mount as an unknown word. **A row IS a sphere of `row.size`** (ruled 2026-09-08): the radius is authored nowhere — it is the field the appearance already draws with and `deposit` already marks with, because a row with two widths would be two rows. It was a zero-width POINT until then, and that was measured as a bug rather than a simplification: in matryoshka's playground, particles walking a floor passed straight through a sphere and a box resting on it — 1.1–1.3× the density of a control annulus inside their footprints, no blocking at all — because the rows rest at y = 0 exactly and both props' cross-section AT y = 0 is a tangent point and a coplanar face. A point through the one height where a prop has no cross-section hits nothing, and no nudge to a prop's height fixes the class of that. The point it emits is the sphere's CENTRE at contact, one radius off the surface along the normal, and never the surface point: `stick` and `slide` both write `pos ← at`, so a centre placed ON the surface starts the next tick interpenetrating, which is the same bug wearing a hat. The normal is still the SURFACE's. **`row.size` = 0 is the point test, bit for bit** — same `t`, `at`, `normal`, `material` — which is what keeps G0's byte-identity and G7's bit-identity claims meaningful across the change, and a host may not carry a "safety" epsilon into that path. The size is read from the row's snapshot like everything else in the sweep (ruling 20), so a row that writes `row.size` this tick collides at the width it had when the kernel began. A NEGATIVE `row.size` refuses by name: a negative radius moves the surface the wrong way, and the row would tunnel further than a point does while the picture looked nearly right. |
| `ground` | `row.pos`, the spray's `World` | — (emits: signed distance, normal) | The host's word: the nearest surface below the row, measured from the row's CENTRE. **No radius**, decided with `collide`'s (2026-09-08): `collide` had to take one because its answer is a POSITION the row adopts and a position that ignores the radius is a position inside the wall, while `ground` answers a distance nothing moves to. So every number a `World` hands back is about the centre — one convention rather than two — and the clearance under the BODY is a kernel line, `ground | sub row.size`, exact and needing no word. It also costs a host nothing: `groundFn` is unchanged. Recorded, with its trigger: the first word that PLACES a row from `ground`'s answer wants the radius the way `collide` does. |
| `slide <at> <normal>` | the contact point, piped; the normal, by name from `collide`; the row's velocity | `row.pos`, `row.normal`, `row.vel` (add) | Take the contact's normal OUT of the velocity and put the row on the surface: `vel −= (n · vel) n`, `pos ← at`. "On the surface" is the sphere's centre one radius off it since 2026-09-08, by the same route as `stick`'s — `at` comes from `collide` and `slide` writes what it was handed — so a sliding row rides the surface at its own radius instead of dragging its centre along it. What is left is the tangent, so the row RUNS ALONG what it hit instead of stopping on it — rain down a window, an ember down a sloped hearth, and a soot streak where `stick` alone leaves a dot. It SUBTRACTS rather than replacing, for the reason `relax` emits a step: as an add it composes. A replace lands the snapshot's tangent over everything else the tick had to say, and a row on a slope then gains speed in STAIR-STEPS — holding a velocity for several ticks and jumping on the one where it has sunk far enough for a real crossing rather than a resume — so its acceleration is a function of the tick rate and the geometry. As an add the gain is the tangential gravity times dt, every tick, by construction. As an add it composes: gravity pulls, the wind pushes, `slide` removes the part of the result that would go through the wall. The correction is computed from the tick's snapshot, so it lags one tick exactly as `collide`'s segment does (ruling 20) — the row ends each tick a `g · dt²` sliver INSIDE the surface and the world's resume puts it back next tick. Without that resume `slide` cannot work at all: the row sinks on its first contact and a mock that says "already through" abandons it there. The normal is taken to be UNIT, as every `World` answers it; a longer one over-corrects by \|n\|², which is the host's bug and would cost a square root per row to catch. `collide \| slide \| stick`. It also SAYS `contact` on the slate (rill `9c97bbe`), because a sliding row is against the cold thing every tick and `row.stuck` is 0 the whole time — the condition has nowhere in the row to live, and a field written here would arrive a tick late and cross a boundary it has no business crossing. `kernels/hearth.rill` reads it. |
| `stick <at> <normal>` | the contact point, piped; the normal, by name from `collide` | `row.pos`, `row.normal`, `row.stuck` | Land the row: position the CONTACT, `row.normal` the contact normal, `row.stuck` set. Since 2026-09-08 the contact is the row's CENTRE at contact, one radius off the surface, because `collide` sweeps the row as a sphere of `row.size` — and `stick` itself learned nothing to make that true, which is the test that the rule is in the right place. **The resting offset therefore moved from the appearance into the sim, and ruling 27b's `pos + normal · size` in a renderer is now a DOUBLE COUNT: a host draws a stuck row at `pos`, flat, exactly as it draws a free one.** What 27b bought and this costs is that a row which SHRINKS after landing keeps its landing centre and lifts off the surface, where the renderer's rule recomputed the offset from the live size every frame; recorded, with a trigger — the first customer scene where a landed row shrinks enough to see it — and the fill is a sim-side re-rest that is state owing a dump. `hear` still samples at `pos`. A stuck row has no velocity — the sweep drops whatever the kernel added, every tick, which is what `stuck` means — so it stays where it landed; it still ages and still reads its curves. `collide \| stick` is the ember on the plate and the spark on the trim in one breath. |
| `hear $chan [grad] at <pos>` | the spray's lattice for `$chan`, at `pos` | — (a value) | The field read. Spelled `$wind at row.pos` (value) or `$wind grad at row.pos` (gradient, toward the caster) — the parser desugars to `hear`. The spray must declare `samples $wind cell <c>` or the kernel is refused at mount; the lattice is rasterised from the host's bag once per tick and the row trilinear-samples it, integer-exact. Coupled deposits (`to #tag`) reach a spray only while it carries the tag. |
| `deposit $chan <amount>` | `row.pos`, `row.size`, the spray's field store | — (the host's channel, ADDED) | Leave a MARK: `deposit $soot 0.4` puts `amount` on the channel at this row's position, as wide as this row's `size` — a mark is as wide as the thing that left it, and a row with no size leaves nothing. funideas §8 — *"a particle shouldn't necessarily disappear without consequence… particles become the transport mechanism connecting simulations."* The spray's `casts` is one standing AGGREGATE the host replaces every tick (where the cloud is, how much of it there is); a deposit is ADDED, decays on the channel's own clock, and is never replaced. Rain leaves wetness, the wetness evaporates, and nobody wrote a "make this wall look wet" system. A negative amount is a mark too — a field sums its deposits, so a raindrop on hot stone deposits negative heat. The row only ASKS: the mark reaches the host serially in the CAST phase, in row id order, because this runs in the parallel sweep and a store is a store — which is also what makes the order the same on every machine. A row leaves ONE mark a tick, so mount refuses a second `deposit`, and a host that takes no marks (`Fields.depositFn` null) refuses by name rather than writing nowhere. |

Rejected at read-aloud (campaign §9): `die`/`kill` for `perish` — `perish`
reads as the row's own verb where `kill` reads as someone else's; `bend`
for the wind coupling is held for P2. For the fifth word: `across` ("age
across life") reads as a span, not a fraction; `curve` ("age curve life")
names the shape, not the operation. `over` reads as the division it is —
age over life — and the knots ride behind it. For the landing word: `land`
fit the plate and not the wall; `settle` and `rest` read as easing, not a
stop; `stick` is the ember on the plate and the spark on the trim. For the
phase word: `entrain` is the right word and the obscure one — it is what the manual says `sync` MEANS, and `sync` is what anybody says out loud; `phase` is a noun where every row word is a verb; `couple` names the parameter, not the act; `chorus` is lovely and says nothing about what it does. For the neighbour word: `neighbours` is a noun where every other row word is a verb;
`around` reads as a rotation; `within` is rill's already and means a point in
a box; `flock` names one customer of many. For the tangent word: `slip` reads
as a failure rather than a motion; `skid`
promises a friction this does not model (a frictionless slide on a flat
floor runs for ever, and that is a thing you can see); `graze` is a near
miss, the opposite; `tangent` names the plane, not the act; `deflect` says
bounce, and nothing here reflects. For the
step word: `decay` only ever goes toward zero and half of `fire.rill`'s
lines climb; `approach` reads as motion in space and this is a scalar;
`cool` names one customer, not the operation; `toward` wants a preposition
it has not got; `ease` and `ramp` are rill's own, on the plane and
stateful — a different thing wearing a near name.

## The tags

Every row word says what it is FOR (`src/words.zig`, `TAGS` and
`BORROWED`), in the vocabulary rill's `OpDef.tags` opened on 2026-09-09.
They feed a palette, a console `help` and tab-complete; they refuse
nothing. **The first tag is a word's HOME** — a grouped listing files it
there and the rest are how it is found. Read the whole thing out of a
running registry with `zig build run -- --words`, which is `rill ops` for
the fifteen words rill cannot see. (`rill ops --host-row` cannot show
them: that flag registers the stubs in `rill/tools/host_row.zig`, which
exist so rill's parser can read a kernel file and are deliberately left
untagged — a second copy of this table is a copy that drifts.)

Five are minted here, because the row plane needed what rill's seventeen
had no name for:

| tag | what it is | at home |
|---|---|---|
| `#field` | a quantity spread over space: read it where the row is, or leave a mark on it | `hear` |
| `#life` | a row's beginning and its end: launched at birth, retired at death | `perish`, `spawn` |
| `#motion` | what changes where a row is going: the launch, the forces on it, and what a surface takes away | `gravity` |
| `#neighbourhood` | the rows close by, and what they do to this one | `align`, `infect`, `near`, `push`, `sync` |
| `#surface` | solid geometry: what the row hit, where, and what it does about it | `collide`, `ground`, `slide`, `stick` |

Six are borrowed from rill. Their sentences live in `rill/src/ops.zig` and
are **not** copied here: a second sentence for one tag is refused at the
registry door, on evidence — Blade3D's operator groups, free-form and
unaudited, ended up declaring `Physics` twice with two descriptions and
`Constraints` misspelled `Contraints`.

| tag | carried by | at home |
|---|---|---|
| `#envelope` | `relax` | `relax` |
| `#oscillator` | `sync` | — |
| `#random` | `spawn` | — |
| `#sink` | `deposit` | `deposit` |
| `#space` | `near` | — |
| `#time` | `perish`, `relax` | — |

`deposit` is at home beside rill's `cast` and `relax` beside its `ease`,
which is what borrowing buys: the row's copy of a word files with the
original. `#field` and `#motion` are CROSS-CUTS and earn their place by
spanning homes — `#field` reaches `deposit` in `sink`, `#motion` reaches
`spawn` in `life`, `push` and `align` in `neighbourhood`, `slide` in
`surface`. `#life`, `#neighbourhood` and `#surface` claim nothing of the
sort: everything carrying them is at home under them, and G22 pins that,
so widening one is a decision rather than a drift.

Nothing enforced is a tag. `row.only`, the slate's `publishes`/`consumes`
and which door registers a word all REFUSE programs; a tag is descriptive.
That is why the tracer four are `#surface` and not `#world` — `#world`
would restate the refusal `registerTracer` already gives — and why the
neighbourhood tag is not `crowd` and the tracer tag not `contact`: both
are slate lane names the mount checks, and a tag wearing an enforced name
invites exactly that confusion.

Rejected at read-aloud: `lattice` and `channel` for `#field` (a lattice is
how a field is sampled, and a channel is a static kind the registry
already carries); `lifecycle`, `birth` and `age` for `#life` (a compound,
a half, and a row field); `force`, `velocity` and `physics` for `#motion`
(force excludes `slide` and `spawn`, velocity is a row field, physics
smears and is Blade3D's own duplicated group); `crowd`, `flock`, `swarm`,
`neighbour` and `social` for `#neighbourhood` (a slate lane, then three
that only three of the five words do, then a noun where the tag is a
subject); `contact`, `world`, `collision` and `hit` for `#surface` (a
slate lane, a restated refusal, a word `ground` does not do, an event).

## `over` — rill's word now

`row.age | over row.life [1.0, 0.7, 0.0]` — a value over normalised life,
piecewise linear over evenly spaced knots, numbers or Oklab colours, the
curve a literal or a broadcast (`plane.drift.@self.k.size_curve`) — was
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
