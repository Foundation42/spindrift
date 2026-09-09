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
- *(beat 4 accepted)* **Byte-identical replay is dumps AND transcript.** A gate that compares only the population can miss a clock that leaked into a number the sim publishes; compare what the sim SAID, first.
- *(beat 4 accepted)* **A landing gate on one surface watches the arithmetic's luck — gate on two.** 1.65 sat 0.4 ulp above its Q16.16 floor, so a wrong hit point landed on the right bits; the box top caught it.
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

## P4 — the tracer words and the budget, the spindrift half (2026-09-02, §3.5, §3.6, G6)

**Rulings that opened the beat (Christian, beat 3 accepted):** the refs
gate is build-agnostic for pixels and ReleaseFast for timing bands, the
build stamped in the manifest (§7.17); the half-pixel coverage stays,
dust2's motes decide per-appearance (§7.18); the beat-3 calls ratified
(§7.19); one new practice above — *a prose claim about a refusal is a
gate to run*. P4's order is ruled: the World caller, `stick`, the budget,
G6, the captures. The engine's tracer, its bank scheduling, the governor
and the captures are matryoshka's; this entry is the half that lives
here.

- **`collide`, `ground`, `stick` are TRACER words** (`words.zig`,
  `registerTracer`): a second table beside `WORDS`, registered by a host
  that HAS a World. `collide` sends the row's segment — `pos` to `pos +
  vel·dt` — through `World.collide` and pipes the hit point, normal, `t`
  and material; `ground` asks for the nearest surface below and pipes
  distance and normal; `stick <at>` writes the row's position and sets
  `row.stuck`. A kernel naming any of them on a host without a World is
  refused at mount by name — the prose claim, run as a gate. Exact at
  the row: the host answers in Q16.16 once per query.
- **The hit point is the host's, not the row's.** The first draft had
  `stick` at `from + (to − from)·t`; that product floors twice and the
  first gate run landed a row one Q16.16 ulp ABOVE the floor (`expected
  0, found 1`). A landed row sits on the surface, so `World.Hit` carries
  `at` and the mock floor answers `y` exactly; the engine converts its
  float point once. Gated on a slanted crossing: `y` exact, `x` between.
- **`stuck` means held, and the sweep holds it — one rule.** The first
  draft zeroed the velocity in `stick`; the next tick's `gravity` put it
  back and the landed row sank through the floor at 2.5 cells a tick. The
  sweep now drops a stuck row's velocity every tick after the kernel's
  writes land, and the integrate then moves it nowhere. Two decorations
  fell out of that under mutation: `stick`'s own velocity write (deleted;
  a `collide | stick` kernel re-hits at t = 0 every tick anyway, and a
  kernel that does not is exactly the case the sweep's rule is for) and a
  skipped integrate for stuck rows (deleted; integrating a zero velocity
  is the same nowhere). A stuck row still ages and still reads its curves.
  Read-aloud: `land` is the picture, not the operation; `settle` and
  `rest` promise a motion that is not there; `stick` says what the bit
  says.
- **The scheduler** (`scheduler.zig`): `plan(candidates, budget, run,
  order)` — a stable insertion sort over (staleness desc, in-frustum,
  touches-dynamic, index), then the greedy fill; pure, allocation-free,
  the same order on every machine. **One rule the campaign did not state
  and this file does: the highest-priority spray always runs.** A budget
  below the smallest spray is otherwise a dead sim that says `throttled`
  forever; the budget bounds the total, it does not veto the first.
- **A spray not run is carried over** (`Spray.carryOver`): fed time does
  not advance for it, `staleness` grows, and `drift/@<name>/throttled`
  fires as a MAILBOX occurrence carrying the staleness. A run resets
  staleness to zero — that is what the word counts. The spawn-refusal
  count is now `Stats.refused` and `drift/@<name>/refused` on the plane,
  so the two facts have two words (ruled); matryoshka's bridge takes the
  rename in its own commit under write-verbs beat 1.
- **G6 lives here as a harness** (`budgetRun`): two sprays, one knob read
  from the mock plane once per tick, `plan` over their live rows and
  staleness; a burst over the budget throttles both in turn, two runs
  give one byte string of dumps AND one hash of every plane write, and a
  coarsened-and-throttled run replays too. Frustum and dynamic inputs
  are the engine's — the harness feeds staleness only.

### P4 mutations, this half (12: 10 bitten, 2 deleted as decorations, 2 gates rewritten)

| # | mutation | bitten by |
|---|---|---|
| S1 | `stick` leaves the velocity | **survived** — the sweep's rule holds the row. A decoration; the line is deleted. |
| S2 | `stick` never sets `stuck` | the landing gate; the flipped negative control |
| S3 | `collide` tests a zero-length segment (ignores velocity) | the landing gate; the flipped control (floor and no-world agree again) |
| S4 | `collide` answers the pre-hit position, not the hit point | the landing gate (`y = 1`, not 0); the flipped control |
| S5 | the sweep does not drop a stuck row's velocity | the flipped control (the row sinks) — and after S1's deletion, the landing gate too |
| S6 | the sweep integrates stuck rows too | **survived** — a zero velocity integrates nowhere. A decoration; the skip is deleted. |
| S7 | `carryOver` does not grow staleness | both G6 gates (`a` starves `b`; `throttled_a` stays 0) |
| S8 | `carryOver` says nothing on the plane (path misspelt) | both G6 gates; the staleness gate |
| S9 | a wall-clock read in the sim path (staleness += clock mod 7) | **survived the dump-only replay gate** — the order of ticks never changed, only what the sim SAID. The gate now hashes every plane write (path, bytes, kind) across the two runs; bites. |
| S10 | `plan`: the first does not always run | the scheduler's own gate; both G6 gates (nothing runs under a budget of 40) |
| S11 | `plan`: staleness ignored | the scheduler's gate; both G6 gates |
| S12 | `tick` does not reset staleness | **survived G6** — a spray that only grows staler still runs in the same order. New gate: the occurrence says 1, 2, then 1 after a run; bites. |

**What S9 says, for the rule above:** *byte-identical replay* is the
dumps AND the transcript. A gate that compares only the population can
miss a clock that leaked into a number the sim publishes. The G6 harness
compares both now, and the engine's G6 should too.

### Recorded, not built

| what | trigger |
|---|---|
| the frustum and dynamic-object priority inputs (the harness feeds staleness only) | the engine's bank — matryoshka's half of this beat |
| releasing a stuck row (`write row.stuck 0` and it moves again) | the first kernel that wants a landed row to lift — rain on a moving thing |
| a bounce (`collide` pipes the normal; no word reflects) | the first kernel that wants a spark to skip off the trim |
| material by name (today a number the host chose, capped at 32767) | a kernel that reads `material` and wants a word |
| segment queries against dynamic prims | fenced (Ironwood's rain) |

### Rejected names

`land`, `settle`, `rest` for `stick` (above). `rejected` and `denied` for
the spawn-refusal count — a spray at capacity refuses a spawn, it does
not judge it; `refused` is the verb the prose already used. `skipped`
for the carry-over — a skipped tick sounds lost; a carried-over spray is
owed a tick, and `throttled` (the campaign's word) keeps that debt.

### P4 — the other half, as reviewed here (matryoshka `307bbbb` … `8712c7b`; write-verbs `4abd61e`, `352943d`)

Built by delegated agents to the ruled order and reviewed against the
commits, the gate names and the frames. `src/spray_world.zig` is the
World on the CPU twin tracer's static tree (mesh leaves in their own
frame, boxes for the solid kinds, portals skipped, the dynamic tree not
walked), bound each frame beside the sight solver; the point is the
host's, snapped to the face's plane; on-a-face is judged at the row's
resolution; a row found inside a solid is placed on the face it came
through. The bank reads `drift/budget/row_steps` once per tick and plans
with `scheduler.plan` from the plane's camera and last frame's dynamic
pool; `throttled` is spindrift's mailbox occurrence, declared by the
bridge, never written by it; the governor (`sweep_ms`, off by default)
writes the knob from a `Source.governor` that replay re-applies and never
regenerates. Engine G6 compares the transcript first. The refs manifest
carries `# build: Debug` (ruling 17). Two findings the engine sent back
here: **`collide` tests the kernel-start move and the integrate makes the
kernel-end move** (rill's snapshot rule; a tunnel of a·dt² per tick;
needs a ruling — the report's first), and the world-point mutation
surviving on the plate by arithmetic luck (1.65 is 0.4 ulp above its
floor) — the gate lands on a box too. Write-verbs beat 1 landed in the
same window: the mask on the kind, a program's bare write refused at
mount naming `hold`, the interim `.mul` fold deleted, the bank reading
the plane's one fold.

### P3b — the half-beat, as reviewed here (matryoshka `6f22cc4`, `c416d50`)

The `light` appearance: a light spray's rows are point lights and draw
nothing else; the four brightest by Oklab L (ties by row id) among rows
giving off light, from row fields and the freelist's ids alone; the unit
mapping said once with the cap as the unit (four lights = one painted
ember); the lights on the painted embers' path from the bank. Six
mutations bitten. dust2's motes: the coverage finding in pixels (3 093
under the half-pixel rule, 13 873 under a quarter; the near half of the
column stays, the far half goes by distance), nothing built — the
threshold's home is a spelling for Christian. Two findings for here: a
long-lived spray fills its chunk leaves and a linear row scan costs 14
ms of traversal (sub-chunk leaves, trigger met); and the rank-swap seam
plus the two-ray shadow budget put the fourth coal's light through the
plate (ruling asked). Also: `row.size` is the disc's RADIUS — two kernel
comments said "across"; respelled in matryoshka after review.

## P5 — the keep, opened (2026-09-02, rulings 20–27)

**Rulings that closed beat 4 (Christian):** segment versus move is (A),
kept and said, with (B) and (C′) recorded and (C) refused (§7.20); every
population-moving verb rides the transcript (§7.21); the engine's three
defaults (§7.22); material as an opaque host handle (§7.23); the resting
offset, re-ruled on Christian's screenshots of half-sunk discs (§7.24);
stochastic coverage as P3c, the threshold knob not built (§7.25); the
light gain (§7.26); ratified-as-reported and two practices (§7.27).

- **The contact on the row, the offset in the appearance — `stick <at>
  <normal>`** (`words.zig`, `population.zig`; ruling 24 as first ruled,
  then 28): the first build offset `pos` by the radius in `stick`, and a
  stuck row kept its landing height as it shrank — its segment is zero
  length once the sweep drops its velocity, so `collide` never fires
  again, and a re-rest in the sweep would have needed the contact stored
  anyway. Re-ruled the same hour: `pos` is the contact, `row.normal` is
  the contact normal (a vec3 field, zero for every unstuck row, zeroed on
  spawn like the rest), and the appearance draws every row at `pos +
  normal · size` — one rule, no stuck branch, a shrinking ember tangent by
  construction; `hear` samples at the contact. Dump format 3 carries
  `nrm_x/y/z`. Gates: the landing gate (on the floor, normal up, zero
  before landing, still on the floor after shrinking), the flipped
  control, the dump, and a reused slot's normal zero.
- **The normal reaches `stick` by rill's new rule** (rill, this beat: a
  pipe carries a producer's other outputs to the consumer's like-named
  open ports; explicit wins; nothing by position). Before it, `collide`'s
  normal, `t` and material rode ports no kernel could reach — beat 4's
  manual said "ride the other ports" and nothing could read them. A prose
  claim about a port is a gate to run, too.
- **Rulings 20 and 23 in the manual**: the kernel-start move with its two
  numbers; material as an opaque handle.

### P5 mutations so far (5/5 bitten)

| # | mutation | bitten by |
|---|---|---|
| R1 | rill: carried outputs bound by position | rill's carry gate (91 for 84) |
| R2 | rill: the carry dropped | rill's carry gate (the refusal) |
| S1 | `stick` without the offset (first build) | the landing gate (y = 0); the flipped control — the build then moved (28) |
| S2 | the offset along the flipped normal (first build) | the landing gate (y = −radius); the flipped control |
| S3 | ONE for the radius (first build) | the landing gate (y = 1 cell, radius 0.5) |
| S4 | `stick` stores no normal | the landing gate; the flipped control (up expected, zero found) |
| S5 | `stick` still offsets `pos` by the radius | the landing gate (y = 0.5, not 0); the flipped control |
| S6 | `clearRow` leaves `normal` | the reused-slot gate |
| S7 | the dump writes zero for `normal` | the dump gate — **after a rewrite**: a key-only substring check let it through; the gate reads the column’s VALUE now |

### `over` goes home to rill (2026-09-02, rill `23ac55c`)

