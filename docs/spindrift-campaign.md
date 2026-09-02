# Spindrift — campaign plan

**Thesis.** A particle system that is rill-shaped from the first line: sprays are rill programs, per-particle behaviour is rill operators evaluated over populations, coupling to the world is `$` fields in both directions and tracer verbs. CPU first; the GPU arrives later as a second evaluator of the same text, not a port.

**Name.** Spindrift — spray lifted off water and carried on the wind. Born off a rill, driven by fields. Plane prefix `drift/`. Read aloud before committing; alternatives recorded in §9.

Rulings in §7 are Christian's; everything else is proposed-and-seconded and proceeds unless overruled. Gates come first because that is what gets built. **All ten rulings ratified 2026-09-01** (beat 0 accepted); the amendments they made to this document are marked *ruled*.

---

## 1. Shape of the repo

`Foundation42/spindrift` — a standalone Zig library beside rill, spark and common. Same house style, same ledger rules.

Owns:
- the population format (struct-of-arrays, fixed capacity per spray)
- the spray archetype/instance tenant on the `^`/`@` spine (`^spray` kind, `@<name>` instance — *ruled*, §7.4a)
- the sim scheduler (chunked over `common/jobs.zig`, fed time only)
- the per-particle kernel words, registered into rill's registry like every other word; rill owns the row plane and the row evaluator (`rill/src/row.zig`, spec §3.16)
- the `World` query interface the host implements (tracer verbs are host words; spindrift is their first client)
- a mock `World` (flat floor at y=0) and `drift-run`, so a spray mounts on rill's mock plane with no engine

Does not own:
- rendering — that is Matryoshka's `LEAF_PARTICLES` and the appearance archetypes
- geometry queries — `solver.zig` implements the `World` interface for Matryoshka
- the evaluator — rill parses and evaluates; rill carries the row-legal column and the row runtime (§3.3, *ruled*)

Dependencies: common (jobs), rill (plane borrow, registry, parser), struple. No dependency on Matryoshka. Matryoshka depends on spindrift the way it depends on rill and spark.

---

## 2. Gates (pre-registered)

Each gate names the mutation that must bite. A gate that passes under its mutation is a finding about the gate, not a pass.

**G0 — Determinism.** Same `.rill` + seed + fed-time script → byte-identical population dump after N ticks, two runs. Mutation: perturb the seed; dumps differ. Precedent: `repro-input`. **Green and bitten, beat 0; re-gated on the rill-text kernel, beat 1** — and it now also asserts the population moved and fell, because a kernel whose every write was refused produced identical bytes of nothing.

**G1 — The population is plane-native.** A spray publishes `drift/<@em>/count` (and bounds, and a change-only digest) on the plane; a second rill reads `count`, pipes it through `above`, and writes a knob. The knob changes when the population crosses the threshold. Mutation: unmount the spray; the knob stays put and `count` says zero (absence is said). Precedent: the live sensor loop. **Green and bitten, beat 1.**

**G2 — Kernels are operators.** Every spindrift word walks the standing wire gate, the argument-spelling gate (adjacent wordless optionals refused), the registry-walk typing gate and the manual/registry identity gate. Structural — the gate is the existing gates admitting the row column. Mutation: register a word with two adjacent wordless optionals; the registry refuses it at build. **Green and bitten, beat 1.**

**G3 — Fields in.** A spray that samples `$wind` bends; unmount the caster and the trail straightens within the deposit's decay. Mutation: disable sampling in the kernel; the trail is straight from tick 0 and the gate fails. **Green and bitten, beat 2.**

**G4 — Fields out.** A smoke spray casts `$dankness`; an ear downstream reads above zero; the spray unmounts and the ear reads zero (casts are owned by their caster — ownership is the ceiling: the bag goes with its owner, at once). Mutation: remove the cast line; the ear never rises. **Green and bitten, beat 2.**

