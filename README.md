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

## Status — P0: population and determinism

Built and gated: the fixed-capacity struct-of-arrays population with a
freelist and stable ids, Q16.16 fixed-point arithmetic with no float in the
loop, the `World` query interface with a mock floor, the canonical struple
dump (readable from Python with no spindrift code), an emitter with a
three-phase tick chunked over `common/jobs.zig`, and `drift-run` to drive
it on rill's mock plane.

**G0 — determinism** is green and mutation-bitten: the same script twice is
the same bytes, a perturbed seed is a different population, and chunking
over four workers cannot reach the result. Eleven hand mutations, eleven
bites; the ledger records which gate caught which.

Not built, on purpose: the kernel is a Zig stand-in for
`spawn`/`gravity`/`perish` that P1 replaces with rill text via a `row`
evaluator — see `docs/recon/r-a-row-routing.md` for what that costs and the
rulings it needs. No rendering, no fields, no collision words yet; each
has its phase in `docs/spindrift-campaign.md`.

## Try it

```sh
zig build                                   # library + drift-run
zig build run -- --rate 400 --speed 3 --spread 1 --gravity -9.8 --life 800 --ticks 60 --dump embers.struple
python3 tools/read_dump.py embers.struple   # the struple Python port reads it back
zig build test                              # the gates
```

Fixed dt is the only clock: `--fixed-dt 16` is sixteen fed milliseconds per
tick, and two runs with the same flags print the same digest.

## Layout

| path | what |
|---|---|
| `src/fixed.zig` | Q16.16 — the sim's one number |
| `src/population.zig` | SoA rows, freelist, `(id, gen)` handles |
| `src/world.zig` | `World` vtable; `Floor` and `Nowhere` (the negative control) |
| `src/dump.zig` | one canonical struple map per population |
| `src/emitter.zig` | knobs, the three-phase tick, the P0 stand-in kernel |
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
