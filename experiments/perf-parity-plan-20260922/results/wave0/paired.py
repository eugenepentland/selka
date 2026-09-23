#!/usr/bin/env python3
"""Paired per-round ratio of two arms in a bench.py result, with a 95% bootstrap interval.

usage: paired.py RESULT.json BENCHMARK NUMERATOR_ARM DENOMINATOR_ARM [--cpu]

bench.py reports every arm against zig-fast. This compares any two arms of one
benchmark directly: round i of each arm ran in the same shuffled round, so the
ratio of their i-th samples is paired exactly as bench.py pairs an arm with the
reference, and the interval uses the same bootstrap (2000 resamples, seed 7).
"""
import json
import random
import statistics
import sys


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    key = "cpu" if "--cpu" in sys.argv else "wall"
    path, name, top, bottom = args
    arms = json.load(open(path))["benchmarks"][name]["arms"]
    pairs = [a / b for a, b in zip(arms[top][key], arms[bottom][key]) if b > 0]
    rng = random.Random(7)
    meds = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(2000))
    print(f"{name}: {top} / {bottom} ({key}) = {statistics.median(pairs):.3f} "
          f"[{meds[50]:.3f}, {meds[1949]:.3f}] over {len(pairs)} rounds; "
          f"medians {statistics.median(arms[top][key]) * 1000:.1f} ms / {statistics.median(arms[bottom][key]) * 1000:.1f} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
