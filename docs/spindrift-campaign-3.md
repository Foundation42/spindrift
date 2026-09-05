# Spindrift, third campaign — the composite: sprites over the traced frame

**Thesis.** Campaign 2 called the ray-traced sprite (its §7 ruling 6): one hashed sample per pixel is noise under a moving camera, the motes and the smoke each needed a rule of their own, the lights hit a budget built for lamps, and the tracer paid one to two milliseconds of traversal for it at 720p — GPU budget Christian would rather spend on screen-space effects. This campaign draws the same rows as **sorted billboards in a raster pass over the traced frame, aware of its G-buffer**: depth-tested and softly faded against the tracer's eye-distance depth, lit by the sun through the CSM and by the sky through the per-pixel ambient, written into the HDR composite before bloom so emission glows for free, and — for the rows that are lights — splatted onto the G-buffer as deferred lights with no cap. The sim does not change. The tracer stops seeing particles, and the leaf stays behind an appearance name for the customer who one day wants a sprite in a mirror.

Rulings in §7 are Christian's; everything else is proposed-and-seconded and proceeds unless overruled. Gates come first because that is what gets built. **The six rulings of §7 ratified as proposed 2026-09-05**; P10 opened the same evening. Campaigns 1 and 2 stand (`docs/spindrift-campaign.md`, `docs/spindrift-campaign-2.md`); their rulings apply here unchanged, ruling 30 above all: test_scene is the lab, one pair per beat, the whole set once at the close.

---

## 1. What the eye asked for

- **No bees.** A blended pixel is an exact function of the rows in front of it: a fade is a fade and a soft rim is a gradient, at one sample, with the camera moving.
- **The tracer's time back.** Traversal with sprays mounted costs what it costs bare.
- **Glow, lit smoke, and lights without a cap** — the "cheap screen-space particle lights and shadows" of ruling 29, as meant.
- **The look that raster makes cheap:** additive sparks, a streak along velocity, a sprite sheet when a splash asks for one.

---

## 2. What the engine already has (the recon, 2026-09-05)

The tracer writes a G-buffer every frame: `depth_out` (R16F, euclidean eye distance), `nee_normal` (rgba16f), `nee_albedo` (rgba8), `nee_irradiance` (rgba16f), `g_env_diff` (the per-pixel sky/probe ambient), `sun` and `shadow`, `ao`, `light_vis`/`light_unsh`, `reflection`. `post_composite.comp` folds those into `composite_image` (rgba16f HDR), which `bloom_down` reads unthresholded (energy-conserving, Karis on the first mip) and `post.comp` lerps toward bloom, grades and tonemaps. A raster overlay pipeline (`gizmo.vert/frag`) already draws straight-alpha geometry over the frame and depth-tests each fragment against `depth_out`; the raster G-buffer producer (`raster_gbuf.frag`) already samples the CSM (D32, 2048²) for sun visibility. Particle rows already reach the GPU as a 48-byte slot per row (position, radius, colour, kind, alpha) and each spray's light rows already reach `main.zig` as a list.

So the composite is a **graphics pass between `post_composite` and `bloom_down`**, rendering into `composite_image` as a colour attachment, reading `depth_out`, `g_env_diff` and the CSM, with fixed-function blending. Nothing new is computed by the tracer; one image gains the colour-attachment usage bit.

---

## 3. Gates (pre-registered)

Each gate names the mutation that must bite. Every gate here has a witness on the lab (ruling 30) and, where it claims a picture, a capture from the plate pose.

**G12 — Nothing mounted, nothing moved.** With no spray mounted the pass draws nothing and every frozen reference holds at AE=0 — `refs.py verify test_scene` bit-identical, and the whole set at the close. Mutation: the pass clearing or touching the attachment with zero rows (a `vkCmdClearAttachments`, a full-screen quad at alpha 0 that still rounds) — the reference moves. Precedent: G5's first assertion.

**G13 — The tracer's time back.** With the embers mounted, the traversal sub-bucket's GPU time equals the bare scene's within its spread (measured 2026-09-05: bare 1.14 ms, mounted 1.94; inside the plume 1.36 against 3.32) — the dynamic tree carries no particle leaf for a `sprite` kind. Mutation: the leaf still published for `sprite` — traversal is a millisecond over bare. The pass's own cost is printed beside it (a new sub-bucket, `sprites`), not banded this campaign.

