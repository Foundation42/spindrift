# Beat 7 — the cloud: smoke over the plate is a cloud, not a column of coins

*CC, 2026-09-05. Campaign 2 (`docs/spindrift-campaign-2.md`), P7, G9.
Built straight after P6 on Christian's word.*

## What landed

**Matryoshka `b4be987`**, and nothing in spindrift's row — a soft rim is
the kind's, a fade the row's. `soft` is the fraction of a disc's radius
over which its alpha falls from the row's to zero, in [0, 1]: 0 the hard
disc of every frozen pair, 1 a cone from the centre. It rides the
archetype's three formats as the appearance does:

- the rig line — `sprayarche <name> … <kernel> <appearance> <soft>`, the
  token always written, absent reads 0;
- the Project pack — a `soft` field, absent 0, outside [0, 1] a bad pack;
- the console — `sprayarche soft <kind> <fraction>`, live, not a kind edit.

One validation for all three, refusing outside [0, 1], never clamping.
The leaf multiplies alpha by the profile `clamp((1 − delta/radius) /
soft, 0, 1)` and beat 6's test follows unchanged; the CPU twin restates
it.

**One change from the plan.** P6 reserved the slot's spare lanes for the
kind's numbers. Built, `soft` rides the run's leaf payload, not a
per-row copy: the upload skips chunks the sim did not dirty, so a
per-row copy would go stale on still rows after a retune. A retune now
reaches every row the next frame.

## The gates, and what bit them

| gate | the mutation that bit |
|---|---|
| **G9**, twin: r = 30 px on a 64² block at soft 1 → 918 hits against the cone's integral 942.5 (σ 21.7), and the integral is a third of the disc on paper (942.7); soft 0 every pixel inside; soft 0.5 the inner half solid; outside never | the profile at 2r — 1876 hits, 43σ |
| rig round-trip: 0.35 survives; a `set` with no soft column keeps it; 1.5 and −0.1 refused | (structural) |
| Project round-trip: 0.35 survives the pack | (structural) |
| the rig-line byte gate | bit on the new token — the line's shape changed and the gate said so; literal updated |
| the lab: four test_scene pairs bit-identical at soft 0; the smoke pair differs from bare | the SHADER ignoring soft — the smoke pair moved to `64cb9ab4…` |

Suite 2561/2561. The control-root compile failure stands as found in
beat 6.

## The capture

`test_scene-smoke`, `ea0205d0…`: the plate pose, one kind `smoke` at
soft 0.7, `kernels/smoke.rill` — grey, non-emissive, growing from 25 cm
to 1.2 m, rising, fading over six seconds. What the frame shows is a
dithered grey column: a capture is FIXED sampling by design, so a soft
rim is a dither at one sample and converges to the profile only under
the sequence. The smooth cloud is the accumulated frame, which no
capture shows; Christian is the judge of the picture, and the kernel's
curves are a first guess.

## Decisions taken, for ratification

1. **The kind's numbers ride the leaf payload**, not the row's slot. The
   slot's spare lanes stay spare.
2. **`sprayarche set` leaves a kind's soft edge as it was** (the spec's
   `soft` is optional). Noted, not changed: the same verb RESETS the
   appearance to `sprite` today, since the spec's default is the tenant's
   — a pre-existing quirk, yours to rule on.
3. **A soft mote is a little under-drawn**: a narrow disc takes the
   profile at the ray's offset, not integrated over the footprint. Stated
   in the twin's doc; the cloud is wide.

## Next

P8, the glow: the read of the bloom chain first — whether an emissive
disc already reaches it through the self-brightness gate — then the
coals as emitting sprites beside the light rows, and a calibration for
your eye.
