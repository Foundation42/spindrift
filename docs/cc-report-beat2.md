# Beat 2 — the smoke leans in the wind, and the room gets dank

*CC, 2026-09-01. Against the rulings that closed beat 1. Built on rill
`0bc2d68` (one commit naming this beat), common `9a75dfb`, struple
`d937815`; matryoshka's fields bridge in its own commit (§4).*

## What was built

**rill `0bc2d68` — the read spelling.** In a kernel, a statement head
`$chan` followed by `at` or `grad` desugars to the host's word `hear`, the
`$` token left in place to bind as the channel static exactly as it binds
to `cast`'s. Bare `$wind` stays the standpoint refusal, now with the
kernel's own spelling in the message; on the plane nothing changed. With
no `hear` registered the read refuses naming the missing word. Gated both
ways and on the plane, spec §3.16 and rill's ledger ride along.

**spindrift `f507bc3` — fields, both ways.** `fields.zig` declares
the `Fields` host interface — `bag` (a channel's live deposits with decay
applied, plus the clamp), `cast` (replace the owner's one aggregate,
whatever its position), `withdraw` (the owner's bag goes with the owner) —
and carries the engine's field model transcribed as the mock store:
`A·exp(−(t − born)/τ)`, cull at ε, restate-replaces across ticks and sums
within one, `k = (1 − (d/r)²)²` with its gradient toward the caster,
clamp on the value, audience coupling. A cast door lets a caster rill and
the spray share one store, as they share the engine's. The spray's tick
has six phases: broadcasts, **materialise** (every sampled channel's bag
onto a lattice over the spray's bounds, cell doubling until 33 points an
axis fit, every point floored once to Q16.16), spawn, sweep, reap,
**cast** (centre of mass as an exact integer mean, amplitude × live,
radius half the bounds' diagonal). `hear $chan [grad] at <pos>` is the
fourth word: trilinear over the lattice, or central differences, both
integer. `kernels/smoke.rill` is the customer, and `drift-run` runs it
headless with `--channel`, `--samples`, `--casts`, `--carried` and an
`--ear` that rises. 55 gates green.

```rill
spawn
gravity plane.drift.@self.gravity
$wind grad at row.pos | mul plane.drift.@self.lean | write row.vel add
perish
```

**G3 is green and bitten.** A caster rill `every 1f | cast $wind 8 radius
6 at {x: -3, …}` through the cast door; every row born under it leans
downwind; the caster is unmounted, its deposit is culled at
`1 + ln(800)` s, and every row born after that rises with `vel.x` exactly
zero while the old rows keep their lean. **G4 is green and bitten.** The
smoke casts `$dankness`; the mock ear a cell above reads above zero after
a few ticks; the store holds exactly one deposit whatever the rows did;
its amplitude is per-row × live to the bit; unmount withdraws it and the
ear reads zero at once. **G0 holds with a field**: same script, same
wind, same bytes — the lattice is re-derived, not remembered.

**The exact-kernel bill is zero.** The radial falloff is evaluated at
rasterisation on the host, once per lattice point, in f32 — that is the
boundary, crossed once per tick. The row only trilinear-samples integers.
No `sqrt`, no squared-distance spelling, nothing to earn or route around.
`sqrt` stays recorded for the first kernel that wants a distance to a
point.

## What each mutation caught (12/12)

| mutation | caught by |
|---|---|
| `hear` answers zero | G3; the hear gate |
| the coupling filter dropped at rasterisation | coupling |
| the cast removed | G4, twice |
| unmount does not withdraw | G4 |
| the aggregate trails instead of replacing | the mock's replace gate; G4 |
| amplitude per row, not × live | G4 |
| kernel `q` instead of `q²` | the mock kernel; lattice; hear |
| an undeclared channel reads as a zero lattice | the dead-lattice gate |
| decay never culls | the mock's decay gate; G3 (the trail never straightens) |
| gradient sign flipped | lattice; hear; G3; G0-with-a-field |
| trilinear reads the nearest point on y and z | **survived the first draft.** The lattice gate's field varied only along x, so the lerps it dropped were lerps of equals. Rewritten as `2x + 3y + 5z`, exact under trilinear everywhere; bites. |
| the unsampled-channel check at mount dropped | the mount-refusal gate |

**Two findings on the way.** The first draft of G3 called rows born
between the caster's unmount and the deposit's cull "straight"; they
leaned by 168/65536 of a cell per second, which is the gradient of a
deposit at 1.1 ε — real physics, and the gate's window moved. And the
lattice gate above: a gate over a field must vary on every axis it
claims.

## Rulings landed

Write-verbs rev 3 (§7.12) with the spray as `hold`'s second customer and
the acceptance masks; `spray dump` to a host channel (§7.13); broadcast
floors stay (§7.14). G4's "reads zero after the decay" and the engine's
"drop the owner and the whole bag goes" differ; the engine's rule is the
ratified one (ownership is the ceiling), so unmount withdraws and the ear
reads zero at once — recorded in the ledger so the two sentences are
known to differ and which won.

**Write-verbs, my call as asked:** brief it after P2 as its own campaign,
with the spray knobs as its first beat's customer. The interim `.mul`
lane on `rate` and `speed` makes the CHOPs example work today, and
folding the knobs into the verb's first beat means the campaign opens
with a customer already waiting rather than a symmetry — the admission
rule the tier-2 discipline set. The acceptance masks are declared on the
tenant now, so the verb's first beat reads them rather than inventing
them.

## Recorded, not built

| what | trigger |
|---|---|
| one field model both repos import (today: a transcription, kept in step by hand) | a third client of the field model |
| `sqrt` as an earned integer kernel | the first kernel that wants a distance |
| lattice gradient by trilinear of gradients (today: central differences at the nearest point) | a scene where the piecewise-constant slope shows |
| per-row casts | the first scene where an aggregate deposit is visibly wrong |
| the write-verbs verb on spray knobs | write-verbs beat 1 |

No picture. No collision. One new word, with its customer.

## The fields bridge in matryoshka — `de55374`, `9239447` (pushed)

Built by a delegated agent to the previous tenant's shape and reviewed
here. `^spray` carries `samples {channel, cell}` and `casts {channel, amp,
radius, decay?, to}` as fixed-capacity values (four each, loud past the
ceiling), one validation shared by the verb, the rig loader and the
Project loader; verbs `sprayarche samples <kind> $wind cell 0.5` /
`… $wind -` and `sprayarche casts <kind> $dankness amp 0.01 [radius <r>]
[decay <ms>] [to #tag]` / `… $dankness -`; all three formats, with a
re-save byte-identical gate. `fields.zig` grew `liveBag` (owner order,
decay folded, clamp returned) and `restate` (one aggregate per owner per
channel, replaced wherever it moved); the bridge implements
`spindrift.Fields` on them with a spray owner id space that cannot
collide with rill mount order, refreshes `carried` from the bound
entity's tag row each reconcile, and treats `samples` as KIND — a kernel
was mount-checked against them, so a change rebuilds rather than leaving
a stale lattice. The interim ruling: a `KNOB_LANES` comptime table
(declared, not enforced — trigger write-verbs beat 1) and
`Plane.pathLanesFold` folding a path's lanes over the authored `rate` and
`speed` every tick; gate: a `mul` lane of 2 doubles the rate, a real
rill composes to 4×, retraction restores the authored bits exactly.
`spray dump` hands bytes to a host-installed sink (headless main writes
the file; the served host's sink is unset and refuses loudly); the dump
gate asserts through a capture sink and that no file appears. Behaviour
gates through the engine's real cast inbox: the kernel bends +x under
the wind, one deposit however many ticks, zero after `spray delete`, a
coupled cast heard only while the ridden entity carries the tag.
Matryoshka's suite: 2471 of 2471 (was 2445).

**Found and fixed on the way:** rill's mount-time entity fold in the
engine ate `plane.drift.@sparks.rate` as an entity reference — an `@`
after a dot is a path segment now, gated. And the campaign's
`plane.mod.…` spelling of the CHOPs example is already retired by
write-verbs (a lane is `write <path> … add|mul`, never a second path);
the campaign doc is respelled.

**One survived mutation, and what it said.** Flipping the bridge's
audience to `hear_all = true` survived every gate, because spindrift
applies the same filter at rasterisation over the engine's bag exactly
as over the mock's. One rule in two places is one rule and one
decoration: the engine-side filter is deleted (`9239447`), the bag hands
over every deposit with its tag, and the coupling gate's comment names
what it actually pays for.

Recorded, not built: `radius bounds` is unsayable on the wire (a string
port refuses a number, an any-port refuses a bare word) — absent means
bounds, the rig line still writes `bounds`; trigger: a word-or-number
console port. The ear tenant's read is not used in the gate (the same
sum at `Fields.sample` is).

## Needs a ruling

Nothing blocks P3. One for the record:

1. **The lattice's cap.** 33 points an axis, cell doubling to fit, `coarsened`
   said in stats. A spray whose bounds span kilometres samples its wind at
   a cell it did not declare. The alternative — refuse the tick — makes a
   wide spray a dead one. Lean: keep coarsening, and have the Spray applet
   show `coarsened` beside `throttled` when P3 builds it.