**G14 — A blended pixel is exact.** The plate pose with the fade rig: the capture is a picture with no dither, frozen once, and two renders hash the same; the twin of the blend (the CPU `over` of N sorted rows at one pixel) agrees with a probed pixel to the tonemapper's rounding. Mutations: the sort reversed (front-to-back — the hash moves and the twin disagrees); a tie broken by slot instead of id (two rows at one depth swap between frames of a still capture — the hash moves between two renders). The sort is on the CPU, by quantised eye distance then id, so the order is a function of the rows.

**G15 — Soft against the world.** A sprite crossing the plate fades over the kind's `near` distance of the surface behind it and is cut where it passes behind it; at `near` 0 it is a hard depth test. Gate: rows placed at known depths against the plate; the probed alpha at three pixels matches the fade on paper. Mutation: the depth compared in clip units instead of eye distance — the fade's width depends on the pixel, the three numbers disagree.

**G16 — Lit by the world.** A smoke sprite in the plate's sun shadow is darker than one in the sun by the CSM's visibility, and both carry the sky's ambient from `g_env_diff` at their pixel; an emitting sprite (Oklab L above 1) is written as emission and blooms — the coals glow with the light rows stood down. Mutation: the CSM read at the row's position instead of the fragment's — a wide sprite half in shadow is uniformly lit; the emission written as albedo — the coals do not glow.

**G17 — Lights without a cap.** A light row splats a deferred diffuse light onto the G-buffer within its range — N·L, distance falloff, the row's colour, the surface's albedo — into the composite, uncapped, no shadow; sixteen coals light the plate where four did, and the rank-swap seam of campaign 1 is gone by construction. Mutation: the splat ignoring the G-buffer normal (the underside of the plate lights up — the warm pool of ruling 24, for the last time).

