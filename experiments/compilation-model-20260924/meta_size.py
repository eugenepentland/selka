#!/usr/bin/env python3
"""Size of the per-function position tables today versus a compact encoding.

usage: meta_size.py MANIFEST.json

Reads a lean manifest whose units carry their metadata inline (the manifest a cold
build hands the driver) and reports, over all units:
  - pcs: bytecode instructions with a position (one table row each);
  - today: 48-byte function record + 24 bytes (path pointer, line, column) + 8 bytes
    (message pointer) per pc, and 2 absolute relocations per pc;
  - compact: the rows as a byte string of zig-zag LEB128 deltas (path index, line,
    column per pc, from the previous pc), messages as a sparse (pc, string) list, and one
    relative reference per function; no relocation per pc.
"""
import json
import sys


def leb(n):
    n = (n << 1) ^ (n >> 63)
    size = 1
    while n >= 0x80:
        n >>= 7
        size += 1
    return size


def main():
    d = json.load(open(sys.argv[1]))
    pcs = funcs = compact = asserts = 0
    for u in d["functions"]:
        meta = u.get("meta")
        if isinstance(meta, str):
            meta = json.loads(meta)
        if not isinstance(meta, dict):
            continue
        funcs += 1
        prev = (0, 0, 0)
        rows = [p for p in meta.get("positions", "").split(" ") if p]
        pcs += len(rows)
        body = 0
        for r in rows:
            f, line, col = (int(x) for x in r.split(":"))
            body += leb(f - prev[0]) + leb(line - prev[1]) + leb(col - prev[2])
            prev = (f, line, col)
        a = meta.get("assertions", [])
        asserts += len(a)
        compact += 16 + body + sum(4 + 4 for _ in a)
    today = funcs * 48 + pcs * 32
    print(json.dumps({"functions": funcs, "pcs": pcs, "pcs_per_function": round(pcs / max(funcs, 1), 1),
                      "today_bytes": today, "today_relocations": 2 * pcs + 3 * funcs,
                      "compact_bytes": compact, "ratio": round(today / max(compact, 1), 1), "assertions": asserts}))


if __name__ == "__main__":
    main()
