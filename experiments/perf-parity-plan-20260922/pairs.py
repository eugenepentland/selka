#!/usr/bin/env python3
"""Paired arm-to-arm ratios from one or more bench.py result files.

usage: pairs.py RESULT.json [...] --arm my --base l5 --base lad-l5-nr [--cpu]

For every benchmark, the per-round ratio arm/base (same round, so the same
machine state) is summarised as a median with a 95% bootstrap interval, next to
each arm's ratio to zig-fast; the last row is the geometric mean of the medians.
Several result files are pooled round by round per benchmark.
"""
import argparse
import json
import math
import random
import statistics


def boot(pairs, reps=2000, seed=7):
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(reps))
    return statistics.median(pairs), meds[int(0.025 * reps)], meds[int(0.975 * reps) - 1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+")
    ap.add_argument("--arm", default="my")
    ap.add_argument("--base", action="append", default=[])
    ap.add_argument("--cpu", action="store_true")
    opts = ap.parse_args()
    key = "cpu" if opts.cpu else "wall"
    samples = {}
    for path in opts.results:
        for name, entry in json.load(open(path))["benchmarks"].items():
            store = samples.setdefault(name, {})
            for arm, data in entry["arms"].items():
                store.setdefault(arm, []).extend(data.get(key) or [])
    columns = [f"{opts.arm}/zig"] + [f"{b}/zig" for b in opts.base] + [f"{opts.arm}/{b}" for b in opts.base]
    print("| benchmark | rounds | " + " | ".join(columns) + " |")
    print("|---|---:|" + "---:|" * len(columns))
    logs = {c: [] for c in columns}
    for name, arms in samples.items():
        ref = arms.get("zig-fast")
        if not ref or opts.arm not in arms:
            continue
        cells = []
        for arm in [opts.arm] + opts.base:
            m, lo, hi = boot([a / r for a, r in zip(arms[arm], ref)])
            cells.append(f"{m:.2f} [{lo:.2f},{hi:.2f}]")
            logs[f"{arm}/zig"].append(math.log(m))
        for b in opts.base:
            m, lo, hi = boot([a / r for a, r in zip(arms[opts.arm], arms[b])])
            cells.append(f"{m:.3f} [{lo:.3f},{hi:.3f}]")
            logs[f"{opts.arm}/{b}"].append(math.log(m))
        print(f"| {name} | {len(ref)} | " + " | ".join(cells) + " |")
    print("| **geomean** | | " + " | ".join(f"**{math.exp(sum(v) / len(v)):.3f}**" for v in logs.values()) + " |")


if __name__ == "__main__":
    main()
