# CC brief — Spindrift, beat 0

You are starting a new repo: `~/dev/spindrift`, a standalone Zig library beside `~/dev/rill`, `~/dev/spark`, `~/dev/common` and `~/dev/matryoshka`. Read `docs/spindrift-campaign.md` first; it is the plan and this brief only tells you where to start and what not to do.

## Who does what

Christian holds the verdict function: he sets evidence standards, rules on naming and semantics, and decides when something is done. You build to gates. Claude Chat holds the rulings against the code. Rulings live in the campaign doc §7; the ledger is `docs/implementation-notes.md` in this repo, started on day one, same rules as rill's.

## Read before writing anything

- `~/dev/rill/docs/implementation-notes.md` — the ledger rules. They apply here unchanged.
- `~/dev/rill/docs/rill-spec.md`, `rill-tier2.md`, `rill-casts.md` — the language you are extending, and the admission discipline for words.
- `~/dev/rill/src` — the registry (routing is a comptime-required per-op field; `routesToMain` derived), the standing wire gate, the argument-spelling gate, the typing gate. You will be adding a routing class; know how the existing three are wired first.
- `~/dev/matryoshka` — the archetype spine and its most recent tenants (sensor S5, prim, actuator, chanarche, ears, derive). The emitter is the eleventh. Note how each tenant was compelled into three-format serialization by the spine's completeness gates.
- `~/dev/common/jobs.zig` — the one JobSystem. Do not make another.
- `CLAUDE.md` in each of those repos — the working rules carry over. Write this repo's `CLAUDE.md` in the same shape before the first commit.

## Standing rules (from the other repos, restated so they are here too)

- Don't run the full test suites or the GPU sweep for small changes. Slim named repro runs. The acceptance sweep gates behaviour, not appearance; appearance changes need a capture.
- Prose approves plausible semantics; execution approves actual semantics. A gate is an executed program. A mutation must bite; a mutation that doesn't compile is not a mutation.
- Read-aloud before naming; record rejected names.
- Recorded-not-built needs a trigger. Fill, don't work around; a deferred fill gets a pointer, never a rule.
- Loud, never a guess. A refusal lands on the node that refused it.
- Time is fed, never read. No wall-clock anywhere in the sim.
- Docs ride the same commit.

## Beat 0: reconnaissance, then population

Reconnaissance first, because it parallelises and building doesn't. Two recons, each a short doc in `docs/recon/`:

**R-a — rill routing.** Price the `row` routing class (campaign §3.3). What does adding a fourth routing touch: registry struct, dispatcher, the comptime gates, the manual index gate, `rill-run`? Which existing operators are row-legal by the stated test (elementwise, state fits in row user channels) — produce the list from the registry, not from prose. Where would a row-legal column live and how is the predicate derived from it. What breaks if a `row` op is piped in a non-row program (should refuse at mount — confirm the mechanism). Flag anything that would need a ruling beyond §7.

**R-b — population and scheduler.** Confirm the SoA layout in §3.1 against what `jobs.zig` wants for chunking; propose chunk size; confirm the freelist keeps ids stable for a row's life; propose the dump format (must be byte-comparable across runs and readable from Python, since the struple Python port gives a free cross-language reader); check what `rill-run`'s mock plane needs to host an emitter with a floor `World`.

Then build P0: repo skeleton (`build.zig` with path deps on `../rill`, `../common`, struple), `CLAUDE.md`, the ledger, population format, freelist, dump, mock `World`, and G0 green and mutation-bitten. P0's kernel is `spawn`/`gravity`/`perish` and nothing more. If R-a says the `row` routing can't land inside P0 honestly, P0 may use a Zig-native stand-in kernel — recorded in the ledger as a stand-in that P1 deletes, with the trigger being P1 itself. Do not let the stand-in grow a second word.

## Rulings status

- §7.1 (name, `drift/` prefix): ratified.
- §7.2–7.10: proposed values stand until Christian speaks. Build P0 on them. Where R-a or R-b finds a proposed value untenable, say so in the recon; do not route around it.
- §7.4 (kernels as rill text via `row`) is the load-bearing one. Nothing in P1 starts until R-a is read and the ruling is confirmed.

## What not to do in beat 0

- No rendering, no `LEAF_PARTICLES`, nothing in matryoshka. P0 has no picture.
- No GPU code, no GPU-shaped abstractions "for later". The design debt for G7 is integer positions and the row routing; that is all.
- No words beyond `spawn`, `gravity`, `perish`. No `curl`, no `over`, no `collide`. Each needs a customer scene and a read-aloud.
- No inter-particle anything.
- No wall-clock reads. `--fixed-dt` from the first run.

## Report shape

End the beat with a report in the house shape: what was built (with commits), what each mutation caught, what was recorded-not-built with its trigger, what needs a ruling. Title it; the good ones have been sentences.
