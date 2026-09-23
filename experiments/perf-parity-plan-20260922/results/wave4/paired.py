#!/usr/bin/env python3
"""Paired arm-vs-arm ratios from bench.py JSON results.

usage: paired.py RESULT.json [RESULT.json ...] --num ARM --den ARM [--cpu]

Per benchmark: median of per-round ratios num/den (same round, shuffled order)
with a 95% bootstrap interval; then the geometric mean of the medians with a
bootstrap interval over rounds.
"""
import argparse
import json
import math
import random
import statistics


def boot(values, reps=2000, seed=7):
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(reps))
    return meds[int(0.025 * reps)], meds[int(0.975 * reps) - 1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+")
    ap.add_argument("--num", required=True)
    ap.add_argument("--den", required=True)
    ap.add_argument("--cpu", action="store_true")
    ap.add_argument("--only", nargs="*")
    opts = ap.parse_args()
    key = "cpu" if opts.cpu else "wall"
    rows = []
    for path in opts.results:
        d = json.load(open(path))
        for name, e in d["benchmarks"].items():
            if opts.only and name not in opts.only:
                continue
            arms = e["arms"]
            if opts.num not in arms or opts.den not in arms or key not in arms[opts.num]:
                continue
            pairs = [a / b for a, b in zip(arms[opts.num][key], arms[opts.den][key]) if b > 0]
            lo, hi = boot(pairs)
            rows.append((name, statistics.median(pairs), lo, hi, pairs, statistics.median(arms[opts.den][key]) * 1000))
    print(f"{'benchmark':16} {opts.num}/{opts.den:<10} {'95% CI':>17}   {opts.den} ms")
    for name, med, lo, hi, _, ms in rows:
        print(f"{name:16} {med:8.3f}   [{lo:.3f}, {hi:.3f}]   {ms:8.1f}")
    geo = math.exp(sum(math.log(r[1]) for r in rows) / len(rows))
    rng = random.Random(11)
    boots = []
    for _ in range(2000):
        logs = []
        for r in rows:
            logs.append(math.log(statistics.median(rng.choices(r[4], k=len(r[4])))))
        boots.append(math.exp(sum(logs) / len(logs)))
    boots.sort()
    print(f"{'geomean':16} {geo:8.3f}   [{boots[50]:.3f}, {boots[1949]:.3f}]   ({len(rows)} programs)")


if __name__ == "__main__":
    main()