**G5 — The leaf.** Matryoshka renders the population through `LEAF_PARTICLES`. Ordinary path first (rule 7): with no spray mounted, every frozen ref holds at AE=0. Then: a capture with one spray mounted differs from the frozen ref, and a capture with the same spray unmounted is AE=0 again. Mutation: leaf returns no hit; the mounted capture equals the frozen ref and the gate fails. **Green and bitten, beat 3** — nine refs at AE=0 before, after the leaf, and after the first picture; captures test_scene (acceptance) and oa_spirit3 (reach).

**G6 — Budget, not clock.** The scheduler consumes a budget in row-steps per tick from a knob, never milliseconds. Under a spawn burst that exceeds the budget, `drift/<@em>/throttled` occurs and the tick still replays byte-identically. Mutation: read wall-clock anywhere in the sim; `repro-input` differs across two runs.

**G7 — Two evaluators, one text.** (Horizon, not v1.) The same kernel `.rill` evaluated on CPU rows and on the GPU produces the same population after N ticks. Integer positions make this a bit-identity gate rather than a tolerance gate. Recorded so the v1 population format is designed to survive it.

Acceptance for the campaign: G0–G6 green, each mutation-bitten, plus one eye-candy capture per customer scene (§5).

---

## 3. Design

### 3.1 Population

Struct-of-arrays, capacity declared on the `^` archetype (everything a program touches exists before mount; unbounded state is a corpse). Rows:

| field | type | note |
|---|---|---|
| pos | i32×3 | scene lattice, Morton-derivable — same lattice the BVH quantises to |
| vel | fixed-point ×3 | |
| age, life | fed nanoseconds | ticks in P0; ns from beat 1 — a tick count made age depend on dt history, and a variable-dt host breaks that |
| seed | u32 | per-row decorrelator for `noise` |
| size | fixed-point | |
| colour | Oklab, fixed-point | grade-native |
| kind | u8 | appearance slot within the spray's archetype |
| user | ≤4 fixed-point channels | kernel scratch, declared on the archetype |

Dead rows sit on a freelist. A row keeps its id for its whole life — stable identity is a sensor precondition, and something will want to watch a particle. Capacity is the only allocation; nothing grows at runtime.

The population is **not on the transcript**. Like scans and fields it is re-derived from fed time and the mounted program. `drift dump <@em>` writes a dump for gates; that is the only way rows leave memory.

*Ruled (§7.3, §7.5):* positions are dyadic Q16.16 cells from day one — the integer part is the lattice cell, sixteen bits the sub-cell fraction. This is what makes G7 a bit-identity gate. **It is not matryoshka's BVH lattice**: the scene-wide gauge lattice steps by `extent / (2²⁰ − 1)`, deliberately not dyadic, and the slim node lattice is dyadic but per-BVH with its own exponent — so position → Morton key is not a shift; the upload quantises once per dirty chunk with integer arithmetic (recon R-b §2; ledger).

### 3.2 Spray — a tenant on the spine

