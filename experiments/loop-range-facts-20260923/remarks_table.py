#!/usr/bin/env python3
"""Count LTO loop-vectorizer remarks per program for two remark directories
(each holds `<program>.yaml` written by the LTO link's --opt-remarks-filename):
vectorized loops, and the missed-vectorization reasons for loops that stayed
scalar, restricted to the guest's code (`entry_run`, which the guest `main` is inlined into, and `myl_f_*`).
usage: remarks_table.py BEFORE_DIR AFTER_DIR PROGRAM..."""
import collections
import os
import re
import sys


def load(path):
    """Remarks of one program: the LTO link's `<program>.yaml` and every
    unit compile's `<program>.units/*.yaml` (full LTO's per-unit pre-link
    optimization already vectorizes most loops)."""
    counts = collections.Counter()
    widths = []
    texts = [open(path).read()] if os.path.exists(path) else []
    units = path[: -len(".yaml")] + ".units"
    if os.path.isdir(units):
        texts += [open(os.path.join(units, f)).read() for f in sorted(os.listdir(units))]
    for doc in re.split(r"^--- ", "\n".join(texts), flags=re.M):
        kind = re.match(r"!(\w+)", doc)
        name = re.search(r"^Name:\s+(\S+)", doc, re.M)
        function = re.search(r"^Function:\s+(\S+)", doc, re.M)
        if not kind or not name or not function:
            continue
        if not (function.group(1) == "entry_run" or function.group(1).startswith("myl_f_")):
            continue
        if kind.group(1) == "Passed" and name.group(1) == "Vectorized":
            counts["vectorized"] += 1
            width = re.search(r"VectorizationFactor:\s+'?(\w+)", doc)
            widths.append(width.group(1) if width else "?")
        elif kind.group(1) == "Analysis":
            counts[name.group(1)] += 1
    return counts, widths


before, after, *programs = sys.argv[1:]
print("| program | vectorized loops before | after | vector widths after | reasons (before → after) |")
print("|---|---:|---:|---|---|")
for program in programs:
    b, _ = load(os.path.join(before, program + ".yaml"))
    a, widths = load(os.path.join(after, program + ".yaml"))
    reasons = []
    for key in ("CantComputeNumberOfIterations", "TooManyUncountableEarlyExits", "EarlyExitNotLatchPredecessor",
                "UnsupportedUncountableLoop", "CantVectorizeLibcall", "NonReductionValueUsedOutsideLoop"):
        if b[key] or a[key]:
            reasons.append(f"{key} {b[key]}→{a[key]}")
    print(f"| {program} | {b['vectorized']} | {a['vectorized']} | {', '.join(widths)} | {'; '.join(reasons)} |")
