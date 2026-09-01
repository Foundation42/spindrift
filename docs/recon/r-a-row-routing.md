# Recon R-a — pricing the `row` routing class (CC, 2026-09-01)

*Read against `docs/spindrift-campaign.md` §3.3 and §7.4/§7.5, and rill at
`d4ebe12`. Baseline verified before anything was claimed: `zig build` and
`zig build test` green on the spindrift skeleton against rill `d4ebe12`,
common `9a75dfb`, struple `d937815`. One thing is built with this note and
nothing else: `tools/row_legal.zig` (`zig build row-legal`), because the
brief asked for the row-legal list from the registry and not from prose,
and a list nobody executes is prose. Rulings marked **fork** are
Christian's; everything else is a price or a mechanism.*

---

## 0. The finding that reframes the question

**There are two routing classes, not three.** `Routing = enum { anywhere,
main }` (`rill/src/registry.zig:405`), comptime-required with no default.
`.main` has three declarers (`cast`, `tag`, `untag`); the other 105 core
ops are `.anywhere`. The brief's "know how the existing three are wired"
counts something else — probably `OpClass = { pure, reads, effect }`, the
three-valued column beside it. Priced accordingly: `row` would be the
*third* value of `Routing`, or a second column. §6 says which and why.

**Routing crosses the C seam as a boolean.** `rill_op_routes` returns u8
0/1 (`c_api.zig:296`), `rill_program_routes_to_main` returns bool
(`:428`), and a host-injected def decodes `if (def.routes == 1) .main else
.anywhere` (`:273`). A third `Routing` value silently becomes `.anywhere`
at that seam unless the ABI widens. Matryoshka's retail build imports rill
as a Zig module and never crosses the seam; the seam is the dev loop
(`zig build seam`). Still: a value that one of two link shapes cannot
carry is a value that will be wrong on the day someone uses the other.

**There is no exhaustive `routes` audit.** `class`, `ticks` and
`fails_mount` each have a both-ways audit in `tests.zig`; `routes` is
asserted only by the literal on each registration. Whatever lands here
lands with the audit it was missing.

## 1. What adding `row` touches

Priced against the code, file by file.

| surface | what changes | size |
|---|---|---|
| `registry.zig` | the column (§6), and `register` refusing an op that declares row use but whose port shapes cannot be row-fed (port 0 typed `array`, a `path`/`channel`/`subject`/`condition` static) — the ambiguity rule's pattern: refused at registration so a host cannot do it either | small |
| `ops.zig` | every core registration answers the column (108 literals, like `routes` did on 2026-08-25) | mechanical |
| `c_api.zig` | seam decode fills the column with *never* for host-injected defs; a `rill_op_row` export if a C host ever asks | small |
| `parser.zig` | a **row def** form: bare row-field names as pre-bound ports; `write <field>` as a row write; a body that may end in a sink; row-only words refused outside a row def and never-words refused inside one — all at parse, where `Target.template` already says which kind of body is open (`parser.zig:554,716,1050,2125`) | the real cost |
| `eval.zig` | **nothing.** rill's sweep never evaluates a row. The row evaluator is spindrift's (§3) | — |
| `tests.zig` | the four gates admit the new column: typing gate (unchanged — row ops are typed from the same table), argument-spelling gate (unchanged — `register` already refuses adjacent wordless optionals for any registrant), a **both-ways audit** of the column, the operator-index gates for any new core word | medium |
| `rill-run` | **nothing.** It has no population. Spindrift ships `drift-run` (R-b §5) | — |
| manuals | rill's parity gate covers rill's words only. Spindrift's words are registered by spindrift, so spindrift needs its own manual and its own parity gate, or the words are untaught by construction | new gate here |

Matryoshka's `routesToMain` (`src/control/commands.zig:2349`) derives from
`routes == .main` and is untouched under §6's lean.

## 2. Which operators are row-legal today — from the registry

