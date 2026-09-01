# Implementation notes — the ledger

**Status:** P0 (population and determinism) built, G0 green and
mutation-bitten. 2026-09-01.

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
