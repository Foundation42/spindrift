# Beat 11 — the light: the cards are lit by the sun and the sky, and the coals light the plate uncapped

*CC, 2026-09-05/06. Campaign 3 (`docs/spindrift-campaign-3.md`), P11 —
the light. Straight after P10 on Christian's "onward".*

## What landed

**Matryoshka `263046f`**, nothing in spindrift's row.

**The card is lit by the world (G16).** The row's colour keeps the
leaf's one rule: what is at or below 1 is albedo, what exceeds 1 is
emission. The albedo is lit as a VOLUME's card: its normal a hemisphere
in the card's own frame — the disc's centre faces the eye, its rim turns
away — and the sun term wrapped (half-Lambert), so a puff has a sun side
and a lee without the lee going black when the sun is behind it. That is
Blade3D's per-card top/bottom gradient (`docs/recon/blade3d-particles.md`)
made real. The ambient is the compose's own hemisphere at the card's
normal, the sky tint and fill folded in on the CPU. The sun's visibility
is the tracer's own — `sun_shadow.comp`'s half-res image, the surface
behind the card — times the CSM at the fragment's world position where a
raster producer drew one; a fully traced scene draws nothing into the
CSM, and test_scene is one. Emission is added unlit and glows, since the
pass writes before bloom. Diffuse only, stated.

**The light rows are splats (G17).** Every live row of a `light` kind is
one instance of a second pipeline in the same pass, additive, drawn
BEFORE the cards: a quad covering the light's range on screen — the
projected bounds of its box, or the whole frame when the eye is inside
the range or any corner is behind the camera, which is how a light
behind the camera lights what is in front of it. The fragment rebuilds
the pixel's primary ray, takes the surface from the tracer's depth, the
normal and albedo from the G-buffer, and applies the engine's own
point-light terms, the diffuse half, no shadow. Uncapped: the bridge's
`lightRows` walks every live row where `lights` ranked four. The
analytic path for sprays is retired — main merges a count of zero — and
with it the cap, the rank-swap seam and the shadow budget.

**Plumbing.** The sprite pass's descriptor set grows the env image, the
CSM sampler, the G-buffer's normal and albedo, the light-row SSBO and
the tracer's sun visibility; its push carries the CSM's view-projection,
the camera's forward and fov, the sun's direction with the shadow
strength, the sun's radiance as the compose scales it, and the two
hemisphere colours — 256 bytes, exactly the device's ceiling. The
renderer keeps the last knob block for the sun's radiance knob.

## The gates, and what bit them

