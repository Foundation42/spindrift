# Beat 6 — the fade: the embers on the plate dim out instead of popping

*CC, 2026-09-05. Campaign 2 (`docs/spindrift-campaign-2.md`), P6, G8.
Christian gave the conn on the plan's five proposals the same day; this
is the first beat built under them.*

## What landed

**Rill `48c0183`** — a row field may carry bounds. `Field.bounds` is a
closed range for a scalar field, checked on the value that would LAND —
after `add` composes with the snapshot, after an axis composes with its
vector — and a value outside lands nothing and is a refusal on the
`write` node that made it, counted like a refusal at eval, its words the
value and the range as decimals (`write: row.alpha = 2.0000 is outside
[0.0000, 1.0000] — the write lands nothing`). A queued write remembers
its node for that.

**Spindrift `e5b83b8`** — `row.alpha`, the row's opacity in [0, 1],
born 1 by the spray's spawn beside size and colour, faded by a kernel
(`row.age | over row.life [1, 1, 0] | write row.alpha`), bounded by the
field. `F_ALPHA` = 10, `F_U0` → 11. Dump format 4 with `alpha` the
last key; the Python reader follows and refuses a value outside [0, 1]
on its side too.

**Matryoshka `af1666e`** — blending is a probability. The slot grows a
third vec4 (x = alpha; yzw reserved for the kind's `soft`/`streak`); the
leaf is hit when the frame's hashed sample is below alpha × c, with c
exactly beat 5's rule; the CPU twin restates it; the reflection pass
passes the pixel's fixed sample instead of a placeholder 0, read only
below alpha 1. A new pair, `test_scene-fade`: the plate pose, the
embers rig one line apart.

## The gates, and what bit them

| gate | green at | the mutation that bit |
|---|---|---|
| rill: bounds refuse the landed value, replace/add/inclusive top, on the write node | rill | the check on the queued operand — `add` past the top lands, count 0 |
| spindrift: dump reads alpha's value at format 4 | spindrift | alpha written as zero into the dump — reads 0 for 32768 |
| spindrift: born 1, faded by `over`, 1 + 0.5 refused with the words, the row unchanged, its other write landing | spindrift | the spawn leaving alpha 0 — the fade kernel HID it (its first tick writes the first knot); the second spray caught it: 0 + 0.5 lands, count 0. And the bounds dropped from the schema: 1.5 lands, count 0 |
| spindrift: G0 with a fade — one byte string, alpha in the dump strictly between 0 and 1 | spindrift | the dump's alpha zeroed — nothing between |
| **G8**, twin: alpha 0.5 wide → 1985 of 4096 (2048 ± 128); alpha 0.5 × coverage 0.25 → 519 (512 ± 85); alpha 1 the old rule with the sample unread; alpha 0 never; a rim miss a miss at any alpha | matryoshka | the twin ignoring alpha — 4096 hits |
| **G8**, accumulation: 32 frames at alpha 0.5, mean 0.5000 ± 0.006, no pixel frozen | matryoshka | the same — mean 1.0000, 4096 frozen |
| **G8**, the lab: the three plate-family pairs bit-identical at alpha 1; the fade pair differs from the plate pair | matryoshka | the SHADER ignoring alpha — the fade pair renders to `379794ed…`, the plate pair's own hash |

Seven mutations across three repos, all bitten. Matryoshka's suite
2560/2560; the one failing build step predates the beat (below).

## The capture

`test_scene-fade`, `8ca3c6d1…`: the plate from its +x side at four
seconds, the embers rig with `kernels/cinders-fade.rill`. Against the
plate pair (`379794ed…`, same pose, alpha 1) 45 388 of 921 600 pixels
differ: the fresh plume is untouched, the older embers lying on the
plate and the strays on the grass beyond are dithered down — at one
sample per pixel a fading ember dithers, and the accumulated frame is
the blend. Christian is the judge of the picture; the fade curve
(`[1, 1, 0]`: hold for half a life, then out) is the first guess.

## Decisions taken, for ratification

1. **The witness is the plate pair; the customer is a new pair.** The
   three plate-family pairs stay at alpha 1 and held bit-identically —
   the proof that the factor is a factor of one at one. The fade is
   `test_scene-fade` beside them, one kernel line apart, so the
   difference between the two frames is the fade and nothing else.
   Rejected: re-freezing the plate pair with the fade (then nothing on
   the lab witnesses alpha 1).
2. **A third vec4 in the slot** (48 B), not alpha packed beside `kind` in
   `colour.w`. The stride will not change again for `soft` and
   `streak`.
3. **The reflection's sample is the pixel's fixed one**, index 0: it does
   not walk with the sequence, so a faded sprite in a mirror dithers the
   same way every frame. Recorded; trigger: a fading ember visible in a
   mirror under accumulation.

## Found, not mine

Matryoshka's `zig build test` fails one build step on
`src/control/commands.zig:42` — `@import("../physics_probe.zig")` is
outside the control test root's module path (`abe240e`, 2026-09-04).
The 2560 tests that compile all pass. Left as found.

## Next

P7, the cloud: `soft` on the kind, the profile in the same test, a
`smoke` kind on the plate. The slot already has its slot.
