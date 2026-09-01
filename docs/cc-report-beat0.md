# Beat 0 — the population is deterministic before it is rill

*CC, 2026-09-01. Against `docs/cc-brief-spindrift.md` and the campaign.
Built on rill `d4ebe12`, common `9a75dfb`, struple `d937815`; matryoshka
`cda0fd4` read, not touched.*

## What was built

**`ef0a68a` — the skeleton, and two recons before anything is built.**
The repo in the siblings' shape (dual license, CLA, `build.zig` with path
deps on rill, common and struple, `CLAUDE.md` in the house shape before
the first commit). Two recon docs in `docs/recon/`:

- **R-a, the `row` routing.** rill has *two* routing classes, not three;
  routing crosses the C seam as a boolean; rill refuses a `def` as a
  section body, so a kernel is a flattened def driven per row by an
  evaluator that lives in spindrift, not in rill's sweep. The row-legal
  list is executed, not written: `zig build row-legal` walks the registry
  and prints 49 pure operators that pass outright, 34 stateful candidates
  the registry cannot size, and 25 refused by their fields. Of the
  campaign's nine named words, five pass now; `noise` passes with the seed
  bound to the row; `ease`/`kick`/`adsr` carry fed-absolute f64 state
  (26–34 bytes) that no row can carry as encoded — true of the arithmetic,
  false of the encoding. "Refuse at mount" is the parser, earlier than
  mount, and today nothing refuses. Verdict: the `row` routing cannot land
  inside P0 honestly.
- **R-b, population and scheduler.** The SoA layout matches
  `parallelFor`'s index-range contract with no gather. Q16.16 with the
  lattice cell as the integer part (a pure lattice integer cannot move a
  third of a cell per tick). Three phases, only the kernel parallel,
  because freelist push order is what the next spawn's ids are a function
  of. A live-rows-only struple dump. `drift-run` in this repo, since rill
  cannot mount an emitter it does not know about. Matryoshka has two
  lattices and the dyadic one is the right target for a position.

**`3fe3053` — P0: population and determinism.** `fixed.zig`,
`population.zig`, `world.zig`, `dump.zig`, `emitter.zig`, `run.zig`, the
gates in `tests.zig`, `tools/read_dump.py`, the ledger and the README.
27 gates green in 12 ms. `zig build verify-dump` has the struple Python
port read a real dump with no spindrift code on that side. `drift-run`
mounts an optional `.rill` beside the emitter on rill's mock plane and
takes the knobs from `plane.drift.@em.*` each tick — the CHOPs layer of
§3.3 driving a P0 emitter with zero new rill.

**G0 is green and bitten.** Same script twice is the same bytes; a
perturbed seed is a different population with the same ids; four workers
over sixty-four chunks with a thousand spawns and deaths a tick cannot
reach the result, five runs over.

## What each mutation caught (11/11)

| mutation | caught by |
|---|---|
| row seed ignores the emitter seed | G0's perturbed-seed gate |
| perish inside the parallel kernel | **the chunking gate**, after it was rescaled (below) |
| gravity dropped | gravity; the negative control (nothing fell below y = 0) |
| spawn fraction dropped each tick | spawn: 1, 2, 1, 2 became 1, 1, 1, 1 |
| perish on `>` not `>=` | perish; freelist |
| dead rows in the dump | both dump gates |
| floor counts a segment ending on the surface | floor collide |
| `fixed.mul` truncates toward zero | fixed products |
| freelist seeded ascending | four gates that hardcode ids, as they should |
| generation not bumped | handle; perish |
| kernel walks the dead too | spawn's row-steps assertion, after the fix (below) |

**Two findings, both the ledger's shapes.** The chunking gate — whose
comment claimed to force perish serial — *passed* under the
perish-in-the-kernel mutation at 64 rows in chunks of 8; two
single-threaded gates caught it for the wrong reason. A gate that watches
for a race must run where the race can happen: it now runs 4096 rows in
chunks of 64 and is the gate that bites. And the kernel-walks-the-dead
mutation survived outright while row-steps were *assumed* from the live
count — the budget unit was a number nobody counted. The kernel now counts
its own steps per chunk into chunk-indexed slots, summed after the join,
and the spawn gate asserts steps equal live.

One more from running, not mutating: at `--fixed-dt 50` the emitter
spawned 19 where 20 were owed, because dt truncated to Q16.16 is 49.99 ms.
Motion may carry that; a count that G1 thresholds on may not. The spawn
accumulator is exact in `rate × dt_ns`; the kernel's dt stays Q16.16.

## Recorded, not built

| what | trigger |
|---|---|
| the `row` evaluator and the rill-text kernel — the stand-in is deleted | P1 |
| a caller for `World.collide` / `ground` (the floor exists and is gated) | P4's `collide`, after its read-aloud |
| `drift/<@em>/count` on the plane; absence said on unmount | P1, G1 |
| the row-legal registry column and its both-ways audit | P1, after R-a forks 1–2 are ruled |
| chunk size as a knob (1024, a constant) | the first customer scene that moves it |
| exact-arithmetic row kernels per word | the first scene that misses budget, or G7 |

The stand-in did not grow a second word. No rendering, no fields, no
GPU-shaped anything, no inter-particle anything, no wall clock.

## Needs a ruling

Beyond §7, from R-a and R-b, each stated as a fork with a lean in the
recon:

1. **`row` as a third `Routing` value or a second column** (R-a fork 1).
   Lean: column — the thread question and the multiplicity question are
   independent, and the seam stays a boolean.
2. **What the column carries** (R-a fork 2). Lean: a record with the user
   channels the op's row state needs and an exactness bit, because the
   state sizes are the whole question.
3. **The kernel's spelling** (R-a fork 3). `def ember { … }` is not rill's
   def grammar; needs a read-aloud before a parser.
4. **The tenant's name** (R-a fork 5). `emitter` is matryoshka's sound
   emitter, `sarche` its archetype.
5. **Which lattice `pos` addresses** (R-b fork 1). Lean: dyadic Q16.16
   cells; the gauge lattice is a multiply at the leaf boundary.
6. **A fact for §7.3.** Bit-identity across evaluators holds for `+ − × ÷`
   and fails for the transcendental words unless they get integer kernels
   (R-a §5). Not a P0 or P1 question; a bit the column should carry when
   it lands.

§7.5 (`$wind at pos`) is read in R-a fork 4 as consistent with the
standpoint ruling — the emitter's declared ear is the instrument, `at pos`
names where within it — and held for P2's brief.

Nothing in P1 starts until R-a is read and §7.4 is confirmed.
