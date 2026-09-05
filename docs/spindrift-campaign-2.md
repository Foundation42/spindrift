# Spindrift, second campaign — the picture on the plate

**Thesis.** The first campaign built the sim and the seam: a population that is right, replayable to the byte, and drawn. This campaign is what the eye sees. Its features are the appearance's — a fade, a soft edge, a glow, a streak — developed on test_scene (ruling 30), each with a gate on the lab's own pair and a capture from the plate, and the sim changes only where the picture needs a number the row does not carry. Sorting, order-independent transparency and a many-light pass stay on the far side of the fence; what crosses it is blending as a probability, which the leaf's coverage rule already is.

Rulings in §7 are Christian's; everything else is proposed-and-seconded and proceeds unless overruled. Gates come first because that is what gets built. **The five rulings of §7 ratified as proposed 2026-09-05**; P6 opened the same day. The first campaign's plan (`docs/spindrift-campaign.md`) stands; its rulings apply here unchanged.

---

## 1. What the eye asked for

- **A fade** (ruling 31): an ember that dims as it cools instead of popping out at the end of its life; smoke that thins as it rises.
- **A cloud**: a disc with a soft edge, so a hundred smoke rows read as one volume and not a wall of coins.
- **A glow without a light** (ruling 29): the plume glows because it emits, into the bloom the engine already has — not because four of its rows are point lights. The cap and its rank stay for the rows that must light the plate.
- **A streak**: a spark or a raindrop drawn along its velocity, a stretched sprite with soft ends — the threejs-punk teardown's rain (`~/Documents/reports/threejspunk-teardown.html`, 2026-09-05), which is a 0.04 × 1.1 quad billboarded on the vertical.

Recorded, not built (§8): the flipbook, additive sprites, the position-buffer collision oracle, MegaLights, G7.

---

## 2. Gates (pre-registered)

Each gate names the mutation that must bite. A gate that passes under its mutation is a finding about the gate, not a pass. Every gate here has two halves: the leaf's rule in matryoshka (with the CPU twin restating it, the same bits) and the lab pair — the frozen test_scene pairs must be **bit-identical at the feature's zero** (alpha 1, soft 0, streak 0), because a feature that moves the picture when it is off has a default that is not off.

**G8 — Blending is a probability.** A row's `alpha` (§6) enters the leaf's hit test as one more factor: the disc is hit when the frame's hashed sample is below `alpha × coverage`, else the ray continues — where `coverage` is exactly the shipped rule (1 inside a wide disc's rim test, the analytic coverage for a disc narrower than the footprint), so alpha 1 is today's picture to the bit. No sort, no OIT: order-independent by construction, and under accumulation the pixel's mean converges to the blend. Gate: the coverage gate's block (`1f2368e`) at coverage 1 and alpha 0.5 — hits about half of 4096 (σ ≈ 32); alpha 1 all, alpha 0 none; 32 accumulated frames, block mean 0.50 ± 0.01; the twin agrees bit for bit. The lab half: the embers rig with a fade kernel (`row.alpha = row.age | over row.life [1, 1, 0]`) renders a plate pair that DIFFERS from the frozen one and is re-frozen once; every alpha-1 pair unmoved. Mutation: alpha ignored in the test — the block is all hits and the fade pair is bit-identical to the opaque one. The row half (spindrift): `alpha` on the row, Q16.16, dump format 4 with the struple reader following in the same beat, G0 re-gated on a fade kernel; a write outside [0, 1] is refused and counted (§7.3). Mutation: the dump omitting `alpha`; the dump gate's value check bites.

**G9 — The soft disc.** An appearance number, `soft` (§6): the fraction of the radius over which the disc's alpha falls from the row's to zero — 0 is campaign 1's hard disc. Local alpha `alpha × profile(r / size)` goes into G8's test; nothing else changes. Gate: at `soft 1`, the hit count of a block covering the disc against the integral of the profile over the disc, to the same σ as G8; unmoved at 0 for every test_scene pair. Mutation: the profile evaluated at the wrong radius (the count is off by more than 3σ). Lab: a `smoke` kind on the plate — grey, slow, large, fading — captured once.

**G10 — Glow without a light.** Ruling 29's first version. A sprite's HDR colour reaches the engine's bloom as EMISSION, the way an emissive surface does: the ember plume glows in a capture with the `coals` light spray stood down, and the same capture with bloom off does not; a light row still lights the plate (the cap and its rank unchanged, ruling 26). Mutation: the leaf's emission written as albedo — the plume is drawn and does not glow. The first question of the beat is a read, not a build: whether an emissive disc already reaches `post.ctrl[2]`'s chain through the self-brightness gate (`vk_renderer.zig` ~691). If it does, G10 is a gate on what exists and the beat is the capture and a calibration for the picture's judge; if it does not, the beat wires it and nothing else.

