# Beat 13 — the puff: the plate's smoke carries lumps that belong to the air

*CC, 2026-09-06. Campaign 4 (`docs/spindrift-campaign-4.md`), P13 — the
field. Built under the plan's proposals on Christian's "rock on"; the
four rulings of its §6 stand asked.*

## What landed

**Matryoshka `8d5310b`**, nothing in spindrift's row.

**The field.** A tiling 3D noise volume — Perlin over an eight-cell
lattice, two octaves, 128³, generated on the CPU from a fixed seed by an
integer hash — is uploaded once up the engine's LUT path with its own
repeat sampler and bound to the sprite pass. The fragment samples it at
its WORLD position over the kind's `noise` metres per period, so two
overlapping cards agree on where the lumps are and the lumps stay with
the air when the eye moves. The field modulates the card's albedo, and,
by `grain`, its alpha through a soft threshold: the silhouette erodes
where the field is low. A finer octave, `dust` metres, scrolls down by
`drift` metres a second of FED time and brightens by max: wisps that
move without washing out. `lift` is a gamma on the albedo before the
light. The light stays campaign 3's. That is Blade3D's cloud recipe
(`docs/recon/blade3d-particles.md` §3) with its fake gradient replaced by
the real sun and sky.

**The kind's five numbers under one verb** — `sprayarche puff <kind>
<noise> <grain> <dust> <drift> <lift>` — one rig token group after the
blend, five pack fields, one validation; the look table is three vec4s
per spray. The generator's gate is its own test root; the repo ships no
bytes.

## The gates, and what bit them

| gate | green | the mutation that bit |
|---|---|---|
| **G19** the field is one field | the volume's hash frozen (`df721bbc20454ed7`), the same on every generation; tiles on every axis; spans the range; the puff pair frozen one line apart from the smoke pair | the noise sampled in the card's frame — the puff pair MOVED (82afb21a → 6559f285) |
| **G20** wisps on fed time | two renders of the puff pair, one hash | the wisps on the wall clock — two renders, two hashes (f99ad6f0, c7be2385) |
| **G21** every campaign-3 pair unmoved at the puff's zero | the eight pairs byte-identical after the field was bound and the look table grew | the field applied whatever the kind says — the smoke pair MOVED (d5d72aa1 → 0ada6da3) |
| the kind's formats | the rig round-trip carries the five; grain past one and a lift of zero refused; the Project round-trip; the rig-line byte gate takes the five tokens | (structural) |

Suite 2567/2567; the control-root compile failure stands as found. G18:
the nine pairs held on the clean rebuild.

## The capture

`test_scene-puff`, `82afb21a…`: the smoke kind with lumps every two
metres, showing at 0.7, half-metre wisps drifting down at 0.35 m/s of fed
time, a lift of 0.8 — beside the unchanged `test_scene-smoke`. The plume
carries soft lumps and a broken silhouette where the column was smooth.
A first cut at a 2.5 m period made thirty-centimetre grain, and an alpha
scaled by the field itself halved the plume; the period is sixteen and
the erosion a soft threshold now. Christian is the judge of the picture.

## Decisions taken, for ratification (the plan's §6, proceeded under)

1. Five numbers under one verb, `sprayarche puff`.
2. The field on albedo and alpha (the alpha through a soft threshold,
   0.35–0.65 of the field), the dust by max, the lift before the light.
3. The volume generated, not shipped: 128³, its hash a gate.
4. The names: `puff`, `noise`, `grain`, `dust`, `drift`, `lift`. And
   one meaning to say aloud: `noise` and `dust` are metres per PERIOD of
   the volume, eight lumps to a period.

## Found

The suite's count did not move when the generator's test was added —
the file was reachable from the renderer but not from a test root; it
is its own root now, like the engine's other standalone files. The
renderer's comptime X-ray table caught the new image view and asked
for its exemption, which is exactly what that table is for.

## Next

P14, the light shafts, if the pass can be handed the sun's frustum;
otherwise the campaign's close and the next ask.
