# Beat 3 — embers off the plate, and sparks in the keep

*CC, 2026-09-02. Against the rulings that closed beat 2 and the ruled order
for P3. Built on rill `f90873c` (three commits naming this beat), common
`9a75dfb`, struple `d937815`, spark `6055875`; matryoshka's renderer and
applet in their own commits (§4, §5). Captures: test_scene as the
acceptance, oa_spirit3 for reach; dust2 later, as asked.*

## What was built, in the ruled order

**(a) Rule 7 first — matryoshka `6ab0287`.** `LEAF_PARTICLES` is the
tenth leaf type, dynamic-tree only, beside `dynamic_proxy`; a spray's row
chunk rides the per-frame tree as a `DynObject` carrying `{row_base,
row_count, slot}` — Path B, the drawbridge precedent, and the static tree
untouched. Rows are 32-byte `GpuParticle`s in a host-mapped SSBO, zeroed
at init. `python3 tools/refs.py verify` across nine scenes: AE=0 before,
AE=0 after, timings within band. That gate landed and was committed
before any spray was drawn.

**(b) Sprite appearance — `3a00411`.** `^spray` gains `appearance`
(default `sprite`; the sound emitter's stem-link precedent), in all three
formats with the round-trip gates extended; the bridge refuses any other
name at reconcile with one log line. A sprite is a camera-facing disc of
`row.size` and `row.colour`, alpha as a cutout through the existing
alpha-test path, not blended; coverage under facet 1 is the disc against
the cone footprint, analytic — at or above half a pixel is a hit, and a
sub-half-pixel mote is a miss, stated as the trade. Reflections shade it;
shadows skip it, on the GPU and on the CPU twin, gated.

**(c) Upload — `2c27377`.** After the sim tick and before the dynamic
tree build, dirty chunks only, whole chunks (dead rows radius 0), one leaf
per chunk with a live row. Positions quantise once in i128 integer
arithmetic onto the gauge lattice when the scene has one and onto the
row's own Q16.16 grid otherwise. Oklab to linear sRGB once, on the CPU, at
upload. The G-buffer X-ray gains a `drift` row and a button.

**(d) G5 — `2be078b`.** `tools/spray_gate.py verify|capture`, two rigs,
two kernels, a manifest with hashes and the exact arguments. Mounted
differs from the frozen ref; unmounted is AE=0; two-hop: all nine refs
unmoved. The hand mutation — the leaf arm made to `continue` — reported
`MOUNTED == REFERENCE` on all three pairs and the gate failed.

**(e) `over` — spindrift `45e9ea0`, `52d4bd9`; rill `84c0c9d`, `f90873c`.**
The fifth word: `row.age | over row.life [1.0, 0.7, 0.0]` — a value over
normalised life, piecewise linear over evenly spaced knots, numbers or
Oklab colours, exact by lerp, a life of zero refused by name. The curve
is rill's first stateless array on the row: the parser builds `[…]` as an
`array` node (and record elements as `record` nodes), and the row runtime
folds those at mount into one shared value every row reads; a live
element is refused. **And a reversal with its customer:** a broadcast may
carry an array — `over row.life plane.drift.@self.size_curve` — converted
once when its bytes change, owned by the spray, never per row. That is
what lets the applet's `:::curve` drive the rows. Read-aloud: `across`
reads as a span, `curve` names the shape; `over` reads as the division it
is. Also this half: `drift/@name/coarsened` on the plane (ruling 15,
change-only, replay-gated on two channels), and dirty chunks reduced to
the one rule after two marks proved decorations.

**(f) The Spray applet and `:::curve` — spark `6055875`; matryoshka §5.**
`:::curve {target= value=${state.…} min= max= label= knots=}`, a reusable
span in spark's component shape: knots evenly spaced over x, a drag moves
one knot's value, one State write per gesture carrying the whole array
(the re-entry trap the trackball fell into is why), the plane the truth
between gestures. A `::sparkline` already existed; its parser now takes
the bracketed array form. 791 spark tests.

## Frame budget

test_scene, 3933 live rows, Debug, 60 frames: the inline sweep averaged
1.90 ms a frame against a 5.2 ms GPU frame and climbed with the count —
it moved the frame. The one JobSystem (`common.jobs`, created in
`main.zig`) now takes the sweep: 0.85 ms at the same rows, frame hash
byte-identical either way. The solver's bake still makes its own
transient instance; recorded as the next hand-off.

## What each mutation caught

Spindrift and rill, eight of eight (two after rewrites): `over`'s segment
never advancing; t unclamped at life; a zero life not refused; `coarsened`
said every tick; `coarsened` reporting the last lattice not the worst
(**survived with one channel**, bit with two); the dirty sweep-mark
dropped (after the spawn and reap marks were found to be decorations and
deleted); the array fold accepting a live element; the array broadcast
not re-converted on change. Matryoshka's renderer: the leaf drawing
nothing (G5, all three pairs); a build tagging every leaf `dynamic_proxy`;
the float quantise path; uploading every chunk or only live rows; the rig
reader swallowing the appearance into the kernel name. Spark: the gesture
guard on ingest removed (the re-entrant echo and the plane-is-truth gates
bit; the single-write gate correctly did not).

## The captures

- `tools/refs/spray/test_scene-embers-plate.ppm` — the plate from its +x
  side: a plume of orange-gold discs rising off its centre, shrinking and
  cooling over life, reflected in the plate. The core saturates to near
  white where the colour curve's Oklab L runs past 1.0 and the surplus
  becomes emitted light — right for an ember, recorded so nobody reads it
  as a tonemap fault.
- `oa_spirit3-sparks.ppm` — a burst of hot white-gold sparks cooling to
  red over a floor-trim light in the Quake-3 map, from the player start.
- `test_scene-embers.ppm` — the gate's own frame at the frozen pose.

Hashes and exact arguments in `tools/refs/spray/manifest.txt`; the
frames themselves are gitignored and regenerated by `spray_gate.py
capture`.

## Rulings landed

Ruling 15 (`coarsened`, never refuse the tick) and 16 (beat 2's calls
ratified) in the campaign's §7; the two beat-2 practices in the ledger's
rules. G5 is green and bitten. The engine's ownership rule, the audience
rule living once, `@` after a dot as a path segment, and the respelled
CHOPs example all stand as ratified.

## Recorded, not built

| what | trigger |
|---|---|
| `light`, `metaball`, `prim` appearances, each with its own capture (light cap 4 stands) | P3b, if sprite has room — it did not this beat |
| the bake's JobSystem handed to main's | a second per-frame customer |
| sub-chunk sweep granularity | a spray whose live rows cluster in one chunk |
| the over-life curve as an AUTHORED knob on the rig (today: a dynamic plane path the applet writes) | the first rig that ships a curve |
| a per-spray selector in the applet (today: one spray, named in the file) | a second spray on one rig |
| named colours in a curve | a palette on the plane |
| dust2 motes in the sun shafts | the next capture pass |

Fenced and untouched: collision, budget/governor, trails, sub-sprays,
per-row casts, blending/OIT.

## The Spray applet and the bridge — matryoshka `f5ba6c3` (pushed)

`hud/spray.md`, in the applet shape, bound to `embers` (the acceptance
rig's spray, named at the top; a per-spray selector is recorded, trigger
a second spray on one rig): four sliders in mirror mode on
`drift/@embers/{rate, speed, spread, life}`, `spray burst embers 200` as
a button, `count`/`throttled`/`coarsened` as read meters (perf.md's
lesson — a number in prose re-wraps), and a `:::curve` in mirror mode on
`drift/@embers/size_curve`. `perf.md` gains a Spray fold: a row-steps
meter and a `::sparkline` over the last sixty samples.

The bridge paths, and where a write lands — the ratified rule made
mechanical: **an applet's bare write sets the authored value.** The four
authored knobs are published at every reconcile as the path's BASE (a
thumb that showed the lane fold would write it back as authored on the
next drag). `Plane.enqueueAcked` gains a spray arm: a `.hud` or console
write on that family lands in a spray inbox the bridge drains first in
reconcile through `spraySet` — the row's authored value, override bit
and all — so the republished number lands in the frame the HUD pumps;
`count`, `throttled`, `coarsened`, `bounds` are dropped at the door.
`checkMountable` accepts a mirror on exactly the family plus
`size_curve`. The curve: the HUD bridge grew an array write (spark's
`curve.parseArray` → an f64 struple array, `.hud`) and an array pump
(`curve.formatArray`, hash-gated so the widget's own echo is silent and a
rill's array moves the pucks); the panel takes an array's first sight as
its write-back baseline, because a curve nobody authored is a path the
plane does not have. `perf/drift/row_steps` and `…/row_steps_hist` ride
the perf publisher's cadence and demand gate. `kernels/cinders.rill`
reads the curve after its literal — quiet with the path absent, so the
captures stand unmoved.

Gates, each with the mutation it bit: the knob write (the spray arm
dropped — the authored rate stayed 40), `throttled` (zero never re-said),
the curve round-trip (knots packed as scalars — the decoder said
`NotAnArray`), the slider reading the lane fold instead of the base (the
thumb became 200), the write-back baseline (the drag wrote nothing), the
history's cap and order (61 where 11 was expected) and its change gate
(an idle ring re-sent ten times). One real catch on the way, not a
mutation: the first gate run found the plane folding a rill's lane over
the published 400 — the slider must show the BASE, which `Plane.pathBase`
now exposes. Matryoshka's suite: 2515 (was 2506). Recorded, not built: `size_curve` authored on the
rig (the first rig that ships a curve); a HUD spray-knob write in the
transcript (the first replay that needs a slider drag on a spray).

## Needs a ruling

1. **`refs.py` builds ReleaseFast for its own binary.** The renderer
   agent bypassed that with `MTR_REFS_NO_BUILD=1` under the Debug rule and
   verified against a Debug build. If the refs gate should go back to
   ReleaseFast for its timing bands, say so; the pixel gate does not
   care.
2. **The half-pixel coverage threshold.** A sub-half-pixel mote is a miss;
   distant dust will vanish before it fades. Right for embers and sparks;
   dust2's motes are the customer that decides whether the threshold
   becomes a per-appearance number.
