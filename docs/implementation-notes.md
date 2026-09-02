# Implementation notes — the ledger

**Status:** P3 (the first picture) built, 2026-09-02: G5 green and
bitten; embers off the plate, sparks in the keep. G0–G5 green.

Everything here is a decision made while building
[spindrift-campaign.md](spindrift-campaign.md), recorded so the next
session doesn't re-derive it. Campaign section numbers in parentheses.
Rulings are Christian's and live in the campaign's §7; this ledger holds
what was decided *against the code* and what each gate was paid for.

## The rules this ledger runs under

Inherited from rill's ledger unchanged (`rill/docs/implementation-notes.md`,
"Gate discipline"), restated here so they are read here:

- **Prose approves plausible semantics; execution approves actual
  semantics.** A gate is an executed program. Documentation is a claim
  about the code; if nothing executes it, it will eventually contradict a
  gate you already have.
- **A mutation must bite.** A gate that passes under its named mutation is
  a finding about the gate, not a pass. A mutation that does not compile
  is not a mutation. A mutation that survives and is *right* is a finding
  about the code — delete the dead thing, with the reason at the site.
- **A gate must run where A ≠ B.** A check that is clean only because the
  corpus happens to be clean has not been run; give it a synthetic
  witness. Gate past the library's fallbacks, or the library is the thing
  under test. When a property has a scale (a race, a period), gate at the
  scale, not below it.
- **A gate that watches the operator is not watching the row.** Where a
  claim is about the customer's sentence, drive the sentence.
- **A rule enforced at the registry binds every host; the same rule as a
  test binds only its own repo.**
- **Recorded-not-built needs a trigger.** Fill, don't work around; a
  deferred fill gets a pointer, never a rule.
- **Read-aloud before naming; record rejected names.**
- **Loud, never a guess.** A refusal lands on the node that refused it.
- **Time is fed, never read.** No wall clock anywhere in the sim.
- **Docs ride the same commit.**
- *(beat 0, ratified 2026-09-01)* **A race gate runs at the scale where the
  race can exist.** A gate that watches for a race at a scale where the
  race never manifests is watching nothing.
- *(beat 0, ratified 2026-09-01)* **Row-steps are counted, not presumed.**
  The budget unit is spent where the work happens; a number nobody
  counted is a number nobody watched.
- *(beat 2, ratified 2026-09-02)* **A gate over a field must vary on every
  axis it claims.** A field constant along an axis lets a mutation that
  breaks that axis survive.
- *(beat 2, ratified 2026-09-02)* **A survived mutation names a
  decoration.** The right response to a mutation that survives and is
  right is to delete the thing it mutated, with the reason at the site.
- *(beat 3, ratified 2026-09-02)* **A prose claim about a refusal is a
  gate to run.** "X is refused" in a comment or a ledger row is a claim
  the code can be asked; ask it before writing it down (matryoshka
  `c609f0f`: the slash spelling the comment said was refused, the gate
  found accepted).
