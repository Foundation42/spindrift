# spindrift

**A particle system that is rill-shaped from the first line.** Emitters are
[rill](../rill) programs, per-particle behaviour is rill operators evaluated
over populations, coupling to the world is `$` fields in both directions
and tracer verbs. CPU first; the GPU arrives later as a second evaluator
of the same text, not a port.

Spray lifted off water and carried on the wind — born off a rill, driven by
fields. Plane prefix `drift/`.

```rill
// the emitter level — ordinary rill over the plane, and it already works
plane.ents.@torch.$alarm | above 0.5 0.3 | kick 50ms 2s | mul 400 | write plane.drift.@sparks.rate
```

## Status — P2: fields, both ways

**A kernel is a rill program whose plane is the row.** You mount a rill; a
kernel is a rill mounted on a spray rather than on the world:

```rill
// kernels/embers.rill
spawn
gravity plane.drift.@self.gravity
perish
```

Row fields are `row.pos`, `row.vel`, `row.age` … (sigil mandatory); the
spray's knobs are `plane.drift.@self.<knob>`, broadcast to every row;
writes are `write row.<field> [add]`. Rill owns the row plane — the
row-legal column, the integer kernels for the exact core set, the row
runtime (`rill/src/row.zig`, spec §3.16). Spindrift owns the population as
a row plane, the spray with its four-phase tick over `common/jobs.zig`, the
three words, the dump, and `drift-run`. Everything in the loop is Q16.16;
no float enters the sim.

**Fields, both ways.** A `^spray` that `samples $wind cell 0.5` gets the
channel's live deposits rasterised onto a lattice over its bounds once a
tick, and a kernel reads `$wind at row.pos` (value) or `$wind grad at
row.pos` (gradient, toward the caster) as exact integers. A spray that
`casts $dankness amp 0.02` deposits one aggregate a tick — centre of mass,
amplitude × live, radius from bounds — that the host replaces, and
withdraws on unmount. The field model is the engine's; the exact-kernel
bill was zero.

```rill
// kernels/smoke.rill — leans away from the wind's source
spawn
gravity plane.drift.@self.gravity
$wind grad at row.pos | mul plane.drift.@self.lean | write row.vel add
perish
```

**G0–G4 are green and mutation-bitten.** Twelve hand mutations this beat,
twelve bites, one after a gate was rewritten to vary on every axis; the
ledger records which gate caught which.

No rendering or collision words yet; each has its phase in
`docs/spindrift-campaign.md`. The spray tenant on matryoshka's spine lands
beside this in matryoshka's own repo.

## Try it

```sh
zig build                                   # library + drift-run
zig build run -- --rate 400 --speed 3 --spread 1 --gravity -9.8 --life 800 --ticks 60 --dump embers.struple
zig build run -- --kernel my.rill --rill hud.rill   # your kernel, a rill driving the knobs
zig build run -- --kernel kernels/smoke.rill --gravity 0.5 --seed plane.drift.@em.lean=-1 \
  --channel '$wind:0.01:1000' --channel '$dankness:0.001:2000' --samples '$wind:0.5' \
  --casts '$dankness:0.02' --rill wind.rill --ear '$dankness@0,3,0'   # smoke in the wind
python3 tools/read_dump.py embers.struple   # the struple Python port reads it back
zig build test                              # the gates
```

Fixed dt is the only clock: `--fixed-dt 16` is sixteen fed milliseconds per
tick, and two runs with the same flags print the same digest.

## Layout

| path | what |
|---|---|
| `src/fixed.zig` | Q16.16 — the sim's one number |
| `src/population.zig` | SoA rows, freelist, `(id, gen)` handles, the row plane a kernel mounts on |
| `src/world.zig` | `World` vtable — `collide` (segment → hit point, normal, t, material) and `ground`; `Floor` and `Nowhere` (the negative control) |
| `src/dump.zig` | one canonical struple map per population |
| `src/fields.zig` | the `Fields` host interface, the engine's kernel, the mock store and its cast door |
| `src/spray.zig` | knobs, the six-phase tick, kernel mount, lattices, the aggregate cast, what the spray says |
| `src/words.zig` | `spawn`, `gravity`, `perish`, `hear`, `over` — row words registered into rill; `collide`, `ground`, `stick` — the TRACER table a host with a World registers (`stick` lands the row at the contact and stores `row.normal`; the appearance draws it at pos + normal × size; the normal rides the pipe by name) |
| `src/scheduler.zig` | the row-steps budget over sprays: `plan` by staleness, frustum, dynamic, index — the first always runs |
| `kernels/embers.rill`, `kernels/smoke.rill` | the first two kernels; embers is `drift-run`'s default |
| `docs/drift-words.md` | the words manual, parity-gated both ways |
| `src/run.zig` | `drift-run` |
| `src/tests.zig` | the gates, each with its named mutation |
| `tools/row_legal.zig` | walks rill's registry, prints the row-legal operators |
| `tools/read_dump.py` | the cross-language dump reader |
| `docs/spindrift-campaign.md` | the plan: gates, design, phases, rulings |
| `docs/recon/` | R-a (the `row` routing), R-b (population and scheduler) |
| `docs/implementation-notes.md` | the ledger |

## Depends on

`../rill` (plane, registry, parser), `../common` (the one JobSystem),
`../struple` (every byte that leaves memory). Matryoshka depends on
spindrift; spindrift never depends on Matryoshka.

## License

Dual-licensed: Apache 2.0 or a commercial license from Foundation42 —
see `LICENSE`.