Another session, working in rill, landed `over` in rill's core the same
day: `row.age | over row.life [1, 0.7, 0]`, the same spelling as
spindrift's fifth word, the same bits (a clamped Q16.16 divide, the
segment by shift, the fraction by mask, `lerpVal`), on the plane as well
as the row — and a zero span refused by port name where spindrift refused
a zero life by value. Two words with one name refuse at register:
spindrift's suite failed at every registry init (`DuplicateOp`) the
moment rill moved. The kernel here is deleted, not kept beside rill's:
one word, one home, and `over` never needed a host — the ruling since
beat 3 was that a kernel is a rill program. The over gates stay and still
bite (they run rill's kernel through `mountKernel`); the zero-life gate
now reads rill's words; the manual moves `over` out of the parity table
into its own paragraph, because the table is the words THIS library
registers. The rill session's note that "no host row words are
registered in matryoshka yet" and "`row.life` needs to be a real field"
was a stale picture: the bridge has registered spindrift's words since
beat 1 and `life` has been in the schema since P0 — nothing to wire.
**The diff was not a no-op at the edges** (rill `529e7d8`, that session's
follow-up): spindrift's kernel refused a life ≤ 0 where rill's refused
only zero and clamped a negative to the first knot; and spindrift tested
`t ≥ ONE` on the wide ratio where rill's narrowed first and refused a
far-past-life read as overflow. Both of spindrift's answers went into
core, each with a gate and a bitten mutation. The middle — the bits every
frozen capture depends on — is identical; the witness for that is the
engine's capture verify against the frozen hashes, not this suite, and
the P5 agent runs it before anything re-freezes.

**Campaign close, 2026-09-05 — rulings 29–31 and the one-ref runner.**
Christian's verdicts on beat 5's six questions, in conversation: the
shadow budget is punted (the analytic lights are not for shadows; a
MegaLights-shaped pass later, cheap screen-space particle light first),
test_scene is the lab and the whole-set ref runs are not development,
features next with blending among them, and the GPU evaluator delegated
to CC — recorded as rulings 29–31 in the campaign's §7, with the four
questions he did not rule taken as defaults there (verbs off the
transcript, the rim as shipped, the rig tracked, no prim parent), each
overruled by a word. The G7 decision: unfired; no lab scene has missed
the budget and the picture's features buy nothing from a second
evaluator; when it fires, a lowered instruction stream walked by a
second CPU evaluator pays the bit-identity before any GPU does. **Built
the same day**, matryoshka `9ee72fe`: `refs.py verify SCENE…` and
`spray_gate.py verify|capture PAIR…`. The tool's own gates are its
refusals — a name that picks nothing exits 1 listing the names, because
a filter that silently ran nothing would print "held" over zero
renders — and one real run of each: test_scene unmoved in one scene, the
gate pair held in 0:01, the plate family in 0:10. **The first cut ran
three renders for the gate pair's own name**: `test_scene-embers` is the
prefix of the two plate pairs, and prefix-or-exact picked all three. Exact
now wins over prefix; the family is still one word (`test_scene`). A
partial `capture` keeps every other manifest line verbatim and says in
its header which were re-taken — one pair's new picture never erases
another's frozen truth. The second campaign's plan is
`docs/spindrift-campaign-2.md`: the picture on the plate, G8–G11
pre-registered (a fade as a probability in the leaf's hit test, the soft
disc, the glow as emission, the streak as a capsule along velocity), the
names read aloud, five rulings asked before P6.

**Beat 6 (campaign 2, P6 "the fade"), the spindrift half — `alpha` on the
row, and the field's bounds in rill.** Christian gave the conn on the
five proposals of campaign 2 §7 (2026-09-05): alpha is the row's, blending
is a probability, a write outside [0, 1] is refused and counted, the glow
is emission into the existing bloom, the names stand. `alpha` is `F_ALPHA`
= 10 (`F_U0` moves to 11 — every user of it is by name), Q16.16, born 1 in
the spray's spawn beside size and colour (the population's own `spawn`
zeroes it like every field: the store has no opinion, the spray does),
dump format 4 with `alpha` as the last key, `tools/read_dump.py` reading
it back and refusing a value outside [0, 1] on the Python side too.
**The bounds are the field's, in rill (`48c0183`):** `Field.bounds`, a
closed range checked on the value that would LAND — after `add` composes
with the snapshot, after an axis composes with its vector — with the
refusal on the `write` node that made it, counted like a refusal at eval,
its words the value and the range as decimals by integer formatting. A
queued write now remembers its node for exactly that. Rejected: counting
a refused write in the population's thunk (no node, no words — a refusal
that lands nowhere); clamping (ruling 3: a kernel that says 1.2 has a
curve wrong, and a clamp would hide it while the picture looked right).
Gates: rill's (replace outside above and below, inside, the inclusive
top by `add`, `add` past it refused with 0.75 kept; first_node the write;
the words `row.alpha = 2.0000 is outside [0.0000, 1.0000]`); here, the
dump gate extended to format 4 with alpha's VALUE; `alpha: born 1, faded
by over, a landed value past 1 refused on the write node, counted, the
row unchanged` (the same row's other write lands); `G0 with a fade` —
two runs one byte string, and the alpha column carries values strictly
between 0 and 1. **Mutations, four, all bitten:** rill's check on the
queued operand instead of the landed value (the add past the top lands;
count 0); the spawn leaving alpha 0 — the fade kernel HID it, its first
tick writing the first knot, and the second spray caught it (0 + 0.5
lands; count 0); the bounds dropped from the schema (1.5 lands; count
0); alpha written as zero into the dump (the dump gate reads 0 for
32768, and G0-with-a-fade finds nothing between 0 and 1). The suite is
73; `verify-dump` reads format 4 from Python. The engine half — the
factor in the leaf's test, the third vec4 in the slot, the G8 block
gates, the fade pair — is the next commit, in matryoshka.

**Beat 6, the engine half — the factor in the leaf (matryoshka `af1666e`).**
The row's alpha rides a THIRD vec4 in the particle slot (32 → 48 B; x =
alpha, yzw reserved for the kind's `soft` and `streak` so campaign 2's
later beats add no stride change); rejected: packing alpha into
`colour.w` beside `kind` (a decode the next reader must know — loud,
never a guess). The leaf's test: hit when the sample is below alpha × c,
with c exactly beat 5's rule, spelled so that at alpha 1 a wide disc does
NOT read the sample (`cover >= 0.5 && (alpha >= 1 || u < alpha)`) — the
reflection pass's placeholder sample was never read before and must not
start being, or the frozen pairs move. The reflection now passes the
pixel's FIXED hashed sample (index 0) instead of 0: read only below
alpha 1, and it does not walk with the sequence, so a faded sprite in a
mirror dithers the same way every frame — recorded, trigger: a fading
ember visible in a mirror under accumulation. **The alpha-1 witness
held**: the three plate-family pairs bit-identical with the stride and
the factor in place, in 0:43 by the one-ref runner — every other pair
waits for the close (ruling 30). **The customer is a NEW pair**,
`test_scene-fade`, rather than the plate pair re-frozen: the plate pose,
the embers rig one line apart (`kernels/cinders-fade.rill`), so the
unmoved plate pair is the witness and the fade pair is the picture, and
the difference between them is the fade and nothing else (45 388 of
921 600 pixels). Rejected: re-freezing the plate pair with a fade (then
nothing on the lab witnesses alpha 1). Gates on the twin: the half block
(1985 of 4096 at alpha 0.5, wide), the eighth (519 at alpha 0.5 ×
coverage 0.25), alpha 1 = the old rule with u unread, alpha 0 never, a
rim miss a miss at any alpha, accumulation mean 0.5000 with no pixel
frozen. **Mutations, both bitten:** the twin ignoring alpha — both G8
gates fail (4096 hits; mean 1.0000, 4096 frozen); the SHADER ignoring
alpha — the fade pair's verify reports it MOVED to `379794ed…`, the
plate pair's own hash, which is the cleanest witness this campaign has
had that a change is one line. Process finding: a regex that appended
the alpha argument to every `spriteHit` call landed two of them inside
the nested `hashedSample(...)` — caught by reading the eight calls
before building, not by the compiler (it would have been). A second: a
`git checkout` meant to revert a mutation reverted the file's whole
uncommitted edit with it; re-applied from the patch, byte-identical —
mutate with a reversible replace, never with checkout, while the edit is
uncommitted. Matryoshka's suite: 2560/2560; one build step fails on
`src/control/commands.zig` importing `../physics_probe.zig` outside the
control test root (Christian's `abe240e`, 2026-09-04), left as found.

**Beat 7 (campaign 2, P7 "the cloud") — the kind's `soft` edge
(matryoshka `b4be987`; nothing changed in spindrift's row).** A soft rim
is the KIND's, a fade the row's (campaign 2 §3's rule): `soft` is the
fraction of a disc's radius over which its alpha falls from the row's to
zero, in [0, 1], and it rides the archetype's three formats the way the
appearance does — the rig line's token after the appearance (always
written, absent reads 0), the Project pack's `soft` field (absent 0,
outside [0, 1] a bad pack refused whole), `sprayarche soft <kind> <n>` on
the console — one validation (`sprayArcheSetSoft`) shared by all three,
refusing outside [0, 1] and never clamping. **A change from the plan:**
P6 reserved the slot's `look.yzw` for the kind's numbers; built, they
ride the RUN's leaf payload (`params.w`) instead of a per-row copy —
the upload skips chunks the sim did not dirty, so a per-row copy of a
kind number would go stale on still rows after a retune, and a rebuild
per retune (the appearance's rule) is too heavy for a look number a
designer slides. Rejected: marking every chunk dirty on a retune (a
sim-side lie for a renderer's convenience). `SprayArcheSpec.soft` is
optional (null leaves a retuned kind's edge as it was) because the
console's `sprayarche set` carries no soft column; noted, not changed:
the same `set` RESETS a kind's appearance to the default today (the
spec's default is `sprite`), a pre-existing quirk — Christian's call
whether `set` should leave the appearance alone too. The leaf: alpha ×
clamp((1 − delta/radius)/soft, 0, 1), then beat 6's test unchanged; the
twin restates it. Stated: a narrow disc takes the profile at the ray's
offset, not integrated over the footprint — a soft mote is a little
under-drawn; the cloud is wide. **Gates:** G9 on the twin (r = 30 px
over a 64² block, point-tested: soft 1 gives 918 hits against the
cone's integral 942.5, σ 21.7 — and the integral is a third of the
disc's area, 942.7, a number a reader checks on paper; soft 0 every
pixel inside; soft 0.5 the inner half solid; outside never); the rig
round-trip carries 0.35, a `set` without a soft column keeps it, 1.5
and −0.1 refused; the Project round-trip carries it; the rig-line byte
gate BIT on the new token, as it should (the line's shape changed and
the gate said so; the literal updated). **Mutations, both bitten:** the
twin's profile at 2r (1876 hits, 43σ); the SHADER ignoring soft (the
smoke pair MOVED to `64cb9ab4…`; reverted, holds at `ea0205d0…`). The
witness: the four test_scene pairs bit-identical at soft 0 in 0:56. The
customer: `test_scene-smoke`, a new pair at the plate pose — one kind,
`smoke`, soft 0.7, `kernels/smoke.rill` (grey, non-emissive, growing
from 25 cm to 1.2 m, rising at 0.35 m/s², fading) — a dithered grey
column at one sample: a capture is FIXED sampling by design, so a soft
rim shows as dither and converges to the profile only under the
sequence; the smooth cloud is the accumulated frame, which no capture
shows. Suite 2561/2561; the control-root compile failure stands as
found. Process: the test fan-out was killed for memory when chained
behind the build in one background command — run it alone, `-j4`.

**Campaign 2 called, 2026-09-05, after P7.** Christian ran the fade and
the smoke on his machine: a loss in quality and, on the Debug binary I
had left in zig-out, a frame cost. Measured before answering (GPU ms at
720p, Debug, 240 frames): bare plate 3.30, embers 4.35, fade 4.23,
smoke soft 0.7 3.35, smoke hard 3.28; inside the plume: bare 3.87,
smoke 4.11, hard 3.99, embers 5.90 — the fade costs nothing over the
opaque embers and the soft edge a tenth of a millisecond, so the cost was
the build, not the features. The quality is the design: one hashed
sample per pixel, noise unless a still camera accumulates, and games
move the camera — "a cloud of bees". His verdict (campaign 2 §7 ruling
6, his words): ray-tracing particles does not cut it; tons of work for
poor results; the motes, the smoke, the lights and shadows were each a
problem made to keep everything uniform, which most games do not need;
a screen-space composite is fine, if not better, for most things. The
sim side stands whole; the leaf's stochastic path and the particle
point lights go; a raster sprite pass over the traced frame replaces
them, planned fresh. Lesson for the ledger: the plan's G8 said "a single
frame dithers; the accumulated frame is the picture" and ruling 2 took
it — the frame a game shows is the single one. A gate on a still capture
cannot see that; the judge's eye on a moving camera can, and did, on the
first evening it could.

**Campaign 3, P10 "the pass" — the composite's sprites (matryoshka
`5a3ed8e`; nothing in spindrift's row).** A graphics pass between
`post_composite` and `bloom_down`, INTO the HDR composite (the image
gained the colour-attachment usage bit; it stays in GENERAL, which a
colour attachment may be, so no layout moves — two barriers order the
compute writes before the blend and the blend before bloom's sampled
read). One instance per drawn row, a four-vertex strip, no vertex
buffer: the vertex pulls the row from the particle SSBO through a sorted
order SSBO; the fragment reads the tracer's R16F depth as a storage
image (the gizmo overlay's test) and a sixteen-entry look table by the
slot's `look.w`, which now carries the SPRAY's slot — the row's `kind`
is the sim's and unset, so the plan's "per-kind table by the slot's
kind" became per spray; a spray has one kind. Rejected: a per-row copy
of `soft`/`near` (beat 7's stale-chunk lesson); the row's `kind` written
by the bridge (a renderer index riding a sim field into every dump).
**The sort is the bridge's**, on the CPU, per frame: every live `sprite`
row's drawn position (`quantiseRow(drawnAt(…))`, the same floats the
slot holds) to the eye, `std.sort.pdq` by distance descending, id
ascending, spray ascending — a function of the rows (G14, G18); the keys
and the order are bank-owned buffers sized to the particle buffer once.
**`traced` is the leaf** (ruling 1): `Appearance` gains it, `upload`
publishes runs only for it, `sortSprites` skips it; the refusal line
names three. The four leaf gates of campaigns 1–2 (DIRTY chunks, the
leaf split, the landed row's drawn position, the light appearance's
relink) now run on `traced` — their claims are the tree's and unchanged;
the beat-3 refusal-wording gate takes the third name. **`near`** rides
the kind's three formats exactly as `soft` did (setter, spec, snapshot,
rig token, pack field, verb); the rig-line byte gate bit again and took
the token. **Stamps:** two more timestamp queries around the pass,
written every frame drawn or not — an unwritten query fails the whole
readback and perf goes dark — so `Perf: sprites` prints beside the trav
split. **G12:** `refs.py verify test_scene` unmoved with the pass in the
frame; every pair's bare hash unchanged at the freeze. **G13:** one set
at the plate pose (Debug; taken inside a half-hour when every pass ran 3× slow — I wrote "the GPU was shared with a second session", an inference WITHDRAWN: nothing was on the card at 23:20 and the bare pose was back to 2.79 ms; re-taken idle: traversal 1.09 bare, 1.06 embers with the coals off, 1.11 with the coals, 1.02 smoke; the pass 0.03–0.04 ms — never assert a cause that was not measured):
traversal 3.29 ms bare, 3.29 with the embers and the coals stood down,
3.55 with the coals' four analytic lights (P11 retires them); the pass
0.07 ms for 2400 rows. **The five plate-family pairs re-frozen once**
(7aa1ebc8, 6a32fbb4, f9311226, 4a193d9a, 482a9ee5); the embers are the
leaf's picture disc for disc, the fade a fade, the smoke a plume — dark,
unlit until P11. **Mutations, three:** the sort reversed (the fade pair MOVED, 4a193d9a → 7910b127); the leaf republished for `sprite` (traversal 5.50 ms against 3.29, coals off); the tie by slot instead of id — which SURVIVED the first G14 gate: within one spray the packing keeps a run's slot order equal to its id order, so every coincident burst draws the same either way, and a survived mutation names a decoration. It is not one: the rules differ ACROSS sprays, when a row of the second spray has a lower id than a tying row of the first. A gate built on exactly that (two sprays bursting a tick apart, the eye halfway between their rows so three distances are one dyadic number) bit the mutation — expected the second spray's slot, found the first's. Recorded: a tie rule that no picture on one spray can see is still a rule two sprays can. Suite 2563/2563.
Process: the first `zig build test` chained behind the build in one
background command was killed for memory (beat 7's lesson, again —
now in the memory file); the Debug rebuild under the shared GPU took
most of a ten-minute timeout and the harness backgrounded it; the
pictures were read from disk while the chain ran, which is the right
use of that time.

**Blade3D recon (2026-09-05, `docs/recon/blade3d-particles.md`).** At
Christian's ask, a sub-agent read his 2010 engine's particles. What
carries over, and where it lands: the CLOUD's recipe — static puff
cards on a depth ramp through a seeded box cluster, world-space 3D
noise added so overlapping cards agree on the lumps, a per-card
top/bottom gradient as fake self-shadow, a scrolling dust octave by
`max`, a gamma lift — with the gradient replaced by P11's real sun and
ambient on the card, and the noise volume (128³ luminance) as a new
binding for the pass: a beat of its own, "the puff", after P12. The
LIGHT SHAFTS (frustum cards shadow-mapped per fragment) once the pass
is handed the sun's frustum: a fill with that trigger. TURBULENCE (three
decorrelated Perlin taps, normalised) is a row word — a customer scene
and a read-aloud before a kernel, and integer Perlin is its own recon.
The EXPLOSION's Gaussian shock ring, likewise a word. PROMOTE-BY-AGE
(one emitter, two appearances) is the fenced "sub-sprays" with a shape
now: recorded. Not inherited: Blade3D's two-pass alpha-test crutch (no
per-particle sort — ours sorts), its `abs()` soft-particle fade (ours is
one-sided), its unlit cards (P11). A finding for the plan: a population
whose kind changes by age spans two blend modes, so the pass must draw
by kind after sorting — decide before P12's `blend add`.

**Campaign 3, P11 "the light" (matryoshka `263046f`; nothing in
spindrift's row).** The card lit by the world and the light rows as
uncapped G-buffer splats — and a beat that found five things on the way.
**The card:** albedo/emission by the leaf's rule; the albedo lit as a
VOLUME's card — a hemisphere normal in the card's frame and a wrapped
sun (a sphere's lee went black against the sky in the first build);
the ambient the compose's own hemisphere at the card's normal, tint and
fill folded in on the CPU (the pixel's env_diff is nothing against the
sky, where half a plume stands — rejected for that; still bound for a
probe-lit card later); the sun's visibility the TRACER's (sun_shadow's
half-res image, the surface behind the card) times the CSM at the
fragment where a raster producer drew one. **The CSM finding:** the
"no shadow on the card" mutation SURVIVED at the plate pose; a
diagnostic with smoke under the plate rendered the same bytes with and
without the lookup — the CSM is the raster producer's, and a fully
traced scene draws nothing into it. The tracer's own visibility is where
a traced scene keeps its shadows, and a new pair (`test_scene-smoke-shade`,
the smoke kind under the plate at the beneath pose) is the gate that
mutation now bites. **The splats:** a second additive pipeline in the
same pass, drawn before the cards, one instance per light row, the quad
the sphere's projected box or the whole frame when the eye is inside the
range or a corner is behind the camera (Christian's light behind the
camera — G17's new gate, `test_scene-behind`, a beacon a metre and a
half behind the eye lighting the plate's near half, a quarter of the
frame's pixels; stood down, nothing); the fragment rebuilds the pixel's
primary ray as traversal.comp does, takes the surface from the tracer's
depth, normal and albedo from the G-buffer, the engine's diffuse
point-light term, no shadow. Uncapped by `lightRows`; **ruling 26
kept**: a spray's light is the cap's SUM spread over its rows (the first
build lit fifteen coals at the gain each — an orange sheet). The
analytic path for sprays is retired (main merges zero) with its cap and
the rank-swap seam. **Found, fixed:** (1) a stage on an older push
layout draws nothing — the vertex stage was on P10's block; the right
and up read rows of the CSM matrix and every card vanished, and a
mutation chain ran on that build before the picture was looked at
(discarded; every mutation re-run); (2) a 272-byte push — a ninth vec4 —
faults the device on every frame, said by the validation layer in one
line; (3) **the harness hashed yesterday's frames**: with every render
faulting, `capture` reported six pairs taken at their previous hashes,
the PPMs being the old files, and only the pair with no earlier frame
said "no output frame" — both `spray_gate.render` and `refs.render` now
delete the target first; (4) the memory watchdog killed two background
chains at a rebuild with 23 GB free a second later — the closing steps
ran in the foreground in pieces; (5) G13 not re-claimed this beat: in
one set the embers' traversal read 1.09 against 0.86 bare with every
other pass 25% slower too — the GPU's clock following the frame's CPU
load in Debug, which is what the "slow window" was; P10's idle set and
its leaf mutation stand. Gates: G12 unmoved; G16/G17 on seven re-frozen
pairs; G18 held; the bridge's `lightRows` gate (fifteen where four; the
cap's sum; ids ascending). Mutations, four, all bitten on the fixed
build: the traced visibility ignored (the shaded smoke MOVED); emission
as albedo (the plate MOVED); the splat ignoring the normal (the
underside an orange sheet — ruling 24's warm pool, for the last time);
lights culled by screen position (behind == bare). The applet's copy no
longer promises four lights.

**Christian's finding on P11 (2026-09-06): the shadow leaks through the
smoke.** Close to the plume, the helmet's shadow pattern shows inside
the smoke — the card takes the tracer's sun visibility of the surface
BEHIND it, pixel for pixel (P11's choice once the CSM proved empty in a
traced scene), so whatever is shadowed behind a card shadows the card's
fragments in that pattern. "Shadow buffer taking priority over the
particles" is exactly what it is. Folded into P12 (his word: not a
race): one visibility per CARD, sampled at the card's centre pixel in
the vertex stage and carried flat — a card is lit or shadowed whole and
nothing can pattern inside it; still the surface behind, still cheap.
The true fix is recorded with its trigger: a sun depth pass over the
traced geometry (the shadow_depth pipeline over the scene's triangles,
not only the raster producer's meshes), so a card's own world position
answers; trigger: a card whose area should be half in shadow.

**Campaign 3, P12 "the look" (matryoshka `1d6f223`; nothing in
spindrift's row) — and Christian's leak closed.** One visibility per
CARD: the vertex stage reads the tracer's sun visibility under the
card's centre pixel (the depth there first — sky is lit) and carries it
flat; the fragment multiplies it with the CSM at its own position. A
card is lit or shadowed whole; the shaded-smoke pair moved when the
per-fragment read was put back. Rejected: blurring the per-fragment
read (a soft version of the surface's shadow is still the surface's).
The true fix stands recorded — a sun depth pass over the traced
geometry. **`blend`** (0 alpha, 1 add) and **`streak`** (seconds of
travel) ride the kind's three formats as `soft` and `near` do — the rig
line is `… <appearance> <soft> <near> <streak> <blend>`, the pack has
`streak` and `blend` (a string), the console `sprayarche streak|blend`;
the rig-line byte gate took the two tokens. **Runs by blend:** the sort
key carries the blend; after the sort the order is cut into runs where
the mode changes (`SpriteRun {first, count, blend}`, the last run taking
overflow past 256); the renderer draws the runs in order, binding the
pipeline each asks for — a second sprite pipeline with the splats'
ONE/ONE blend and the same shaders, the fragment premultiplying when the
look says add. Rejected: all alpha then all additive (a spark behind
smoke drawn over it). Gate: an additive spray between two alpha depths
makes three runs in order, one mode one; mutation: the cut by spray —
three runs for one. **The streak:** the slot gains `vel` (64 B); the
vertex turns the card's first axis along the velocity projected onto the
card's plane and stretches it by streak × speed — an ellipse, the
fragment's disc test unchanged, the soft edge intact (a capsule with
round ends is a fill); mutation: the axis from the position — the sparks
moved. The fed dt is kept by the bank (`lastDt`; a bit for "have a
previous tick", since the epoch is at time zero — the first cut compared
against zero and read no dt) and reaches the push, unused this beat: the
streak is per second so a dash does not change with the frame rate.
**Found:** the bank already had a local `runs` — the accessor is
`spriteRuns`. Eight pairs frozen and held (G18); four mutations bitten;
suite 2566/2566. The sparks pair is oa_spirit3's kernel as an additive,
streaked kind beside the coals on the plate.

**Campaign 3 CLOSED, 2026-09-06** (`docs/cc-report-campaign3-close.md`;
matryoshka `202dc51` the manifest). Ruling 30's one whole run:
`refs.py verify --really` — nine scenes unmoved with both pipelines in
every frame (G12 whole), timings within band; then the four pairs that
were the leaf's re-taken as the composite's (oa_spirit3's sparks
9ac6cb99 → a8b721a0, dust2's motes c49d3756 → c4d0885d, the torch
81304695 → c9c3042d, the fountain 33041ea4 → 26ad3c5a), their old frames
kept beside the new for the report — the harness now deletes a target
before rendering, so the before had to be copied out first. **Two bares
moved** (oa ad404c38 → 69a74dc1, dust2 6168e525 → 846948cb), the
tiltyard's two not: the pairs' bares were frozen on the 2nd, and the
engine's own history re-froze dust2's reference after the importers'
BC7 alpha fix (`e87d898`, the 5th) and put a floor decal into the q3
after-frame that the before-frame lacks. The nine references at their
own poses are the witness that the pass moves nothing; the two bares
are re-frozen with their pairs and said. The pictures: dust2's motes are
the same scatter as cards; the sparks the same burst, lit. Eleven
mutations across the campaign, all bitten or the gate rewritten. The
leaf's gates stay in the suite on `traced`; no mounted capture uses
`traced`, so nothing to retire. Next: "the puff", its own campaign.

**Campaign 4, P13 "the field" (matryoshka `8d5310b`; nothing in
spindrift's row).** The puff: a tiling 3D field generated on the CPU
(`src/puff_noise.zig`: Perlin over an 8-cell lattice with gradients
hashed by lowbias32 and wrapped at the edge, two octaves, 128³ RGBA8 —
the LUT path takes RGBA8 — wyhash frozen `df721bbc20454ed7`), up
`createLut3D` with its own REPEAT sampler (the LUT's clamps), bound at 10
on the sprite set; `puff_view` exempted from the renderer's X-ray table
by name, as the LUT is. The fragment samples at the world position over
`noise` metres per period; albedo × mix(1, 2n, grain); alpha ×
mix(1, smoothstep(0.35, 0.65, n), grain) — the first cut scaled alpha by
n itself and halved the plume; dust: a second sample at (world − (0,
drift × fed_time, 0)) / dust, albedo = max(albedo, d/2); lift:
pow(albedo, lift). Fed time reaches the push in `hemi_sky.w` (the bank's
`lastTime`). `sprayarche puff` — five numbers, one verb, one validation,
one rig token group after the blend, five pack fields; the look table is
three vec4s per spray (the shaders index `looks[spray × 3 + k]`). The
rig's numbers: a 2.5 m period made 30 cm grain (eight lumps to a period)
— 16 m now, dust 4 m. **Gates:** G19 (frozen hash; tiles — the perlin
one period on equals the perlin at 0 on every axis; not flat), G20, G21
(eight pairs byte-identical after the field was bound and the look
table grew — the stride change alone could have moved them), the rig
and Project round-trips, the rig-line byte gate. **Mutations, three,
all bitten:** the noise in the card's frame (the puff pair MOVED); the
wisps on the wall clock (two renders, TWO hashes — the claim itself);
the field applied at grain 0 (the smoke pair MOVED). **Found:** the
generator's test was reachable from the renderer but not from a test
root — the suite's count did not move — so it is its own root now
(build.zig's `puff_noise_tests`), the same shape as the engine's other
standalone files; the first regex that copied the block stopped at the
run/dependOn lines and the gate was hooked in a second pass. Suite
2567/2567; nine pairs held.

**Campaign 4 CLOSED, 2026-09-06, after P13** (`docs/cc-report-campaign4-close.md`).
At Christian's word the whole set was not re-run: he checked the
pictures by eye, the context was short, and G21 had already held the
eight campaign-3 pairs byte-identical at the puff's zero — the honest
statement is that ruling 30's whole run belongs to the next close, and
that is said in the report rather than implied. "We have puffs."


**The manifold, 2026-09-07 (`kernels/fire.rill`; nothing in rill, nothing
in loam).** Christian's week of particles, and `docs/funideas.md` §9's
jump: an RBF set does not care that its query point is a POSITION. Read
loam's `rbf.Set` at a particle's STATE instead and the same evaluator
that skins the marble skins a flame — `State → Field → Properties`. So
`fire.rill` is the first kernel that writes NO COLOUR. It writes a point
in an appearance manifold (`row.u0` cooled, `u1` sooted, `u2` thinned),
and what moves that point is what happened to the row. Age is still in
here — `perish` reads it — but nothing about how the row LOOKS comes
from it.

Three shapes came out of the code rather than the design. (1) A spawn
zeroes a row's user channels (`population.clearRow`), so the axes are
spelled as how much has HAPPENED, never as what is left: a newborn has
no history and (0,0,0) is the flame. Authored the manifold the other way
up first — x as temperature — and every number stayed in range while
cold soot glowed orange on the floor; numbers in range are not numbers
that agree, and it was the PICTURE that said so. (2) Every line is
`(1 − x) · rate`, an approach that saturates, so no influence can drive a
channel past 1 and no clamp is needed to say so. (3) Every write is
`add`, because `row.zig`'s `landedVal` reads the LIVE field: a row's
queued adds land in order, so the influences SUM. A second cooling term
is not a special case of the first, it is another force on the same
channel. That is the whole trick, and it is why `write row.u0` (replace)
is a mutation that bites.

**Gate:** "fire.rill: the appearance coordinate is the WORLD's, not the
clock's" — one kernel, one seed, one schedule, two worlds. `world.zig`'s
negative control read the other way up: an emitter whose dump is
identical over `Nowhere` and over `Floor` never asked, so this one's two
must DIFFER, by name. Landed: cooled > 0.95, sooted > 0.90. Falling:
cooled < 0.60, sooted < 0.40. **Mutations, five, all bitten:** the
`plunge` line dropped; the `settle` line dropped; `plunge` ungated (`mul
row.stuck` dropped, so it fires for every row and the worlds agree
again); the `quench` line dropped; `write row.u0 add` made replace.

**Found, three.** (a) **A kernel's knobs and the SPRAY's own knobs share
one namespace, with no guard.** `plane.drift.@self.spread` named as a
kernel's thinning rate silently retunes the launch cone: `run.zig:446`
re-reads knobs from the plane every tick, so the mount line printed the
1.6 the flag asked for and the plane then made it 0.013. Every ember went
straight up in a pencil, green. Same shape as the gravity-knob bite in
CLAUDE.md. RULING WANTED: refuse a kernel knob that shadows a spray
knob, or namespace them apart. (b) **Ruling 20's recorded trigger fired.**
"A tunnel at frame rate in a customer scene" — 2.6% of embers pass
through the mock floor and fall for the rest of their life. `collide`
tests `pos → pos + vel_start · dt`; the integrate moves by
`vel_end · dt`, which is `g · dt²` further, so a row that stops in that
sliver passes the test, lands below, and `world.zig:68` says "already
through" for ever after. Measured, not asserted: 2.57% at 16 ms, 0.93% at
8, 0.49% at 4 — linear in dt, a positional error and not a physical one.
Matryoshka's tracer places such a row on the face it came through; the
mock floor does not. (c) A stuck row still spreads — `thin` is not gated
on being free and `settle` only BALANCES it — so `thinned` goes to
`thin/(thin + |settle|)`, not to zero. The gate pins that balance rather
than calling it small.

**Recorded, not built.** (i) `relax <target> <rate>` — every state line
spells `| mul -1 | add 1 | mul <rate> |` to say "approach 1", and the
rates are PER TICK, so the kernel is correct at one dt only: a kernel
cannot spell dt (`ctx.dt` is Zig's, there is no `row.dt`, and every
stateful rill op that would relax is not row-legal). Trigger: this
kernel, which exists. (ii) Two saturating factors in one flow — gating
`thin` on being free wants `(1 − u2) · (1 − stuck)`, and a row cannot
nest a sub-expression as an argument. Trigger: a second customer that
wants it; one is a coincidence.


**`relax`, 2026-09-07 (the eighth word; nothing in rill).** Built the same
day its customer scene landed, which is the order the house rule asks for:
`fire.rill` spelled `| mul -1 | add 1 | mul <rate>` seven times to say
"approach", and the rates were PER TICK — correct at one dt and quietly
wrong at every other. A kernel cannot say dt (`ctx.dt` is Zig's, there is
no `row.dt`, and every stateful core op that would relax — `ease`, `ramp`
— is not row-legal), so the word eats the fed delta and the knob is per
second, exactly as `gravity`'s is cells per second².

`relax <target> <rate>` emits the STEP, `(target − in) · rate · dt`, not
the arrival. That is the design, not a convenience: a row's state is
pushed by several things at once, and a word returning the new value could
only ever be the LAST word to speak. A step composes under `write … add`,
so the influences sum the way forces do — `fire.rill` has three of them on
`cooled` alone. Two refusals, both loud: a NEGATIVE rate (divergence, not
a slow relax) and `rate · dt > 1` (a step past the target; past two, away
from it every tick). A clamp there would leave a kernel oscillating while
the picture looked plausible, which is campaign 2's ruling 3 again.
Read-aloud "u0, relax toward 1 at nine tenths a second"; rejected `decay`
(only ever toward zero, and half these lines climb), `approach` (motion in
space; this is a scalar), `cool` (one customer, not the operation),
`toward` (wants a preposition it has not got); `ease`/`ramp` are rill's,
on the plane and stateful.

**Gates, two.** "the step is the FED delta's — double the tick, double the
step, exactly": both runs share tick 1 and differ only in the second
tick's fed delta, so ¼ and ⅛ are asserted as themselves as well as as a
ratio (a mutation cannot pass by making both zero). Exact in Q16.16
because the STEP is linear in dt even though the relaxation is not — which
is also why the gate compares steps rather than two schedules' arrivals.
"a rate that walks away, or that closes more than the whole gap in a tick,
refuses by name", with the control beside it, and the tail that the same
rate 4 which refuses at a one-second tick is fine at 16 ms: the guard is on
the STEP, which is the fed delta's business. **Mutations, four, all
bitten:** the `· dt` dropped; the gap taken backwards (`x − target`);
either guard dropped.

`fire.rill` rewritten onto it — two nodes a line where there were five,
`settle` now a rate toward 0 rather than a negative multiplier, and the
demo re-run knob-for-knob (×62.5, per tick to per second) lands the same
picture: stuck cooled 0.982 / sooted 0.951 / thinned 0.063 against
0.984 / 0.956 / 0.061 before. Its four mutations still bite, plus a new
one the rewrite made spellable — `settle` relaxing toward 1 instead of 0.


**`slide`, and the mock's resume, 2026-09-07 (the ninth word).** The
surface family's second half: `collide | slide | stick` — take the
contact's normal OUT of the velocity and put the row on the surface, so
what is left is the tangent and the row RUNS ALONG what it hit. Rain down
a window, an ember down a sloped hearth, and a soot STREAK where `stick`
alone leaves a dot, which is the manifold's next story because a sliding
row keeps arriving somewhere new while it cools. Read-aloud "collide,
slide, stick"; rejected `slip` (a failure, not a motion), `skid` (promises
a friction this does not model — a frictionless slide on a flat floor runs
for ever, and that is a thing you can see), `graze` (a near miss, the
opposite), `tangent` (the plane, not the act), `deflect` (says bounce, and
nothing here reflects).

**It could not be built without overturning a prior decision, and
Christian ruled that it should be** ("just because we did something,
didn't mean it was right"). `Floor` said a segment starting BELOW it is
"already through, no crossing" (beat 4, deliberate). But ruling 20's
sliver puts rows there: `collide` tests `pos → pos + vel_start · dt` while
the integrate moves by `vel_end · dt`, `g · dt²` further. For a fire that
was 2.57% of embers tunnelling at 16 ms; for `slide` it is FATAL, because
a sliding row sinks by exactly that sliver every tick — it slid once and
was abandoned. So both mocks now do what the engine already does
(`drift-words.md`, `collide`): a row found inside a surface is placed on
the face it came through, at t = 0. The fire's tunnel went to 0.00% at
16, 8 and 4 ms. It cost no frozen hash — spindrift freezes none, G0
compares two runs to each other — which is the only reason this was a
half-hour and not a campaign. Ruling 20's (B) is still open and still
worth it: the resume BOUNDS the penetration at `g · dt²` and corrects it
every tick, it does not remove it.

New mock: `Plane` (any unit normal, `n · p = d`), kept BESIDE `Floor`
rather than folded into it — every beat-4 gate is written against `Floor`'s
exact answers and a mock rewritten under its own gates is a mock nobody
checked. It exists because `slide` cannot be gated on a floor: there
gravity is entirely normal, the tangent a slide leaves is the velocity the
row already had, and a kernel that did NOTHING would pass.

**Gates, two.** "the contact's normal leaves the velocity" — a wall,
n = (1, 0, 0), exact in Q16.16, so equalities: the normal component is 0,
the tangent untouched, the row on the surface. "it SUBTRACTS, so what it
leaves still accelerates" — a 3-4-5 slope against a flat floor, run
identically. **Mutations, five, all bitten:** the correction signed wrong;
the row not placed at the contact; `Plane`'s resume dropped; `Floor`'s
resume dropped; and `slide` REPLACING instead of subtracting.

**The last of those is the one that taught something.** It SURVIVED the
first cut of the gate, and the reason is a claim in the first draft of
`slide`'s own comment that was simply false: that a replace would lose
`gravity`'s add and a row on a slope would never accelerate. It does
accelerate — in STAIR-STEPS, holding a velocity for several ticks and
jumping on the one where it has sunk far enough for a real crossing rather
than a resume (−1.44, −1.44, −1.44, −1.44, −1.68, −1.68 against a clean
−1.44, −1.68, −1.92, …). Three samples straddled a step. The gate now
takes six and asserts the increments are equal to within ONE ulp — the
step is the tangential gravity times dt = 0.24 cells/s, which is 15728.64
in Q16.16, so the rounding lands 15729 once and 15728 after; a plateau is
a step of zero, 15728 ulps out. The comment and the manual were corrected
to what the run says. Prose approved a plausible mechanism; the mutation
approved the actual one.

**Also found:** the slope gate's first cut asserted over a population of
NONE. Four a second at a quarter-second tick is one row; a rate of 1/s is
a quarter of one, and the rate was zeroed before it had been born. It
failed loudly, which is the only reason it is not still passing quietly —
the gate now asserts `live == 1` at the spawn tick and again at the end.


**Knob rooms, 2026-09-07 (ruled: "break stuff early").** The fire beat's
finding (a) closed. `plane.drift.@self.spread` named as a kernel's own
spreading rate silently retuned the SPRAY's launch cone to 0.013 cells/s,
because the host re-reads its knobs from the plane every tick — which is
the documented interface, `write plane.drift.@sparks.rate 2 mul`, the
README's headline. One path, two owners, and NEITHER WRONG: no guard on
names could tell a kernel meaning `spread` from a host meaning it. So the
fix is a room, not a rule.

`rate`, `speed`, `spread`, `life` — the four in `Knobs`, and exactly the
four matryoshka's rills write — stay flat and stay readable by a kernel;
that is what they are for. Everything else a kernel wants told to it goes
under `.k.`, and a kernel naming any other knob flat under its own `@name`
is refused at MOUNT, by name, with where to put it. The check walks the
mounted program's subscriptions, beside the `hear` refusal that was
already there. **`gravity` moved with the rest** — it was never a spray
knob at all, only a kernel one that `drift-run` seeded on the flat path,
which is the confusion in miniature and is why the old spelling
`gravity plane.drift.@self.gravity` now refuses.

The direction was chosen for cost: moving the SPRAY's four into a
sub-room would have broken the README's headline and every rill in
matryoshka that drives a spray. Moving the KERNEL's own knobs cost
matryoshka three string sites (one kernel source, two comments) and no
plane path at all — it writes only the reserved four and reads only
`@self.gravity`.

**Gate:** "a kernel's own knob in the SPRAY's room is refused at mount by
name, and the spray's own four are still readable" — six cases: `.k.`
mounts; the same knob flat refuses; `@self.speed` mounts, because reading
the spray's own knob is the point; the spray's `@name` is the same room as
`@self`; another spray's room and the rest of the plane are not ours to
police. The refusal is asserted to NAME the `.k.` spelling — a refusal
nobody can act on is half a refusal. **Mutations, three, all bitten:** the
guard dropped; `SPRAY_KNOBS` emptied (a legitimate `@self.speed` read
starts refusing); the `.k.` room not recognised.

**Not run:** matryoshka's suite. Its half of this is three string sites
with no matching plane path anywhere in the repo, and a heavy run is
Christian's call, not a reflex — said here rather than implied.


**The slate's customer, 2026-09-07 (`kernels/hearth.rill`; rill `9c97bbe`
is the mechanism).** The gap `slide` left the same afternoon: a sliding row
is against the cold thing on every tick and `row.stuck` is 0 the whole time,
so "I am touching something right now" had nowhere in the row to live. A
field written by `slide` would arrive a tick late and, crossing the tick
boundary, would be state owing a dump and a format version. `slate.contact`
crosses nothing. `slide` says it; the lines below read it.

`stick` says it too, and the two facts are not the same one: `row.stuck` is
the STATE that follows a landing, `slate.contact` is the EVENT. A stuck row
stops colliding, so `stick` never runs twice for one landing — a kernel
wanting the moment (a burst on impact) can have it, and one wanting the
condition still reads the field.

`hearth.rill` is fire.rill's manifold on a tilted surface: `collide | slide`,
and every quench line gated on `slate.contact` instead of `row.stuck`.

**Gates two.** "a row running down a slope quenches, and `row.stuck` never
once says so" — the slope against `Nowhere`, one kernel, one seed, one
schedule, asserting `!ever_stuck` beside cooled > 0.90 and sooted > 0.85
against a falling row's 0.50 and 0.40. "`stick` says contact on the landing
tick and on no other" — u3 is 0 before, 1 on the tick it lands, and 0 again
after, with the channel cleared between so "quiet" is visible as itself.
**Mutations three, all bitten:** the plunge line ungated; `slide` never
saying contact; `stick` never saying contact.

**Two mutations of mine were wrong before they were right**, and both are
worth the ink. One deleted the FIRST `ctx.publish` in the file, which is
`stick`'s, and ran it against a gate that only exercises `slide` — a
survivor that was a bad pairing, not a weak gate. The other claimed the
slate leaks between rows; it does not, because the seed overwrites the slot
either way, and chasing why it would not reproduce is what found rill's
uninitialised `sub_slate`. The line's real job is refusing a HOST-fed slate
value, and it is gated as that now, in rill.

**Found while gating:** `stick`'s publish had no gate at all when first
written — a line nobody checks. It has one now rather than being dropped,
because the landing-tick fact is one a kernel will want.


**`--world slope`, same day.** `drift-run`'s existing `--world` learned the
third mock rather than the CLI learning a fourth flag — Christian's note:
*"we keep adding command line arguments to the renderer, we shouldn't need
those, that's what --exec is for"*. The flag whose entire job is choosing
the mock world now chooses among the three that exist (`floor`, `slope`,
`none`), and nothing was added beside it. Matryoshka's CLI was not touched
at all; `--exec` is its door and it already has one.

The slope is the gates' own 3-4-5 plane, so the picture and the gate collide
against the same numbers.


**Neighbours, 2026-09-07 (`near`, `push`; rill `9777ea9` is the lane they
forced).** The eleventh and twelfth words, and the customer that turned the
slate's handle lane from recorded into built: `near` has a LIST of row ids
to hand to `push`, and a list is the one thing a row `Val` cannot hold —
the row plane's arrays are literal-only and no operator emits one. So the
list rides the slate as a native handle, a pointer into the spray's
per-chunk buffer, valid for exactly that row's evaluation.

The neighbourhood is a uniform hash grid over the live rows, built at the
TAIL OF THE SERIAL SPAWN rather than in a seventh phase — the sweep must
see one snapshot of where everybody is, and the end of spawn is exactly
that instant. Built only when a mounted kernel says `near`, so a spray that
never asks pays nothing. Counting sort, two passes, no allocation; capacity
is still the only one.

**Found, and it is the beat's real lesson.** The first cut read `pop.pos`
live. But `sweepRows` integrates a row the instant its kernel is done, so
by the time row 1 was swept, row 0 had already moved — row 1 saw NO
neighbour where row 0 saw one, and the answer depended on the order rows
happened to be visited in, which under chunking is no order at all. The
neighbourhood now stores the positions it was built from and both words
read those. The gate that caught it is the one asserting the pair leans
apart by equal and opposite amounts: symmetry is exactly what a
half-updated world destroys.

**Gates three.** The pair (counts, the exact ∓ push, and a lone row that
does not move); the two mount refusals (a `push` with no `near` above it,
and `near`'s radius wider than the cell — the first two at mount, the third
per row, because the cell is the host's and may change between ticks); and
**one at scale**, a 4×4×4 lattice whose 288 counted neighbour-ends are what
the geometry says. **Mutations eight, all bitten** — but two only after the
scale gate existed: the cell check dropped (two of the 27 cells around a
row hash to one bucket, and its rows are counted twice) and the bucket mask
off by one (`& buckets` instead of `& buckets − 1`, so every row lands in
one of two buckets). The second is not a correctness bug at all — the cell
check still filters — so it is gated on the SPREAD instead, which is the
honest claim: the hash is doing no work and every query has become a scan
of half the population. A three-row scene showed neither. CLAUDE.md already
said so about chunking: a grid's bugs are invisible until there is a grid.

**Recorded, not built.** `push`'s falloff is the neighbourhood's own edge
and nothing softer — a row just inside pushes, one just outside does not,
and the step across is a discontinuity. Trigger: a customer that can see
the seam. And the rest of funideas §6 — cohesion, alignment, `infect`,
`synchronise` — all of which now have the machinery and want only a scene.


**`sync`, 2026-09-07 (the thirteenth word).** funideas §6's `synchronise`,
and Christian's ask: *"let's get those travelling waves of light"*. A phase
oscillator that listens to the rows `near` found —
`phase += (drift + couple · mean(wrap(other − phase))) · dt`, wrapped into
[0, 1). To ENTRAIN, which is the word for what it does and the one the
manual keeps; `sync` is what anybody says out loud.

The coupling is the phase difference itself and not its sine: the sawtooth
oscillator rather than Kuramoto proper. It entrains the same way and is
exact in Q16.16, where a sine would want a table and would put a SECOND
definition of `sin` in the ecosystem — the argument the RBF beat already
made about `exp` this morning.

Only a user channel may be synchronised, refused by name otherwise: a phase
is the row's own state, and the user channels are what the neighbourhood
snapshots. Which is the load-bearing part — neighbours' phases are read
from the SNAPSHOT, so the spray now copies the user channels beside the
positions at build. A live read would have row 1 seeing row 0's new phase
and row 0 seeing row 1's old one: Gauss-Seidel where the sweep promises
Jacobi, and an answer depending on the order chunks happened to run in.
Second time today the same bug tried to happen, and the second time the
same gate shape caught it.

Two refusals, both `relax`'s: a NEGATIVE coupling (that drives neighbours
apart, which is a different word) and `couple · dt > 1` (the pull is at
most half a turn, so that steps past what it was leaning toward).

**Gate:** "two coupled rows meet at their mean exactly" — half the coupling
closes half the gap from both ends, so an eighth and three-eighths land on
a quarter, exactly, in Q16.16. Then an uncoupled pair that does not move; a
pair either side of the WRAP that meets at 0 going opposite ways; and drift
advancing and wrapping. **Mutations three, all bitten:** neighbour phases
read live; `wrapHalf` dropped; the wrap into [0, 1) dropped.

**Two things the gate taught, both mine.** The wrap case was missing at
first, so `wrapHalf` dropped SURVIVED — a pair an eighth apart never
crosses the seam the function exists for. And the wrap case then failed on
correct code because its tick skipped a frame: the fed delta was two
seconds, every step doubled, and the pair sailed past each other. `relax`
and `sync` both scale by the fed delta, which is the whole point of them,
so a gate that changes it by accident is testing a different program. A
third mutation — the row's OWN phase read live — does not bite and is
recorded as not biting: nothing has written that row's phase when its
kernel runs, so the two reads are the same number, and the snapshot is
chosen for uniformity rather than correctness.

**Seen running.** `kernels/motes.rill`: 5600 rows, a frequency gradient
along x plus per-row jitter from `row.seed`, reach 0.75, coupling 6. The
order parameter says it plainly — global R = 0.468 while the x-slabs run
0.35 to 0.89, and the mean phase ramps 0.29 → 0.59 → 0.81 → 0.39 → 0.61
across the cloud and wraps. Local coherence far above global, with a
spatial phase ramp, is a travelling wave and nothing else. Nothing in the
kernel makes a wave; every row is a lone oscillator that can see about
forty neighbours.


**The appearance contract, 2026-09-07.** Christian: *"dependency on loam
isn't needed, just a loam like interface to fields, and Matryoshka can
provide the bridge as long as the contract is there."* So the contract now
exists and spindrift still evaluates nothing.

A spray declares `Appearance{ coord, manifold }` — which user channels
carry the coordinate, and a NAME the host resolves — and says it on the
plane beside its count and bounds, once, change-only. `manifold` is
resolved by nobody here: matryoshka resolves it to a loam RBF set and reads
it in a shader. That is the seam `World` and `Fields` already have —
spindrift declares it, a host fills it, the mock fills it for the gates,
and no dependency travels in either direction. It also means no struple
decoder anywhere it was not already needed, which was the other half of
the ask.

Until this, what `row.u0`–`u2` MEANT lived in a comment and a reader knew
by agreement — which is precisely how the fire manifold got authored upside
down that morning with every number still in range and the picture the only
witness. A declaration is the fix for that class of bug, not more care.

**Gate:** says nothing until there is something to say (a spray whose rows
mean nothing in particular must not publish a default a host could read as
a promise); says it when set; does NOT say it again on a tick that changed
nothing; says it again when a host changes it; refuses a channel the
population has not got, at the door. **Mutations three, all bitten:**
`said_appearance` never set; the change-only guard dropped; the channel
check dropped.

**Found:** the first cut cleared the mock's store to check "not re-said"
and LEAKED — the store owns those bytes. The change-only claim is
observable without touching it, because a re-write replaces the allocation:
the same pointer still being there is the assertion, and it costs nothing.

## The neighbourhood, rebuilt — 2026-09-08

**The complaint.** The playground's fireflies cost **44.5 ms a tick for 2481
rows** — 18 µs a particle, which as Christian put it is a number you have to
work quite hard to get. The note left the night before blamed the cell being
1 m against a reach of 0.75. That was a quarter of the answer and the wrong
quarter to lead with.

**Measured first, in Debug, because Debug is the target.** `drift-run`
reproduces the scene exactly (`--rate 550 --speed 0 --spread 0.7 --life 4500`
gives 2482 rows; `spread` is a VELOCITY draw, so this is a 6 m cloud at ~11
rows/m³ and not the degenerate pile the note assumed). A temporary probe over
the six phases and inside `gatherNear`:

| phase | µs/tick | | `gatherNear`, per row | |
|---|---:|---|---|---:|
| broadcasts | 13 | | candidates examined | **521** |
| materialise | 0 | | kept | 52 (10%) |
| spawn | 0.5 | | rejected on distance | 338 (65%) |
| build | 76 | | rejected on CELL, not bucket | **130 (25%)** |
| **sweep** | **17,558** | | cell probes finding an empty bucket | 17% |
| reap | 11 | | | |

The same scene with `near`/`sync` deleted from the kernel sweeps in 611 µs.
So `near` was **96% of the tick**, and everything outside the sweep was
rounding error. Two numbers in that table are the diagnosis: nine candidates
in ten were thrown away, and a QUARTER of them for no geometric reason at all
— they were rows the hash had put in the bucket, not rows the geometry had
put near.

**The complexity.** Per row the cost is `27 · cell³ · ρ · c` against useful
work of `(4/3)πr³ · ρ`, so the waste is `6.44 · (cell/r)³` — 15× at cell 1 m
and reach 0.75, which is the measured 10% hit rate. And since a life-bounded
emitter has a roughly fixed volume, `ρ ∝ n`: the search is **O(n²)**, because
`MAX_NEIGHBOURS` caps what a query KEEPS and never what it SCANS.

**Three changes, one idea: build it the way the lattices already are.**
`Lattice` is a dense grid over the spray's bounds that coarsens until it fits
and says so. The neighbourhood hashed into a masked bucket table instead, and
paid for it three times.

1. **Dense, not hashed.** A hash needs a cell-equality test per candidate to
   undo its own collisions; that test was rejecting a quarter of everything
   examined. A dense cell index cannot collide, so the test is gone, the
   per-row `neigh_cells` array is gone, and an empty cell is an empty range
   instead of somebody else's rows.
2. **The cell follows the rows.** Derived from the live bounds to at most one
   cell per live row, stepping ×3/4 from a cell wider than the extent.
   Halving multiplies the cell COUNT by eight, so the target can only be hit
   to within that — measured, halving left the tick at 3.73 ms where
   three-quarters reaches 3.59. Occupancy 4 → 2 → 1 gave 4.23 → 3.73 → 3.59.
3. **The payload rides along.** `Item{pos, id}` in cell order, so the
   candidate loop is a sequential walk instead of chasing `neigh_pos[other]`
   by row id into another array.

And a fourth that fell out of being dense: **x is the contiguous axis, so a
whole RUN of cells along x is one range.** A 3×3×3 neighbourhood costs nine
range lookups, not twenty-seven — and the range itself is computed from the
radius rather than fixed at 3×3×3, which is why `near` no longer refuses a
wide radius (see below).

**Before that, the cheap half, and it is the one worth remembering.** The cap
was being enforced on the STORE and not on the SCAN: `gatherNear` walked the
rest of the cell to discard every row past the 64th. `near` reports the
capped count and hands on the first `MAX_NEIGHBOURS`, so stopping there is
**bit-identical** — same 64, same `crowded` — for a fortieth of the work in a
crowd. 39.4 → 17.4 ms on its own, with the digest unchanged to prove it.

**Result, Debug, `--jobs 1`, whole process:**

| | crowd (playground's) | spread |
|---|---:|---:|
| morning | 39.4 ms | 16.8 ms |
| + cap stops the scan | 17.4 | 12.1 |
| + dense grid | **3.8** | **3.4** |

Candidates per row went 521 → 197 with the cell rejects at zero, and range
lookups 15.7 → 11.6 while covering a far larger volume. In the engine, same
scene, same 420 frames: **44.506 ms → 2.470 ms** (ReleaseFast; the 44.5 was
Debug, and ReleaseFast is a data point here, not the target).

**A refusal deleted.** `near` refused a radius wider than the cell, and had
to: the search walked a fixed 3×3×3, so a wider radius would have MISSED rows
rather than found them. The range is the radius's now, so the refusal went
with the constant that made it necessary. This is a prior decision reopened
on Christian's standing rule — they keep us honest, they are not sacred.

**Found while writing the gates, not by running them.** `sizeGrid` first
started its search AT the widest extent, which gives dims of two on every
axis — eight cells — and a spray of capacity four has room for five. Nothing
downstream would have said a word. It now starts WIDER than the extent, so
the grid is one cell whatever the rows are doing and only ever steps to a
size that still fits; `cellCount() <= grid_starts.len - 1` is true by
construction, and asserted.

**Gates.** One new (`near`: the cap stops the scan) and two rewritten, both
because the rewrite invalidated their claims rather than their subjects — the
at-scale gate's bucket-SPREAD assertion became a grid-CUT assertion plus "the
grid holds the live population exactly once", and the radius-refusal gate
became a wide-radius-is-ANSWERED gate. **Mutations eight, all bitten:** the
early-out one row early; the distance test dropped; `crowded` left false; the
x-run ending at `hi[0]` instead of `hi[0] + 1`; `sizeGrid` never refining;
`cellOf` dropping the z stride; the row counting itself; the cell range
clamped back to the old ±1.

**Two gate-writing lessons, both mine, both from mutations SURVIVING.**
The first cut of the cap gate put all 100 rows on one spot, and two of its
four mutations walked straight through: with one populated cell, cell VISIT
ORDER cannot show, and with the far rows at high ids the cap fills before the
distance test is ever reached. It needed three groups in two cells, with the
too-far rows scanned FIRST. And the prefix assertion (`capped == uncapped
cut short`) is only self-consistent — reorder the cells and both halves move
together. Which 64 a crowd hands on is a picture, so the gate names them.

### And then the chunk

**The last of it, same day.** The sweep chunked at `DEFAULT_CHUNK = 1024`, so
2482 rows were 2.4 chunks over the engine's THIRTY workers — a tenth of the
machine, and why the engine's Debug tick (5.12 ms, 30 workers) was slower
than drift-run's single thread (3.78 ms) on a lighter kernel. Christian:
*"it was just something we pulled out of thin air ... there is no rhyme or
reason it is what it is, and memory isn't tight. Better to go too big than
pretend we are running on a Z80."*

The chunk is TWO units wearing one name — the sweep's work division and the
host's dirty-upload granularity — and 1024 was a cache number (≈80 KB of row,
inside L2) serving only the second. It is cut from CAPACITY at init now:
`clamp(capacity / TARGET_CHUNKS, MIN_CHUNK, DEFAULT_CHUNK)`, 256 chunks, 32
rows apiece at the playground's capacity.

**Measured**, fireflies scene, 2482 rows, 30 workers, Debug, µs a tick:

| chunk | 1024 | 512 | 256 | 128 | 64 | 32 | 16 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| | 2860 | 1833 | 1304 | 1052 | 925 | **895** | 953 | 952 |

Both clamps are load-bearing and neither is about cache. The floor: a small
spray asks for `capacity / 256 = 0` rows a chunk and `sizeChunks` divides by
it. The ceiling: `DEFAULT_CHUNK` is the number matryoshka sized its staging
buffers from (`spray_bridge.zig` allocates that many `GpuParticle` and
asserts the chunk fits), so a bigger chunk runs off the end of them.

**The bug this beat is actually about, and it is the good one.** The first
cut derived the chunk from the JOB SYSTEM'S WORKER COUNT — a strictly better
number, since the machine is what the division is for — on the first tick,
because that is when a `JobSystem` is first in hand. Every gate passed, the
suite was green, the sim's digest was identical at every chunk size and
worker count, drift-run went 2860 → 912 µs, and the engine went 5.12 → 1.36
ms with the GPU frame and the traversal split unchanged to the last digit.

**And the picture was empty.** No fireflies at all.

matryoshka allocates `run_n` from `spray.chunk` when it takes the spray, and
then:

```zig
const dirty = l.spray.dirtyChunks();
// Before the first tick the sim has no chunk table — and no rows.
if (dirty.len != l.run_n.len) continue;
```

Deriving on the first tick moved the chunk AFTER the host had sized from it —
8 entries against 242 — so the upload skipped that spray silently, every
frame, for ever. **A number a host builds on has to be final before the host
can read it**, which is why it is capacity-only and at init: the worker count
is the better number and it cannot be had in time.

**How it was caught, and how it nearly was not.** `Perf: sprites 0.09ms →
0.00ms` was in the output of the very first run and I read past it. The
frame-difference metric said 21.5% of bytes differed with a mean delta of 27,
which I explained to myself as additive blending being order-sensitive — a
plausible story for a real number, which is the most dangerous kind. What
settled it was looking: two frames side by side, particles in one and none in
the other. Same lesson as the playground's shadow the day before, and the
same instrument. Before that, the run-to-run check earned its keep too — the
engine is byte-identical across two runs of one binary, so the difference
could not be blamed on timing.

**What the chunk legitimately does change.** The engine's frame is not
byte-identical across chunk sizes, and should not be: a chunk's live rows are
packed into runs and each run is a BVH leaf, so the chunk decides the order an
additive sprite pass accumulates in, and float addition is not associative.
Measured against the 1024 baseline, the difference is 92% of the glow-core
pixels at a mean delta of 6/255 and **zero** outside the glow — sky, ground
and geometry untouched, mean exposure and saturated-pixel count unmoved. The
SIM is bit-identical: `fireflies.rill` through `drift-run` gives digest
`128740cb7ccea4a2` at chunk 1024, 34, 32 and derived.

**Gate:** the chunk before any tick and after one; the floor on a small
spray; the ceiling on a large one; `dirtyChunks().len` agreeing with it, which
is the assertion that would have caught this; and a host's `setChunk`
surviving a tick. **Mutations four, all bitten** — the ceiling only after the
gate grew a spray big enough to WANT an oversized chunk, which is the same
lesson as the crowd in one cell: a clamp cannot be tested by data that never
reaches it.

## `infect` — the thirteenth word, 2026-09-08

funideas §6, the entry beside `Synchronise` that had not been built:
*"transfer a state variable between neighbours. Now you've got spreading
fire, bioluminescence, chemical reactions, disease, magic, whatever."*
Everything it needed was already here — the neighbourhood, the slate's handle
lane, and the user-channel snapshot `sync` reads — so it is thirty lines.

`infect row.uN <rate>`: a row closes `rate · dt` of the gap to the HIGHEST
value among the rows `near` found.

**Two decisions, and both are about what the word refuses to be.**

**The maximum, not the mean.** A mean is diffusion — it is `relax` toward a
neighbour average, and it smears a peak into a haze. A maximum is
transmission, and it makes a FRONT. Watching a front cross a cloud is the
thing this word is for, and the gate's numbers are chosen so the two answers
differ: a row seeing a 1 and a 0 goes to 0.5 under a maximum and 0.25 under a
mean.

**Monotone, so recovery is somebody else's job.** A row among cleaner rows
does not get cleaner; you catch it from somebody who has more. Healing is a
separate fact with its own rate and `relax 0 <rate>` was already the word for
it. Written as one operator with two rates it would have worked and hidden
the number worth playing with — because `spread` against `heal` is an
epidemic threshold, and `kernels/kindle.rill` shows it plainly: at 0.5 only
the sources glow, at 2 the light propagates without taking, at 8 the whole
cloud catches. One picture, three renders, two numbers.

It adds its step rather than replacing (unlike `sync`, whose phase wraps), so
it composes with the recovery line and with anything else a kernel does to
the channel.

**Gates two:** transmission on a four-row line — half the gap to the maximum,
the source not dimming, a row out of reach untouched, and a second tick to
tell `add` from `replace` (0.75, not 0.25); and the three refusals (not a
user channel, a negative rate, a rate that would overshoot a whole gap).
**Mutations six, all bitten.**

**And one that took two tries to write.** "The monotone rule dropped" is not
a mutation of either half on its own: `best` is seeded with the row's own
value AND the write is skipped when nothing beats it, so removing either
leaves the property standing. Only removing both bites. That is belt and
braces in the code and a trap in the gate — a reader tidying one away would
find everything green — so the gate says so where the mutations are listed.

**Found:** the G2 parity gate caught the missing manual row the moment the
word was registered, before a single test of the word itself ran. That is the
gate doing exactly what it is for.

## `align`, and the flocking trio — 2026-09-08

Christian: *"Boids… flocking behavior with avoid. Or cockroach particles on
the floor, and scattering and regrouping. They are kind of the same thing."*
They are the same kernel, and two thirds of it already existed.

**Separation is `push`. Cohesion is `push` with a NEGATIVE gain** — the
arithmetic is identical and only the direction differs, which is why `push`
never had a sign guard and does not get one now. **Alignment** is the only
one that needed anything, and what it needed was not a word but a FIELD: the
neighbourhood snapshotted positions and user channels, and a flock has to
know which way its neighbours are going. `neigh_vel`, filled in the same
pass, and `align <k>` steers by `(mean(other.vel) − vel) · k · dt`.

**The mean, and `infect` takes the maximum** — the two words are opposites on
purpose. Alignment is a consensus, so one fast row must not drag the flock;
transmission is a front, so one lit row must reach everybody. Each gate picks
numbers where the two answers differ, so neither can quietly become the
other.

**Two radii for free.** A flock wants a tight ring it will not crowd into and
a wide one it belongs to, and one `near` gives one ring. Two `near` lines do
it — a `push` or an `align` reads whichever `near` is nearest ABOVE it,
because the slate resolves a consumer to the last publisher above it. That is
the slate's own rule doing a job nobody designed it for, and it cost nothing.

**Scatter and regroup is one number crossing zero.** `kernels/boids.rill`
takes its cohesion gain from `plane.drift.@self.k.flock`, and
matryoshka's `rills/scare.rill` is one `lfo` line swinging it −5 → +3 over
seven seconds. Nothing in the kernel knows it moved: it reads a knob, as it
always did. Measured through `drift-run`'s grid readout — the line added
this morning for a different reason — cohesion gives `grid 864@1.37` and
scatter `grid 1000@7.90`: six times the extent, from the sign.

**Gates two, mutations six, all bitten.** The behaviour gate is four rows on
a line whose mean and maximum disagree, and its load-bearing assertion is the
row that must NOT move: row 0's neighbours average exactly its own velocity,
so a missing `− mine` moves it and nothing else would show. **A gate on a
floor, not just a value:** a lone row out of reach steers nowhere, which is
what catches the dropped empty-handle return before it divides by zero.

**Found, twice, and it is a host problem rather than ours.** A kernel using a
word matryoshka's binary predates fails to mount, and an unmounted spray is
pinned to rate zero — so the scene runs, says nothing, and shows nothing. It
happened for `infect` and again for `align`. The engine says nothing on a
mount failure; the symptom is `0 live rows` and no other word. RECORDED,
trigger: the next time it costs more than a rebuild.

## `deposit` — the sixteenth word, and §8 — 2026-09-08

funideas §8, which the doc itself calls out as the big one: *"a particle
shouldn't necessarily disappear without consequence… particles become the
transport mechanism connecting simulations."*

**The spray already cast, and a cast is the wrong shape for this.** `casts`
is ONE standing aggregate the host replaces every tick — where the cloud is,
how much of it there is. A mark is the opposite on every axis: many per tick,
at the rows' own positions, added rather than replaced, and it outlives the
row that made it. The mock store had carried an `aggregate: bool` on every
stored deposit since the cast door was built, so the model had been waiting
for this; `deposit` is the other value it was always for.

**`Fields.depositFn` is OPTIONAL and that is the design.** A host that has
built nowhere for marks to go leaves it null and a kernel that deposits is
refused BY NAME, counted in `Stats.deposits_refused`. Same shape as `World`,
`Fields` and the appearance manifold: spindrift declares the seam and
evaluates nothing, matryoshka keeps compiling untouched, and nothing writes
into a hole. `error.NoDeposits`.

**One slot per row, flushed serially in the cast phase.** The sweep is
parallel and a store is a store, so the row only ASKS — `dep_amp[row]` — and
`flushDeposits` walks the slots in row id order during the cast phase and
hands them over. Row id order is what makes the marks land the same way on
every machine. One slot per row means a row leaves ONE mark a tick, and mount
refuses a second `deposit` rather than letting the second silently overwrite
the first for every row.

The radius is the row's own `size`, which is the only honest answer — a mark
is as wide as the thing that left it — and a row with no size leaves nothing.
A negative amount is a mark too: a field sums its deposits, so a raindrop on
hot stone deposits negative heat.

**Seen working.** `kernels/soot.rill` is `collide | stick` and
`row.stuck | mul k | deposit $soot` — the amount IS the condition, so an
airborne row asks for nothing. After 300 ticks the ear reads **4.59** under
the fire, **0.56** a metre out, **0.00** at three metres and 0.00 four metres
up. A stain, where the embers actually landed, outliving them.

**Gates two, mutations six, all bitten — and three of them only after the
gate was rewritten.** The first cut asserted in a comment that it ran a cast
and a deposit on one store and never did, so "a mark stored with the
AGGREGATE flag" walked straight through; the count could not catch it either,
because `castThunk` replaces IN PLACE and the length is the same both ways.
What catches it is counting what the entries ARE: twelve marks and one
aggregate. "The slot never cleared" needed a kernel that STOPS asking while
still mounted (`deposit $soot row.u0` with the channel zeroed), because
re-mounting a kernel without `deposit` clears `dep_channel` and the flush
never reads a slot at all. And the dead-row check needed a row actually
reaped on a depositing tick — life is converted to TICKS at spawn, so the
scene runs on until the reap happens rather than assuming the next tick.

Three gate-holes in one word, each found by a mutation surviving. That is the
third time today, and it keeps being the same shape: the gate asserts the
thing that is easy to assert rather than the thing that is claimed.

## A row is a SPHERE — `collide` takes a radius — 2026-09-08

**Measured first, in matryoshka's playground.** A sphere and a box rest on
the floor at y = 0; `roaches` walk that floor and pass straight through
both. From a live population dump: the density inside the props' floor
footprints is **1.1–1.3× the density of a control annulus at the same
radius from the swarm centre** — not reduced blocking, *no blocking at
all*. The cause is geometric and certain. The props occupy y ∈ [0, 1.5] and
y ∈ [0, 1.1]; the rows rest at y = 0 exactly (755 of 790 in the dump). At
y = 0 the sphere is a single tangent point and the box's bottom face is
coplanar with the row's path — so a **zero-width point travelling through
the one height where both props have no cross-section** hits nothing. No
nudge to a prop's height fixes the class of that, which is why the ruling
was to fix it properly: *a row is a sphere of `size`, and collision should
treat it as one.*

**The seam.** `world.zig`:

    collideFn: *const fn (ctx, from: Vec, to: Vec, radius: Fixed) ?Hit

`groundFn` is unchanged. `collide` passes the row's own `size`, so nothing
new is authored and no kernel changes: the radius is the field the
appearance already draws with and `deposit` already marks with, because a
row with two widths would be two rows.

**Rule 1 — `r = 0` is the old point test, bit for bit.** Christian's words:
*"We can still preserve the cheap point test."* Both mocks get the radius
by moving the plane the CENTRE is tested against, not by a second branch:
`Floor` tests against `self.y + r`, `Plane` against `depth − r`. At r = 0
those are `self.y` and `depth`, the same arithmetic and the same bits, and
a host implementing this may not carry a "safety" epsilon into that path —
G0's byte-identity and the campaign's G7 bit-identity claim are only worth
anything if the zero-radius answer is unchanged.

**Rule 2 — `at` is the sphere's CENTRE at contact, not the surface point;
`normal` stays the SURFACE normal.** `stick` and `slide` both write
`pos ← at`, so a surface point would put the row's centre ON the wall and
the next tick's sweep would start already interpenetrating — the same bug
in a new hat. A landed row's centre therefore rests one radius off the
surface. **`stick` and `slide` learned nothing** to make that true: they
write the point they were handed, which is the test that the rule is in the
right place.

**Rule 3, recorded and NOT built here — ruling 27b is now a double count.**
27b put the resting offset in the APPEARANCE: a landed row is drawn at
`pos + normal · size`, one rule for every row with no stuck branch, so a
landed row that shrinks stays tangent by construction. The sim now holds
the row a radius off itself, so a renderer that still adds `normal · size`
draws a landed row TWO radii up. **The rule moves into the sim — one rule
instead of two — and matryoshka must draw a stuck row at `pos`, flat,
exactly as it draws a free one.** Written into `spray.zig`'s `Appearance`
(the contract a host reads), `population.zig`'s `normal` field,
`drift-words.md` and the README; the renderer is matryoshka's and is a
separate beat. What 27b bought and this costs: a row that shrinks AFTER
landing keeps its landing centre and lifts off, where the renderer's rule
recomputed the offset from the live size every frame. Recorded, with a
trigger — the first customer scene where a landed row shrinks enough to see
it (fire.rill's embers shrink by 0.3 cells, a tenth of a metre, under the
pixel) — and the fill is a sim-side re-rest, `pos ← pos − normal · Δsize`,
which is state owing a dump and is why it is not free.

**`ground` gets NO radius, and that is a decision, not an omission.**
`collide` had to take one because its answer is a POSITION the row adopts,
and a position that ignores the radius is a position inside the wall.
`ground` answers a distance and a normal; nothing moves to them. So every
number a `World` hands back stays about the row's CENTRE — one convention
rather than two, where a `ground` that quietly subtracted the radius would
answer clearance while `collide` answered centres and a kernel reading both
would have to know which was which. The clearance under the BODY is already
spellable at the row, exactly and with no new word: **`ground | sub
row.size`** (`sub` is rill core and row-legal). It costs a host nothing —
`groundFn` is untouched, so matryoshka's compiles as it stands. Recorded
with its trigger: the first word that PLACES a row from `ground`'s answer —
a `settle` or a `hover` — is placement, not measurement, and wants the
radius the way `collide` does.

**The mocks' conventions, restated for a radius.** A crossing is the SPHERE
going from clear-or-touching to overlapping. *Ending exactly TOUCHING is
not a crossing* — the point on the wall is on the wall, and a landed row
asks again every tick and must not be told "you are hitting me" for ever.
That one turns out to be load-bearing rather than tasteful: a resting row's
segment is `from == to`, and the test is the only thing between that and
`fromRatio(0, 0)` (the mutation that flips it to `>` does not fail the
resting gate, it CRASHES it). *A sphere found OVERLAPPING is pushed back
out along the normal until it just touches*, at t = 0 — the resume of
2026-09-07, one radius further out.

**Ruling 20 (B), still open, and what the radius did to it.** Nothing: the
sliver is `g · dt²` of the CENTRE, and the centre does not care how big the
row is. What changes is what the sliver LOOKS like — at r = 0 a row inside
the surface is a row under the floor; at r > 0 it is a sphere dented by
`g · dt²` with its body still mostly outside, and the resume presses the
dent out every tick. So the radius shrinks the symptom by the ratio of the
sliver to r and removes nothing. The fix is still to test the segment the
integrate will actually take.

**Gates, eight, and every mutation run per gate rather than as a suite
count.** In `world.zig`, where the geometry lives: (1) *a radius of zero is
the point test, bit for bit* — beat 4's own literals, plus the normal and
the material it never asserted, bitten by `surface = y + r + 1` (an ulp of
"safety") and SURVIVING the radius-dropped mutation, which is the point of
it. (2) *a sphere stops a radius short, and its centre rests a radius off*
— bitten by the radius ignored, by `at` answered as the surface point, and
by the resume placing the centre on the face. (3) *the roaches bug in
miniature* — a centre that passes ABOVE the plane the whole way while the
body crosses it, with the point control returning null beside it; bitten by
the radius dropped, which is the shipped bug reproduced. (4) *the second
mock sweeps its sphere too* — `Plane` is a second implementation and a
radius that reached only `Floor` would leave every sliding row half inside
its wall. In `tests.zig`, driven through kernels: (5) *`collide` sweeps the
row's own `size`* — three radii from one knob (0, 0.25, 1), each landing at
its own radius with its own `t`, held for ten further ticks with no creep
and no sink; bitten by `collide` passing 0, by passing a constant, by
`stick` adding the radius (the double count), and by the sweep's
stuck-velocity hold. (6) *the roaches bug driven through a kernel* — one
kernel, one seed, one schedule, and only the size differs: the sphere is
stopped half way along the tick its body touched and rests at y = 1; the
point sails over, still airborne at y = 0.5, past the far side. (7) *a
negative `row.size` refuses by name* — a negative radius moves the surface
the wrong way, so the row tunnels FURTHER than a point does; bitten by a
`@max(0, r)` clamp and by dropping the guard. (8) *`ground` has no radius*
— the distance is the centre's and the clearance is a kernel line; bitten
by teaching `kGround` to subtract `p.size`.

**Three gates MOVED, examined rather than re-baselined.** The beat-4
landing gate (the row lands at y = 0.5, its size at the landing tick, and
the size it collides with is read from the SNAPSHOT — ruling 20's rule, one
word further along); the negative control (every landed row at y = its
size, 1, since that kernel never writes one); and the wall gate below.

**Found: a mutation that had been a decoration since beat 4.** The slide
wall gate names "`pos ← at` dropped — the row is through the wall" and it
did not bite, on the moved scene or on HEAD (checked in a worktree, not
argued). The scene threw the row from x = 2 at 2 cells/s, so it arrived
EXACTLY on the wall: `d0 = 0`, `t = 0`, `at == from`, and the write put
back the position the row already had. Re-deriving the scene for a unit
sphere is what surfaced it. It is thrown from 3.5 now, the contact is
strictly inside the tick (t = 0.25), and the mutation bites. The other half
of the old scene — "ending exactly touching is not a crossing" — moved to
`world.zig`, where the geometry it is about lives.

**Found: in `Plane`, the radius appears twice and one of them hides the
other.** Dropping it from the crossing test alone leaves `t` wrong (0.5
where it should be 0.25) while the `off` correction — which exists to kill
beat 4's double-flooring ulp — projects the point back onto the offset
plane and makes `at` RIGHT. So that mutation is invisible to any gate that
watches only the position, and the slide gate is one: it survived there and
bit only on the mock's own gate, which asserts `t`. A contact point and a
contact time can disagree, and a kernel reading `t` would have been the one
to find out.

**Seen working, end to end, not only in the gates.** `drift-run` with
`kernels/soot.rill` over the mock floor, 300 ticks, the same seed and the
same knobs on HEAD and on this: the dump's `pos_y` floor moves from
**0.0000** to **0.0501** cells and nothing else in it moves — same live
count, same tick, same age range, same ceiling. soot.rill sizes its embers
`row.seed | mul 0.05 | add 0.05`, so the smallest landed row rests at
exactly its own radius, and the row that used to sit with its centre in the
floor now sits on it.

**What matryoshka must change.** (a) `SprayWorld.collideThunk` gains the
`radius: Fixed` parameter — it will not compile without it — and the swept
query must use it (the parallel beat building the swept-sphere BVH query is
the fill); `groundThunk` is untouched. (b) It must answer the sphere's
CENTRE at contact, not the surface point, and keep the surface normal.
(c) `radius = 0` must take the same path it takes today, bit for bit.
(d) The appearance must stop adding `normal · size` for a stuck row and
draw it at `pos` — ruling 27b's rule now lives in the sim.

## The fifteen words say what they are FOR — tags, 2026-09-09

rill grew `tags` on `OpDef` this morning (rill `8e044ec`): free-form
strings, an operator carries several, it is found under each, and **the
first is its home** — declaration order carries primacy. Christian's
reframe is what settled the model: *"I guess we could view them as filters
huh. So an operator could exist in multiple groups. Think of them as
#tags."* They feed a coming graph-editor palette, a console `help`,
tab-complete and a vocabulary document for an agent to read.

rill tagged its 109. Spindrift's fifteen were not, and `rill ops --tag
untagged --host-row` printed them as a fifteen-line to-do list under the
heading *"nobody said"*. Fifteen untagged words is a bad first palette.

**Eleven tags: six of rill's borrowed, five minted.** The rule for
borrowing was that rill's own SENTENCE had to be true of the word, not
merely nearby — a tag is a `{name, doc}` pair and the doc is what a palette
shows in the tooltip.

| word | home | also | why |
|---|---|---|---|
| `spawn` | `life` | `motion`, `random` | birth is the lifecycle word; it sets `vel`; the ±spread is a seeded draw off `row.seed`, bit-identical, which is `random`'s sentence exactly |
| `perish` | `life` | `time` | the other end of it; the threshold is a duration |
| `gravity` | `motion` | — | the only word in the set that is nothing but a force |
| `relax` | `envelope` | `time` | it IS rill's `ease` at the row — "a value in motion over fed time: it chases" |
| `near` | `neighbourhood` | `space` | `within` asked of a whole population; "what is near what" is rill's own sentence |
| `push` | `neighbourhood` | `motion` | separation, and it adds to `vel` |
| `align` | `neighbourhood` | `motion` | alignment, likewise |
| `sync` | `neighbourhood` | `oscillator` | a phase oscillator; the coupling is what is new, not the going round |
| `infect` | `neighbourhood` | — | transmission; it moves a channel, not the row, so it carries nothing else |
| `deposit` | `sink` | `field` | `cast`'s row-plane sibling, filed with it |
| `hear` | `field` | — | the read half |
| `collide` | `surface` | — | finds one |
| `ground` | `surface` | — | measures to one |
| `slide` | `surface` | `motion` | runs along one, by taking the normal out of `vel` |
| `stick` | `surface` | — | lands on one |

**`stick` is deliberately not `motion`.** It stops the row, but it does not
write `vel` — the SWEEP drops the velocity because `row.stuck` is set. A
tag for an effect the word does not perform is a tag that stops being true
the day the sweep changes.

**`gravity` is not a world-contact word.** The brief grouped it with
`collide` and `slide`; it never touches `World`, it is in `WORDS` and not
`TRACER`, and it is a force. Likewise `relax` is not a lifecycle word: it
is `ease`, and putting it with `spawn` and `perish` would have hidden that
the row plane had already borrowed one of rill's shapes.

**The one word that sat awkwardly is `deposit`, and the awkwardness is
information about the word.** It is a sink and it is a field write, and
those are two different questions a reader asks. Filing it under `field`
beside `hear` would have separated it from `cast`, which is the word it is
a copy of; filing it under `sink` beside `cast` separates it from `hear`.
`sink` won because the kinship with `cast` is Christian's own filing, and
`field` — carried, not home — is what reunites the pair. That is also what
makes `field` a genuine cross-cut rather than a second name for `hear`.

**Two tags where the count is one, and both stay.** `motion` is home to
`gravity` alone and `field` to `hear` alone. rill has the same shape
(`contract` and `rbf` hold two each, and `gate` is home to nothing at all),
and the alternative — folding a one-member home into a bigger one — is how
`misc` gets born.

**Nothing enforced became a tag**, and two names died of it. `#world` for
the tracer four would restate which door registered them, which
`registerTracer` already refuses at mount by leaving the word unknown; a
label shadowing a real refusal is free to drift from it. `#crowd` and
`#contact` are SLATE lane names that mount checks — a tag wearing an
enforced name invites the confusion the rule exists to prevent. `surface`
and `neighbourhood` say what the words are for instead. Every rejected name
is recorded at `TAGS` in `words.zig`, with its reason.