`zig build row-legal` walks `registerCore` and applies the stated test
(§3.3: *elementwise, and any state it carries fits in the row's user
channels*) from the fields the registry carries now. Output at
`docs/recon/row-legal.txt`. The mechanical half of the test is derivable;
the state half is not, and that gap is the column.

**Row-legal now by the declared fields — 49 ops, all `.pure`:** `select
lerp and or not wave range shape add sub mul div min max clamp abs floor
round sin cos tan sqrt exp log ceil sign fract pow mod atan2 = != < <= >
>= choose distance dot within angle inside cross transpose nearest along
match project merge`.

Of the campaign's nine named candidates: `mul`, `add`, `clamp`, `lerp`,
`range` pass outright. `noise`, `ease`, `kick`, `adsr` are `.reads` and
land in the next bucket.

**Elementwise by declaration, carrying state the registry cannot size —
34 ops.** Read from `ops.zig` by hand, which is exactly the fact P1's
column declares:

| state layout | bytes | ops | fits 4 × i32 user channels? |
|---|---|---|---|
| none — reads fed time + seed | 0 | `noise` | **yes** (seed from the row's `seed` field, time from the row's `age`) |
| one side byte | 1 | `dropped_below rose_above edge above below once toggle` | yes |
| `RegState` {frames, at:u64, a:f64, b:f64, started} | 26 | `ease ramp hold diff integrate` | **no as encoded** — 16 bytes at most; `at` is absolute fed time and `a`/`b` are f64. Re-encoded row-relative (age instead of `at`, Q16.16 instead of f64) it is 8 bytes |
| `EnvState` {frames, at, span, from:f64, to:f64, phase} | 34 | `kick adsr` | **no as encoded**; row-relative and fixed-point it is 12 bytes |
| `PendState` {until, pending payload} | unbounded | `debounce delay sample` | no — carries a payload |
| rolling buffer | unbounded | `window` | no |
| wheel epoch, per-node | 8 | `every pulse lfo` | sources with literal ports only; per row they are the row's own age, so yes — but they are not *over* anything |
| arrival-shaped (ask `in_fresh`) | 0–1 | `where partition changed latch arm disarm rand tap tally step` | **not row semantics** — per row, every tick is an arrival, so "pass while fresh" and "count arrivals" mean "every tick" |

So the campaign's claim that `kick`/`adsr` give per-particle envelopes
"for free" is true of the *arithmetic* and false of the *encoding*: the
register family's state is fed-absolute and f64, and a row cannot carry
that. It can carry an age-relative fixed-point copy. That is a second
encoding per word, gated against the first — not free, but bounded.

**Not row-legal by the declared fields — 25 ops:** the array consumers
(`stats nth first last len take shuffle`), the section drivers (`map keep
reduce sort`), the variadics (`record array`), the effects (`write notify
inc cast tag untag`), the sources (`clock frame pi tau const`), and
`expect` (asserts at mount, once).

**One caveat on the walker's proxy.** "Has an input" is a proxy for
"elementwise over a row value" and it misclassifies `every`/`pulse`/`lfo`
/`noise` (literal-only ports) as elementwise. That is not a bug in the
walker; it is the reason the answer must be a declared column rather
than a derived predicate. Four rows of a 108-row table disagree with the
best predicate the fields support, and the ruled pattern for exactly that
is *the registry carries the answer and the predicate is derived*.

## 3. Where the row evaluator lives, and what "row" is not

`row` is **not a value of `Routing`.** Routing answers *which thread may
this eval run on* — `.main` because the eval touches host-serial state.
A row op has that question too, and the answer is `.anywhere` (rows are
chunked over `common/jobs.zig` and evaluated off-thread; a `.main` row op
would serialise the whole population). "Evaluated once per live row" is a
*multiplicity*, and rill already has one of those: `OpDef.body`, the
consumer-declared section arity that `map`/`keep`/`reduce` drive through
`EvalCtx.call` (`registry.zig:451-467`, `eval.zig:705`).

