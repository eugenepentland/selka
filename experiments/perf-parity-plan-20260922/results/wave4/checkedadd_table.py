#!/usr/bin/env python3
"""The checked-arithmetic lane's report table: paired medians per program.

usage: checkedadd_table.py RESULT.json [RESULT.json]  (the second gives an extra lane/before column)
"""
import json
import math
import random
import statistics
import sys


def ratios(arms, num, den):
    return [a / b for a, b in zip(arms[num]["wall"], arms[den]["wall"]) if b > 0]


def interval(values, reps=2000, seed=7):
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(reps))
    return meds[int(0.025 * reps)], meds[int(0.975 * reps) - 1]


def main():
    main_result = json.load(open(sys.argv[1]))["benchmarks"]
    other = json.load(open(sys.argv[2]))["benchmarks"] if len(sys.argv) > 2 else {}
    columns = [("before", "zig-fast"), ("my", "zig-fast"), ("my-unchecked", "zig-fast"),
               ("zig-safe", "zig-fast"), ("before", "my-unchecked"), ("my", "my-unchecked")]
    head = ["program", "before/Zig", "lane/Zig", "unchecked/Zig", "Zig safe/fast",
            "before/unchecked", "lane/unchecked", "lane/before [95% CI]"]
    if other:
        head.append("lane/before (other run)")
    print("| " + " | ".join(head) + " |")
    print("|---" + "|---:" * (len(head) - 1) + "|")
    logs = {c: [] for c in columns + [("my", "before")]}
    for name, entry in main_result.items():
        arms = entry["arms"]
        cells = [name]
        for column in columns:
            value = statistics.median(ratios(arms, *column))
            logs[column].append(math.log(value))
            cells.append(f"{value:.2f}")
        pair = ratios(arms, "my", "before")
        value = statistics.median(pair)
        logs[("my", "before")].append(math.log(value))
        low, high = interval(pair)
        cells.append(f"{value:.3f} [{low:.3f}, {high:.3f}]")
        if other and name in other:
            cells.append(f"{statistics.median(ratios(other[name]['arms'], 'my', 'before')):.3f}")
        print("| " + " | ".join(cells) + " |")
    geo = ["**geomean**"] + [f"**{math.exp(sum(logs[c]) / len(logs[c])):.2f}**" for c in columns]
    geo.append(f"**{math.exp(sum(logs[('my', 'before')]) / len(logs[('my', 'before')])):.3f}**")
    if other:
        geo.append("")
    print("| " + " | ".join(geo) + " |")


if __name__ == "__main__":
    main()
