# Beat 1 — the kernel is rill text, and the row is its plane

*CC, 2026-09-01. Against the six rulings that closed beat 0. Built on rill
`ae2f3ee` (two commits in rill naming this beat), common `9a75dfb`, struple
`d937815`; matryoshka's spray tenant in its own commit (§4).*

## What was built

**rill `cbff4c9`, `ae2f3ee` — the row plane.** `src/row.zig`: the `Row`
column on `OpDef` (channels, exactness, `only`, the kernel), `Val`
(Q16.16 scalar / vec3 / boolean), the row `Plane` vtable a host implements,
`Runtime` (mount refuses by name — a non-row-legal op, an unknown field, a
read-only field, a lane mode, a plane write, a non-row literal; `evalRow`
is pure per row with a `Scratch` per thread), and integer kernels for the
exact core set — 29 ops, audited both ways: the four arithmetic ops
outright, `min max clamp abs floor ceil round sign fract mod`, `lerp
range`, `select and or not` and the six comparators, `project record`,
`write`. `row` is the second path head through one helper; `parseKernel`
is `parse` with row words allowed; `findCycle` exempts `row.` writes
because the row plane has no dirty propagation and `row.vel | add g |
write row.vel` is the integration step. Spec §3.16, rill's ledger, seven
mutants bitten (one after a rewrite: an absent broadcast read as zero
survived a gate whose field was already zero).

**spindrift `c73ec76` — the spray.** The P0 stand-in is deleted.
`words.zig` registers `spawn`, `gravity`, `perish` through rill's one
door, each `row.only` with an exact kernel. `population.zig` is a
`rill.row.Plane`: twelve fields, age and life in nanoseconds read back as
seconds, the seed as a per-row uniform, `doomed` for `perish` to mark.
`spray.zig` ticks in four phases — broadcasts (every `plane.…` a kernel
reads, `@self` resolved, converted once), spawn (serial), the sweep
(kernel, integrate, age — chunked over the job system), reap (serial,
ascending) — and says `count`, `bounds`, `digest` on the plane,
change-only, zero on unmount. `kernels/embers.rill` is the first kernel
and `drift-run --kernel` mounts any other; `docs/drift-words.md` is the
manual, parity-gated. 40 gates green; `zig build verify-dump` still reads
the dump from Python.

```rill
spawn
gravity plane.drift.@self.gravity
perish
```

**G1 is green and bitten.** A watcher rill reads
`plane.drift.@em.count | above 10 5 | write plane.ui.alarm`; the alarm
rises on the tick after count crosses ten, unmount says zero, the alarm
falls, the knob is still there. **G2 is green and bitten.** Every word is
row-legal, exact, row-only, refused at parse in a plane program by name,
and named in the manual both ways; a word with two adjacent wordless
optionals is refused at registration. **G0 is re-gated on the rill-text
kernel** and now refuses a run whose population never moved or never fell.

## What each mutation caught (12/12, spindrift; 7/7, rill)

| mutation | caught by |
|---|---|
| `spawn` relaunches every tick | the birth-tick gate |
| `gravity` replaces instead of adds | gravity, broadcast, spawn |
| `perish` on `>` | perish, freelist |
| reap inside the parallel sweep | **the chunking gate — a panic.** Two workers race `kill`, and `kill` asserts |
| unmount does not say zero | G1 |
| `@self` not resolved | broadcast, G0 three ways, the negative control |
| count said every tick | the change-only gate |
| `gravity` loses `row.only` | G2 |
| a word's row removed from the manual | G2 parity |
| broadcasts never fed | broadcast, G0 three ways, the negative control |
| `spawn` ignores the row seed | the spread gate |
| integration dropped | G0 three ways, gravity, spawn, the negative control |

Rill's seven: the cycle exemption dropped, `floor` truncating, `add`
losing its column, a lane mode accepted, the read-only check dropped, a
refusal uncounted, an absent broadcast read as zero.

**Four findings on the way, each the ledger's shape:**

- **`fails_mount` leaked.** A row word's plane-side refusal was declared
  with `fails_mount`, and `plane.x | gravity` mounted cleanly: an unfed
  input means the node never evaluates at tick 0. G2 asserted the refusal
  and found it. The parser is the gate now — it is the one place that
  knows what kind of program it reads.
- **G0 passed on a population that never moved.** The row runtime's write
  queue was sized to `write` nodes; `gravity` and `spawn` refused every
  row as "too many writes"; two runs of nothing agreed byte for byte. The
  negative control caught it (nothing fell through the floor). *Determinism
  of stillness is not the claim* — G0's harness now refuses it.
