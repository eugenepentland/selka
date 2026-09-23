#!/usr/bin/env python3
"""verdicts.py SSA... — print the sticky-loop verdict of every innermost loop of each unit.
With -o DIR also write the rewritten unit's LLVM IR to DIR/<name>.ll."""
import glob
import os
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "llvm-backend"))
import qbe_llvm  # noqa: E402
import sticky_loops  # noqa: E402

args = sys.argv[1:]
out = None
if args and args[0] == "-o":
    out, args = args[1], args[2:]
paths = []
for a in args:
    paths.extend(sorted(glob.glob(a)) if any(c in a for c in "*?[") else [a])
for path in paths:
    unit = qbe_llvm.parse_unit(open(path).read(), os.path.basename(path))
    for header, verdict in sticky_loops.version_loops(unit):
        print(f"{path.split('/census-')[-1][:60]} {header} {verdict}")