- *(beat 3, the applet's first outing)* **A panel whose subject is absent
  must say so on the panel** — and the word it says it with is read
  aloud on screen, beside its neighbours: `lit` beside `count 293` read
  as particle lights; `mounted` it is.

## P0 — population and determinism (2026-09-01, §3.1, §3.6, G0)

Built against rill `d4ebe12`, common `9a75dfb`, struple `d937815`;
recon docs `docs/recon/r-a-row-routing.md` and `r-b-population-scheduler.md`
are the evidence for the shapes below.

- **The kernel is a Zig stand-in.** `emitter.zig` implements
  `spawn`/`gravity`/`perish` as functions over the population, not as rill
  text. Recon R-a §7: the `row` routing needs a parser form that needs a
  read-aloud (fork 3), a registry column that needs a ruling (forks 1–2),
  and an evaluator that does not exist; none of that is P0's gate. The
  brief allowed exactly this. **Recorded-not-built: the `row` evaluator.
  Trigger: P1.** The stand-in is deleted by P1, and does not grow a second
  word before then.

- **Q16.16 everywhere, no float in the loop** (`fixed.zig`). §3.1 says
  positions are integer on the lattice; a pure lattice integer truncated
  per tick cannot move a third of a cell per tick, so the integer part is
  the cell and 16 bits are the sub-cell fraction (R-b §1). Products floor
  toward −∞ on both signs — one rule, stated once, so a GPU twin can match
  it. Knobs parse from decimal text with integer arithmetic. The ONE
  boundary where a float may appear is a plane knob arriving through
  `drift-run` (`knobFromPlane`), converted once and floored — the same
  bargain rill's ledger records for `feed()`: foreign bytes enter at the
  boundary, the interior is canonical.

- **dt has two encodings, and that is deliberate.** The kernel integrates
  with dt as Q16.16 seconds (50 ms is 49.99 ms — fine for motion, and what
  a GPU twin would use). The spawn accumulator works in `rate × dt_ns`
  exactly, because a *count* that G1 will threshold on must not
  under-spawn by 0.02 % forever. Found by running `drift-run` at 50 ms and
  reading 19 live where 20 were owed.

- **Life is a duration on the knob and a tick count in the row** (R-b
  fork 3): `life_ns / dt_ns` at spawn, floored at one tick. A row never
  carries a unit. A life shorter than a tick is one tick — zero would let
  `age >= life` retire a row before the kernel moved it once.

- **The tick is three phases; only the kernel is parallel** (R-b §3).
  Spawn pops the freelist serially; the kernel is `parallelFor` over
  `[0, capacity)` in chunks of 1024 (a constant until a scene moves it);
  perish walks ascending ids serially and pushes the dead. Push order is
  what the next spawn's ids are a function of, so perish cannot be inside
  the parallel phase. **Row-steps are counted by the kernel, per chunk,
  into a chunk-indexed slot, and summed after the join** — not assumed from
  the live count (see M11 below).

- **The first tick is the epoch.** dt = 0: nothing spawns, nothing moves.
  A regression on either lane is `error.TimeRegression`; equal is fine.

- **`(id, gen)` handles** (`population.zig`). Ids are reused after death,
  so a watcher that holds an id across a death would see a stranger. A
  generation counter bumped on spawn makes a stale handle refusable. Cheap
  now; this is the sensor's handle shape when one wants a particle.

- **A spawn re-zeroes its row.** Dead scratch never leaks into a new life,
  so a row's fields are a function of its own history since spawn.

- **The dump is one canonical struple map, live rows only, ascending id,
  field-major** (`dump.zig`, R-b §5). Every value is a struple int; fixed
  point rides raw. Dead rows do not ride (R-b fork 2, lean taken): a dump
  that carried them would make two identical populations differ by what
  died when. The digest is printed beside the file, never inside it.
  `zig build verify-dump` has the struple Python port read a real dump
  with no spindrift code on that side — the second witness.

- **`World` is a vtable no P0 word calls** (`world.zig`). `Floor` answers
  `ground` and `collide`; `Nowhere` answers null to everything and is the
  negative control (§8). The floor's crossing rule: from on-or-above to
  strictly below; ending on the surface is on the wall, matching rill's
  `inside`/`within`. **Recorded-not-built: a caller. Trigger: P4's
  `collide`**, whose read-aloud has not happened.

- **`drift-run` lives here, not in rill** (R-b §6): rill does not depend on
  spindrift. It mirrors `rill-run`'s flag grammar, mounts an optional
  `.rill` on the same `MockPlane`, and reads the emitter's knobs from
  `plane.drift.@<name>.<knob>` each tick, plane over command line — so a
  mounted rill drives a P0 emitter with zero new rill. `--rng` is the
  emitter seed because `--seed` is already rill-run's plane seed and one
  flag cannot mean two things.

- **Row-legality is not a registry column yet.** `tools/row_legal.zig`
  derives the mechanical half of §3.3's test from today's fields and says
  where the registry cannot answer (R-a §2). It is the seed of P1's audit,
  not a substitute for the column.

### P0 mutations — what each gate caught (11/11 bitten)

| # | mutation | bitten by |
|---|---|---|
| M1 | row seed ignores the emitter seed | G0 mutation (perturbed seed) |
| M2 | perish inside the parallel kernel | **G0 chunking** (after the rescale, below), perish, freelist |
| M3 | gravity dropped | gravity; negative control (rows no longer fall below y = 0) |
| M4 | spawn accumulator reset each tick | spawn (1, 2, 1, 2 became 1, 1, 1, 1) |
| M5 | perish on `age > life` | perish; freelist |
| M6 | dump carries dead rows | both dump gates |
| M7 | floor: ending on the surface counts as a crossing | floor collide |
| M8 | `fixed.mul` truncates toward zero | fixed products |
| M9 | freelist seeded ascending | population, dump, gravity, perish (four gates hardcode ids — as they should: ids are the contract) |
| M10 | generation not bumped on spawn | handle; perish |
| M11 | kernel does not skip dead rows | spawn's row-steps assertion (after the fix, below) |

**Two findings from the first pass, both the ledger's shapes:**

- **M2 was bitten for the wrong reason.** At 64 rows in chunks of 8 the
  chunking gate — the one whose comment claimed to force perish serial —
  passed under M2. The perish and freelist gates caught it, and they run
  single-threaded; they saw the semantic slip (died counted 0), not the
  race. *A gate that watches for a race must run where the race can
  happen.* The gate now runs 4096 rows in chunks of 64 with a thousand
  spawns and deaths a tick, and it is the gate that bites M2.

- **M11 survived outright.** With `row_steps = pop.live`, a kernel that
  walked every dead row too was invisible: dead rows never reach the dump,
  and the number nobody counted was the number nobody watched. Row-steps
  are the budget unit (§3.6, G6) and a budget that is assumed rather than
  spent is not a budget. The kernel now counts its own steps per chunk;
  the spawn gate asserts steps == live; M11 bites.

### Recorded, not built

| what | trigger |
|---|---|
| the `row` evaluator and the rill-text kernel (replaces the stand-in) | P1 |
| a caller for `World.collide`/`ground` | P4's `collide`, after its read-aloud |
| `drift/<@em>/count` on the plane, absence said on unmount | P1, G1 |
| the row-legal registry column and its both-ways audit | P1, after rulings on R-a forks 1–2 |
| chunk size as a knob | the first customer scene that moves it |
| an exact-arithmetic kernel per row-legal word (R-a §3 (b)) | the first scene that misses budget, or G7 |

### Needs a ruling (beyond §7)

From R-a: `row` as a `Routing` value or as a separate column (fork 1);
what the column carries (fork 2); the kernel's spelling (fork 3, needs a
read-aloud); the tenant's name, since `emitter` is matryoshka's sound
emitter (fork 5). From R-b: which lattice `pos` addresses (fork 1, lean
dyadic). And a fact for §7.3: bit-identity across evaluators holds for
`+ − × ÷` and fails for the transcendental words unless they get integer
kernels (R-a §5).

