# Spindrift — campaign plan

**Thesis.** A particle system that is rill-shaped from the first line: emitters are rill programs, per-particle behaviour is rill operators evaluated over populations, coupling to the world is `$` fields in both directions and tracer verbs. CPU first; the GPU arrives later as a second evaluator of the same text, not a port.

**Name.** Spindrift — spray lifted off water and carried on the wind. Born off a rill, driven by fields. Plane prefix `drift/`. Read aloud before committing; alternatives recorded in §9.

Draft for ratification. Rulings in §7 are his; everything else is proposed-and-seconded and proceeds unless overruled. Gates come first because that is what gets built.

---

## 1. Shape of the repo

`Foundation42/spindrift` — a standalone Zig library beside rill, spark and common. Same house style, same ledger rules.

Owns:
- the population format (struct-of-arrays, fixed capacity per emitter)
- the emitter archetype/instance tenant on the `^`/`@` spine
- the sim scheduler (chunked over `common/jobs.zig`, fed time only)
- the per-particle kernel operators, registered into rill's registry like every other word
- the `World` query interface the host implements (tracer verbs are host words; spindrift is their first client)
- a mock `World` (flat floor at y=0) so `rill-run` can mount an emitter with no engine

Does not own:
- rendering — that is Matryoshka's `LEAF_PARTICLES` and the appearance archetypes
- geometry queries — `solver.zig` implements the `World` interface for Matryoshka
- the evaluator — rill parses and evaluates; spindrift adds a row routing class (§3.3)

Dependencies: common (jobs), rill (plane borrow, registry, parser), struple. No dependency on Matryoshka. Matryoshka depends on spindrift the way it depends on rill and spark.

---

## 2. Gates (pre-registered)

Each gate names the mutation that must bite. A gate that passes under its mutation is a finding about the gate, not a pass.

**G0 — Determinism.** Same `.rill` + seed + fed-time script → byte-identical population dump after N ticks, two runs. Mutation: perturb the seed; dumps differ. Precedent: `repro-input`.

**G1 — The population is plane-native.** An emitter publishes `drift/<@em>/count` (and bounds, and a change-only digest) on the plane; a second rill reads `count`, pipes it through `above`, and writes a knob. The knob changes when the population crosses the threshold. Mutation: unmount the emitter; the knob stays put and `count` says zero (absence is said). Precedent: the live sensor loop.

**G2 — Kernels are operators.** Every spindrift word walks the standing wire gate, the argument-spelling gate (adjacent wordless optionals refused), the registry-walk typing gate and the manual/registry identity gate. Structural — the gate is the existing gates admitting a new routing class. Mutation: register a word with two adjacent wordless optionals; the registry refuses it at build.

**G3 — Fields in.** An emitter that samples `$wind` bends; unmount the caster and the trail straightens within the deposit's decay. Mutation: disable sampling in the kernel; the trail is straight from tick 0 and the gate fails.

**G4 — Fields out.** A smoke emitter casts `$dankness`; an ear downstream reads above zero; the emitter unmounts and the ear reads zero after the decay (casts are owned by their caster — ownership is the ceiling). Mutation: remove the cast line; the ear never rises.

**G5 — The leaf.** Matryoshka renders the population through `LEAF_PARTICLES`. Ordinary path first (rule 7): with no emitter mounted, every frozen ref holds at AE=0. Then: a capture with one emitter mounted differs from the frozen ref, and a capture with the same emitter unmounted is AE=0 again. Mutation: leaf returns no hit; the mounted capture equals the frozen ref and the gate fails.

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
| age, life | fed ticks | |
| seed | u32 | per-row decorrelator for `noise` |
| size | fixed-point | |
| colour | Oklab, fixed-point | grade-native |
| kind | u8 | appearance slot within the emitter's archetype |
| user | ≤4 fixed-point channels | kernel scratch, declared on the archetype |

Dead rows sit on a freelist. A row keeps its id for its whole life — stable identity is a sensor precondition, and something will want to watch a particle. Capacity is the only allocation; nothing grows at runtime.

The population is **not on the transcript**. Like scans and fields it is re-derived from fed time and the mounted program. `drift dump <@em>` writes a dump for gates; that is the only way rows leave memory.

Proposed and worth a ruling: positions integer from day one. This is what makes G7 a bit-identity gate and it matches the BVH's lattice, so a particle position is a Morton key with no conversion.

### 3.2 Emitter — a tenant on the spine

The eleventh archetype-spine tenant. Same split as sensors: time constants and behaviour inherit, position and aim never.

