#!/usr/bin/env python3
"""Print a parity.py measure JSON as base-relative ratios (lane U1).

usage: parity_table.py MEASURE.json BASE_ARM NEW_ARM
Rows above 1.005x instructions or 1.03x cycles are marked.
"""
import json, sys

data = json.load(open(sys.argv[1]))
base, new = sys.argv[2], sys.argv[3]
programs = data["programs"]
items = programs.items() if isinstance(programs, dict) else ((p["name"], p) for p in programs)
for name, entry in items:
    med = entry.get("median", entry)
    if base not in med or new not in med:
        continue
    b, n = med[base], med[new]
    ri, rc = n["instructions"] / b["instructions"], n["cycles"] / b["cycles"]
    z = med.get("zig-safe")
    zs = f"  ÷zig-safe {n['cycles'] / z['cycles']:.3f}" if z else ""
    flag = "  <<" if ri > 1.005 or rc > 1.03 else ""
    print(f"{name:28s} instr {ri:.3f} cycles {rc:.3f}{zs}{flag}")
