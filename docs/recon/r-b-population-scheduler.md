# Recon R-b — population and scheduler (CC, 2026-09-01)

*Read against `docs/spindrift-campaign.md` §3.1, §3.6, §2 (G0, G6) and
`common/src/jobs.zig` at `9a75dfb`, rill `d4ebe12`, matryoshka `cda0fd4`.
Nothing is built with this note; what it proposes is P0's shape and P0 is
the evidence. Rulings marked **fork** are Christian's.*

---

## 1. The SoA layout against what `jobs.zig` wants

**What the scheduler offers.** `JobSystem.parallelFor(count, batch_size,
func, context, counter)` (`jobs.zig:498`) splits `[0, count)` into
`[start, end)` batches, one `Job` each, and hands every batch a
`BatchRange { start, end, context }` in the job's 48 inline bytes. The
caller then `waitFor(counter)` and helps execute. That is the whole
contract: **the unit of work is an index range**, and the callee slices
whatever it owns by `[start..end)`.

**What that asks of the population.** Nothing more than the campaign's
SoA already gives: one contiguous array per field, indexed by row id. A
chunk is `pos_x[start..end]`, `vel_y[start..end]`, and so on — no gather,
no per-row struct, each field a straight streaming read. The layout in
§3.1 is confirmed as stated, with two decisions the table leaves open and
P0 makes:

| field | §3.1 says | P0 layout | why |
|---|---|---|---|
| pos | i32×3, scene lattice | **3 × `[]i32`, Q16.16 fixed** — integer part is the lattice cell, 16 fractional bits sub-cell | a particle at 0.3 cells/tick must move; a pure lattice integer with truncation per tick never does (§2 below) |
| vel | fixed-point ×3 | 3 × `[]i32`, Q16.16 cells/s | same scale as pos so `pos += vel·dt` is one multiply-shift |
| age, life | fed ticks | `[]u32` each | ticks, never ns — dt is fed and life is a count of it |
| seed | u32 | `[]u32` | per-row decorrelator, from the emitter seed and the spawn ordinal |
| size | fixed | `[]i32` Q16.16 | |
| colour | Oklab fixed | 3 × `[]i32` Q16.16 | L, a, b |
| kind | u8 | `[]u8` | |
| user | ≤4 fixed | 4 × `[]i32` | kernel scratch; R-a §2 says which words need how many |
| *alive* | — | `[]bool` | the dead-row mask (§3); a row on the freelist is not iterated |

Field-major, never row-major. Sixteen arrays, one allocation each at
mount, capacity from the archetype. **Nothing grows.**

**Q16.16.** ±32768 cells range, 1/65536 cell resolution; a Q16.16 × Q16.16
product is one i64 multiply and a 16-bit shift. Integer-only arithmetic
throughout the P0 sim, so G0 is byte-identity with no float in the loop
and G7's bit-identity claim (R-a §5) is at least true of the stand-in.

## 2. The lattice, and which one

Matryoshka has **two** lattices, and "the same lattice the BVH quantises
to" names the wrong one for a position:

- `gauge_quantise.zig` — `Config { bits: 20, origin, extent }`, step =
  `extent / (2²⁰ − 1)` (**not** a power of two, deliberately), Morton key
  `mortonKey3` over `latticeIndices` (`:471,478`); the scene-wide default
  Morton-orders BLAS roots (`mesh_bvh.zig:1241`). 21 bits/axis is the
  packing limit.
