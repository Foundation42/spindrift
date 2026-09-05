# Beat 10 — the composite: the embers, the fade and the smoke drawn as cards over the traced frame

*CC, 2026-09-05. Campaign 3 (`docs/spindrift-campaign-3.md`), P10 — the
pass. Built the evening the campaign was ratified.*

## What landed

**Matryoshka `5a3ed8e`**, nothing in spindrift's row. A graphics
pass between the lit HDR compose and bloom draws every `sprite` row as a
screen-aligned card into the HDR composite: one instance per row, a
strip of four vertices, the row pulled from the same 48-byte slot the
tracer's leaf read, through a draw order the bridge sorts on the CPU
each frame — back to front by the drawn position's distance from the
eye, ties by id then spray. Fixed-function straight-alpha blending; the
fragment tests its eye distance against the tracer's R16F depth and
fades over the kind's new `near` metres of the surface behind it; the
kind's `soft` is a gradient on the row's alpha. The composite image
gained the colour-attachment usage bit and nothing else in the frame
graph moved. With no rows the pass records only its two timestamps.

**The appearance names say which path draws a kind** (ruling 1).
`sprite` is the composite and what every rig means; `traced` is the
leaf, kept whole and off by default — a `traced` kind still publishes
its runs to the dynamic tree, a `sprite` kind never does. The four
leaf gates of campaigns 1 and 2 now run on `traced`; their claims are
unchanged. `near` rides the kind's three formats as `soft` does (the
rig line's token after `soft`, a pack field, `sprayarche near`), with
one validation.

**The kinds' looks are per spray.** The plan said a per-kind table
indexed by the slot's `kind`; the row's `kind` is the sim's and unset,
so the slot's `look.w` carries the SPRAY's slot and the fragment reads
`soft` and `near` from a sixteen-entry table by that. Per spray, never
per row — beat 7's lesson.

## The gates, and what bit them

| gate | green | the mutation that bit |
|---|---|---|
| **G12** nothing mounted, nothing moved | `refs.py verify test_scene` unmoved with the pass in the frame; every pair's bare hash unchanged at the freeze | structural — the pass is skipped whole at zero rows |
| **G13** the tracer's time back | plate pose, Debug, one set: traversal 3.29 ms bare, **3.29 ms with the embers mounted and the coals stood down**, 3.55 with the coals (four analytic lights — P11's to retire); the pass 0.07 ms for 2400 rows, 0.05 for the smoke | the leaf republished for `sprite` — traversal 5.50 ms against 3.29 bare, the coals stood down: the tracer paying again |
| **G14** a blended pixel is exact, sorted back to front by distance then id | the twin gate: two sprays at two depths, three coincident rows each — far first, ids ascending within, the order flipping from beyond, the same eye twice the same order | the comparator flipped — the fade pair MOVED to 7910b127…; the tie by slot — SURVIVED the first gate (within a spray, slot order equals id order), then bit the cross-spray gate written for it: expected the second spray's slot, found the first's |
| **G15** soft against the world | `near` on the kind: the fade in the fragment over `scene_d − d`; the round trips carry 0.4, a negative refused | (the numbers gate is P11's, with the lit card — recorded) |
| **G18** two renders hash the same | the five plate-family pairs held on re-verify after the freeze | (the same witness as G14's) |
| the bridge: a `sprite` kind uploads rows and publishes no leaf, a `traced` kind publishes its runs, a traced kind is not in the order | green | the appearance test dropped in `upload` |

Suite 2563/2563; the control-root compile failure stands as found.

## The captures

All five plate-family pairs re-frozen once through the composite; every
bare unmoved:

| pair | before (leaf) | after (composite) |
|---|---|---|
| test_scene-embers | 677e6b7a… | 7aa1ebc8… |
| test_scene-embers-plate | 379794ed… | 6a32fbb4… |
| test_scene-embers-plate-beneath | 285ec93c… | f9311226… |
| test_scene-fade | 8ca3c6d1… | 4a193d9a… |
| test_scene-smoke | ea0205d0… | 482a9ee5… |

The embers are the leaf's picture disc for disc, occluded by the gnomon
and the plate as before. The fade is a fade: the old embers on the plate
go translucent and the far strays vanish, no dither. The smoke is a
plume, not bees — dark, because P10 writes the row's colour unlit; P11
lights the card.

## Decisions taken, for ratification

1. **The looks are keyed by spray slot**, not by the row's `kind` (which
   is the sim's and unset). Sixteen entries; a spray has one kind.
2. **The card is screen-aligned** (the camera's right and up), where the
   leaf's disc faced the camera's position. At the plate's distance the
   difference is invisible; stated.
3. **The pass draws unlit this beat**: the row's colour as radiance,
   blended. Emission (L above 1) already blooms, since the pass writes
   before bloom. The sun, the sky and the CSM are P11's.
4. **G15's numbers gate waits for P11**: the fade is built and rides the
   formats, but its three-pixel probe belongs with the lit card.

## Found

**The slow window, unexplained.** For about half an hour every GPU pass
ran uniformly three times slower than the afternoon's (bare plate 10 ms
against 3.3), across two separate chains. I first wrote "the GPU was
shared with a second session" — an inference, withdrawn: at 23:20
`nvidia-smi` showed nothing on the card but the desktop, and the bare
pose measured 2.79 ms. A uniform slowdown of every pass reads like the
card at low clocks between sparsely submitted frames (the SM clock is
not pinned, as `refs.py` says on every run), but that was not measured
either. What stands: the G13 set was re-taken with the GPU idle —
traversal 1.09 ms bare, 1.06 with the embers and the coals stood down,
1.11 with the coals, 1.02 with the smoke; the pass 0.03–0.04 ms — and
the claim holds at full speed as it did at a third of it. The earlier
Debug rebuild under that window took most of a ten-minute timeout; the
harness backgrounded the chain and it finished.

**Blade3D, surveyed** at Christian's ask (`docs/recon/blade3d-particles.md`):
the cloud is static puff cards along a depth ramp inside a seeded box
cluster, shaded by world-space 3D noise, a per-card top/bottom gradient
and a scrolling dust octave; the light shafts are frustum cards
shadow-mapped per pixel; the missile promotes fire to smoke by age; the
explosion is a Gaussian shock ring; turbulence is three decorrelated
Perlin taps. Blade3D had no per-particle sort, no velocity stretch and
no lit particles — the three things this campaign has or is building.
Where each lands is in the plan's fills and P11's scope.

## Next

P11, the light: sun × CSM and the sky's ambient on the card, emission as
emission, the coals as emitting sprites, the light rows as G-buffer
splats replacing the analytic point lights — and G13's last 0.26 ms.
