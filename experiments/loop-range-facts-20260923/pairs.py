#!/usr/bin/env python3
"""Paired per-round ratios from a bench.py JSON: each arm against zig-fast and
the lane (`my`, `my-array`) against its before arm (`vecblock`,
`array:vecblock`), medians with 95% bootstrap intervals.
usage: pairs.py RESULT.json"""
import json
import random
import statistics
import sys


def ratio(a, b, reps=4000, seed=20260923):
    pairs = [x / y for x, y in zip(a, b)]
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(reps))
    return statistics.median(pairs), meds[int(0.025 * reps)], meds[int(0.975 * reps) - 1]


data = json.load(open(sys.argv[1]))
print("| program | Zig ms | before (vecblock) × Zig | lane × Zig | lane ÷ before [95% CI] |")
print("|---|---:|---:|---:|---|")
for name, entry in data["benchmarks"].items():
    arms = entry["arms"]
    zig = arms["zig-fast"]["wall"]
    for lane, before, label in (("my", "vecblock", name), ("my-array", "array:vecblock", name + "_array")):
        if lane not in arms or before not in arms or "wall" not in arms[lane]:
            continue
        l = ratio(arms[lane]["wall"], zig)[0]
        b = ratio(arms[before]["wall"], zig)[0]
        m, lo, hi = ratio(arms[lane]["wall"], arms[before]["wall"])
        print(f"| {label} | {statistics.median(zig) * 1000:.1f} | {b:.2f} | {l:.2f} | {m:.3f} [{lo:.3f}, {hi:.3f}] |")
