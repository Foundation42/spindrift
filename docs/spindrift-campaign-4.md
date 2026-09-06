# Spindrift, fourth campaign — the puff: a handful of cards that read as a cloud

**Thesis.** Campaign 3 draws the rows as lit, sorted, blended cards over the traced frame. A plume of them still reads as a stack of discs up close. Christian's 2010 engine had a cloud that did not (`docs/recon/blade3d-particles.md` §3), and its recipe is eight shader lines: a 3D noise field sampled in WORLD space and added to every card, so overlapping cards agree on where the lumps are; a second, finer octave scrolling with time and combined by `max`, so wisps move without washing out; a per-card top/bottom gradient — which campaign 3 already made real as the sun and the sky on a hemisphere normal; and a gamma lift. This campaign puts that field on the composite's card as the kind's numbers, with the plate's smoke as the customer, and takes the light shafts as its second beat if the pass can be handed the sun's frustum.

Rulings in §6 are Christian's; everything else is proposed-and-seconded and proceeds unless overruled. Gates come first because that is what gets built. Campaigns 1–3 stand; ruling 30 above all: test_scene is the lab.

---

## 1. What the eye asked for

- **A cloud, not coins.** Lumps that belong to the volume, not to the card: move the eye and the lumps stay where the air is.
- **Wisps that move** with fed time, never a clock, so a capture freezes and a replay agrees.
- **The knobs on the kind**, in the three formats, so a rig says what a cloud is.

Recorded, not built (§7): the light shafts, the flipbook, the capsule streak.

---

## 2. Gates (pre-registered)

**G19 — The field is one field.** A tiling 3D noise volume, generated at init from a fixed seed on the CPU by an integer hash (a Perlin lattice over 128³ cells, R8), uploaded once, sampled by the card's fragment at its WORLD position over the kind's `noise` scale. Gate: the volume's bytes hash to a frozen value (the generator is deterministic and the same on every machine); it tiles — the value at 0 equals the value at 128 on every axis; the smoke pair with the puff numbers differs from the smoke pair without, frozen once. Mutations: the noise sampled in the card's own frame instead of the world (the puff pair MOVED — and its lumps would ride with the cards); the seed from the clock (the volume's hash moves between two inits).

**G20 — Wisps on fed time.** The dust octave scrolls by the sim's fed time: two renders of the puff pair hash the same (G18 stands), and a capture at a later fed frame differs only in the wisps. Mutation: the scroll from the wall clock — two renders differ.

**G21 — Every campaign-3 pair unmoved at the puff's zero.** With `grain`, `dust` and `lift` at their zeros (0, 0, 1) the card is campaign 3's card to the bit: the eight lab pairs held. Mutation: the noise applied at grain 0 — the smoke pair moves.

Acceptance: G19–G21 green and bitten, the puff pair frozen from the plate; the whole set once at the close.

---

## 3. The seam, restated

- **The sim is untouched.** No row field; the puff is the KIND's.
- **The kind's numbers, one verb:** `sprayarche puff <kind> <noise> <grain> <dust> <drift> <lift>` — `noise` metres per lump, `grain` how much the lumps show in [0, 1], `dust` metres per wisp (0 off), `drift` the wisps' rate in metres a second, `lift` the gamma on the card's albedo (1 none). One rig token group after `blend`, five pack fields, one verb; one validation.
- **The look table grows** to three vec4s per spray (soft, near, blend, streak | noise, grain, dust, drift | lift, 0, 0, 0).
- **Where the field acts:** the noise modulates the card's ALBEDO (the lumps are shading, consistent across cards) and, by `grain`, its alpha (the silhouette erodes where the field is low, so the edge of a plume is the field's, not the disc's); the dust brightens by `max`; the lift is `pow(albedo, lift)` before the light. The light stays campaign 3's.
- **Fed time reaches the pass** in the push's spare lane (the bank already keeps its last tick time).
- **The volume is procedural**, not an asset: the repo keeps no binaries, and a generator with a frozen hash is a gate; Blade3D's 128³ DDS is the reference for the look, not the bytes.

---

## 4. Beats

| beat | what lands | gates | where |
|---|---|---|---|
| **P13 — the field** | the volume generated and bound (a `sampler3D`, repeat, linear); `puff` on the kind in three formats; the fragment's noise, dust and lift; the puff pair from the plate | G19, G20, G21 | matryoshka |
| **P14 — the shafts** (if the pass is handed the sun's frustum) | frustum-aligned cards through the sun's visibility; the beam over the plate | (its own gate) | matryoshka |
| **close** | the whole set once | G21 whole | matryoshka |

---

## 5. Customer scene

test_scene, the plate pose: the smoke kind with the puff — `test_scene-puff` beside the unchanged `test_scene-smoke`, one line apart, so the difference is the field and nothing else.

---

## 6. Rulings needed before P13

1. **The puff is the kind's, five numbers under one verb** (`sprayarche puff`), rather than five verbs. Proposed for the rig line and the read-aloud.
2. **The noise modulates albedo and alpha both** (shading and silhouette), the dust by `max`, the lift on the albedo before the light. Proposed as the recon's recipe with the lighting kept real.
3. **The volume is generated, not shipped**: a CPU generator with a frozen hash, 128³ R8.
4. **Names** (§8): `puff`, `noise`, `grain`, `dust`, `drift`, `lift`.

---

## 7. Fence and deferred fills

The light shafts wait on the sun's frustum reaching the pass (P14 if it does). Not here: the flipbook; the capsule streak; a probe-lit card; sprite reflections; the sun depth pass over traced geometry (campaign 3's fill, unchanged).

---

## 8. Names to read aloud

- **`puff`** (proposed) for the group — "give the smoke a puff". Rejected: `cloud` (a kind's name, not a look's), `volume` (the texture's word), `lumps`.
- **`noise`** metres per lump; **`grain`** how much it shows (rejected: `amount`, `strength` — say nothing); **`dust`** the wisp octave's scale (Blade3D's own word); **`drift`** its rate (rejected: `rate` — the spray's word for rows a second; `wind` — a field's word); **`lift`** the gamma (rejected: `gamma` (the display's word), `bias` (Blade3D's, but it reads as an offset)).