`^` archetype (immutable kind):
- capacity, kernel (a `.rill`), appearance link (an archetype — sprite, light, metaball, prim — following the sound emitter's stem links)
- channels sampled, with a lattice cell size (this is the emitter's authored ear; entities have no implicit instrument)
- channels cast, with amplitude-per-row and radius policy
- world queries the kernel uses, so capability check at mount can refuse

`@` instance (addressable individual):
- position, aim, bound entity (optional — a torch's sparks follow `@torch`)
- knobs: `rate`, `speed`, `spread`, `life`, `size`, and whatever the archetype declares; all lane-capable

Console verbs, prim-sized: `drift add/move/aim/bind/rate/dump/delete`, plus `drift burst <@em> <n>` as an occurrence. Three-format serialization is compelled by the spine's completeness gates (S5 precedent); a Project re-cut from a loaded plane must be byte-identical.

### 3.3 Two rill surfaces

**Emitter-level.** Ordinary rill over the plane. This is the CHOPs layer and it already exists:

```rill
// bursts on a trigger, rate as a lane, palette stepping
plane.ents.@torch.$alarm | above 0.5 0.3 | kick 50ms 2s | mul 400 | write plane.mod.drift.@sparks.rate add
plane.world.gunshot | step [red, orange, white] loop | write plane.drift.@sparks.tint
every 4s | also { drift burst @sparks 200 }
```

(`write` per write-verbs rev 3; `set` if that lands otherwise. `above`, `kick`, `step`, `every`, `also` unchanged.)

**Per-particle.** The kernel is rill text: a `def` whose body rill evaluates per row. This needs one rill change and it is the load-bearing decision of the campaign:

- a fourth routing class, `row` — an operator with `.row` routing is evaluated once per live row of a population, with row fields addressable by bare name inside the kernel body
- an operator is row-legal if it is elementwise and any state it carries fits in the row's user channels. `mul`, `add`, `clamp`, `lerp`, `noise`, `ease`, `kick`, `adsr`, `range` are row-legal today by that test; `kick`/`adsr` per row gives per-particle envelopes for free (a flash on spawn, a fade at death). Legality is a registry column, not a list in prose (registry carries the answer, predicate derived)
- "an elementwise operator carries the kind it is piped" already holds; a row is just another kind

```rill
def ember {
  gravity -9.8
  drag 0.4
  curl 0.8 seed
  $wind at pos | mul 2 | add vel
  age | over life [1.0, 0.7, 0.0] | write size
  age | over life [white, orange, dark] | write colour
  collide | stick
}
```

Word admission follows the tier-2 discipline: nothing enters on prose; every word has a customer scene in §5; ~30-word budget across the whole campaign. Initial vocabulary proposed (names for read-aloud, §9): `spawn`, `gravity`, `drag`, `curl`, `over` (value over life), `collide`, `stick`, `perish`. `gravity`/`drag`/`curl` are sugar over add/mul/noise and may not survive admission; `over`, `collide`, `stick`, `perish` are new semantics.

Standpoint spelling for a row read of a field — "a read names where it samples, neither has an implicit here" — proposed as `$wind at pos`, where `pos` is the row's own field. Bare `$wind` stays a parse error inside a kernel too. Ruling requested.

### 3.4 Fields, both ways

**Sampling.** Fields are receiver-summed over live casters. That is right for a dozen ears and wrong for 10⁵ rows. When an archetype declares `samples $wind cell 0.5`, spindrift rasterises the channel's deposit bag onto a lattice over the emitter's bounds once per tick (sum of radial kernels; cross-tick coalesce already keeps the bag small), and rows trilinear-sample it. The lattice is re-derivable, stays out of the log, and is the same shape as the Sponge cache. Coupling via `#tag` applies at the emitter's ear exactly as for entity-bound ears.

**Casting.** v1 casts one aggregate deposit per emitter per tick: centre of mass, amplitude ∝ live count × per-row amplitude, radius from bounds. Cross-tick coalesce replaces it each tick. Per-row casts are a deferred fill (§6).

### 3.5 Tracer verbs

Spindrift declares `World`: `collide(from, to) → {t, normal, material}`, `ground(pos) → {distance, normal}`, later `radiance(pos, dir)`. Matryoshka implements it on `solver.zig`'s CPU twin tracer, which already carries `sightClear` with alpha cutout and per-post cadence. The mock `World` in spindrift is a floor.

These are **host words** (SOP-shaped things are host verbs). Spindrift is the customer that makes them exist; once they are registry words the sentries, actuators and Ironwood have them too. Ruling requested on where they register: proposed in Matryoshka's registry, with spindrift's kernels refusing at mount if the host lacks a word the archetype declared.

Static tree only in v1. Collision against dynamic prims (the drawbridge) is a deferred fill with a named customer.

### 3.6 Scheduler

`common/jobs.zig`, one JobSystem per process (the elephant is dead; keep it dead). Each emitter partitions rows into chunks; the kernel runs per chunk; fed time only.

Budget is a knob, `drift/budget/row_steps`, read once per tick. Over budget, emitters are updated by priority computed from fed-time-only inputs — staleness first, then frustum (from `plane.camera`, which is on the plane), then dynamic-object intersection — and the rest carry over to the next tick with `throttled` on their mailbox. This is the Sponge policy with the clock removed. A wall-clock governor may write the budget knob, as the adaptive frame budget controller writes resolution; that write is on the transcript, so replay stays honest. The sim never reads the clock.

### 3.7 The Matryoshka seam

- `LEAF_PARTICLES` references an SSBO population; the emitter's bounds ride as a dynamic-tree object (Path B, the drawbridge precedent), so the static tree stays untouched
- appearance is an archetype link: sprite (billboard leaf, new), light, metaball (existing leaf), prim (existing AABB leaf). A row's `kind` selects within the archetype's appearance set
- upload is per dirty chunk, SoA → GPU, after the sim tick and before traversal
- billboards need a coverage function under facet 1 (per-leaf-type coverage); a sprite's is its disc/quad against the cone footprint — cheap and analytic
- particle lights are capped per emitter in v1 (proposed 4). Many near-tied contributors is exactly the rank-swap condition (facet 4) — Mercury's light ring, but moving. Recorded, not solved
- G-buffer X-ray gains a `drift` surface row: one line in `resolveSurface`

### 3.8 Spark

An Emitter applet, one file: `intent:`/`about:`/`label:`/`icon:`, sliders bound in mirror mode to the instance knobs, a `drift burst` button as `cmd=`, live `count` and `throttled` as read paths. Over-life curves want a `:::curve` span — the thing the stranger model kept assuming existed. Spindrift is its first paying customer; it lands as a reusable span like the colour wheel did. Perf applet gets a row-steps sparkline.

### 3.9 Asset packs

`^emitter` + its kernel `.rill` + appearance links ride in a pack as an archetype branch (the placeholder unit). Nothing new for the pack format.

---

## 4. Phases

**P0 — Population and determinism.** Repo, population format, freelist, dump, mock `World`, `rill-run` mounting an emitter with a `spawn`/`gravity`/`perish` kernel. G0. No engine, no picture.

**P1 — Emitter tenant and the row routing.** The eleventh tenant with three-format serialization; `drift` console verbs; the `row` routing class in rill with the row-legal registry column; G1, G2. First emitter-level rill drives an emitter on the plane.

**P2 — Fields.** Lattice materialisation for sampled channels; aggregate cast; `$wind at pos`; G3, G4. Customer: smoke that leans in the wind and makes a room dank.

**P3 — Leaf, appearance, applet.** `LEAF_PARTICLES`, billboard leaf with its coverage function, appearance links, dirty-chunk upload, Emitter applet, `:::curve`; G5. First captures on the customer scenes.

**P4 — Tracer verbs and budget.** `collide`/`ground` on the CPU twin tracer, `stick`, the row-steps budget and priority scheduler, the governor writing the knob; G6.

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
- sub-emitters and spawn-on-event (a particle that emits on death)
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
| trails via loop-loft spines | first emitter that wants a ribbon |
| per-row casts | first scene where an aggregate deposit is visibly wrong |
| dynamic-prim collision | Ironwood rain on the drawbridge |
| particle lights beyond the cap | rank-swap seam observed in a capture |
| `:::curve` outside the Emitter applet | second applet that wants one |
| `window` trace history for row-steps | Perf applet asks for it |

---

## 7. Rulings requested

1. Name and prefix — Spindrift, `drift/`.
2. Population rows off-plane with a plane-addressable summary (count, bounds, digest), versus rows literally as arrays on the plane. Proposed: off-plane; the plane sees what a sensor would publish.
3. Integer positions on the scene lattice from day one. Proposed: yes.
4. Kernel = rill text via a `row` routing class and a row-legal registry column, versus a separate kernel DSL. Proposed: rill text. This is the whole meet-in-the-middle bet.
5. Standpoint spelling for a row read: `$wind at pos`.
6. Budget unit: row-steps per tick as a knob, governor writes it. Proposed: yes; the sim never reads the clock.
7. Tracer verbs register in the host; spindrift refuses at mount when a declared word is missing.
8. Appearance as an archetype link (sound-emitter precedent) rather than inline.
9. Emitter as the eleventh spine tenant with full three-format serialization.
10. Particle-light cap per emitter in v1 — proposed 4.

---

## 8. Ledger practices this campaign is likely to add

- a population dump is a gate artefact, not a transcript entry
- a budget is fed, a governor is clocked, and only the governor's write is on the transcript
- row-legality is declared, not inferred — a registry column with the predicate derived
- the mock `World` is a negative control: an emitter that behaves identically with the floor removed has no collision

---

## 9. Names to read aloud

Library: **Spindrift** (chosen). Rejected on the way: Motes (too small for the whole system), Flurry (weather-shaped, wrong for sparks), Murmuration (flocking is out of scope in v1), Spume (sounds unwell).

Words: `spawn`, `gravity`, `drag`, `curl`, `over`, `collide`, `stick`, `perish`. Also to consider before naming: `die`/`kill` for `perish`; `bend` for the wind coupling if `$wind at pos | add vel` reads badly aloud.