**G11 — The streak.** An appearance number, `streak` (§6): a moving row is drawn as a capsule along its velocity — the disc of radius `size` swept by `streak × |vel| × dt` (one fed tick's travel, so a still row is the disc and unmoved at 0). The leaf's test becomes a capsule test with the same coverage rule against the cone footprint; the twin restates it. Gate: rows at one speed and one `streak`; the lit pixel count along the velocity axis grows with the factor as the capsule's area says, to the same σ; unmoved at 0 for every pair. Mutation: the axis taken from `pos` instead of `vel` — a still row stretches. Lab: rain over the plate — a spray above it falling under gravity with `collide | stick`, captured once.

Acceptance for the campaign: G8–G11 green, each mutation-bitten, every campaign-1 pair unmoved at the features' zeros, four captures from the plate (the fade, the cloud, the glow, the rain), and the whole set — dust2, oa_spirit3, the tiltyard — re-verified ONCE at the close, not per beat (ruling 30).

---

## 3. The seam, restated for the picture

- **The row carries what a kernel varies per row**; the appearance carries what is true of every row of a kind. `alpha` is the row's (a fade is a curve over age, and `over` is already the word for it); `soft` and `streak` are the kind's. A number that is the kind's today and a kernel wants per row tomorrow moves to the row with its trigger — not before.
- **The row's numbers today:** pos, vel, age, life, seed, size, colour, kind, stuck, normal (`F_NORMAL` = 9). `alpha` is `F_ALPHA` = 10, born 1; dump format 4 adds one column; `dump.column` reads it back.
- **The upload converts once per dirty chunk** (ruling 11); alpha rides in the slot beside size and colour. The leaf's tests — disc, soft disc, capsule — are one function with three numbers, not three arms.
- **Blending is stochastic transparency**, the coverage rule with one more factor. A single frame dithers; the accumulated frame is the picture (ruling 25's ground). Sorting and OIT stay fenced. Beat 5's rim question (the footprint switch) is answered by G8's construction: alpha 1 must be today's picture, so the switch stays; the pure rule for every disc is what `soft` gives a kind that asks for it.
- **The glow is emission, not light.** A light row is one of the capped four and casts; an emitting sprite blooms and casts nothing. Ruling 29 says which the first version prefers.
- **Every feature has a zero that is today.** The frozen pairs are the witness that a feature at zero costs the picture nothing; a beat that moves a pair at zero has found a bug, not a calibration.

---

## 4. Beats

| beat | what lands | gate | where |
|---|---|---|---|
| **P6 — the fade** | `alpha` on the row, dump 4, the reader; the leaf's test with the factor; the fade kernel on the embers rig; the plate pair re-frozen once | G8 | spindrift, struple, matryoshka |
| **P7 — the cloud** | `soft` on the kind, three formats; the profile in the test; a `smoke` kind on the plate | G9 | matryoshka |
| **P8 — the glow** | the read first; then the wiring if needed; the coals as emitting sprites beside the light rows; calibration for Christian's eye | G10 | matryoshka |
| **P9 — the rain** | `streak` on the kind; the capsule test and its coverage; rain on the plate | G11 | matryoshka |

Each beat re-renders its own pair on the lab (`spray_gate.py verify test_scene`, ten seconds for the family) and freezes its capture with a partial `capture`; the whole set runs once at the close. Ledger and reports as before: `docs/cc-report-beat<N>.md`, titled as a sentence with the customer scene in it.

---

## 5. Customer scenes

test_scene only, by ruling 30: the plate seen from its +x side, the frozen pose of `test_scene-embers-plate`. The fade (P6), smoke over the plate (P7), the coals glowing (P8), rain on the plate (P9). The close re-verifies dust2's motes, oa_spirit3's sparks and the tiltyard whole, once, and reports what moved and why.

---

## 6. Names to read aloud

- **`alpha`** (proposed) for the row's opacity. `row.alpha = row.age | over row.life [1, 1, 0]` reads. Rejected on read-aloud: `opacity` (the right word and the long one; the row's fields are `size`, `life`, `kind`, and the shader's name for the number is alpha); `fade` (the action a curve does to alpha, not the quantity); `tint` (colour).
- **`soft`** (proposed) for the kind's edge fraction: `sprayarche smoke … sprite soft 0.6`. Rejected: `edge` (which edge, and of what); `feather` (a tool's verb); `falloff` (the light's word already).
- **`streak`** (proposed) for the kind's stretch along velocity. Rejected: `stretch` (a disc stretched is still round-ended; sparks streak); `smear`; `trail` (fenced — a trail is a loop-loft spine and the word stays free for it); `motion` (the camera's word).
- **Campaign:** "the picture on the plate". Rejected: "the look" (matryoshka's saved looks are a thing), "eye candy" (the brief's own phrase, but not a title).

---

## 7. Rulings needed before P6 — all five ratified as proposed, 2026-09-05 ("go on the proposals, you have the conn")

1. **`alpha` on the row**, the kernel's, per row — or an appearance curve over age, the kind's? Proposed: the row's, by §3's rule; a curve on the kind would be a second curve mechanism beside `over`, and the kernel already writes size the same way.
2. **Blending as stochastic transparency** — a probability in the leaf's hit test, converging under accumulation — against a sorted blend in a raster pass. Proposed: stochastic; the path tracer already accumulates, the rule is one factor on what shipped in beat 5, and sorting and OIT stay fenced.
3. **A write outside [0, 1]**: refused and counted on `drift/@name/refused` with the row's alpha unchanged (loud, never a guess), or clamped at the write? Proposed: refused and counted — a kernel that says 1.2 has a curve wrong, and a clamp would hide it while the picture looked right.
4. **The glow's first version** (ruling 29): emission into the existing bloom, with the light cap untouched — confirm this is the "cheap screen-space particle light" meant, before P8 reads the chain.
5. **The names in §6.**

---

## 8. Fence and deferred fills

Not in this campaign: sorting and order-independent transparency; additive sprites (contribution without occlusion — a different walk through the leaves; trigger: a scene whose sparks must not occlude each other); the flipbook (a sprite sheet by `age / life`, two frames lerped; trigger: a splash); the position-buffer collision oracle (the teardown's top-down `vec4(worldPos, 1)` target as a `World` that answers `ground` for any number of rows at one pass's cost; trigger: a spray whose `collide` misses budget — Ironwood's rain); a MegaLights-shaped many-light pass (ruling 29, later); the GPU evaluator (G7, campaign 1 §6, unfired).