**Sentences, not just nouns.** Each minted tag carries a `TagDoc`, and they
go in through `describeTag` at `words.register`. A second sentence for one
tag is refused there — which means a tag rill later adopts under one of
these five names fails every host at startup, loudly, rather than leaving
two descriptions racing to be the one a palette read last. Christian's own
Blade3D is the evidence: `Physics` declared twice with two descriptions,
`Constraints` misspelled `Contraints`, groups with a Description and no
DisplayName, unnoticed for years.

**Where a human reads them: `zig build run -- --words`.** drift-run has a
`World`, so it registers all fifteen and prints them grouped by home with
each tag's sentence — `rill ops` for the words rill cannot see. `rill ops
--host-row` CANNOT show them and must not be made to: that flag registers
the stubs in `rill/tools/host_row.zig`, which exist so rill's parser can
read a kernel file, and a second copy of this table is a copy that drifts.
The tags live on the registered word, and matryoshka will see them the
moment it registers spindrift's words.

**`row-legal` was left alone, and here is why.** It groups by VERDICT —
row-legal now, stateful candidate, refused — which is the question recon
R-a asks it, and it walks rill's core only (spindrift's fifteen are all
row-legal by construction, so they would land in one bucket and say
nothing). A second grouping by tag would answer neither question well, and
a tag COLUMN would be output no gate watches. The listing that needed
building was the one that did not exist: `--words`.

### The gates, and the mutation each was paid for

All five are exhaustive over `words.WORDS ++ words.TRACER`, in G2's shape,
so a sixteenth word is caught by all of them at once.

1. *G22: every drift word carries a tag, and every tag it carries has a
   sentence* — plus both rosters closed both ways, disjoint from rill's,
   and sorted. Bitten by (a) a typo'd tag, `"spce"` for `"space"` on
   `near`: *"'near' carries tag 'spce', which nobody has described"*, and
   the cross-cut gate fired too. That mutation is the one Blade3D actually
   made. (b) `.tags` deleted from `spawn`: it falls through to `UNTAGGED`
   at the registry's door SILENTLY — rill defaults a tag rather than
   refusing, because a wrong tag shows a wrong tray while a wrong route
   computes on the wrong thread — and the gate says *"'spawn' is untagged
   — spindrift's table declares, it does not fall back"*. That default is
   the whole reason this audit is exhaustive over the table instead of
   trusting `register` to say no. (c) `"gate"` added to `infect`: rill
   DESCRIBES `gate`, so the `tagDoc` branch is routed straight around and
   only the roster check bites — *"'infect' carries tag 'gate', which is on
   neither roster"*. Without (c) the roster half would have been
   decoration.
2. *G22: the first tag is the home — declaration order, never alphabetical*
   — bitten by sorting `push`'s and `deposit`'s tag lists, which is the
   tidying edit that looks harmless: it compiles, every tag is still
   carried, every sentence still exists, gate 1 stays green, and `push`
   files under `motion` beside `gravity`, away from the `near` it cannot
   run without. Each fixture also asserts it WOULD have moved
   (`lessThan("motion", "neighbourhood")`), because `spawn`, `near`,
   `sync`, `perish` and `relax` are alphabetical already and any of them
   would have made the gate a decoration.
3. *G22: the manual's tag tables say what the registry says* — the rows in
   `drift-words.md` are REBUILT from `words.TAGS`, `words.BORROWED` and the
   registry and compared verbatim, both tables, plus a count off the `#`
   sigil so a sixth row cannot be invented. Bitten by rewording one
   sentence in the manual alone ("a row's start" for "a row's beginning"):
   *"the manual has no such row"*, with the row it wanted printed. G2's
   word-table gate now skips `#` rows, and the sigil is a safe
   discriminator because `register` refuses an operator wearing one.