### Rejected names

`--seed` for the emitter seed (taken by rill-run's plane seed; `--rng`).
`Void` for the null world (reads as a type; `Nowhere` reads as a place).
`steps` alone for the budget unit (`row_steps`, so the unit is in the
name).

## P1 — the spray tenant and the row plane (2026-09-01, §3.2, §3.3, §7, G1, G2)

**The six rulings (Christian, beat 0 accepted):** row-legality is a
COLUMN on `OpDef`, not a `Routing` value; the column carries channels used
plus an exactness bit, and the bit is EARNED — v1's row-legal set is the
exact set; a kernel is a rill program whose plane is the row (`row.pos`,
sigil mandatory, no def body, no section, no new grammar — `def ember {
… }` withdrawn); the tenant is `spray`; positions are dyadic Q16.16
cells; beat 0's finding 6 (bit-identity holds for `+ − × ÷`, fails for
transcendentals without integer kernels) is a fact, recorded verbatim in
the campaign's §7.3. Every one landed in the campaign doc, marked *ruled*.

**Where things went, and why:**

- **rill owns the row plane** (`rill/src/row.zig`, two commits in rill
  naming this beat: `cbff4c9`, `ae2f3ee`). The column, the `Val`, the row
  `Plane` vtable, the `Runtime` (mount + `evalRow`), the 29 exact core
  kernels, `parseKernel`, and the cycle-check exemption for `row.` writes.
  Rill's ledger has the seam's own decisions and its seven mutants.