- `mesh_bvh_slim.zig` — the shipping node format's `SlimLattice { origin,
  step, e, m }` with **`step == 2^e` exactly** (`:98`).

A Q16.16 position is a dyadic lattice: it converts to the slim lattice by
a shift and to the gauge lattice by a multiply. A Morton key is derivable
from the top bits either way. **Fork 1:** which lattice `pos` is
addressed to. Lean: dyadic (Q16.16 in cells, cell = a power-of-two
fraction of a metre, declared per emitter), because it makes the position
arithmetic shift-only and matches the node format the GPU reads. The
gauge lattice conversion is a multiply at the leaf boundary (P3), once
per upload, not per row per tick.

## 3. Chunk size, and the phases that must not chunk

**Proposal: 1024 rows per chunk.** Row width across all sixteen arrays is
≈ 69 bytes, so a chunk streams ≈ 70 KB — inside L2 on the 9950X3D with
room for the kernel's scratch. A 65 536-row emitter is 64 jobs; a 512-row
one is a single job and runs inline on the caller (`schedule` falls back
to executing when nothing is queued, `jobs.zig:443`). Not measured; P0
makes it a knob-shaped constant so the first customer scene can move it.

**Determinism under chunking** holds only for the phase that is
row-local. The tick is three phases and only the middle one is parallel:

1. **spawn** — serial. Pops the freelist in a fixed order, so which id a
   new row gets is a function of fed history and nothing else.
2. **kernel** — `parallelFor` over `[0, capacity)` in chunks; every row
   reads and writes its own fields only. No inter-particle anything
   (fence, §6), so chunk boundaries and thread scheduling cannot reach
   the result. Dead rows are skipped by the alive mask.
3. **perish** — serial, ascending row id: `age ≥ life` pushes the row
   onto the freelist. Ascending order is what makes the freelist's
   *contents* deterministic, which makes the next spawn's ids
   deterministic.

Putting perish inside the parallel kernel — each chunk pushing its dead
onto a shared freelist — would make the push order a race and the next
tick's ids nondeterministic even though every row's own fields were
right. G0 would catch it (two runs differ in which slot a spawn lands),
and it is worth saying that G0 is the gate that *forces* this shape, not
merely one that checks it.

## 4. The freelist keeps ids stable for a row's life — confirmed

A row's id is its index. The population never compacts, never moves a
row, never reuses an index while the row is alive: the freelist holds
*dead* indices only, a spawn pops one, a perish pushes one, and a live
row is in neither list. Stability is by construction rather than by
policy — there is no code path that could renumber a living row. The
gate (`tests.zig`, "freelist: a row keeps its id for its whole life")
spawns, perishes a subset, spawns again, and asserts every surviving
row's id and fields are untouched and no new row landed on a live id.

**One consequence for the sensor precondition** ("something will want to
watch a particle"): an id is reused after death. A watcher that holds an
id across a death sees a different particle. P0 gives each row a
**generation** counter beside the alive mask (`[]u16`, bumped on spawn),
so a handle is `(id, gen)` and a stale handle is refusable rather than
silently re-pointed. Cheap now; recorded as the sensor's handle shape.

## 5. The dump format

Requirements: byte-comparable across runs, readable from Python via the
struple port, a pure function of population state.

**One struple map**, canonical (struple's `appendMap` sorts keys, so the
bytes are fixed by content):

```
{
  fmt: 1,
  tick: <u64 fed ticks>,
  capacity: <n>,
  live: <count>,
  ids: [<live row ids, ascending>],
  gen:      [per live row, ids order],
  pos_x: [...], pos_y: [...], pos_z: [...],      // Q16.16 raw ints
  vel_x: [...], vel_y: [...], vel_z: [...],
  age: [...], life: [...], seed: [...],
  size: [...], col_l: [...], col_a: [...], col_b: [...],
  kind: [...], u0: [...], u1: [...], u2: [...], u3: [...]
}
```

Field-major like memory, live rows only, in ascending id order. Every
number is a struple int — fixed-point rides raw, so the dump is exact and
the Python side reads `struple.decode()` into lists with no float
anywhere. A `digest` (Wyhash of the map bytes) is *printed* by `drift-run`
beside the file for eyeballing, and is not in the map — a digest inside
the thing it digests is a fixed-point problem nobody needs.

**Fork 2:** whether dead rows ride in the dump. Lean: no — a dead row's
fields are stale scratch, and a dump that carried them would make two
identical populations differ by what died when. The freelist order *is*
observable through the next spawn's ids, which the dump carries.

## 6. What `rill-run`'s mock plane needs to host an emitter

**Nothing in rill.** `rill-run` is rill's binary and rill does not depend
on spindrift, so the emitter cannot be mounted *in* it. What it needs is
already exported: `rill.MockPlane` (a path→struple store with a write
log, a cast log and a tag log), `rill.Registry` + `registerCore`,
`rill.Runtime.mount/feed/tick`, and `MountOpts.host_ctx`. Spindrift ships
**`drift-run`** with `rill-run`'s flag grammar (`--seed`, `--tick`,
`--ticks`, a fixed dt) and the emitter mounted beside an optional `.rill`
on the same `MockPlane`:

- the emitter reads its knobs (`rate`, `speed`, `spread`, `life`,
  `gravity`) from the plane each tick at `plane.drift.@<name>.<knob>`, so
  a mounted rill that writes those paths drives the emitter — the CHOPs
  layer of §3.3, working at P0 with zero new rill;
- `--fixed-dt <ms>` is the only clock; `time_ns = tick × dt` is fed to
  both the rill runtime and the sim;
- `--dump <file>` writes §5's struple after the last tick and prints its
  digest.

The mock `World` (a floor at y = 0) is a `World` vtable — `ground(pos) →
{distance, normal}` and `collide(from, to) → ?{t, normal}` — that P0
builds and gates but **no P0 word calls**: `collide`/`stick` are P4's
words and need their read-aloud. Recorded-not-built, trigger: P4's
`collide`. The interface exists now so that P4 adds a caller and not a
seam.

**The mock plane's one gap for G1 (P1):** publishing `drift/<@em>/count`
is a `Plane.write` and the mock records it; a second rill reading it is a
`plane.drift.<@em>.count` subscription, and the mock serves reads from
its store — which `writeThunk` fills for `.base` writes. So G1's loop
closes on the mock with nothing added. Absence (unmount ⇒ `count` says
zero) is a final write on unmount, the S5 precedent (`Watch.declare`
publishes a zero baseline; a stood-down post writes nothing further).

## 7. Budget (G6) — shape only, not built

`drift/budget/row_steps` is a knob the scheduler reads once per tick; the
tick consumes it across emitters in a priority order computed from fed
inputs. P0 counts row-steps (the kernel phase increments a per-emitter
counter by rows evaluated) so the number exists from the first tick and
the Perf sparkline has something to read; it enforces nothing. The
governor and the priority order are P4.

## 8. Forks

1. **Which lattice `pos` addresses** (§2). Lean: dyadic Q16.16 cells.
2. **Dead rows in the dump** (§5). Lean: no.
3. **Life in ticks or in fed ns.** §3.1 says ticks; a `life` knob written
   from a rill is a duration. P0 stores ticks and converts at spawn from
   the knob's ms by the fixed dt. Lean: ticks in the row, duration on the
   knob, conversion at spawn — a row never carries a unit.
4. **Chunk size 1024** (§3) — a constant until a scene moves it.

## 9. Where this leaves P0

Build: `fixed.zig` (Q16.16), `population.zig` (SoA + freelist + gen),
`dump.zig`, `world.zig` (`World` + floor), `emitter.zig` (knobs, the
three-phase tick, the stand-in `spawn`/`gravity`/`perish`), `run.zig`
(`drift-run`), gates in `tests.zig`: G0 with its seed mutation, freelist
id stability, dump byte-identity and Python readability, floor `World`
answers.