| gate | green | the mutation that bit |
|---|---|---|
| **G12** nothing mounted, nothing moved | `refs.py verify test_scene` unmoved with both pipelines in the frame; every bare unchanged at the freeze | structural |
| **G13** the tracer's time back, now with the coals ON | not re-claimed this beat: in one set the embers' traversal read 1.09 against 0.86 bare with EVERY other pass 25% slower too — the GPU's clock following the frame's CPU load in Debug, not the tracer. P10's idle set and its leaf mutation stand as the witness | (P10's mutation stands) |
| **G16** lit by the world | the smoke and the embers re-frozen lit; a new pair, `test_scene-smoke-shade` — the smoke kind under the plate at the beneath pose — is in the plate's shadow; the fresh embers glow | the tracer's visibility ignored on the card — the shaded smoke MOVED (5edfc765 → 206d2ab5); emission written as albedo — the plate MOVED (ded85519 → 15e8ea9f) |
| **G17** lights without a cap | fifteen coals light the plate as a soft warm pool (the cap's sum spread over the rows), the plate's underside dark from beneath; the behind pair: the beacon a metre and a half behind the eye lights the plate's near half — a quarter of the frame's pixels differ from the bare — stood down it does not | the splat ignoring the normal — the underside an orange sheet, the beneath pair MOVED (14a9e734 → daea1728); lights culled by their screen position — the behind pair equal to its bare |
| the bridge: `lightRows` gives fifteen where `lights` gave four, ids ascending, every row from the light kind | green | `lightRows` calling `lights` — the count reads 4 |

Suite 2565/2565; the control-root compile failure stands as found. G18: the seven pairs held on the clean rebuild.

## The captures

All seven plate-family pairs frozen through P11; every bare unchanged:

| pair | P10 | P11 |
|---|---|---|
| test_scene-embers | 7aa1ebc8… | 4c5c268e… |
| test_scene-embers-plate | 6a32fbb4… | ded85519… |
| test_scene-embers-plate-beneath | f9311226… | 14a9e734… |
| test_scene-fade | 4a193d9a… | 3bba8919… |
| test_scene-smoke | 482a9ee5… | 50a1bd43… |
| test_scene-behind (new) | — | c79317fd… |
| test_scene-smoke-shade (new) | — | 5edfc765… |

The embers are lit spheres with a sun side and a lee; the plume stands
grey against the sky with its sun side lighter; the smoke under the
plate is dark in the plate's shadow; the coals light the plate top as a
soft warm pool and its underside not at all, the grass beneath lit
through the plate as unshadowed splats must. Christian is the judge of
the picture.

## Decisions taken, for ratification

1. **The card's normal is a hemisphere in its frame, and the sun wraps.**
   A flat card facing the eye would light every puff the same from any
   sun; a sphere's lee went black against the sky (the first build). The
   hemisphere with half-Lambert gives a sun side and a lee that reads as
   a volume, and the recon's cloud recipe wants it.
2. **The ambient is the compose's hemisphere at the card's normal**, not
   the pixel's env_diff: half a plume stands against the sky, where
   env_diff is nothing (the first build lit the smoke black there). A
   probe-lit card is a later fill; env_diff stays bound for it.
3. **The sun's visibility is the tracer's, at the pixel** — the surface
   behind the card — with the CSM kept for raster-produced scenes. In a
   traced scene the CSM holds nothing, which the "no shadow on the
   card" mutation SURVIVING at the plate pose revealed: smoke placed
   under the plate rendered the same bytes with and without the CSM
   lookup, so the card's shadow now comes from where the tracer keeps
   it. Nine CSM taps, not twenty-five, where it does apply.
4. **The splat is the engine's diffuse point-light term with kD = 1**,
   no specular, no shadow ray (ruling 4). Metallic surfaces under a
   coal are lit as dielectrics; stated.
5. **The analytic spray lights are retired**, the code kept for the
   bridge's own gates of the ranked list.

## Found

**A stage on an older push layout draws nothing.** The first build kept
the vertex stage on P10's push block while the fragment and the layout
moved: right and up read rows of the CSM matrix, every card vanished,
and a mutation chain ran on that build before the picture was looked at.
Its results were discarded; every mutation was re-run on the fixed build.

**A push of 272 bytes faults the device on every frame.** Adding a ninth
vec4 for the sky tint went past the 256-byte ceiling; the validation
layer said so in one line (`VUID-VkPushConstantRange-size-00298`); the
tint is folded into the two hemisphere colours on the CPU.

**The harness hashed yesterday's frames.** With every render faulting,
`spray_gate.py capture` reported six pairs "taken" at exactly their
previous hashes — the PPMs were the old files — and only the new pair,
with no earlier frame, said "no output frame". Both harnesses now delete
their target before rendering.

**Ruling 26 uncapped.** Fifteen coals at the gain that was the cap's sum
lit the plate as an orange sheet; the sum is spread over the rows.

**Background chains and the memory watchdog.** Two chains were killed at
a rebuild for "low memory" with 23 GB free a second later; the closing
steps ran in the foreground in short pieces.

## Next

P12, the look: `blend add` for sparks, `streak` along velocity, the kind
table's last two columns — and the decision the recon forced first: a
population whose kind changes by age spans two blend modes, so the pass
draws by kind after sorting.
