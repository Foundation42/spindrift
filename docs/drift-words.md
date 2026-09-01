# The drift words

Spindrift's operators, registered into rill's registry through the same
`Registry.register` as every core word — so the reserved-name rule, the
tail rule and the argument-spelling rule bind them at registration. Every
word here is a **row word**: it means something on a spray and nothing on
the world plane. Piped into a plane program, it refuses at mount by name.

A kernel is a rill program whose plane is the row (`rill-spec.md` §3.16).
Row fields are `row.pos`, `row.vel`, `row.age`, `row.life`, `row.seed`,
`row.size`, `row.colour`, `row.kind`, `row.u0`–`row.u3`; the spray's knobs
are `plane.drift.@self.<knob>`, broadcast to every row.

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
| `over <life> <curve>` | `row.age` (piped), `row.life`, an array literal | — (a value) | A value over normalised life: `row.age \| over row.life [1.0, 0.7, 0.0]` is 1.0 at birth, 0.7 halfway, 0.0 at the end, piecewise linear over evenly spaced knots; `[{l: 1, a: 0, b: 0}, …]` does colours the same way in Oklab. Exact by lerp. The curve is the first stateless array on the row. A life of zero refuses. |
| `hear $chan [grad] at <pos>` | the spray's lattice for `$chan`, at `pos` | — (a value) | The field read. Spelled `$wind at row.pos` (value) or `$wind grad at row.pos` (gradient, toward the caster) — the parser desugars to `hear`. The spray must declare `samples $wind cell <c>` or the kernel is refused at mount; the lattice is rasterised from the host's bag once per tick and the row trilinear-samples it, integer-exact. Coupled deposits (`to #tag`) reach a spray only while it carries the tag. |

Rejected at read-aloud (campaign §9): `die`/`kill` for `perish` — `perish`
reads as the row's own verb where `kill` reads as someone else's; `bend`
for the wind coupling is held for P2. For the fifth word: `across` ("age
across life") reads as a span, not a fraction; `curve` ("age curve life")
names the shape, not the operation. `over` reads as the division it is —
age over life — and the knots ride behind it.