4. *G22: the cross-cutting tags cut across* — `field`, `motion`,
   `oscillator`, `random`, `space` and `time` each COUNTED off the registry
   for two or more distinct homes, measured over core + spindrift because
   that is the registry a host holds and because four of the six span into
   rill's homes (`space` reaches `near` from `within`, `random` reaches
   `spawn` from `noise`). Bitten by dropping `field` from `deposit` — one
   edit, and the tag becomes a sub-name for `hear`: *"'field' is carried
   only by words at home in one place — it is a sub-name, not a
   cross-cut"*. `life`, `neighbourhood` and `surface` are pinned the
   opposite way, as homes (rill's `constant` precedent): everything
   carrying them is at home under them, so if one ever spans, that is a
   finding about the word that moved.
5. *G22: `--words` prints the fifteen under their home tags, each heading
   carrying that tag's sentence* — the human end. Bitten by (a) filing on
   `def.tags[def.tags.len - 1]` instead of `def.home()`, which compiles and
   still prints seven groups of fifteen: *"no heading 'life (2) — ' in the
   listing"*; and (b) printing the heading as `"{s} ({d})"` with the
   sentence dropped, which is a palette of bare nouns with no tooltip —
   same red. `reg.tagDoc(h) orelse "(no sentence)"` is NOT a mutation here
   and is not claimed as one: every tag on a registered word has a
   sentence, so the fallback is unreachable and the code routes around the
   edit.

**What matryoshka gets, and it needs no change to get it.** Its console
`help` and any palette it builds group spindrift's words the moment they
are registered; the tags come off the registry, not off a table over there.
Its own `(verb, subop)` vocabulary already organises itself, because rill
prepends a two-word name's first word as the home.
