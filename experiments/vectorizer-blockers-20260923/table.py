#!/usr/bin/env python3
"""table.py BASE.json LANE.json — per benchmark: time ratio to Zig (each batch), lane/base, and the
my/zig instruction and branch ratios plus branch misses per thousand instructions."""
import json
import math
import sys

base = json.load(open(sys.argv[1]))["benchmarks"]
lane = json.load(open(sys.argv[2]))["benchmarks"]


def ratio(bench, arm="my"):
    a = bench["arms"].get(arm, {})
    r = a.get("ratio_wall") or {}
    return r.get("median")


def counter(bench, arm, event):
    return (bench["arms"].get(arm, {}).get("counters") or {}).get(event)


print("| group | benchmark | Zig ms | before ×Zig | after ×Zig | after/before | unchecked ×Zig | instr my/zig before → after | branches my/zig before → after | br-miss/ki my before → after (zig) |")
print("|---|---|---:|---:|---:|---:|---:|---|---|---|")
groups = {}
for name, lb in lane.items():
    bb = base.get(name)
    if bb is None:
        continue
    rb, rl = ratio(bb), ratio(lb)
    if rb is None or rl is None:
        continue
    zig_ms = lb["arms"]["zig-fast"]["wall_median"] * 1000

    def ins(bench):
        m, z = counter(bench, "my", "instructions"), counter(bench, "zig-fast", "instructions")
        return m / z if m and z else float("nan")

    def br(bench):
        m, z = counter(bench, "my", "branches"), counter(bench, "zig-fast", "branches")
        return m / z if m and z else float("nan")

    def miss(bench, arm="my"):
        m, i = counter(bench, arm, "branch-misses"), counter(bench, arm, "instructions")
        return 1000 * m / i if m is not None and i else float("nan")

    unchecked = ratio(lb, "my-unchecked")
    group = lb.get("group", "")
    groups.setdefault(group, []).append((rb, rl))
    print(f"| {group} | {name} | {zig_ms:.1f} | {rb:.2f} | {rl:.2f} | {rl / rb:.3f} | "
          f"{unchecked:.2f} | {ins(bb):.2f} → {ins(lb):.2f} | {br(bb):.1f} → {br(lb):.1f} | "
          f"{miss(bb):.2f} → {miss(lb):.2f} ({miss(lb, 'zig-fast'):.2f}) |" if unchecked else
          f"| {group} | {name} | {zig_ms:.1f} | {rb:.2f} | {rl:.2f} | {rl / rb:.3f} | | "
          f"{ins(bb):.2f} → {ins(lb):.2f} | {br(bb):.1f} → {br(lb):.1f} | {miss(bb):.2f} → {miss(lb):.2f} ({miss(lb, 'zig-fast'):.2f}) |")
for group, rows in groups.items():
    gb = math.exp(sum(math.log(b) for b, _ in rows) / len(rows))
    gl = math.exp(sum(math.log(l) for _, l in rows) / len(rows))
    print(f"| {group} | **geomean** | | **{gb:.2f}** | **{gl:.2f}** | **{gl / gb:.3f}** | | | | |")
