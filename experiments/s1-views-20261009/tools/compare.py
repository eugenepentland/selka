#!/usr/bin/env python3
"""Table of a pstat.py result: per program, each arm's instructions and cycles relative to
the first arm (`base`). usage: compare.py PSTAT.json [BASE_ARM]"""
import json, sys
d = json.load(open(sys.argv[1]))
base = sys.argv[2] if len(sys.argv) > 2 else "base"
rows = {}
for a in d["arms"]:
    rows.setdefault(a["program"], {})[a["arm"]] = a
print(f"| program | arm | instructions (M) | cycles (M) | instr ÷ {base} | cycles ÷ {base} | status |")
print("|---|---|---:|---:|---:|---:|---|")
for prog, arms in rows.items():
    b = arms.get(base)
    for arm, a in arms.items():
        m = a["median"]
        ri = m["instructions"] / b["median"]["instructions"] if b else float("nan")
        rc = m["cycles"] / b["median"]["cycles"] if b else float("nan")
        flag = " **" if arm != base and (ri > 1.03 or rc > 1.03) else ""
        print(f"| {prog} | {arm} | {m['instructions']/1e6:.1f} | {m['cycles']/1e6:.1f} | {ri:.3f} | {rc:.3f}{flag} | {sorted(set(a['status']))} |")