The section mechanism is the closest analogue and it is explicitly closed
against the kernel's shape: **"a body is one operator"** — a `def` as a
body needs the caller to drive a *range* of nodes, which needs re-entrant
evaluation, and both are refused by name (`rill-spec.md` §3.15). A kernel
is a range of nodes driven per row. So the kernel is not a section.

What it is: a **flattened def** — rill's def machinery already produces
exactly the artefact a row evaluator wants. `parseDef` builds a
`Template` (nodes, slots with `.port` sources, outputs); instantiation
splices it with `.port` sources substituted (`parser.zig:2165`). A row
def is a template whose ports are the row fields, instantiated *once*
into a `Program` whose port sources are row-field reads, and whose sinks
are row-field writes. Nodes are in topological order by construction
("parse order is topological order"). The row evaluator is then a sweep
over that node list per row — the same sweep as `Runtime.tick`, with the
two ends replaced (inputs from the row, outputs to the row), which is the
shape `callBody` already has (`eval.zig:696-703`).

**The evaluator lives in spindrift**, over rill's `Program`, not in rill's
`Runtime`. Three prices for how it calls each op:

- **(a) Call the existing `eval` fns with struple-encoded inputs.** One
  arena per chunk, one encode per input per op per row. Honest to the
  language, zero second implementations, and 10⁵ rows × 10 ops ≈ 10⁶
  struple round-trips per tick — measured nowhere yet, expected in the
  hundreds of ms. Viable at G0/G1 scale (10²–10³ rows); not at the
  customer scenes.
