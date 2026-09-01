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

## Status — P1: the spray, and a kernel that is rill text

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

**G0, G1 and G2 are green and mutation-bitten** — determinism of the dump,
the population on the plane (`plane.drift.@<name>.count`, a second rill
thresholds it, unmount says zero), and the words as operators through
rill's own registration gates. Twelve hand mutations in this beat, twelve
bites, one of them a crash; the ledger records which gate caught which.

No rendering, no fields, no collision words yet; each has its phase in
`docs/spindrift-campaign.md`. The spray tenant on matryoshka's spine lands
beside this in matryoshka's own repo.

## Try it

```sh
zig build                                   # library + drift-run
zig build run -- --rate 400 --speed 3 --spread 1 --gravity -9.8 --life 800 --ticks 60 --dump embers.struple
zig build run -- --kernel my.rill --rill hud.rill   # your kernel, a rill driving the knobs
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
| `src/world.zig` | `World` vtable; `Floor` and `Nowhere` (the negative control) |
| `src/dump.zig` | one canonical struple map per population |
| `src/spray.zig` | knobs, the four-phase tick, kernel mount, what the spray says on the plane |
| `src/words.zig` | `spawn`, `gravity`, `perish` — row words registered into rill |
| `kernels/embers.rill` | the first kernel, embedded as `drift-run`'s default |
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
