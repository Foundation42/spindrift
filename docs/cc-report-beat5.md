# Beat 5 — the keep: the coals rest on the plate, the motes fill the shaft, and the torch moves

*CC, 2026-09-02. The closing beat, against rulings 20–28. Spindrift
`0853186`, rill `675a049`; matryoshka's slices in their own commits (§3).
The campaign's close-out is its own document,
`docs/cc-report-campaign-close.md`.*

## The spindrift and rill half

**The normal reaches `stick` — rill `675a049`.** Ruling 24 puts the
landed row's rest at the hit point plus the normal times its radius, and
`collide` had been emitting the normal on a port no kernel could reach:
rill's pipe fed a producer's FIRST output to the consumer and nothing
else — no `outputs[1]` anywhere in the tree. Beat 4's manual said the
other ports "ride along", and nothing could read them; a prose claim
about a port is a gate to run, too. The rule now (spec §3.16): after the
explicit bindings, a consumer port left open that is spelled like one of
the producer's other outputs binds to it — by name, never by position,
never port 0, an explicit argument always winning. `collide | stick`
reads as it always did and hands the normal across. Gate: `twoout |
takeb` (84, not the 91 a positional carry would give), `takeb 5` (the
explicit wins), `takec` (refused naming port `c`). Mutations: by
position, dropped — both bitten. 384 rill tests.

**The resting offset — ruled, built, and moved in the same hour.** Built
as first ruled (`48a5549`): `stick` rested the row at `at + normal ·
size`, gated on the floor by exactly its radius, three mutations bitten
(no offset; the flipped normal; ONE for the radius). And a finding on
the way, reported before the re-ruling: a stuck row's segment is zero
length once the sweep drops its velocity, so `collide` never fires again
and a landed ember that shrinks from 0.3 to 0.06 hovers 24 cm above the
plate. Ruling 28 (Christian's 27b) moved the offset from the sim to the
appearance, and that is what stands (`0853186`): a stuck row's `pos` is
the CONTACT point; `stick` stores the contact normal on the row
(`row.normal`, a vec3 field, zero for every unstuck row, zeroed on spawn
like the rest); the upload draws the sprite and places the light at `pos
+ normal · size`, one rule for every row with no stuck branch, so a
landed row that shrinks stays on the surface by construction; `hear`
still samples at the contact; no re-rest anywhere. Dump format 3 carries
`nrm_x/y/z`, and `dump.column` reads a value back.

**`over` went home to rill — rill `23ac55c`, another session, the same
day.** The same spelling and the same bits as spindrift's fifth word,
now on the plane as well as the row. Two words with one name refuse at
register, and spindrift's suite failed at every registry init the moment
rill moved; the kernel here is deleted rather than kept beside rill's —
one word, one home, and `over` never needed a host. The diff was not a
no-op at the edges: spindrift refused a life ≤ 0 and clamped a read far
past life where rill's first draft clamped a negative silently and
refused the far read as overflow; both of spindrift's answers are in
core now (rill `529e7d8`), gated and bitten there. The gates here stay
and still bite through `mountKernel`; the manual moves `over` out of the
parity table into its own paragraph. That session's note that matryoshka
registers no row words and lacks `row.life` was a stale picture: the
bridge has registered spindrift's words since beat 1 and `life` has been
in the schema since P0.

## What each mutation caught (this half: 9, all bitten, one gate rewritten)

| mutation | caught by |
|---|---|
| rill: carried outputs bound by position | the carry gate (91 for 84) |
| rill: the carry dropped | the carry gate (the refusal) |
| `stick` without the offset — first build | the landing gate; the flipped control |
| the offset along the flipped normal — first build | the landing gate; the flipped control |
| ONE for the radius — first build | the landing gate |
| `stick` stores no normal | the landing gate; the flipped control (up expected, zero found) |
| `stick` still offsets `pos` by the radius | the landing gate (0.5, not 0); the flipped control |
| `clearRow` leaves `normal` | the reused-slot gate |
| the dump writes zero for `normal` | the dump gate — **after a rewrite**: a key-only substring check let it through, and the rewritten gate then panicked on a row the dump did not carry (only live rows ride), a panic that hid behind a 70/70 count. Fixed; reads the column's VALUE on two live rows. |

## Recorded, not built (this half)

| what | trigger |
|---|---|
| (B) explicit Euler; (C′) a second snapshot after an `integrate` line | a tunnel at frame rate in a customer scene (ruling 20) |
| a coverage knob on the kind | a mote scene the stochastic fill does not serve (ruling 25) |

## The engine half — matryoshka (§3)

[pending: slice 1 — the upload offset with the shrink gate, the plate
from above and beneath, `spray burst` on the transcript, the material
handle said, `spray_gate.py` loading dust2 once, the applet's per-spray
selector; slice 2 — P3c stochastic coverage, sub-chunk leaves, dust2
re-captured; slice 3 — `spray bind` following an entity with the torch in
the tiltyard, the fountain against the quintain.]

## Needs a ruling

[pending]