**G18 — Determinism holds across the seam.** G0 and G6 unchanged (dumps and transcript are the sim's); and two renders of any mounted pair hash the same — a raster blend on one GPU in one order is exact. This is G14's second half, stated as the campaign's claim.

Acceptance: G12–G18 green, each mutation-bitten; the plate captures re-frozen once per beat; the whole set re-captured once at the close with the dust2 motes as the honest before/after.

---

## 4. The seam, restated for the composite

- **The sim is untouched.** No row field changes; `alpha` and `soft` carry over as they are; the words, the dumps, the budget, the replay are campaign 1's and 2's.
- **The appearance names say which path draws a kind.** `sprite` becomes the raster composite — the default, and what every rig means today. `traced` is the old leaf, kept whole and off by default, for the customer who one day needs a sprite in a reflection: its twin gates stay in the suite (cheap), its mounted captures leave the verify set. `light` becomes the G-buffer splat (G17); the analytic point-light path for sprays, its cap and its shadow budget, are retired.
- **The pass reads the G-buffer, never the tracer's tree.** Inputs: `depth_out`, `g_env_diff`, the CSM, the slot buffer, a sorted index buffer. Output: `composite_image`, blended. Bloom and post see sprites as scene.
- **Sorting is the CPU's, per frame, deterministic**: live rows across every `sprite` spray by quantised eye distance, id breaking ties, into an index buffer beside the slots. At sixteen thousand rows this is under a millisecond in Debug and noise in ReleaseFast; a GPU sort is recorded with its trigger (a population the CPU sort misses budget on).
- **The kind's look numbers ride a per-kind table** (`soft`, `near`, the blend mode, the streak factor), indexed by the slot's `kind`: one small uniform buffer, not a per-row copy and not the leaf payload — the leaf is gone from this path.
- **A lit sprite is a camera-facing card lit as a surface**: `albedo × (env_diff(pixel) + sun × csm(world))`, diffuse only; emission where L exceeds 1, as the leaf's rule was. No AO, no reflection, no shadow from the sprite onto the world — stated.
- **The float boundary** stays where it was: rows are converted once per dirty chunk at upload; the sort reads the converted floats.

---

## 5. Beats

| beat | what lands | gates | where |
|---|---|---|---|
| **P10 — the pass** | the graphics pass into the HDR composite; the CPU sort; depth test and `near` fade; `sprite` drawn here, `traced` named and off; the sub-bucket; the plate pairs re-frozen (embers, fade, smoke) | G12, G13, G14, G15, G18 | matryoshka |
| **P11 — the light** | sun × CSM and the sky's ambient on the card; emission into the composite; the coals as emitting sprites; the light splat replacing the point lights; the coals rig re-frozen from above and beneath | G16, G17 | matryoshka |
| **P12 — the look** | `blend add` for sparks; `streak` along velocity in the vertex; the kind table's last two columns; the sparks rig on the plate | (extends G14) | matryoshka |
| **close** | the whole set re-captured once — dust2's motes, oa_spirit3's sparks, the tiltyard — with the before/after in the report; the tracer's leaf gates kept, its captures retired | G12 whole | matryoshka |

Each beat: `spray_gate.py verify test_scene` for the witness, a partial `capture` for its pair, matryoshka's suite alone with `-j4` before the commit. Reports as before.

---

## 6. Customer scenes

test_scene only until the close (ruling 30): the embers on the plate (P10, the hash that proves exactness), the fade and the smoke re-taken without bees (P10), the coals glowing and lighting the plate uncapped (P11), sparks additive and streaked (P12). At the close, dust2's motes — the scene that first asked for a special rule — drawn as what they are.

---

## 7. Rulings needed before P10 — all six ratified as proposed, 2026-09-05 ("I like the sound of this. agreed. let's go")

1. **`sprite` is the raster composite; `traced` keeps the leaf, off by default.** Proposed so a rig from campaign 1 means the new picture with no edit, and the leaf's code and twin gates stay for a customer. The alternative is deleting the leaf; Christian said "we can return to it", so kept.
2. **The pass sits before bloom, into the HDR composite.** Proposed: sprites bloom and tonemap as scene, and emission needs no second path. The alternative, over the final image like the gizmos, would need its own tonemap and would never glow.
3. **The sort is the CPU's, by quantised eye distance then id.** Proposed for determinism (G14, G18) and simplicity; a GPU sort is recorded with its trigger.
4. **The light rows become G-buffer splats, uncapped, unshadowed.** Proposed as ruling 29's "cheap screen-space particle lights" — shadows are the MegaLights-shaped pass, later. The analytic path for sprays is retired with its cap.
5. **Names** (§8): `near` for the kind's depth-fade distance; `blend alpha|add`; `traced`; `streak` stands from campaign 2.
6. **The traced captures leave the verify set** and the leaf's twin gates stay. (The mounted hashes for every pair change in this campaign; the bare references must not — G12.)

---

## 8. Names to read aloud

- **`near`** (proposed) for the kind's depth-fade distance — `sprayarche near smoke 0.4` — "the kind fades within 0.4 m of what is behind it". Rejected: `fade` (the row's alpha over life is the fade; two fades is a confusion), `contact` (`stick`'s word), `depthfade` (a compound; reads as code), `soften` (a verb, and `soft` is taken).
- **`blend alpha|add`** (proposed) — `sprayarche blend sparks add`. Rejected: `over` (rill's curve word), `mode` (says nothing), `additive` (longer for no gain), `glow` (emission is a colour's L above 1, not a blend).
- **`traced`** (proposed) for the leaf's appearance — `sprayarche appearance dust traced`. Rejected: `leaf` (the tree's word, not a look), `rt`, `raytraced` (long; and everything here is traced but this).
- **`sprites`** for the pass and its perf sub-bucket. Rejected: `composite` (the HDR image's own name — the pass draws INTO the composite), `overlay` (the gizmos' word, after post), `particles` (the buffer's name).
- **Campaign:** "the composite". Rejected: "screen space" (the lights are, the sprites are cards in the world), "the overlay" (after post is what an overlay is).

---

## 9. Fence and deferred fills

Not in this campaign: shadows cast by particles onto the world or each other; shadows ON particles from lights other than the sun (the MegaLights-shaped pass — ruling 29's "later"); particles in reflections (that is what `traced` is for); a GPU sort (trigger: a population the CPU sort misses budget on); the sprite sheet / flipbook (trigger: a splash — cheap now, and one beat when it fires); soft particles against other particles (an order-independent volume — a different thing); the position-buffer collision oracle (campaign 2 §8, unchanged); the GPU evaluator (G7, unchanged).
