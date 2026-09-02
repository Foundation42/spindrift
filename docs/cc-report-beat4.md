# Beat 4 — the embers come to rest on the plate, and the sparks on the trim

*CC, 2026-09-02. Against the rulings that closed beat 3 and the ruled order
for P4. Spindrift `bc3bd54`; matryoshka's tracer, budget, G6 and captures
in their own commits (§4). Write-verbs beat 1 ran in parallel in
matryoshka (§5).*

## What was built, in the ruled order — the spindrift half

**(a) The World caller — `collide`, `ground`.** A second word table,
`TRACER`, beside `WORDS`: a host that HAS a World registers it
(`words.registerTracer`); a kernel naming `collide` on a host without one
is refused at mount by name — the prose claim, run as a gate. `collide`
sends the row's segment, `pos` to `pos + vel·dt`, through `World.collide`
and pipes the hit point, the normal, `t` and the material; `ground` asks
for the nearest surface below and pipes distance and normal. Exact at the
row: the host answers in Q16.16, once per query. The mock floor stays as
the World every gate here runs against; `Nowhere` stays as the negative
control — and the negative control now has its caller: with `collide |
stick` in the kernel, the floor and no-world runs DISAGREE, where every
earlier beat had them agree.

**The hit point is the host's.** The first draft computed it at the row,
`from + (to − from)·t`, and the first gate run landed a row one Q16.16
ulp ABOVE the floor (`expected 0, found 1` — two floors in the product).
A landed row sits on the surface, so `World.Hit` carries `at`: the mock
floor answers `y` exactly, the engine converts its float point once.
Gated on a slanted crossing — `y` exact, `x` between.

**(b) `stick`.** `stick <at>` writes the row's position and sets
`row.stuck`. `stuck` means held, and the sweep is what holds it: after the
kernel's writes land, a stuck row's velocity is dropped and the integrate
moves it nowhere. That took two drafts. The first zeroed the velocity in
`stick` alone; the next tick's `gravity` put it back and the landed row
sank through the floor at 2.5 cells a tick. The second held it in the
sweep AND in the word AND skipped the integrate — and two of those three
survived their mutations, which is the ledger's definition of a
decoration. Deleted both; one rule, in the sweep, and the mutation that
removes it bites twice. A stuck row still ages and still reads its curve
(gated: its size keeps shrinking after it lands). Read-aloud: `land` is
the picture, not the operation; `settle` and `rest` promise a motion that
is not there; `stick` says what the bit says.

**(c) The budget.** `scheduler.plan` over candidates `{rows, priority}`
with fed-time-only priority — staleness first, then in-frustum, then
touches-dynamic, then index — a stable insertion sort and a greedy fill,
pure and allocation-free, the same order on every machine. **One rule the
campaign did not state and the file does: the highest-priority spray
always runs.** A budget below the smallest spray would otherwise be a dead
sim that says `throttled` forever; the budget bounds the total, it does
not veto the first. A spray not run is carried over (`Spray.carryOver`):
fed time does not advance for it, its staleness grows, and
`drift/@<name>/throttled` fires as a MAILBOX occurrence carrying the
staleness; a run resets it to zero — that is what the word counts. The
spawn-refusal count is `Stats.refused` and `drift/@<name>/refused` on the
plane, so the two facts have two words (ruled; matryoshka's bridge took the
rename in its own commit, `4abd61e`). Rejected: `rejected`/`denied` for the
count — a spray at capacity refuses a spawn, it does not judge it;
`skipped` for the carry-over — a skipped tick sounds lost, a carried-over
spray is owed a tick.

