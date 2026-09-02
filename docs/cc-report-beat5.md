# Beat 5 — the keep: the coals rest on the plate, the motes fill the shaft, and the torch moves

*CC, 2026-09-02. The closing beat, against rulings 20–28. Spindrift
`865959f`, rill `529e7d8`; matryoshka's three slices in their own commits
(`6534b27` … `9c2bd9f`).
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

## The engine half — matryoshka, slice 1 (`6534b27` … `4325ba4`, pushed)

Built by a delegated agent, reviewed here against the commits, the gates
and the frames. Six commits, each with its ledger row; suite 2585; the
bridge's gates 251; `refs.py verify` nine references unmoved. One thing
to state plainly: the six commits were split by hunk from one tested
tree under ONE full-suite run, because the `over` collision (above) broke
every bank init mid-slice and the agent held its commits while it kept
building — the split is additive-only and the spray gates ran at every
step, but the rule is one run per commit and slice 2 was briefed to keep
it.

**Ruling 21 — `spray burst` rides the transcript (`6534b27`).** A burst
under `--exec-at`, the console or the applet is recorded like a knob
write and re-applied at the same frame; a record/replay pair with a
burst is byte-identical in dumps and transcript hash, the control
without the burst differs, a burst typed under replay is refused and
said once. Mutations: the burst record dropped; the bank's fed-time
record dropped — **a bug the gate found**: the rills' tick recorded fed
time only while a rill was mounted, so a spray-only replay ran at the
zero epoch; the bank records it now, one record per tick whoever asks.
Not on the transcript: `spray add/delete/set` and every tenant's
authored verbs — the rig's Project surface; a mid-session `spray set`
under `--exec-at` does not replay. Recorded, and a ruling asked below.

**Ruling 28 — the offset is the appearance's (`357dd3f`, `3ec4d20`).**
`drawnAt = pos + normal · size`, one rule used by the upload and by the
light placement; the row gate unchanged (rows ON the plate and the box);
the shrink gate — 900 ms on, every live row stuck at the contact at
about 8 cm radius, drawn 8 cm above the plate, not the 30 cm it landed
with; the light gate — four landed coals lit a radius above the plate.
Mutations: `drawnAt` ignoring the normal (the first attempt did not
compile — not a mutation; the second bit both gates); the light placed
at `pos` (the light gate). **Verify before the re-freeze, the `over`
witness:** with the beat-4 upload rule and the P3b manifest, on rill
`529e7d8` and spindrift `cde9eec`, three renders each, the machine idle
— all four pairs bit-identical. Then the hashes re-frozen once: the
plate from above and, new, from beneath; the sparks moved with the
landing; the embers-at-60 and dust2 unmoved (nothing has landed at frame
60; motes never collide).

**The two plate frames.** Whole discs: yes — the embers on the grass
past the plate's edges are round and whole in both frames. The shadow:
the plate's shadow band is on the grass beside it and the underside is
one even sheet, **but the coals' warm pool on the grass under the plate
is still there in both frames**; a control at the same pose with the
coals off the rig shows a dark shadow rectangle and no pool. So the pool
is the coals' light through the shadow budget after all, brought back
as ruling 24's last sentence asked. No blocker built.

**Ruling 23 — the material handle, said (`2e496f0`).** An opaque host
handle, 0 nothing; `spray material <x> <y> <z>` answers on the log bus
with the handle straight below the point through the walk `collide`
takes; the readout gated over the box, the plate and empty ground
against the world's own `collide`; mutation: the readout saying the
table index. Materials carry no names in the engine yet; a dropped
instance's leaf carries a pinned index 0 so `collide` on it answers 1.

**The applet's per-spray selector (`ed24d86`).** `:::sprays` in the
applet's own shape, and `{spray}` in a binding's path that follows the
selection; the plane lists mounted sprays (a refused kernel's is still
mounted — `mounted` is 1 from light to drop — a deleted one is not); the
meters say they are rows, never lights. Mutations: the path resolved
once; every `drift/@name/` owner listed; the selection left out of the
digest — each bitten.

**`spray_gate.py` renders each pair once (`4325ba4`).** dust2 loads
once; verify 2:48 for five pairs (was about twelve minutes), capture
5:32 mounted and bare.

**A reproducibility finding, recorded.** The first dust2 mounted render
of the capture, made while tests compiled beside it, differed from the
frozen frame by 46 pixels in the mote column's top third; its own second
run and an idle re-render matched P3b's hash exactly, four runs
agreeing. Fed time is frame × dt and the motes never collide, so the
machine reached the picture by an unnamed path — the row upload racing
an in-flight frame's SSBO read, or the static tree's settle landing on
a wall-clock frame are the candidates. Trigger: reproduce under load
with the upload's fence instrumented. The gate's docstring now says
"alone on the machine", and slice 2 was briefed to keep the GPU alone.

