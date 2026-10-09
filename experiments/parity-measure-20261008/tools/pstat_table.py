#!/usr/bin/env python3
"""Markdown table from pstat.py output: per program, mylang's instructions, cycles and
events against each reference arm. usage: pstat_table.py PSTAT.json [--base my]"""
import json, sys
from collections import defaultdict
d = json.load(open(sys.argv[1]))
base = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv else "my"
by = defaultdict(dict)
for a in d["arms"]:
    by[a["program"]][a["arm"]] = a["median"]
refs = ["zig-fast", "zig-safe", "rust", "rust-checked"]
print("| program | arm | Minstr | Mcycles | IPC | br-miss/ki | L1-miss/ki | LLC-miss/ki | loads/ki | stores/ki | instr ÷my | cyc ÷my |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for p, arms in by.items():
    m = arms.get(base)
    for name, e in arms.items():
        i, c = e["instructions"], e["cycles"]
        ki = i / 1000
        f = lambda k: (e.get(k) or 0) / ki
        ri = m["instructions"] / i if m else 0
        rc = m["cycles"] / c if m else 0
        print(f"| {p} | {name} | {i/1e6:.0f} | {c/1e6:.0f} | {i/c:.2f} | {f('branch-misses'):.2f} | {f('L1-dcache-load-misses'):.2f} | {f('LLC-load-misses'):.3f} | {f('L1-dcache-loads'):.0f} | {f('mem_inst_retired.all_stores'):.0f} | {ri:.2f} | {rc:.2f} |")