- **spindrift owns the population as a row plane** (`population.zig`:
  `asRowPlane`, the schema, `doomed`), **the spray** (`spray.zig`: the
  four-phase tick — broadcasts, spawn, sweep, reap — and what it says on
  the plane) and **the words** (`words.zig`: `spawn`, `gravity`,
  `perish`, each `row.only` with an exact kernel). The P0 stand-in kernel
  is deleted; `emitter.zig` is gone.
- **The tick gained a phase.** Broadcasts first: every `plane.…` the
  kernel reads is fetched once, `@self` resolved to the spray's name,
  converted once to a row value (the one float boundary), handed to the
  runtime. Then spawn (serial), the sweep (parallel: kernel, integrate,
  age), reap (serial, ascending). `perish` MARKS (`doomed`); the reap
  kills. A kill inside the sweep is the freelist race — and now it is a
  crash, not a silent wrong answer (mutation P4 below).
- **Integration is not a word.** A velocity that did not move its
  position would not be a velocity: the sweep does `pos += vel · dt` after
  the kernel's writes land, so `gravity` then integrate is semi-implicit
  Euler and the beat-0 closed form (`-k(k+1)/2`) still holds exactly.
- **`spawn` launches; the spray births.** The host creates a row (seed,
  life, position) at `rate`; `spawn` gives it a velocity on its birth tick
  and never again. A kernel without `spawn` has rows that sit where they
  were born, which is a thing you can see; a kernel without `perish` has
  immortal rows and a full population that says `throttled`.
- **Age and life are nanoseconds now, not ticks** (R-b fork 3, revised).
  Ticks made a row's age depend on the dt history it lived through, and a
  variable-dt host breaks that. The row reads them back as Q16.16
  seconds; `perish` compares nanoseconds. The dump carries ns.
- **`row.seed` is a per-row uniform in [0, 1)** — the seed's low sixteen
  bits as the fraction. `row.seed | mul 2` is a decorrelated 0..2.
- **What the spray says: `count`, `bounds`, `digest`, change-only.** The
  digest is a cheap hash over live rows (ids, pos, vel, age), not the
  dump's — building a dump every tick to hash it is a dump every tick.
  Unmount says `count = 0`; bounds and digest keep their last value (a
  bound of nothing is not a box).
- **The harness feeds the spray's writes to the rill as deltas.** The mock
  plane records writes and notifies nobody; `drift-run` and the G1 gate
  do what the engine's plane does. The tenant's bridge in matryoshka gets
  it for free from the real plane.
