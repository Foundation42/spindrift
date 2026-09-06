# Campaign 3, closed — the composite holds, and the puff is next

*CC, 2026-09-06, the close-out of `docs/spindrift-campaign-3.md`. Three
beats (`docs/cc-report-beat10.md`, `-beat11.md`, `-beat12.md`). Written
to be read by someone who has read none of them.*

## What was built, in one paragraph

Particles are drawn as sorted, blended cards over the path-traced frame,
aware of its G-buffer. A graphics pass between the lit HDR compose and
bloom draws every `sprite` row as a screen-aligned card pulled from the
same slot buffer the tracer's leaf read, through a draw order the bridge
sorts on the CPU each frame — back to front by the drawn position's
distance from the eye, ties by id then spray — cut into runs by blend
mode and drawn with the pipeline each run asks for. The card is
depth-tested and faded against the tracer's eye-distance depth, lit by
the sun through the tracer's own visibility under its centre and the
CSM where one exists, wrapped over a hemisphere normal, with the
compose's hemisphere ambient; what exceeds one in the row's colour is
emission and glows. Light rows are additive splats over the G-buffer,
uncapped, a light behind the camera lighting what is in front of it.
The kind carries `soft`, `near`, `streak` and `blend` in three formats.
The tracer stops seeing particles — `traced` names the old leaf, kept
whole and off — and its traversal costs what it costs bare. The sim did
not change.

## The gates, and what bit them

| gate | what it holds | the mutation that bit |
|---|---|---|
| **G12** nothing mounted, nothing moved | every frozen reference unmoved with both pipelines in the frame — the lab pose at every beat, the whole set at the close (below); every pair's bare hash unchanged at every freeze | structural — the pass records only its stamps at zero rows |
| **G13** the tracer's time back | traversal 1.09 ms bare against 1.06 with the embers and the coals stood down, the card pass 0.03–0.07 ms (P10, idle set) | the leaf republished for `sprite` — traversal 5.50 against 3.29 |
| **G14** a blended pixel is exact | frozen pairs held on clean rebuilds after every beat; the sort back to front by distance, ties by id then spray; runs by blend | the sort reversed (the fade pair moved); the tie by slot — survived the single-spray gate, bit the cross-spray one; the runs cut by spray (three for one) |
| **G15** soft against the world | `near` on the kind, the fade in the fragment over the depth behind | (the numbers gate not built: recorded) |
| **G16** lit by the world | the plume lit with a sun side and a lee; smoke under the plate in its shadow; one visibility per card after Christian's leak | the traced visibility ignored (the shaded smoke moved); emission as albedo (the plate moved); the visibility read per fragment (the shaded smoke moved) |
| **G17** lights without a cap | fifteen coals light the plate as a soft pool, the cap's sum spread over them; the underside dark; a beacon behind the eye lights the plate's near half | the splat ignoring the normal (the underside an orange sheet); lights culled by screen position (behind == bare) |
| **G18** determinism across the seam | eight pairs held on the clean rebuild after every beat; G0 and G6 untouched | (G14's second half) |

Mutations across the campaign: eleven run, all bitten or the gate
rewritten — one survivor named a real cross-spray case in P10 and then
bit; every one is in the ledger with the gate that caught it.

## The whole set, once (ruling 30)

`refs.py verify --really`, nine scenes, with both pipelines in every
frame and nothing mounted — every reference unmoved, timings within band:

| scene | | gpu ms |
|---|---|---|
| dust2 | unmoved | 6.27 |
| q3 | unmoved | 2.41 |
| cornell | unmoved | 1.65 |
| test_scene | unmoved | 2.39 |
| shapes | unmoved | 1.25 |
| lights | unmoved | 1.74 |
| towers | unmoved | 2.08 |
| mesh | unmoved | 0.56 |
| sponza | unmoved | 8.56 |

That is G12 whole: a pass that records only its two timestamps at zero
rows moves no reference in any scene.

## The customer captures

The four pairs that were the leaf's, re-taken once as the composite's:

| pair | the leaf (campaign 1–2) | the composite (close) |
|---|---|---|
| oa_spirit3-sparks | 9ac6cb99… | a8b721a0… |
| dust2-motes | c49d3756… | c4d0885d… |
| tiltyard-torch | 81304695… | c9c3042d… |
| tiltyard-fountain | 33041ea4… | 26ad3c5a… |

dust2's motes — the scene that first asked for a special rule — are the
same scatter in the shaft, drawn as cards: no coverage rule, no hashed
sample, no cloud of anything. oa_spirit3's sparks are the burst they
were, lit now. The torch and the fountain moved as every mounted pair
did.

**Two bares moved, and not by this campaign.** The pairs' bare frames
were frozen on 2026-09-02; since then the engine's own history re-froze
dust2's reference after the importers' BC7 alpha fix (`e87d898`,
2026-09-05), and the q3 after-frame carries a floor decal absent from the
before-frame. The tiltyard's two bares, a scene nothing touched since,
match to the byte; the nine references at their own poses, kept current
by that same history, are unmoved with the pass in the frame. The moved
bares are re-frozen with their pairs and said here.

## The fence, as it stands

Untouched by design: shadows cast by particles onto the world or each
other; shadows ON particles from lights other than the sun; particles in
reflections without `traced` (recorded: the reflection pass sampling
the composited layer, trigger the first reflective floor under a spray);
a GPU sort; the sprite sheet / flipbook; soft particles against other
particles; the position-buffer collision oracle; the GPU evaluator (G7).

## Deferred fills, with their triggers

| fill | trigger | state at close |
|---|---|---|
| a sun depth pass over the traced geometry, so a card's own position answers its shadow | a card whose area should be half in shadow | recorded (P12); the per-card visibility stands in |
| G15's numbers gate (three pixels against the fade on paper) | the first `near` that is tuned by eye | recorded |
| a capsule streak with round ends | a customer who wants one | recorded; the ellipse stands |
| a probe-lit card (env_diff at the pixel) | a spray in a probe-lit room | recorded; the hemisphere stands, env_diff stays bound |
| sprite reflections through the composited layer | the first reflective floor under a spray | recorded (Christian, P10) |
| **the puff** — the Blade3D cloud recipe: a noise volume bound to the pass, world-space noise so overlapping cards agree, a dust octave, a gamma lift; the cloud kind | **fired** — Christian's ask, the recon in `docs/recon/blade3d-particles.md` | the next campaign's opening beat |
| light shafts (frustum cards through the sun's visibility) | the pass handed the sun's frustum | recorded |
| turbulence and the shock ring as row words | a customer scene and a read-aloud | recorded (spindrift's, not this campaign's) |
| promote-by-age | the fenced sub-sprays, with a shape now | recorded |

## Rulings

Six ratified at the campaign's open (§7). Taken during the campaign for
ratification, all in the beat reports: the looks keyed by spray slot
(P10); the card's hemisphere normal and wrapped sun, the compose's
hemisphere ambient, the tracer's visibility as the card's shadow, the
splat as the engine's diffuse term with no shadow, ruling 26's sum spread
over the rows (P11); one visibility per card, runs by blend in the
sorted order, the streak an ellipse in seconds of travel (P12).

## What the campaign moved in the siblings

Nothing in spindrift's row or in rill. Everything in matryoshka:
`5a3ed8e` (P10), `263046f` (P11), `1d6f223` (P12), and the close's
manifest.

## Next

"The puff", written fresh as its own campaign: the noise volume as a
binding of the pass, world-space noise on the card, the cloud kind and
its numbers in three formats, the plate's smoke as the customer — with
the light shafts as its second beat if the sun's frustum reaches the
pass.