**(d) G6, here as a harness.** Two sprays, one knob read from the mock
plane once per tick, `plan` over their live rows and staleness. A burst
over a budget of 40 throttles both in turn (once `a` is over, `b` runs,
then `a`'s staleness puts it first); two runs give one byte string of
dumps AND one hash of every plane write; a budget for everything throttles
nobody and its populations differ; a coarsened-and-throttled run replays
too.

## What each mutation caught (12: 10 bitten, 2 deleted, 2 gates rewritten)

| mutation | caught by |
|---|---|
| `stick` leaves the velocity | **survived** — the sweep holds the row. Decoration; deleted. |
| `stick` never sets `stuck` | the landing gate; the flipped control |
| `collide` tests a zero-length segment | the landing gate; the flipped control (floor and no-world agree again) |
| `collide` answers the pre-hit position | the landing gate (`y = 1`); the flipped control |
| the sweep does not drop a stuck row's velocity | the flipped control (the row sinks); after the deletion above, the landing gate too |
| the sweep integrates stuck rows too | **survived** — a zero velocity integrates nowhere. Decoration; deleted. |
| `carryOver` does not grow staleness | both G6 gates (`a` starves `b`) |
| `carryOver` says nothing on the plane | both G6 gates; the staleness gate |
| **a wall-clock read in the sim path** (staleness += clock mod 7) | **survived the dump-only replay gate.** The order of ticks never changed, only what the sim SAID about them. The gate now hashes every plane write across the two runs; bites. |
| `plan`: the first does not always run | the scheduler's gate; both G6 gates (nothing runs under 40) |
| `plan`: staleness ignored | the scheduler's gate; both G6 gates |
| `tick` does not reset staleness | **survived G6** — a spray that only grows staler still runs in the same order. New gate: the occurrence says 1, 2, then 1 after a run; bites. |

**What the wall-clock survivor says, for the campaign's G6 line:**
*byte-identical replay* is the dumps AND the transcript. A gate that
compares only the population can miss a clock that leaked into a number
the sim publishes. Spindrift's harness compares both now; the engine's G6
was briefed to do the same.

## Recorded, not built

| what | trigger |
|---|---|
| releasing a stuck row (`write row.stuck 0` and it moves again) | the first kernel that wants a landed row to lift — rain on a moving thing |
| a bounce (`collide` pipes the normal; no word reflects) | the first kernel that wants a spark to skip off the trim |
| material by name (today a number the host chose, capped at 32767) | a kernel that reads `material` and wants a word |
| segment queries against dynamic prims | fenced (Ironwood's rain) |

Fenced and untouched: trails, sub-sprays, per-row casts, blending/OIT.

## The engine half — matryoshka `307bbbb` … `8712c7b` (pushed)

Built by a delegated agent to the ruled order and reviewed here; six
commits, each with its ledger row, the suite once before each; the spray
gates 198 → 234; `refs.py verify` once at the end, nine references
unmoved.

**(a) The World on the CPU twin tracer — `307bbbb`, `src/spray_world.zig`.**
One closest-hit walk over the static tree, bound every frame beside the
sight solver's rebuild: mesh leaves in the leaf's own frame, boxes for
the solid kinds (the plate is a thermal surface), the bounding box as the
curved kinds' stand-in, portals skipped, the dynamic tree not walked.
Units cross through the upload's own conversion and its declared inverse,
so `collide` and the drawn sprite agree by construction. `t` in Q16.16;
the point the host's, snapped onto a box face's plane and converted once;
the material id is the leaf's table index + 1 so 0 stays "nothing named".
Re-entrant under the JobSystem's chunks by construction — const slices,
no allocation, none of the solver's tally globals. Two rules the gates
found and the file records: *on a face* is judged at the row's
resolution (1.65 is no Q16.16 number, so a landed row sits 6 µm inside
the plate, and an exact-float rule re-hit it at t = 0.9999 — on a face
and leaving is no hit, entering is t = 0); and *a row found inside a
solid is placed on the face it came through*, traced back along its
velocity, not the nearest face — the first row-gate run put an ember on
the plate's underside (why that can happen is the first ruling below).
Sweep timing on test_scene, Debug, 30 workers: 1080 rows, 1.124 ms with
`collide` against 0.800 without — about 0.3 µs a row-query.

**(b) `collide | stick` in the kernels — `1167d8e`.** `cinders.rill` and
`sparks.rill`, one line each with its comment; the applet's curve line
stays; both rigs mount without a refusal.

**(c) The budget, the scheduler, the governor — `52125fe`.**
`drift/budget/row_steps`, default 65 536 = the picture's own ceiling, so
nothing drawable is throttled by default and a gate pins the number to
the engine constant; read once before any spray runs, then spindrift's
`plan` over the bank from fed inputs — staleness from the spray,
`in_frustum` from the PLANE's camera paths (what the pose publisher
writes and a replay's re-flown camera writes again; the frustum's shape
is a run constant; no camera on the plane reads as in view),
`touches_dynamic` against last frame's dynamic pool excluding the spray's
own leaves. A carried-over spray is `carryOver`ed and spindrift says
`throttled` on a mailbox the bridge declares at light and drops at drop;
the bridge never writes it. The governor is a host thing and pure: an
EMA of the sweep's ms, every ten frames a proportional cut floored at 256
rows or a ×1.25 relaxation toward the AUTHORED value (a person's slider
under a governed budget is heard) and never past it; its one act is a
plane write from a new `Source.governor` that replay re-applies from the
log and never regenerates, and the live governor stands down while
replaying. Its target, `drift/budget/sweep_ms`, defaults to 0 = off: a
governor on by default makes every capture a function of the machine's
speed, and the refs must not be. Read-aloud: `sweep_ms` says what is
measured and its unit; rejected `target_ms` (target of what?),
`governor_ms` (names the mechanism), `frame_share` (a fraction nobody
types). The applet gains a `throttled` meter beside `refused`: a mailbox
path reads as its LATEST record, and the copy says so — "the number is
how many ticks in a row it has waited … a `throttled 1` beside a rising
count is a spray that was skipped once and has run since"; Perf shows
the budget under row steps.

**(d) G6 in the engine — `d50b100`.** Two sprays in the engine's frame
order, a 300-row burst under 40 row-steps for 25 frames; `throttled`
occurs for both; two runs give byte-identical dumps and a byte-identical
hash of every drift write, hashed frame by frame as the writes are
applied (a value delta's blob points at the live entry, so an end-of-run
hash would read every count as the last one). The transcript is compared
FIRST. The mutation — the clock's nanoseconds mod 7 added to the
staleness — fails both gates on the transcript hash. Headless with the
binary: two runs, both sprays' dumps `cmp` identical, 38 of 60 frames
carried a spray over, the governor wrote the knob 0 times.

**Ruling 17 — `618f499`.** The refs harness stamps its build in the
manifest and bands timings only under ReleaseFast; under Debug they are
"recorded, not banded".

**(e) The captures — `8712c7b`.** What the first capture found: the
test_scene hashes did not move, because an ember thrown up at 3.5 under
−2.5 comes back after 2.8 s and the rig's 1.8 s life perished every one
in the air. The rig's life is 4 s now, the applet's cited line and
default follow, and a capture pair may name its own frame count.

## What each engine mutation caught

| mutation | caught by |
|---|---|
| the World answers the row's own `from + (to − from)·t` | the world gate on the box top (65537 for 65536; deep inside, 99614 for 108134). **Survived on the plate**: 1.65 sits 0.4 ulp above its Q16.16 floor, so the floored product lands on the same bits for any realistic t. The row gate lands on the box too for that reason — a landing gate on one surface watches the arithmetic's luck. |
| the knob read and planned per spray | the one-knob-one-plan gate (`planned 60` for 30) and three with it |
| staleness zeroed in the priority | the starvation gate (`b.ticks` 2 for 3) |
| the frustum from the renderer's camera | the plane-camera gate (yaw 0 / yaw π / no camera; `readCamera` null regardless) |
| the spray's own leaf counted as dynamic contact | the own-leaf gate |
| the governor pinning the bank instead of writing the plane | the replay gate (the plans diverge) |
| a wall-clock read in the priority (nanoseconds mod 7) | both engine G6 gates, on the transcript hash |

## The captures

- `tools/refs/spray/test_scene-embers-plate.ppm` / `.png` — the plate
  from its +x side: a dense plume of orange-gold discs rising off its
  centre, and on the plate's top a carpet of paler, cooling embers lying
  around the gnomon, with a few dark-red ones past the plate's edges on
  the grass. That carpet is `collide | stick`.
- `oa_spirit3-sparks.ppm` / `.png` — the Quake-3 floor with its pale
  trim: a burst of hot white-gold sparks over the trim junction, and the
  ones that flew farthest lying red and orange on the floor and along the
  trim to the lower left.
- `test_scene-embers.ppm` — the gate's frame at the frozen pose.

Hashes, exact arguments and `# build: Debug` in
`tools/refs/spray/manifest.txt`; the frames gitignored, regenerated by
`spray_gate.py capture`.

## Rulings landed

Rulings 17 (the refs build), 18 (half-pixel coverage) and 19 (beat 3
ratified as reported) in §7; the practice *a prose claim about a refusal
is a gate to run* in the ledger's rules. G6 is green and bitten, in
spindrift's harness and in the engine, both on the transcript as well as
the dumps. `mounted` replaced `lit` on the applet before the beat opened;
the dock's paragraph was its own body prose, untouched by any beat.

## Needs a ruling

1. **`collide` tests the move as of the kernel's start; the integrate
   makes the move as of its end.** Rill's row rule is that every node in
   a row's sweep reads the tick's snapshot and the writes land after —
   so `collide` sees the velocity before this tick's `gravity`, and the
   integrate uses the velocity after it. The two differ by the tick's
   acceleration × dt²: 0.0007 cells at 60 Hz, 0.1 cells on a 100 ms
   headless tick — enough to put a row through the 0.15-thick plate's
   midplane with no hit, which is what the engine's came-through-face
   placement absorbs. Three honest spellings: (A) keep the rule and say
   it — `collide` tests the kernel-start move, hosts place a row found
   inside on the face it came through (built); (B) integrate with the
   kernel-start velocity too (explicit Euler), so the segment IS the
   move, at the cost of every dump and capture hash moving once; (C) a
   rill change letting `collide` read the velocity as it will be, which
   breaks the snapshot rule for one word. Lean: (A), documented in
   `drift-words.md` and the campaign, with (B) as the switch if a
   customer scene shows the tunnel at frame rate.
2. **`spray burst` is not transcript weight.** `--record` carries knob
   writes (the governor's rides it), but a burst by `--exec-at` does not,
   so a record/replay pair with a burst is not like-for-like and the
   replay planned differently. Lean: every spray verb that moves the
   population is fed input and belongs on the transcript.
3. **Three engine choices to ratify:** the budget's default is the
   picture's ceiling (65 536 rows); the governor is off by default
   (`sweep_ms` 0) so captures are not a function of the machine; the
   applet's `throttled` meter shows the latest occurrence, not a count.
4. **The material id is index + 1** so that 0 means "nothing named"; a
   kernel reading `material` gets a number one off the engine's table.
   Material by name is the trigger; until then, is the +1 acceptable?

## Recorded, not built (the engine half)

| what | trigger |
|---|---|
| a rill leaning on the budget through a lane (`.modulation` refused by the ROUTES gate) | the first rill that wants to |
| `probe` on a `drift/@…` path | someone probing a spray path from the console |
| a per-spray budget (the knob is the bank's) | a rig wanting one spray starved before another |
| a counted unresolved-instance miss in the world walk | a scene that shows a placed instance traced untransformed |

## Write-verbs beat 1 ran in parallel — matryoshka `352943d` (pushed)

The spray knobs as the verb's first customer, as briefed after beat 2 and
ruled at beat 3. Built by a delegated agent and reviewed here. The
acceptance mask lives on the kind — `Plane.SPRAY_KNOB_LANES`: `rate` and
`speed` add|mul, `spread` add, `life` mul, `hold` on all four — and the
bridge's `KNOB_LANES` is now that table by name, so the refusal text is
derived from the bools and cannot drift from them. A program's bare
`write plane.drift.@embers.rate` is refused at MOUNT naming `hold` ("a
rig knob's base is the rig's; seize it with `hold`, or modulate with
`add|mul`"), and again at the write barrier a tick late if the walk is
bypassed; a mode outside the mask refuses as "this rig knob's lanes are
`add` — or seize it with `hold`". Console and applet bare writes stay
AUTHORED, beat 3 (f)'s door. **The interim is gone:** `foldKnobLanes` and
`Plane.pathLanesFold` are deleted, and the bank reads the plane's one fold
back each tick on all four knobs, `life` through an f64 nanosecond read
whose whole milliseconds are `msToNs`'s bits. Six gates, each with its
bitten mutation: the mask at mount (`spread` widened to `mul` in the
table — `spreadmul` mounts); the bare write naming `hold` (the walk's
branch never matches — the mount-time line is missing); the order-permute
(base 40, console add 20, rill add 10, rill mul 2 = 140, not 110/130/120);
the seat (`pl.base orelse held` — 40 with the seat at 100); retraction to
the authored bits (80, not 40); the fold read back (`liveKnob` returning
the authored value — 40 under a 20 add). Matryoshka's suite: 2517 (was
2515). Recorded, not built: a program's `inc` on a rig knob still reaches
the entry through the registry-knob precedent — trigger: the first rill
that `inc`s a spray knob and expects a lane.

On the way it hit this beat's rename mid-flight — the bridge read
`last.throttled`, which spindrift had just renamed — and landed the
rename as its own commit first (`4abd61e`: the count is `refused`,
published as `drift/@<name>/refused`, the applet's meter and copy with
it), which is the order the ruling asked for: two facts, two words, and
the `throttled` occurrence arrives with the engine's scheduler.