- **(b) A fixed-point row kernel per word**, keyed by op name in
  spindrift, with an identity gate: every op the registry marks row-legal
  has a kernel and every kernel names a row-legal op. Fast, integer-only
  (so G7's bit-identity is real, §5), and a second implementation of
  every row-legal word — bounded by the ~30-word budget, and gated
  against the f64 `eval` on a grid.
- **(c) (a) now, (b) per word as a customer scene misses budget.** The
  fill trigger is already in §6 of the campaign ("GPU row evaluator: first
  customer scene where a kernel misses budget"); the CPU fixed-point
  kernel is the same fill one step earlier.

Lean: **(c)**, with the row-legal column landing in P1 and (a) as P1's
evaluator. The column is what lets (b) arrive word by word without a
second decision.

## 4. What breaks if a `row` op is piped in a non-row program

"Should refuse at mount — confirm the mechanism." **The mechanism is the
parser, and it refuses earlier than mount.** `Runtime.mount` inspects one
registry column (`fails_mount`, `eval.zig:594`) and no other; there is no
mount-time registry walk to hang a row check on, and adding one would be
a second place that knows what a row def is. The parser already knows:
`Target.template` is non-null inside a def body, and every plane-path
refusal inside a def is made there (`parser.zig:2125`). A row def sets a
row flag on its `Target`; binding an op whose column says *only* outside
one, or *never* inside one, fails at that line with both names.

That satisfies the campaign's "refuse at mount" a fortiori — parse
precedes mount and a parse refusal never reaches a runtime — and it is
the same door the cycle check and the close-over-nothing rule use.

Confirmed the other way: today nothing refuses. `spawn` registered by a
host as an ordinary `.anywhere` op would bind in a HUD rill and evaluate
once per tick against no row. The column is what makes the refusal
sayable.

## 5. The number problem, which §7.3 did not price

**Math emits f64 always** (ledger, "Decisions the spec left open"): every
core arithmetic op decodes to f64 and encodes f64. Row fields are
fixed-point i32 (§3.1). Under evaluator (a), every row value round-trips
i32 → f64 → op → f64 → i32 per op. On one CPU that is deterministic
(IEEE), so **G0 holds under (a)**. G7's *bit-identity* across CPU and GPU
holds only where the GPU reproduces the f64 op exactly: `+ − × ÷`, `min`,
`max`, `floor`, `abs` — yes, with fma contraction off; `sin cos exp pow
log sqrt noise` — no, transcendental libraries differ by ulps, and a
one-ulp difference before a fixed-point truncation is a one-lattice-step
difference in position.

So §7.3's "integer positions make G7 a bit-identity gate" is true of the
*storage* and conditional on the *arithmetic*: bit-identity needs
evaluator (b) for the transcendental words, or G7 becomes a tolerance
gate for programs that use them. Not a P0 or P1 question, but a fact the
row-legal column should carry when it lands (a per-word "exact under (b)"
bit is cheap now and unaffordable to retrofit).

## 6. Forks — stated as forks, with my lean

1. **`row` as a third `Routing` value, or a second column.** (§0, §3.)
   *Routing value:* matches the campaign's words; widens the C seam;
   every `switch` on `Routing` gains an arm; `routesToMain` must decide
   what `row` means for a thread it never runs on. *Column:* `OpDef.row:
   RowUse = never | also | only`, no default (a safety fact, like
   `routes` — a wrong answer evaluates a plane op per row or a row op
   against no row), both-ways audit, seam fills `never`. **Lean:
   column.** The thread question and the multiplicity question are
   independent, and an op has to answer both.

2. **What the column carries.** *Boolean* (row-legal yes/no): the
   minimum, and it leaves state-size and exactness in prose. *Record*
   (`{use, channels: u3, exact: bool}`): declares the user channels the
   op's row state needs and whether its fixed-point kernel is bit-exact,
   so the parser can refuse a kernel whose words overflow the four
   channels and G7 can be a gate on `exact` words. **Lean: record.** §2's
   table is the evidence — the state sizes are the whole question, and a
   column that cannot say them is a column that says "see the ledger".

3. **The kernel's spelling.** The campaign writes `def ember { … }`. rill's
   def is `def name(ports) = body` and requires a value-producing last
   statement (`parser.zig:592`). Options: a `row` def form (`def ember
   row = …`? `kernel ember`?) whose ports are the row fields implicitly,
   whose body may end in a sink, and in which `write <field>` targets a
   row field. **Needs a read-aloud** before it needs a parser. Lean: the
   `def` keyword with the row fields pre-bound — a kernel *is* a def over
   a row, and a second keyword for the same shape is a symmetry admission.

4. **§7.5, `$wind at pos`.** The standpoint ruling (`rill-casts.md` §9)
   refuses a rill-side positioned read: *an entity has no implicit
   instrument.* The campaign is consistent with it — the emitter's `^`
   declares `samples $wind cell 0.5` and that is the instrument; `at pos`
   names where *within the emitter's own lattice* the row samples. That
   is a read inside a declared instrument, not an implicit one. But it is
   a new spelling for a read that today is a plane path
   (`sensors.<post>.$chan`), and it lands in P2, not P1. Lean: hold until
   P2's brief, with this reading recorded so the ruling starts from it.

5. **The name `emitter`.** Taken: `Surface.emitter` is matryoshka's sound
   emitter tenant, `sarche` its archetype (recon R-b §6). The campaign's
   console verbs are `drift …`, which does not collide; the *tenant* and
   its archetype verb need a name that is not `emitter`/`emitterarche`.
   P1's read-aloud.

## 7. Where this leaves P0

**The `row` routing cannot land inside P0 honestly.** It is a parser form
that needs a read-aloud (fork 3), a registry column that needs a ruling
(forks 1–2), an evaluator that does not exist (§3), and a gate suite
(§1). None of that is P0's population-and-determinism gate. P0 uses the
Zig-native stand-in kernel the brief allows — `spawn`/`gravity`/`perish`
as Zig functions over the population — recorded in the ledger as a
stand-in that P1 deletes, trigger: P1 itself. The stand-in does not grow
a second word.

What P0 *does* carry from this recon so P1 starts from evidence: the
walker (`zig build row-legal`) as the seed of the column's audit, the
fixed-point row layout that evaluator (b) wants (R-b §1), and integer-only
arithmetic in the stand-in so that G0 is byte-identity with no float
anywhere in the sim.
