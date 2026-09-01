# Working in spindrift

## Running tests — the default is to run NOTHING

Pick a gate because the change can break the thing it watches, never to
feel reassured. Chris has asked for this in every sibling repo; a suite
run per edit makes the harness the activity rather than the work.

    zig build test -Dtest-filter=perish     # one gate, milliseconds
    zig build test                          # 55, and quick — before a commit

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
- **No float in the loop.** Every sim number is Q16.16 (`fixed.zig`,
  `rill.row.Val`). The one boundary where a float may appear is a plane
  value arriving as a broadcast or a knob, converted once per tick.
  Parsing a decimal knob is integer arithmetic. This is what makes G0
  byte-identity and keeps G7's bit-identity claim honest. **Seed the
  gravity knob as a number in cells, never as the raw fixed integer** —
  the harness did once, the boundary refused it as out of range, and
  every G0 run was gravity-free while green.
- **Four phases, one parallel** — see the seam below. The chunking gate
  runs at a scale where breaking this shows.

## The seam: rill owns the row plane

A kernel is a rill program whose plane is the row. The column, the row
runtime and the integer kernels for the core set live in
`rill/src/row.zig`; a change to how a row is evaluated is a rill change
with its own commit there, naming the spindrift beat. What lives here: the
population as a row plane (`population.zig`), the spray's four-phase tick
(`spray.zig`), and the words (`words.zig`). A new word needs a customer
scene and a read-aloud before it needs a kernel, and it registers through
`words.register` with `row.only` set and an exact integer kernel — the G2
audit and the manual parity gate refuse anything less.

- **Six phases, one parallel.** Broadcasts, materialise (every sampled
  channel's bag onto a lattice), spawn (serial), the sweep (kernel,
  integrate, age — chunked), reap (serial, ascending), cast (one aggregate
  per channel). `perish` marks; only the reap kills. A kill inside the
  sweep is a race that now crashes the chunking gate rather than passing
  it.
- **The field model in `fields.zig` is matryoshka's, transcribed.** If the
  engine's kernel or decay changes, this copy changes in the same beat —
  the mock exists so an ear and a row agree, and a mock that drifts from
  the engine is a gate that watches nothing. A gate over a field must
  vary on every axis it claims (the lattice gate once did not, and a
  mutation that dropped two of three lerps survived it).
- **A spray with a mounted kernel must not be moved** — the runtime holds
  a pointer into it. Heap-allocate or keep it in a stable slot.
- **Integration is not a word.**