## The engine half — slice 2, P3c (`5a820c0`, `1f2368e`, pushed)

Built by a delegated agent (the first launch never started: its shell
calls were refused by a permission classifier that fires on `git -C`,
Christian's diagnosis; relaunched with `cd`), reviewed here. Suite once
before each commit; nine refs at zero error after each; the five spray
pairs held after piece 1.

**A leaf per run of rows, pixel-identical (`5a820c0`).** A dirty chunk's
live rows are packed into runs of at most 16 by a recursive median split
along the longest axis of their centres, ties by id so the layout is one
order on every machine; one dynamic-tree object per run with the bounds
of its own discs; dead rows behind; an undirtied chunk keeps its runs.
Rows-sorted-with-a-bound-per-run over a-leaf-per-N-ids because the
freelist hands out ids in death order — consecutive ids are same-age
rows, a slab the spray's width. **Why 16, measured:** rows read by the
dust2 pose's rays fell from 14 985 216 to 818 417 (80 leaves, worst ray
2048 → 140); the GPU's traversal on that pose 17.27 ms unsplit, 6.08 at
32, 3.64 at 16, against 2.72 bare — the motes now cost 0.9 ms where they
cost 14.5, the frame 20.57 → 5.77 ms. The dynamic pool grew 256 → 1024
(dust2's 80 leaves are an eighth of it; 96 KB nodes, 64 KB instances,
the binned-SAH build 308 µs in Debug); an adaptive run size is recorded
with the pool-full log line as its trigger. A first comment ("32 is
where the curve flattens") was wrong and was replaced with the numbers.
Gates: the split's scan count, the beat-3 chunk gate re-aimed, the
ruling-28 shrink gate reading rows through the slot map. Mutations: no
split (1.0×); bounds over centres instead of discs (three gates at the
bounds). dust2 hashed `2efd1f8e…` at 32 and at 16; every pair and every
ref unmoved.

**Coverage by sampling (`1f2368e`).** A disc NARROWER than the footprint
is a hit when the frame's hashed sample is below its analytic coverage,
else the ray continues; a disc that spans the footprint keeps the rim
test it had. The sample is the renderer's own per-pixel hash — a
function of the pixel alone under the fixed pattern, walking with the
frame under the sequence — and the CPU twin restates the rule with the
same bits (there was no twin of the coverage test before; the sight
walker skips the leaf by ruling). Gates: c = 0.25 over a 64×64 block,
1032 hits of 4096 (mean 1024, σ 27.7); c = 1 always, c = 0 never; 32
accumulated frames, block mean 0.2498 against 0.25; four hashed values
frozen; three dust2 renders alone on the machine, one hash `c49d3756…`.
Mutations: the twin comparing to one half again (0 hits); the sample
seeded from the clock (a frozen value moves while the quarter count
still passes — the frozen values are the witness; a GPU-side clock
mutation was not run, since no clock reaches the shader's inputs). **The
motes:** mounted-minus-bare 9 602 pixels against P3b's 3 093 under the
half rule and 13 873 under the quarter threshold; by vertical third
6 386 / 3 036 / 180 — the throat at nine metres, where the half rule
lost everything, is full. The number is now a Bernoulli estimate of the
column's coverage; specks are still single full pixels, the fade is in
their density and in the mean under accumulation. dust2 re-frozen; the
other four pairs bit-identical.

**The rim question, for a ruling.** "No threshold" and "the other pairs
unmoved" cannot both hold under the pure rule for every disc: a wide
disc's rim has coverage strictly between 0 and 1 and would dither,
moving all four ember and spark pairs, and under accumulation its edge
would blur by a footprint — an average averaged again, the finding the
foliage-coverage note made about filtered alpha. What shipped is the
ruling's own word, "sub-pixel": the switch is the footprint, not a
number; its cost, executed, is a step at radius = footprint where the
rim test lights 0.652 of the disc and the sample test 1.000, crossed
once by a shrinking disc. Recorded as the alternative: the pure rule for
every disc with the point test at threshold zero.

## The engine half — slice 3, the torch and the fountain (`a555307`, `9c2bd9f`, pushed)

Built by a delegated agent, reviewed here. Suite once before each
commit, with Christian's in-flight HUD edits present in the tree and
untouched (his own `0d8421a` landed under the agent mid-slice; the agent
staged only its files). The nine-reference verify was not run for this slice: the agent stopped
before it, I started it and Christian waved it off. What stands in its
place is reasoning, said as such: the renderer-side change is confined
to the driven-pose overlay, whose undriven path is bit-identical, and no
reference scene carries an actuator.

**A bound spray follows its entity (`a555307`).** One rule, one spelling
in all three formats: bound, a spray's authored `pos` and `aim` are said
in the ENTITY's frame — an offset and a direction; the bind changes what
the six numbers mean and nothing new is typed; unbound is exactly today
(the follow returns at its first line, and all five earlier pairs and
their bares hashed bit-identical). Rejected on read-aloud: a separate
`follow` flag, `spray attach`; `attach`, `carry`, `ride` for the function.
The pose reaches the plane as an entity rotation mirror beside its
position, published at bind, at load and on change; a prim's driven pose
is the actuator's overlay spelled once and read by both the plane's
service pass and the renderer's dynamic pool from the same fed fraction;
the quaternion arithmetic moved where the plane can import it, gated
against the leaf's matrix. Stated latency: a follower reads last frame's
pose, as every tenant does. **The torch IS the quintain's arm** — `entity
@torch prim quintain-arm`, three sparks sprays along the arm's top face,
thrown up — and it needed nothing the keep cannot use; what the surface
would not allow was a torch-head prim riding the arm (no prim parenting;
an actuator turns a body about its own centre), so the torch is visible
by its sparks alone — priced below. Gates: born at the entity's pose
(move it on the plane, the next row is born there; the unbound twin
unmoved; an unknown entity said once; freeing the entity leaves the
follower where it was); the offset composes (derived on paper at three
arm positions, the rotation mirror's bytes changing each time); replay
(main's frame with a real winch, the drill mounted at frame 8 riding the
transcript, dumps and said-hash byte-identical, the no-strike control
differing). Mutations: the pose read once at light (born at the old
pose; the control stops differing); the pose from the renderer's pool
(born at the origin; the control stops differing) — both bit all three
gates. Capture `tiltyard-torch`, three renders one hash: the yard washed
pink from the left and cyan from the right, the post dark at centre, the
arm 133° into its turn, a dense gold cloud of fresh sparks at its tip
and the trail of landed sparks cooling gold to red along the swept arc
behind it.

**The fountain against the quintain, built for nothing (`9c2bd9f`).** A
jet of small pale discs from the right, rising in a thin arc and coming
down on the post — drops piled on its near face and heaped at its foot —
with the arm resting edge-on into the landing zone. **The fence,
executed:** of 1 000 live drops at frame 236, 250 on the ground, 356
stuck on the post's faces (a static prim collides), and 61 below the
arm's band inside its footprint — there only by falling through it —
against none resting on its top. Each yard picture stands the other's
spray down, so a change to one spray moves one hash. **The priced gaps**
(`docs/tiltyard.md` §4c and the ledger row): aiming at a thing (`spray
aim @post`, an arc solve) — half a beat in matryoshka and half in
spindrift; a kernel from the console (the fountain's had to be a file) —
a quarter beat; a curve authored on the rig (the applet's array is never
persisted) — half a beat plus a quarter; dynamic-prim collision (the
World over the pool's boxes, with the ruled latency of 8 cm at the arm's
tip speed) — one beat; readback (`probe` prints a byte count for an
array; `spray where`) — a quarter; a prim parent — one to two beats; the
yard loaded whole (a rig carries no rills) — half a beat; a console
write to a dynamic path — a quarter; `spray drop` and position, aim and
bind absent from the applet — hours. Frictions, not priced: `aim ×
speed` unnormalised; the landing frame worked on paper.

**Two findings.** `rigs/tiltyard.rig` had never been tracked — the
directory is gitignored as saved looks, and the yard lived only on this
disk since its rulings; a capture whose rig nobody else has is a gate
nobody else can run, so the rig rides `a555307` with a gitignore
exception (revert if the yard was meant to stay local). And the
actuation doc says a target is written "by a rill or a console line"
while the console's `write` refuses dynamic paths — recorded, not fixed.

## Needs a ruling

1. **The shadow budget** (ruling 24's last sentence): the warm pool under
   the plate remains with the offset in place; the frames are with you.
   The ways stand as listed at P3b — a bound light spray names its
   entity's box as a blocker; the shadow budget grows for spray lights;
   the cap spends as two when near-tied; or the trade stands recorded.
2. **Authored tenant verbs on the transcript.** `spray burst` rides now
   (ruling 21); `spray add/delete/set` and every tenant's authored verbs
   are the rig's Project surface and do not — a mid-session `spray set`
   under `--exec-at` does not replay. Every tenant's question, not the
   spray's.
3. **The 46-pixel dust2 difference under load** (above): recorded with
   its trigger; is that enough, or is "alone on the machine" a rule the
   capture harness should enforce (refuse to capture while another
   process holds the GPU)?
4. **The rim** (above): the footprint switch as shipped, or the pure
   rule for every disc with the point test at zero.
5. **`rigs/tiltyard.rig` is tracked now** (the gitignore excepts it) —
   keep, or revert if the yard was meant to stay local.
6. **The torch cannot be a prim riding the arm** — no prim parenting;
   the torch is its sparks. A prim parent is priced at one to two beats.