- **The gravity knob was seeded as a raw fixed integer**, out of range at
  the boundary, and every G0 run was gravity-free while green. Same catch,
  same fix.
- **The mutation harness read a crashed runner as green.** Zig's summary
  after a panic still lists the tests that had passed. A crashed runner is
  a bite.

## Rulings landed in the campaign doc

All six, marked *ruled* in §7 with their amendments (4a–4d, 11), plus the
two beat-0 practices in §8 and the ledger's rules. The tenant is `spray`
throughout; `def ember { … }` is withdrawn for `row.`-spelled flows;
finding 6 sits under §7.3 verbatim.

**Ruling 5's check:** matryoshka's per-scene BVH quantisation lattice is
**not** dyadic in the same units. The gauge lattice steps by
`extent / (2²⁰ − 1)` — deliberately, the comment says why — and the slim
node lattice is dyadic but per-BVH with its own exponent and origin. So
position → Morton key is not a shift; the upload quantises once per dirty
chunk with deterministic integer arithmetic. Recorded in §3.1 and §7.11.

## Recorded, not built

| what | trigger |
|---|---|
| a stateful row op (`channels > 0`) — allocation and overflow refusal exist, nothing exercises them past mount | the first per-row envelope |
| `sqrt` and the transcendentals as earned integer kernels | the first kernel that wants a distance or a curve |
| `spray bind` following an entity | Ironwood's torch |
| the World caller | P4's `collide` |
| `drift/<@em>/throttled` as a mailbox occurrence | G6 |

No picture. No fields. No collision. No fourth word.

## The spray tenant in matryoshka — `cb9af47` (local, not pushed)

The eleventh tenant, built to the S5 sensor's pattern by a delegated
agent and reviewed here. `^spray` kind (`capacity`, kernel name, `rate`,
`speed`, `spread`, `life_ms`) and `@<name>` instance (`pos`, `aim`,
`enabled`, `bind`, the four knobs under a packed override mask, `arche`,
`iid`, `prov`); `Source.drift`, derived and skipped on replay; fourteen
console verbs — `sprayarche set|del`, `spray add|move|aim|bind|rate|set|
revert|arche|enable|delete|burst|dump` — through the comptime completeness
and wire gates unchanged; all three formats (Project records, rig lines,
the wire). `src/spray_bridge.zig` is perception's shape one tenant over:
reconcile live sprays against the authored snapshots once a frame, convert
units once at the seam, tick on the engine's fed time with the engine plane
handed down as `rill.Plane`, speak the zero baseline at reconcile so a
sentry's `rose_above 0` arms, say zero on delete or stand-down. Bursts are
an exact deposit into the spawn accumulator; dumps are serviced after the
tick through `spindrift.dump.write`. Sixteen gates including the behaviour
gate (verb → reconcile → fed ticks → `drift/@sparks/count` 0, 2, 4 … →
delete → 0); five hand mutations of the bridge, five bites. Matryoshka's
suite: 2445 of 2445 in one Debug run. No picture, by the brief.

Recorded, not built, with triggers: following a bound entity (Ironwood's
torch); a second kernel from the console (the verb has no kernel column —
a rig or Project may name `kernels/<name>.rill`, and a missing kernel
leaves the spray inert with one log line, gated); the job system on the
frame thread (none in hand; the sweep runs inline).

## Needs a ruling

Nothing blocks P2. One question the tenant surfaced, and two for when
they come up:

0. **A plane-written knob against the authored one.** The campaign's
   CHOPs example writes `plane.mod.drift.@sparks.rate add` from a HUD rill;
   the tenant's knob is authored on the rig. Which wins, and through which
   lane — the same lane-versus-last-writer question `write` modes settled
   for grade knobs, now asked of `drift/` paths. The kernel's own
   broadcasts (`@self.gravity`) already work; a rill overriding a rig knob
   is what waits on this.

1. **`spray dump <name> <path>` writes a file from a console verb** — the
   only verb in the inventory that touches the filesystem from the
   transcript. It is a gate artefact, not a transcript entry; the ledger
   line already says so. If the verb should instead hand the dump to a
   host channel, that is a one-line move.
2. **Broadcast conversion floors.** A knob written as `2.5` reaches every
   row as 2.5 exactly; `9.8` reaches it as 9.7999. The same floor the
   literal takes at mount. Fine for v1, and stated in the spec; a ruling
   only if a customer scene wants round-to-nearest at the boundary.
