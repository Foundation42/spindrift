#!/usr/bin/env python3
"""read_dump — read a spindrift population dump with the struple Python port.

No spindrift code on this side: the dump is one canonical struple map and
`struple.unpack` is the whole reader. This is the cross-language half of
the dump gate (recon R-b §5) — a format only Zig can read is a format with
one witness. Run by `zig build verify-dump`, which produces a dump with
drift-run first.

Prints the scalars, checks the shape (every array is `live` long, ids are
ascending and unique, every value is an int), and exits non-zero on any
disagreement.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "struple", "py"))

import struple  # noqa: E402

ARRAYS = [
    "ids", "gen", "pos_x", "pos_y", "pos_z", "vel_x", "vel_y", "vel_z",
    "age", "life", "seed", "size", "col_l", "col_a", "col_b", "kind",
    "u0", "u1", "u2", "u3", "stuck", "nrm_x", "nrm_y", "nrm_z",
    "alpha",
]
SCALARS = ["fmt", "tick", "capacity", "live"]


def fail(msg):
    print(f"read_dump: {msg}", file=sys.stderr)
    sys.exit(1)


def main(path):
    with open(path, "rb") as f:
        data = f.read()
    elems = struple.unpack(data)
    if len(elems) != 1 or not isinstance(elems[0], dict):
        fail(f"expected one map, got {type(elems[0]).__name__ if elems else 'nothing'}")
    m = elems[0]

    for k in SCALARS:
        if k not in m or not isinstance(m[k], int):
            fail(f"scalar {k!r} missing or not an int")
    if m["fmt"] != 4:
        fail(f"fmt {m['fmt']} is not 4")
    live = m["live"]
    for k in ARRAYS:
        if k not in m or not isinstance(m[k], list):
            fail(f"array {k!r} missing")
        if len(m[k]) != live:
            fail(f"array {k!r} has {len(m[k])} entries, live is {live}")
        if any(not isinstance(v, int) for v in m[k]):
            fail(f"array {k!r} carries a non-int")
    ids = m["ids"]
    if ids != sorted(ids) or len(set(ids)) != len(ids):
        fail("ids are not ascending and unique")
    if any(i >= m["capacity"] for i in ids):
        fail("an id is past capacity")
    # alpha is the row's opacity in [0, 1] (Q16.16): the field's bounds hold
    # on the writer's side, so a value outside is a writer bug, not a row.
    if any(v < 0 or v > 65536 for v in m["alpha"]):
        fail("an alpha is outside [0, 1]")
    extra = set(m) - set(SCALARS) - set(ARRAYS)
    if extra:
        fail(f"unexpected keys {sorted(extra)}")

    print(f"fmt {m['fmt']}  tick {m['tick']}  capacity {m['capacity']}  live {live}")
    if live:
        lo = min(m["pos_y"]) / 65536.0
        hi = max(m["pos_y"]) / 65536.0
        print(f"pos_y in [{lo:.4f}, {hi:.4f}] cells; ages {min(m['age'])/1e9:.3f}..{max(m['age'])/1e9:.3f} s")
    print("read_dump: ok")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: read_dump.py <dump.struple>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
