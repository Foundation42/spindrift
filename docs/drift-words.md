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

| word | reads | writes | what |
|---|---|---|---|
| `spawn` | the spray's aim, speed, spread; the row's seed | `row.vel` | On a row's birth tick, launch it: `vel ← aim × speed`, plus a per-axis draw in ±spread from the seed. Nothing on later ticks. A kernel without it has rows that sit where they were born. |
| `gravity <g>` | `g` — a literal, or a broadcast knob | `row.vel.y`, add mode | `vel.y += g · dt`, cells per second², negative is down. |
| `perish` | `row.age`, `row.life` | retires the row | On the first tick the row's age has reached its life, mark it; the spray reaps in its serial phase. A kernel without it has immortal rows, and a full population says `throttled`. |

Rejected at read-aloud (campaign §9): `die`/`kill` for `perish` — `perish`
reads as the row's own verb where `kill` reads as someone else's; `bend`
for the wind coupling is held for P2.