*Ruled 2026-09-01:* the tenant is **`spray`** — `^spray` kind, `@<name>` instance, console `spray add/move/aim/bind/rate/dump/delete`, `spray burst <@name> <n>`. Rejected on read-aloud: `emitter` (taken — matryoshka's sound emitter), `source` (the Source enum), `spring` (an unbuilt operator), `fount`, `nozzle`.

The eleventh archetype-spine tenant. Same split as sensors: time constants and behaviour inherit, position and aim never.

`^` archetype (immutable kind):
- capacity, kernel (a `.rill`), appearance link (an archetype — sprite, light, metaball, prim — following the sound emitter's stem links)
- channels sampled, with a lattice cell size (this is the spray's authored ear; entities have no implicit instrument)
- channels cast, with amplitude-per-row and radius policy
- world queries the kernel uses, so capability check at mount can refuse

`@` instance (addressable individual):
- position, aim, bound entity (optional — a torch's sparks follow `@torch`)
- knobs: `rate`, `speed`, `spread`, `life`, `size`, and whatever the archetype declares; all lane-capable

Console verbs, prim-sized: `spray add/move/aim/bind/rate/dump/delete`, plus `spray burst <@name> <n>` as an occurrence. Three-format serialization is compelled by the spine's completeness gates (S5 precedent); a Project re-cut from a loaded plane must be byte-identical.

### 3.3 Two rill surfaces

**Spray-level.** Ordinary rill over the plane. This is the CHOPs layer and it already exists:

```rill
// bursts on a trigger, rate as a lane, palette stepping
plane.ents.@torch.$alarm | above 0.5 0.3 | kick 50ms 2s | mul 400 | write plane.drift.@sparks.rate add
plane.world.gunshot | step [red, orange, white] loop | write plane.drift.@sparks.tint
every 4s | also { spray burst @sparks 200 }
```

(`write` per write-verbs rev 3, ratified: the mode word rides the verb and the `plane.mod.…` path spelling is retired — a lane is `write <path> … add|mul`, never a second path. `above`, `kick`, `step`, `every`, `also` unchanged. In matryoshka today the interim `.mul` lane on `rate` and `speed` folds exactly this; §7.12.)

**Per-particle.** *Ruled 2026-09-01 (§7.4, §7.5):* **a kernel is a rill program whose plane is the row.** You mount a rill; a kernel is a rill mounted on a spray rather than on the world. The file is a fan-out of independent flows over the row — no def body, no section, no new grammar. The earlier `def ember { … }` spelling is withdrawn.

- row fields are `row.pos`, `row.vel`, `row.age`, `row.life`, `row.seed`, `row.size`, `row.colour`, `row.kind`, `row.u0`–`row.u3` — sigil mandatory like `plane.`, bare names a parse error; `row.vel.y` is an axis
- the spray's knobs read as `plane.drift.@self.<knob>` and broadcast to every row; any `plane.…` read in a kernel is a broadcast
- a field read is `$wind at row.pos` (P2)
- writes into row fields use the write verb with its mode word — bare replaces, `add` is the blind delta; the lane modes are refused (a row has no lanes)
- reading and writing one field is the integration step, not a cycle: the row plane has no dirty propagation (rill spec §3.16)
- **row-legality is a column on `OpDef`, not a `Routing` value** — routing says which thread, the column says whether an op can be evaluated per row; orthogonal, and the C seam stays a boolean. The column carries the user channels the op's per-row state needs and an exactness bit. **The bit is earned, not declared:** an op is exact when its result is defined by integer arithmetic only. The four arithmetic ops have it outright; a transcendental earns it by getting an integer kernel, and that kernel is then the definition for rows — the float path retires for rows. **v1's row-legal set = the exact set**: 29 core ops today (`rill/src/tests.zig`, the row audit), plus the drift words.
- row words (`spawn`, `gravity`, `perish`) are registered by spindrift with `row.only`; a plane program that names one is refused at parse by name

```rill
// embers.rill — a rill mounted on a spray
spawn
gravity plane.drift.@self.gravity
row.age | div row.life | range 1 0 | write row.size
perish
```

Integration is not a word: a velocity that did not move its position would not be a velocity. The spray integrates `pos += vel · dt` after the kernel's sweep of a row and ages it; `perish` marks and the spray reaps serially.

Word admission follows the tier-2 discipline: nothing enters on prose; every word has a customer scene in §5; ~30-word budget across the whole campaign. Vocabulary so far: `spawn`, `gravity`, `perish` (beat 1), `hear` (beat 2), `over` (beat 3 — value over normalised life, piecewise linear over an array literal, exact by lerp; the first stateless array on the row). Proposed for later beats (read-aloud in §9): `drag`, `curl`, `collide`, `stick`. `drag`/`curl` are sugar over add/mul/noise and may not survive admission.

### 3.4 Fields, both ways

*Ruled 2026-09-01 (beat 1 accepted), built beat 2.* The read is spelled `$wind at row.pos` (value) and `$wind grad at row.pos` (gradient, toward the caster); bare `$wind` is a parse error in a kernel too; the parser desugars to the host's word `hear`. Coupling via `#tag` applies at the spray's authored ear: a coupled deposit reaches a spray only while it carries the tag. The exact-kernel bill was zero: the radial falloff is evaluated at rasterisation on the host, once per lattice point, and the row only trilinear-samples integers — no `sqrt`, no squares, no route-around.

**Sampling.** Fields are receiver-summed over live casters. That is right for a dozen ears and wrong for 10⁵ rows. When an archetype declares `samples $wind cell 0.5`, spindrift rasterises the channel's deposit bag onto a lattice over the spray's bounds once per tick (sum of radial kernels; cross-tick coalesce already keeps the bag small), and rows trilinear-sample it. The lattice is re-derivable, stays out of the log, and is the same shape as the Sponge cache. Coupling via `#tag` applies at the spray's ear exactly as for entity-bound ears.

**Casting.** v1 casts one aggregate deposit per spray per tick: centre of mass, amplitude ∝ live count × per-row amplitude, radius from bounds. Cross-tick coalesce replaces it each tick. Per-row casts are a deferred fill (§6).

### 3.5 Tracer verbs

Spindrift declares `World`: `collide(from, to) → {t, normal, material}`, `ground(pos) → {distance, normal}`, later `radiance(pos, dir)`. Matryoshka implements it on `solver.zig`'s CPU twin tracer, which already carries `sightClear` with alpha cutout and per-post cadence. The mock `World` in spindrift is a floor.

These are **host words** (SOP-shaped things are host verbs). Spindrift is the customer that makes them exist; once they are registry words the sentries, actuators and Ironwood have them too. Ruling requested on where they register: proposed in Matryoshka's registry, with spindrift's kernels refusing at mount if the host lacks a word the archetype declared.

Static tree only in v1. Collision against dynamic prims (the drawbridge) is a deferred fill with a named customer.

### 3.6 Scheduler

`common/jobs.zig`, one JobSystem per process (the elephant is dead; keep it dead). Each spray partitions rows into chunks; the kernel runs per chunk; fed time only.

Budget is a knob, `drift/budget/row_steps`, read once per tick. Over budget, sprays are updated by priority computed from fed-time-only inputs — staleness first, then frustum (from `plane.camera`, which is on the plane), then dynamic-object intersection — and the rest carry over to the next tick with `throttled` on their mailbox. This is the Sponge policy with the clock removed. A wall-clock governor may write the budget knob, as the adaptive frame budget controller writes resolution; that write is on the transcript, so replay stays honest. The sim never reads the clock.

### 3.7 The Matryoshka seam

- `LEAF_PARTICLES` references an SSBO population; the spray's bounds ride as a dynamic-tree object (Path B, the drawbridge precedent), so the static tree stays untouched
- appearance is an archetype link: sprite (billboard leaf, new), light, metaball (existing leaf), prim (existing AABB leaf). A row's `kind` selects within the archetype's appearance set
- upload is per dirty chunk, SoA → GPU, after the sim tick and before traversal
- billboards need a coverage function under facet 1 (per-leaf-type coverage); a sprite's is its disc/quad against the cone footprint — cheap and analytic
- particle lights are capped per spray in v1 (4, ruled). Many near-tied contributors is exactly the rank-swap condition (facet 4) — Mercury's light ring, but moving. Recorded, not solved
- G-buffer X-ray gains a `drift` surface row: one line in `resolveSurface`

### 3.8 Spark

A Spray applet, one file: `intent:`/`about:`/`label:`/`icon:`, sliders bound in mirror mode to the instance knobs, a `drift burst` button as `cmd=`, live `count` and `throttled` as read paths. Over-life curves want a `:::curve` span — the thing the stranger model kept assuming existed. Spindrift is its first paying customer; it lands as a reusable span like the colour wheel did. Perf applet gets a row-steps sparkline.

### 3.9 Asset packs

`^spray` + its kernel `.rill` + appearance links ride in a pack as an archetype branch (the placeholder unit). Nothing new for the pack format.

---

## 4. Phases

**P0 — Population and determinism.** Repo, population format, freelist, dump, mock `World`, `drift-run` mounting a spray with a Zig stand-in `spawn`/`gravity`/`perish` kernel. G0. No engine, no picture. **Done, beat 0** (`docs/cc-report-beat0.md`).

**P1 — Spray tenant and the row plane.** The eleventh tenant with three-format serialization; `spray` console verbs; the row-legal column and the row runtime in rill; the stand-in deleted and the three words as rill row words; G1, G2. First spray-level rill drives a spray on the plane. **Beat 1** (`docs/cc-report-beat1.md`).

**P2 — Fields.** Lattice materialisation for sampled channels; aggregate cast; `$wind at row.pos`; G3, G4. Customer: smoke that leans in the wind and makes a room dank. **Beat 2** (`docs/cc-report-beat2.md`).

**P3 — Leaf, appearance, applet.** `LEAF_PARTICLES`, billboard leaf with its coverage function, appearance links, dirty-chunk upload, Spray applet, `:::curve`; G5. First captures on the customer scenes. *Ruled order (beat 2 accepted):* rule 7 first — the leaf and the spray bounds as a dynamic-tree object, every frozen ref at AE=0 with no spray mounted, before anything is drawn; sprite appearance only (a camera-facing disc of `row.size`, `row.colour`, alpha as a cutout, not blended; light and metaball only if sprite lands with room); upload per dirty chunk after the sim tick, quantising once to the gauge lattice with integer arithmetic; G5 with the two-hop; the fifth word `over`; the Spray applet with a reusable `:::curve` span and a row-steps sparkline on Perf. **Beat 3** (`docs/cc-report-beat3.md`).

**P4 — Tracer verbs and budget.** `collide`/`ground` on the CPU twin tracer, `stick`, the row-steps budget and priority scheduler, the governor writing the knob; G6. *Ruled order (beat 3 accepted):* the World caller — `collide` (the row's segment against the static tree through the CPU twin tracer: hit t, normal, material) and `ground` (nearest surface below), host words in matryoshka's registry (§7.7), the mock floor kept, a kernel naming a word the host lacks refused at mount, both exact at the row (the host's float query once, fixed-point results across the boundary); `stick` (pos ← hit, vel ← 0, `row.stuck` set; a stuck row still ages and reads its curves), read aloud before naming; the budget — `drift/budget/row_steps` read once per tick, over budget sprays updated by priority from fed-time-only inputs (staleness, then frustum from `plane.camera`, then dynamic-object intersection), the rest carried over with `drift/@name/throttled` as a MAILBOX occurrence (the spawn-refusal count keeps its meter under another word), a wall-clock governor writing the knob on the transcript; G6 — a burst over budget produces `throttled`, the tick replays byte-identically, and a coarsened-and-throttled run replays too (mutation: any wall-clock read in the sim path; repro-input differs); captures — spirit3 sparks landing on the trim, test_scene embers landing on the plate. **Then P3b as a half-beat:** the light appearance with the cap of 4, dust2's motes as its capture. Still fenced: trails, sub-sprays, per-row casts, blending, dynamic-prim collision (Ironwood's rain is the trigger).

Each beat ends with a report in the house shape: what was built, what the mutation caught, what was recorded-not-built with its trigger.

---

## 5. Customer scenes

- **test_scene** — embers off the heated plate (the painted-ember tool already makes lights follow a brush; this is the same idea as a population), and a smoke column for G3/G4
- **dust2** — dust motes in the sun shafts; the volumetric NEE bloom already exists, so lit motes are a real test of the light/particle seam
- **Ironwood** — torch sparks bound to `@torch`; rain that hits the drawbridge is the customer for dynamic-prim collision (deferred, §6)
- **tiltyard** — a fountain against the quintain, purely to price the editor gaps

---

## 6. Scope fence and deferred fills

v1 does not do:

- GPU simulation (G7 is the horizon gate; the row routing and integer positions are the design debt paid now)
- ribbons and trails — a trail is a loop-loft spine, and that convergence is worth doing properly later
- sub-sprays and spawn-on-event (a particle that emits on death)
- inter-particle forces (flocking, repulsion) — needs neighbour queries, which is the Morton broad phase deliberately not built for the keep
- per-row casts
- collision against dynamic prims
- mesh particles beyond prims
- sorting / order-independent transparency beyond what the leaf gives

Deferred fills, each with a trigger:

| fill | trigger |
|---|---|
| Morton broad phase for rows | first kernel that needs a neighbour |
| GPU row evaluator (G7) | first customer scene where a kernel misses budget on the 9950X3D |
| trails via loop-loft spines | first spray that wants a ribbon |
| per-row casts | first scene where an aggregate deposit is visibly wrong |
| dynamic-prim collision | Ironwood rain on the drawbridge |
| particle lights beyond the cap | rank-swap seam observed in a capture |
| `:::curve` outside the Spray applet | second applet that wants one |
| `window` trace history for row-steps | Perf applet asks for it |

---

## 7. Rulings — all ratified 2026-09-01

1. Name and prefix — Spindrift, `drift/`. **Ratified.**
2. Population rows off-plane with a plane-addressable summary (count, bounds, digest). **Ratified:** off-plane; the plane sees what a sensor would publish.
3. Integer positions on the scene lattice from day one. **Ratified**, with the fact recorded verbatim from beat 0's report: *bit-identity across evaluators holds for `+ − × ÷` and fails for the transcendental words unless they get integer kernels (recon R-a §5). Not a P0 or P1 question; a bit the column should carry when it lands.* — Accepted as a fact; see ruling 4b.
4. Kernel = rill text, versus a separate kernel DSL. **Ratified: rill text.** With three amendments from beat 0's forks:
   - 4a **row-legality is a COLUMN, not a Routing value.** Routing says which thread; the column says whether an op can be evaluated per row. Orthogonal. The C seam stays a boolean.
   - 4b **the column carries channels used plus an exactness bit. The bit is EARNED, not declared:** an op is exact when its result is defined by integer arithmetic only. The four arithmetic ops have it outright. A transcendental earns it by getting an integer kernel, and that kernel then is the definition for rows — the float path retires for rows, per "faithful to the implementation's arithmetic". **v1 row-legal set = the exact set.**
   - 4c **a kernel is a rill program whose plane is the row.** You mount a rill; a kernel is a rill mounted on a spray rather than on the world. The file is a fan-out of independent flows over the row — no def body, no section, no new grammar. `def ember { … }` is withdrawn. Row fields are `row.pos`, `row.vel`, `row.age` …, sigil mandatory like `plane.`, bare names a parse error. Spray-level knobs read as `plane.drift.@self.<knob>` and broadcast to every row. A field read is `$wind at row.pos`. Writes into row fields use the write verb with its mode word.
   - 4d **the tenant is `spray`:** `^spray` kind, `@<name>` instance, console `spray add/move/aim/bind/rate/dump/delete`, `spray burst <@name> <n>`. Rejected on read-aloud: emitter (taken), source (Source enum), spring (unbuilt operator), fount, nozzle.
5. Standpoint spelling for a row read: `$wind at row.pos`. **Ratified** (the `row.` sigil added by 4c); the standpoint ruling in `rill-casts.md` §9 holds — the spray's declared ear is the instrument, `at row.pos` names where within it.
6. Budget unit: row-steps per tick as a knob, governor writes it. **Ratified**; the sim never reads the clock. Row-steps are counted by the sweep, never presumed (beat 0 practice).
7. Tracer verbs register in the host; spindrift refuses at mount when a declared word is missing. **Ratified.**
8. Appearance as an archetype link (sound-emitter precedent). **Ratified.**
9. Spray as the eleventh spine tenant with full three-format serialization. **Ratified.**
10. Particle-light cap per spray in v1 — 4. **Ratified.**
12. *(beat 1 accepted)* **Write-verbs rev 3 is ratified, §5 all five**, and the spray is `hold`'s second customer beside `camera/pose/*`: the rig authors the base; a rill modulates with `write … add|mul|stops` as a lane that folds in owner order and retracts on unmount; a rill seizes with `write … hold`; a program's bare `write` on a rig knob is refused at mount naming `hold`; console/applet bare `write` sets the authored value. Each spray knob declares its acceptance mask on `^spray` — `rate` add|mul, `speed` add|mul, `spread` add, `life` mul — refused at mount for a mode not accepted. **Interim** until the verb lands: `rate` and `speed` take the existing modulation lane with `.mul` semantics so the CHOPs example works today; recorded with the write-verbs landing as its trigger. Write-verbs is a campaign with a customer waiting; whether it is briefed after P2 or folds the spray knobs into its first beat is said in the P2 report.
13. *(beat 1 accepted)* **`spray dump` hands its bytes to a host channel**; the verb does not touch the filesystem. The host decides where bytes land — a file when headless, the bus over the wire.
14. *(beat 1 accepted)* **Broadcast floors stay as they are.** A knob written as `9.8` reaches every row as 9.7999, the same floor a literal takes at mount. Trigger as recorded: a customer scene that wants round-to-nearest at the boundary.
15. *(beat 2 accepted)* **The lattice cap: keep coarsening, never refuse the tick.** `drift/@name/coarsened` is a change-only plane value beside `count`, `bounds`, `digest` — zero when the declared cell held — so a sentry can watch it, not only the Spray applet. Coarsening is a function of the bounds and the declared cell only, fed inputs, so replay holds; gated: a coarsened run replays byte-identical.
16. *(beat 2 accepted, ratified as reported)* the engine's ownership rule wins over G4's "after the decay" sentence; write-verbs is briefed after P2 as its own campaign with the spray knobs as beat 1's customer; the engine-side audience filter is deleted so the rule lives once; `@` after a dot is a path segment; the CHOPs example is respelled `write plane.drift.@sparks.rate add`.
17. *(beat 3 accepted)* **`refs.py` builds:** the pixel gate is build-agnostic and runs under the Debug rule like everything else; the timing bands belong to ReleaseFast only. `refs.py` stamps the build mode into the manifest beside the hashes, records timings under any build, and compares against the band only when the stamp says ReleaseFast. A Debug run is never read as a band failure or a band pass.
18. *(beat 3 accepted)* **Half-pixel coverage stays as sprite's number.** A sub-half-pixel mote is a miss, stated as the trade. dust2's motes are the customer; when they arrive the threshold becomes per-appearance if that fixes them, and if it does not, the honest fix is fractional coverage, which is blending and stays fenced until then.
19. *(beat 3 accepted, ratified as reported)* the array broadcast reversal with its customer (converted once per change, owned by the spray, never per row); `over` over `across`/`curve`; the sweep on the one JobSystem, the bake's transient JobSystem recorded with its trigger; the two dirty-chunk decorations deleted; `c609f0f`'s correction.
11. *(beat 0 fork 5, ruled)* **Dyadic Q16.16 cells.** Matryoshka's per-scene BVH quantisation lattice is **not** dyadic in the same units (gauge: `extent / (2²⁰ − 1)`; slim nodes: dyadic per BVH with its own exponent), so position → Morton key is not a shift: the upload quantises once per dirty chunk, deterministically.

## 8. Ledger practices this campaign is likely to add

- a population dump is a gate artefact, not a transcript entry
- a budget is fed, a governor is clocked, and only the governor's write is on the transcript
- row-legality is declared, not inferred — a registry column with the predicate derived
- the mock `World` is a negative control: a spray that behaves identically with the floor removed has no collision
- *(beat 0, ratified)* a race gate runs at the scale where the race can exist
- *(beat 0, ratified)* row-steps are counted, not presumed
- *(beat 2, ratified)* a gate over a field must vary on every axis it claims
- *(beat 2, ratified)* a survived mutation names a decoration
- *(beat 3, ratified)* a prose claim about a refusal is a gate to run

---

## 9. Names to read aloud

Library: **Spindrift** (chosen). Rejected on the way: Motes (too small for the whole system), Flurry (weather-shaped, wrong for sparks), Murmuration (flocking is out of scope in v1), Spume (sounds unwell).

Tenant: **spray** (ruled). Rejected on read-aloud: emitter (taken by the sound emitter), source (the Source enum), spring (an unbuilt operator), fount, nozzle.

Words: `spawn`, `gravity`, `perish` (admitted, beat 1); `hear` (beat 2); `over` (beat 3 — rejected on read-aloud: `across`, a span not a fraction; `curve`, the shape not the operation); `drag`, `curl`, `collide`, `stick` (proposed). Rejected: `die`/`kill` for `perish` — `perish` reads as the row's own verb where `kill` reads as someone else's. Held: `bend` for the wind coupling if `$wind at row.pos | add row.vel` reads badly aloud.
