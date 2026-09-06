# Beat 12 — the look: sparks add and streak along their flight, and the shadow stops leaking through the smoke

*CC, 2026-09-06. Campaign 3 (`docs/spindrift-campaign-3.md`), P12 — the
look, with Christian's P11 finding folded in.*

## What landed

**Matryoshka `1d6f223`**, nothing in spindrift's row.

**The shadow leak, closed.** P11's card took the tracer's sun visibility
of the surface behind it, pixel for pixel, so the helmet's shadow
pattern behind the plume showed through it. The vertex stage now reads
that visibility ONCE, under the card's centre, and carries it flat: a
card is lit or shadowed whole and nothing can pattern inside it. Sky
under the centre is lit. The CSM at the fragment's world position stays
for raster-produced scenes. The true fix — a sun depth pass over the
traced geometry — is recorded with its trigger.

**`blend add`, drawn as runs.** The kind's blend rides the three formats
(the rig line's token after the streak, a pack field, `sprayarche blend
<kind> alpha|add`). The sort carries each row's mode and cuts the order
into runs where it changes; the pass draws the runs back to front, each
with the pipeline its mode asks for — a second sprite pipeline, the same
shaders with ONE/ONE, the fragment premultiplying when the look says
add. A spray of additive sparks between two alpha depths draws between
them, not after everything.

**`streak`.** The slot gains the row's velocity (64 bytes now). With the
kind's streak — seconds of travel — the card's first axis turns along
the velocity projected onto the card's plane and stretches by streak ×
speed: a spark is a dash along its flight, a still row is round. The fed
dt reaches the push for the day a streak is per tick rather than per
second; the streak is per second, so a row's dash does not change length
with the frame rate.

## The gates, and what bit them

| gate | green | the mutation that bit |
|---|---|---|
| **G12** nothing mounted, nothing moved | `refs.py verify test_scene` unmoved; every bare unchanged | structural |
| **G16** re-gated on the leak | the shaded smoke re-frozen with one visibility per card | the visibility read per fragment again — the shaded smoke MOVED (5f51a172 → 4ba8bcbc) |
| **G14** extended: runs by blend | the bridge's gate — an additive spray between two alpha depths makes three runs in order, one mode makes one; the fed dt is the tick's | the run cut by spray, not blend — the gate read three runs where one mode should make one |
| the sparks pair: additive and streaked | `test_scene-sparks` frozen | an additive run drawn with the alpha pipeline — the sparks MOVED (f67bdb82 → 0808f93b); the streak's axis from the position instead of the velocity — the sparks MOVED (f67bdb82 → 96852981) |
| the kind's formats | the rig round-trip carries 0.05 and `add`, a blend by another name refused, `-` alpha; the Project round-trip; the rig-line byte gate takes the two tokens | (structural) |

Suite 2566/2566; the control-root compile failure stands as found. G18:
the eight pairs held on the clean rebuild.

## The captures

Eight plate-family pairs frozen through P12; every bare unchanged:

| pair | P11 | P12 |
|---|---|---|
| test_scene-embers | 4c5c268e… | 5857879c… |
| test_scene-embers-plate | ded85519… | d52170c6… |
| test_scene-embers-plate-beneath | 14a9e734… | a4bede9e… |
| test_scene-fade | 3bba8919… | 876bd53e… |
| test_scene-smoke | 50a1bd43… | d5d72aa1… |
| test_scene-behind | c79317fd… | c79317fd… |
| test_scene-smoke-shade | 5edfc765… | 5f51a172… |
| test_scene-sparks (new) | — | f67bdb82… |

The sparks are a fountain of additive dashes along their flight over the
coals' pool, dots once landed; the plume is unchanged in kind, its
visibility one number per card. The behind pair, cards-free, is the
same bytes as P11's.

## Decisions taken, for ratification

1. **One visibility per card**, at the centre, rather than a blurred
   per-fragment read: a blur would still paint a soft version of the
   surface's shadow onto the air. The real fix is a shadow map that
   knows the traced geometry; recorded.
2. **Runs by blend, in the sorted order**, rather than all alpha then all
   additive: an additive spark behind smoke stays behind it. The cost is
   a pipeline bind per run; the sparks rig makes three.
3. **The streak is an ellipse**, the disc stretched along the velocity,
   not a capsule: the fragment's disc test is unchanged and the soft
   edge still works. A capsule with round ends is a fill if a customer
   wants one.
4. **The streak is seconds of travel**, so the dash's length does not
   depend on the frame rate.

## Found

**A name clash with the bank's own `runs`.** The accessor is
`spriteRuns`; the upload's local kept its name.

**The epoch is at time zero.** The fed dt's "have a previous tick" was a
comparison against zero, which the epoch satisfies; it is a bit now.

**Memory kills at rebuilds, again.** The closing steps ran in the
foreground in pieces; one piece went past ten minutes and finished in
the background regardless.

## Next

The close of campaign 3: the whole set re-captured once — dust2's
motes, oa_spirit3's sparks, the tiltyard — with the before and after in
the report; then "the puff" from the Blade3D recon.
