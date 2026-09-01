# Working in spindrift

## Running tests — the default is to run NOTHING

Pick a gate because the change can break the thing it watches, never to
feel reassured. Chris has asked for this in every sibling repo; a suite
run per edit makes the harness the activity rather than the work.

    zig build test -Dtest-filter=perish     # one gate, milliseconds
    zig build test                          # 27, and quick — before a commit

The whole suite here is cheap (no GPU, no engine), so the calculus is
gentler than matryoshka's: run it when you have changed code, not after
every edit, and once before a commit. What is NOT cheap is downstream —
matryoshka will depend on this library the way it depends on rill and
spark, and once it does, anything a host reads (the population layout, the
dump format, the `World` interface) puts its GPU sweep in the blast
radius. See `matryoshka/CLAUDE.md` for that table.

    zig build verify-dump    # drift-run writes a dump, the struple PYTHON port reads it
    zig build row-legal      # walk rill's registry, print the row-legal list (recon R-a)
    zig build run -- …       # drift-run; `--help` for the flags

Rules that hold whatever you picked:

- A gate that passed stays passed until the code changes.
- Debug builds while iterating. Nothing here needs ReleaseFast to be
  meaningful, and the Matryoshka ReleaseFast build is the one that takes
  forever.
- One GPU gate at a time, when a sibling repo's are involved.

## The ledger

`docs/implementation-notes.md` — every decision made while building, with
the mutation that paid for each gate. Same rules as rill's ledger, restated
at its head. Docs ride the same commit as the code they describe.

## House style

Write the reasoning into the code. A gate's comment should name the bug it
was paid for. A gate that cannot fail is decoration: check it fails against
the old behaviour before believing it — every gate in `src/tests.zig` has
a named mutation, and the ledger records which gate bit it.

Prose approves plausible semantics; execution approves actual semantics.
A gate is an executed program. A mutation must bite; a mutation that does
not compile is not a mutation.

Read-aloud before naming; record rejected names. Recorded-not-built needs
a trigger. Loud, never a guess — a refusal lands on the node that refused.

## The sim's three rules

- **Time is fed, never read.** `tick(now)` carries `{frame, time_ns}`; dt
  is the fed delta; no wall clock anywhere in `src/`. A regression is
  `error.TimeRegression`, never a clamp.
- **No float in the loop.** Every sim number is Q16.16 (`fixed.zig`). The
  one boundary where a float may appear is a plane knob arriving through
  `drift-run`, converted once. Parsing a decimal knob is integer
  arithmetic. This is what makes G0 byte-identity and keeps G7's
  bit-identity claim honest.
- **Three phases, one parallel.** Spawn is serial (freelist pop order),
  the kernel is chunked over `common/jobs.zig` (row-local by the
  campaign's fence), perish is serial in ascending id (freelist push
  order). The chunking gate runs at a scale where breaking this shows.

## The trap: the kernel is a stand-in

`emitter.zig`'s `spawn`/`gravity`/`perish` are Zig, not rill text. That is
P0's allowed stand-in (recon R-a §7) and P1 deletes it. Do not grow it a
fourth word, a curl, a collision, or a per-row anything — each of those
needs a customer scene and a read-aloud, and the place they land is the
row evaluator P1 builds over rill's parsed graph, not this file.
