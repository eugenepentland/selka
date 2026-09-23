#!/usr/bin/env python3
"""paired_table.py PAIRED.json — lane/before per benchmark: median of per-round ratios with a
95% bootstrap interval, plus each arm's ratio to Zig."""
import json
import math
import random
import statistics
import sys

d = json.load(open(sys.argv[1]))
rng = random.Random(7)
print("| benchmark | before ×Zig | lane ×Zig | lane/before [95% CI] |")
print("|---|---:|---:|---|")
logs = []
for name, b in d["benchmarks"].items():
    arms = b["arms"]
    if "before" not in arms or "lane" not in arms or "wall" not in arms["lane"]:
        continue
    lw, bw, zw = arms["lane"]["wall"], arms["before"]["wall"], arms["zig-fast"]["wall"]
    pairs = [l / p for l, p in zip(lw, bw)]
    med = statistics.median(pairs)
    boots = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(2000))
    lo, hi = boots[50], boots[1949]
    zb = statistics.median(p / z for p, z in zip(bw, zw))
    zl = statistics.median(l / z for l, z in zip(lw, zw))
    logs.append(math.log(med))
    print(f"| {name} | {zb:.2f} | {zl:.2f} | {med:.3f} [{lo:.3f}, {hi:.3f}] |")
print(f"| **geomean** | | | **{math.exp(sum(logs) / len(logs)):.3f}** |")