- **`drift-run --kernel`**, default the embedded `kernels/embers.rill`
  (which reads `gravity plane.drift.@self.gravity` — the knob is a
  broadcast, seeded from `--gravity`). The embedded text is the tested
  text (the runner's own gate parses it with `parseKernel`).
- **G2's manual is `docs/drift-words.md`**, embedded and parity-gated both
  ways like rill's: every registered word has a table row, every table
  row names a registered word.

**Four findings on the way, each a ledger shape:**

- **`fails_mount` leaked.** A row word's plane-side refusal was declared
  with `fails_mount`; `plane.x | gravity` mounted cleanly because an unfed
  `plane.x` means the node never evaluates at tick 0. Found by G2, which
  asserted the refusal. The parser is the gate now (`parseKernel`), and
  the spec says why.
- **G0 passed on a population that never moved.** The row runtime's write
  queue was sized to `write` nodes, so `gravity` and `spawn` refused
  every row as "too many writes" and two runs of nothing agreed byte for
  byte. The negative control caught it (nothing fell below the floor).
  G0's harness now refuses a run with kernel refusals, a population that
  never moved, or one that never fell. *Determinism of stillness is not
  the claim.*
- **The gravity knob was seeded as a raw fixed integer** (−655360 cells),
  out of range at the boundary, so every G0 run was gravity-free while
  green. Same catch, same fix: the harness asserts a row fell.
- **The mutation harness read a crashed runner as green.** Under P4 the
  suite panics inside the chunking gate; zig's summary after a crash still
  prints the tests that had passed, and the parser took that line. A
  crashed runner is a bite, and the harness says so now.

### P1 mutations — what each gate caught (12/12 bitten)

| # | mutation | bitten by |
|---|---|---|
| P1 | `spawn` relaunches every tick | spawn birth-tick gate |
| P2 | `gravity` replaces instead of adds | gravity; broadcast; spawn |
| P3 | `perish` on `>` | perish; freelist |
| P4 | reap inside the parallel sweep | **the chunking gate — a panic**: two workers race `kill`, and `kill` asserts. The loudest honest bite. |
| P5 | unmount does not say zero | G1 |
| P6 | `@self` not resolved | broadcast; G0 ×3; negative control (every row gravity-free) |
| P7 | count said every tick | change-only gate |
| P8 | `gravity` loses `row.only` | G2 |
| P9 | a word's row removed from the manual | G2 parity |
| P10 | broadcasts never fed | broadcast; G0 ×3; negative control |
| P11 | `spawn` ignores the row seed | spread gate (all rows one draw) |
| P12 | integration dropped | G0 ×3; gravity; spawn; negative control |

### Recorded, not built

| what | trigger |
|---|---|
| a stateful row op (`channels > 0`) — allocation and overflow refusal exist in rill, nothing exercises them past mount | the first per-row envelope (`kick` earning its integer kernel) |
| `sqrt` and the transcendentals as earned integer kernels | the first kernel that wants a distance or a curve |
| `spray bind` following an entity | Ironwood's torch (§5) |
| the World caller | P4's `collide`, after its read-aloud |
| the row-legal column's `channels` audited against a real op | same as the first row |
| `drift/<@em>/throttled` as a mailbox occurrence (it is a per-tick stat today) | G6 |

### Rejected names

`emitter` (taken by the sound emitter), `source`, `spring`, `fount`,
`nozzle` for the tenant — `spray`. `die`/`kill` for `perish`. `launch` for
`spawn` was considered for one sentence and dropped: `spawn` is the word
every particle system already says, and the read-aloud found nothing
wrong with it.

## P2 — fields, both ways (2026-09-01, §3.4, G3, G4)

**Rulings that opened the beat (Christian, beat 1 accepted):** write-verbs
rev 3 ratified with the spray as `hold`'s second customer and the interim
`.mul` lane for `rate`/`speed` (campaign §7.12); `spray dump` hands bytes
to a host channel (§7.13); broadcast floors stay (§7.14). The read is
`$wind at row.pos`, bare `$wind` a parse error in a kernel too; coupling
via `#tag` at the spray's authored ear; one aggregate cast per spray per
tick, replaced cross-tick; customer: smoke that leans in the wind and
makes a room dank. Still no picture.

- **The exact-kernel bill is zero, said plainly.** The radial falloff
  `k = (1 − (d/r)²)²` is evaluated at RASTERISATION on the host, in f32,
  once per lattice point per tick — that is the boundary, crossed once.
  The row trilinear-samples Q16.16 integers and takes central
  differences; no `sqrt`, no squared-distance spelling, nothing to earn
  or route around this beat. `sqrt` stays recorded for the first kernel
  that wants a distance to a point.
- **The field model is the engine's, transcribed** (`fields.zig`):
  contribution `A·exp(−(t − born)/τ)`, cull below ε, restate-replaces on
  a later tick and sums within one, `k = q²` with `∇k = −(4q/r²)(at −
  pos)` toward the caster, value clamped by the channel and the gradient
  from the unclamped sum, coupling by audience. A second copy on purpose:
  the mock must agree with the engine and spindrift cannot import it.
  **Recorded-not-built: one field model in a sibling both import. Trigger:
  a third client.** The spatial kernel is applied by spindrift in both
  the mock and the engine (the bridge hands the bag; the spray
  rasterises), so an ear and a row agree about the same deposit by
  construction.
- **The `Fields` host interface is three thunks**: `bag` (a channel's live
  deposits with decay applied, plus the clamp; null = undeclared), `cast`
  (replace the owner's ONE aggregate on a channel, whatever its position
  — the ruled cross-tick coalesce, which the engine's same-place rule does
  not give a moving centre of mass), `withdraw` (the owner's bag goes with
  the owner). Same fn-pointer discipline as `World` and rill's `Plane`.
- **The tick has six phases now**: broadcasts, **materialise**, spawn,
  sweep, reap, **cast**. Materialise is the field's one entry into the
  sim: the box is last tick's rows plus the spawn point padded by a cell,
  the cell doubles until the grid fits 33 points an axis (`coarsened`
  said in stats, never a bigger allocation), every point sums the kernel
  over the deposits the spray hears and floors to Q16.16. Cast is the
  field's one exit: centre of mass as an exact integer mean converted
  once, amplitude = per-row × live, radius = half the bounds' diagonal
  floored at a cell. No live rows, no cast — the last one decays alone.
- **`hear` is spindrift's word** (`words.zig`): `hear $chan [grad] at
  <pos>`, statics `channel` (cast's kind) and a `grad` flag, keyword port
  `at`. The parser desugars `$wind at row.pos` to it in a kernel (rill
  `0bc2d68`). `mountKernel` refuses a `hear` of a channel the spray does
  not sample, naming the declaration to add, and any `hear` on a spray
  with no field store. A channel the HOST never declared leaves the
  lattice dead and `hear` refuses per row by name — never a quiet zero.
- **Unmount withdraws the casts.** G4 says "the ear reads zero after the
  decay"; the engine's rule says "drop the owner and the whole bag goes,
  whatever each deposit's remaining life". The engine's rule is the
  ruling that was ratified (ownership is the ceiling), so unmount
  withdraws and the ear reads zero at once. Recorded so the two sentences
  are known to differ and which one won.
- **`drift-run` grew the field flags** (`--channel`, `--samples`,
  `--casts`, `--carried`, `--ear`) and a cast door: the mounted rill's
  `cast` lands in the mock store under one owner, as a rill's does in the
  engine by mount order. The customer scene runs headless:
  `kernels/smoke.rill` with a wind rill and an ear that rises.
- **A real lean from a nearly dead deposit is not a bug.** G3's first
  draft called rows born between the caster's unmount and the deposit's
  cull "straight"; they leaned by 168/65536 of a cell per second — the
  gradient of a deposit at 1.1 ε. The gate's window moved; the physics
  did not.

### P2 mutations — what each gate caught (12/12 bitten, one after a rewrite)

| # | mutation | bitten by |
|---|---|---|
| Q1 | `hear` answers zero (sampling disabled) | G3; the hear gate |
| Q2 | the coupling filter dropped at rasterisation | coupling |
| Q3 | the cast removed | G4 ×2 |
| Q4 | unmount does not withdraw | G4 |
| Q5 | the aggregate trails instead of replacing | mock fields; G4 |
| Q6 | amplitude per row, not × live | G4 |
| Q7 | kernel `q` instead of `q²` | mock kernel; lattice; hear |
| Q8 | an undeclared channel reads as a zero lattice | the dead-lattice gate |
| Q9 | decay never culls | mock decay; G3 (the trail never straightens) |
| Q10 | gradient sign flipped | lattice; hear; G3; G0-with-a-field |
| Q11 | trilinear reads the nearest point on y and z | **survived the first draft** — the lattice gate's field varied only along x, so the lerps it dropped were lerps of equals. Rewritten as `2x + 3y + 5z`, exact under trilinear everywhere; bites. |
| Q12 | the unsampled-channel check at mount dropped | the mount-refusal gate |

Rill's one: the `$`-desugar gated both ways and on the plane.

### Recorded, not built

| what | trigger |
|---|---|
| one field model both repos import | a third client of the field model |
| `sqrt` as an earned integer kernel | the first kernel that wants a distance |
| lattice gradient by trilinear of gradients (today: central differences at the nearest point) | a scene where the piecewise-constant slope shows |
| per-row casts | the first scene where an aggregate deposit is visibly wrong (campaign §6) |
| the write-verbs verb on spray knobs (the interim `.mul` lane is in matryoshka) | write-verbs beat 1 |

### Rejected names

`listen`/`sense` for the field read (`hear` reads as the ear's verb, and
the ear tenant already listens); `read` (too general, and `write`'s
mirror would promise a plane read it is not); `dank` as a channel name in
the docs stayed `$dankness` because the campaign said so.

## P3 — the spindrift and rill half of the first picture (2026-09-02, §3.3, §3.7)

**Rulings that opened the beat (Christian, beat 2 accepted):** the lattice
cap keeps coarsening and never refuses the tick, `drift/@name/coarsened`
is a change-only plane value, and coarsening is a function of fed inputs
so a coarsened run replays byte-identical (campaign §7.15); the beat-2
report's calls ratified as reported (§7.16); two new ledger practices
above. P3's order is ruled — rule 7 first — and the renderer, the sprite
appearance, the upload, G5, the captures and the applet are matryoshka's
and spark's; this entry is the half that lives here.

- **`over` is the fifth word** (`words.zig`): `row.age | over row.life
  [1.0, 0.7, 0.0]` — `t = age / life` clamped to [0, 1], piecewise linear
  over evenly spaced knots, numbers or Oklab vec3s, exact by lerp; a life
  of zero refuses by name. Read-aloud: `over` reads as the division it is;
  `across` reads as a span; `curve` names the shape, not the operation.
- **The first stateless array on the row** is rill's (rill `84c0c9d`):
  the parser builds `[1, 0.5, 0]` as an `array` node and `[{l: 1, a: 0,
  b: 0}, …]` as record nodes under it — a live tuple on the plane — and
  the row runtime FOLDS those at mount into one shared value every row
  reads, skipping the nodes in the sweep. A live element, an empty array,
  a nested one, a boolean inside: refused at mount by name. A broadcast
  never carries an array. Records spell x, y, z or l, a, b.
- **`coarsened` is said on the plane** beside `count`, `bounds`, `digest`:
  the largest doubling over the sampled channels' lattices, change-only,
  zero when the declared cell held. Gated with two channels — a fine one
  that doubles and a coarse one that holds — because with one channel
  "the last lattice" and "the worst" were the same lattice and a mutation
  reporting the last survived. And gated for replay: two coarsened runs,
  one byte string.
- **A broadcast may carry an array — a reversal, with its customer.** The
  first draft of the array literal said "a broadcast never carries an
  array", because a per-tick array from the plane read like a per-tick
  allocation on the row. The Spray applet's `:::curve` is the customer:
  the curve it edits must reach `over` live, so `over row.life
  plane.drift.@self.size_curve` reads a broadcast array. The conversion
  is the spray's, once when the bytes change (cached by bytes per
  subscription), owned by the spray, handed to the runtime by pointer —
  once per tick per spray at most, never per row, so the row's arrays
  stay stateless. A number where a curve should be refuses per row by
  name. rill `f90873c`.
- **Dirty chunks for the renderer** (`spray.dirtyChunks()`): a chunk is
  dirty on every tick a live row was swept in it — that is the whole
  rule. The first draft also marked at spawn and at reap; mutations
  dropping either survived, because a row born this tick is swept this
  tick and a row reaped this tick was swept this tick. Two decorations,
  deleted; the sweep's mark dropped is now the mutation, and it bites.

### P3 mutations, this half (8/8 bitten, two after rewrites)

| # | mutation | bitten by |
|---|---|---|
| S1 | `over`: the segment never advances | the over gate (second half of life) |
| S2 | `over`: t not clamped at life | the over gate (past the last knot) |
| S3 | `over`: a zero life not refused | the over refusal gate |
| S4 | `coarsened` said every tick | G1's change-only gate; the coarsened gate |
| S5 | `coarsened` reports the last lattice, not the worst | **survived with one channel** — A equalled B. Two channels, fine first; bites. |
| S6 | dirty: the sweep's mark dropped | the dirty-chunk gate (after the spawn and reap marks were found to be decorations and deleted) |
| S7 | array fold accepts a live element as zero | the over refusal gate (rill-side mutation) |
| S8 | the array broadcast is not re-converted when its bytes change | the broadcast-curve gate (the second curve never seen) |

### Recorded, not built

| what | trigger |
|---|---|
| named colours in a curve (`[white, orange, dark]`) | a palette on the plane — the applet's `:::curve` may want one first |
| `over` with knots at authored x positions (today evenly spaced) | a curve the applet cannot draw evenly |

### P3 — the other half, as reviewed here (matryoshka `6ab0287` … `2be078b`, spark `6055875`)

Not this repo's code, but this ledger is where the campaign's decisions
live, and four were made against the renderer that the campaign doc only
sketched:

- **A sub-half-pixel sprite is a miss.** Coverage under facet 1 is the
  disc against the cone footprint, analytic; at or above half a pixel is
  a hit. Right for embers and sparks, wrong-shaped for distant dust, which
  will vanish before it fades — dust2's motes are the customer that
  decides whether the threshold becomes a per-appearance number.
- **Oklab → linear sRGB once at upload, on the CPU.** The row carries
  Oklab because the grade is Oklab-native; the leaf carries what the
  shader shades. One conversion per dirty row per tick, never per ray.
  An Oklab L past 1.0 becomes emitted light above the split — an ember's
  core blows to near-white on purpose, recorded so it is not read as a
  tonemap fault.
- **Quantise once, in i128.** The upload snaps positions to the gauge
  lattice when the scene has one and to the row's own Q16.16 grid
  otherwise; the float path missed the index by a few percent at 500 m
  and is the mutation the gate is paid for.
- **The one JobSystem takes the sweep** the moment the budget showed it:
  1.90 ms inline against a 5.2 ms frame at 3933 rows, 0.85 ms on
  `common.jobs` from `main.zig`, frame hash byte-identical. The solver's
  bake still makes a transient instance — recorded, trigger: a second
  per-frame customer.
- **`refs.py` builds ReleaseFast for itself**; the renderer verified
  against Debug with `MTR_REFS_NO_BUILD=1` under the Debug rule. Needs a
  ruling on which build the refs bands belong to; the pixel gate does not
  care.

### The first outing (2026-09-02)

Christian mounted the Spray applet on a plain `matryoshka test_scene` and
the Burst button did nothing. Not a bug in the button: the panel is bound
to `embers`, the acceptance rig's spray, and without `--rig
tools/refs/spray/test_scene-embers.rig` no such spray exists — `spray
burst embers 200` was refused on the console bus, where the panel could
not show it, and `count` reading zero could not say it either, because
zero is also what an empty lit spray says. **A panel whose subject is
absent must say so on the panel.** The bridge now publishes
`drift/@<name>/lit` (1 at light, 0 at drop, absent when never lit) and
`lit` is the panel's first meter, with the two ways to light the spray in
the prose beside it (matryoshka `3fbc52c`). Recorded as the applet's
first finding, and as the reason the per-spray selector's trigger is
closer than "a second spray on one rig": a panel that could name its
spray could also offer to light it.
