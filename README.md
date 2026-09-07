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
gravity plane.drift.@self.k.gravity
perish
```

Row fields are `row.pos`, `row.vel`, `row.age` … (sigil mandatory); the
spray's knobs are `plane.drift.@self.<knob>`, broadcast to every row;
writes are `write row.<field> [add]`. The spray's own four (`rate`,
`speed`, `spread`, `life`) are the host's interface and a kernel may read
them; a kernel's OWN knobs go under `.k.` and naming one flat is refused
at mount. Rill owns the row plane — the
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
gravity plane.drift.@self.k.gravity
$wind grad at row.pos | mul plane.drift.@self.k.lean | write row.vel add
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
zig build run -- --kernel kernels/smoke.rill --gravity 0.5 --seed plane.drift.@em.k.lean=-1 \
  --channel '$wind:0.01:1000' --channel '$dankness:0.001:2000' --samples '$wind:0.5' \
  --casts '$dankness:0.02' --rill wind.rill --ear '$dankness@0,3,0'   # smoke in the wind
zig build run -- --kernel kernels/fire.rill --rate 380 --speed 4.2 --spread 1.6 --life 2600 \
  --gravity -9.8 --pos 0,0.15,0 --aim 0,1,0 --ticks 220 --world floor \
  --seed plane.drift.@em.k.cool=1.25 --seed plane.drift.@em.k.plunge=10 --seed plane.drift.@em.k.chill=0.75 \
  --seed plane.drift.@em.k.smoke=0.875 --seed plane.drift.@em.k.quench=5.625 \
  --seed plane.drift.@em.k.thin=0.8125 --seed plane.drift.@em.k.settle=17.5 \
  --seed plane.drift.@em.k.puff=0.3 --seed plane.drift.@em.k.grain=0.06 --dump fire.struple
  # the manifold walk: rows leave with no history and the world writes it —
  # a landed ember quenches (cooled .98, sooted .95, dense), one still in
  # the air blows thin (.48/.36/.34). No colour is written anywhere.
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
| `src/world.zig` | `World` vtable — `collide` (segment → hit point, normal, t, material) and `ground`; `Floor`, `Plane` (any unit normal — a wall or a slope, which is what `slide` needs, since on a flat floor gravity is entirely normal and a slide has nothing to show) and `Nowhere` (the negative control). A segment starting INSIDE a surface is a row put back on the face it came through, as the engine does — the mock said "already through" until 2026-09-07 and a tunnelled row fell for ever |
| `src/dump.zig` | one canonical struple map per population |
| `src/fields.zig` | the `Fields` host interface, the engine's kernel, the mock store and its cast door |
| `src/spray.zig` | knobs, the six-phase tick, the APPEARANCE a spray declares (which user channels carry its coordinate, and the name a host reads them against — spindrift resolves neither and evaluates nothing; the seam has the shape `World` and `Fields` already have), the neighbourhood (a DENSE grid over the live rows' bounds, cut at most one cell per row, built at the tail of the serial spawn — one snapshot of where everybody is, which is what keeps `near` row-local in the parallel sweep; it was a hash grid with a 1 m cell until 2026-09-08, and that cost 96% of a playground tick), kernel mount, lattices, the aggregate cast, the CHUNK (rows per job and the host's dirty-upload unit, cut from capacity at INIT because a host sizes per-chunk arrays the moment it has the spray — 1024 was a cache number and made 2482 rows into 2.4 chunks for thirty workers), what the spray says |
| `src/words.zig` | `spawn`, `gravity`, `perish`, `hear`, `relax`, `near`, `push`, `sync` — row words registered into rill (`over`, the fifth from beat 3, is rill's core word since rill `23ac55c`); `collide`, `ground`, `slide`, `stick` — the TRACER table a host with a World registers (`stick` lands the row at the contact and stores `row.normal`; the appearance draws it at pos + normal × size; the normal rides the pipe by name; `slide` takes the normal OUT of the velocity and leaves the tangent, so a row runs along what it hit — `collide | slide | stick`) |
| `src/scheduler.zig` | the row-steps budget over sprays: `plan` by staleness, frustum, dynamic, index — the first always runs |
| `kernels/embers.rill`, `kernels/smoke.rill`, `kernels/fire.rill`, `kernels/hearth.rill`, `kernels/motes.rill` | the kernels; embers is `drift-run`'s default. `fire` writes no colour — it writes a point in an APPEARANCE MANIFOLD (`row.u0`–`u2`: cooled, sooted, thinned) that a renderer reads an RBF set at, so a landed ember quenches to soot and a flying one blows thin, from one file and one kernel. `hearth` is the same manifold on a SLOPE: the ember runs down it instead of stopping, quenching the whole way, gated on `slate.contact` because a sliding row never sets `row.stuck`. `motes` is funideas §6: every row a lone oscillator with its own frequency and a whisper of coupling to whoever is in reach — nothing in it makes a wave, and a field of them makes travelling ones |
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
