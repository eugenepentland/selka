#!/usr/bin/env python3
"""Markdown table for the report from R6 (suite + micro)."""
import json
import math
import random
import statistics
import sys


def paired(arms, num, den, key="wall"):
    pairs = [a / b for a, b in zip(arms[num][key], arms[den][key])]
    rng = random.Random(7)
    meds = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(2000))
    return statistics.median(pairs), meds[50], meds[1949], pairs


rows = []
for path in sys.argv[1:]:
    d = json.load(open(path))
    for name, e in d["benchmarks"].items():
        a = e["arms"]
        zb = a["before"]["ratio_wall"]["median"]
        zm = a["my"]["ratio_wall"]["median"]
        m, lo, hi, p = paired(a, "my", "before")
        f, _, _, fp = paired(a, "fr", "before")
        k, _, _, kp = paired(a, "my", "fr")
        rows.append((name, zb, zm, m, lo, hi, f, k, p, fp))
print("| program | base / Zig | lane / Zig | lane / base [95% CI] | ladder rung / base | lane / ladder rung |")
print("|---|---:|---:|---:|---:|---:|")
for name, zb, zm, m, lo, hi, f, k, *_ in rows:
    print(f"| {name} | {zb:.2f} | {zm:.2f} | {m:.3f} [{lo:.3f}, {hi:.3f}] | {f:.3f} | {k:.3f} |")
suite = [r for r in rows if r[0] not in ("fib", "calls")]
def geo(vals):
    return math.exp(sum(math.log(v) for v in vals) / len(vals))
print(f"| **13-program geomean** | {geo([r[1] for r in suite]):.2f} | {geo([r[2] for r in suite]):.2f} | **{geo([r[3] for r in suite]):.3f}** | {geo([r[6] for r in suite]):.3f} | {geo([r[7] for r in suite]):.3f} |")
