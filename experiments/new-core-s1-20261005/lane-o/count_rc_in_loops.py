#!/usr/bin/env python3
"""Count the retain/release operations left inside loops after -O3 (R-2).

Compiles a mylang-core `--emit-llvm` file with `zig cc -O3 -march=native -S` and
reads LLVM's loop annotations in the assembly (`Loop Header: Depth=N`, `in Loop:
... Depth=N`). Per loop depth it counts the count updates (the `rc.inc` and `rc.dec` blocks every inline retain
and release has: LLVM keeps the IR block names in the assembly comments) and the calls that
free, copy or allocate a block (`myl_core_free_block`, `myl_core_list_copy`,
`myl_core_list_new_slow`, `myl_core_list_grow`), and prints the innermost loops'
totals: R-2's target is 0 count updates where ownership is static.

usage: count_rc_in_loops.py FILE.ll
"""
import os, re, subprocess, sys, tempfile


def main():
    source = sys.argv[1]
    out = tempfile.mktemp(suffix=".s", dir=os.environ.get("TMPDIR"))
    subprocess.run(["zig", "cc", "-O3", "-march=native", "-S", "-Wno-override-module", "-o", out, source], check=True, stderr=subprocess.DEVNULL)
    lines = open(out).read().splitlines()
    os.unlink(out)
    depth = 0
    counts = {}
    innermost = 0
    pending = 0
    for line in lines:
        if re.match(r"^[.\w]+:", line) or line.startswith("# %bb."):
            depth = 0
            pending = 1 if re.search(r"# %rc\.(inc|dec)\.", line) else 0
            continue
        found = re.search(r"Depth=(\d+)", line)
        if found and ("Loop Header" in line or "in Loop" in line):
            depth = int(found.group(1))
            innermost = max(innermost, depth)
            continue
        entry = counts.setdefault(depth, [0, 0])
        if pending and line.startswith("\t") and not line.lstrip().startswith("#"):
            entry[0] += 1
            pending = 0
        if re.search(r"call\w*\s+(myl_core_free_block|myl_core_list_copy|myl_core_list_new_slow|myl_core_list_grow)", line):
            entry[1] += 1
    detail = ", ".join("depth %d: %d count updates, %d calls" % (k, v[0], v[1]) for k, v in sorted(counts.items()) if v != [0, 0])
    inner = counts.get(innermost, [0, 0])
    print(f"innermost loops (depth {innermost}): {inner[0]} count updates, {inner[1]} free/copy/alloc calls; all: [{detail}]")


if __name__ == "__main__":
    main()
