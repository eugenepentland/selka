#!/usr/bin/env python3
"""Counterfactual: disable chosen versioned loops by making their guard's first
step jump straight to the original loop.

usage: cf_noversion.py MYLANG SOURCE FUNCTION OUT [HEAD...]
With no HEAD, lists the versioned loop heads of FUNCTION (the @oi labels).
"""
import json
import re
import subprocess
import sys

mylang, source, function, out, *heads = sys.argv[1:]
p = subprocess.run([mylang, "emit-qbe", source, "--drop-debug", "--drop-step-checks", "--drop-frame-checks"],
                   capture_output=True, text=True, check=True)
data = json.loads(p.stdout)
for unit in data["functions"]:
    if unit["name"] != function:
        continue
    il = unit["il"]
    found = sorted(set(re.findall(r"^@oi(\d+)$", il, re.M)), key=int)
    if not heads:
        print("versioned heads:", " ".join(found))
        sys.exit(0)
    for head in heads:
        il, n = re.subn(r" jnz %v\d+, @guard\d+, @oi" + head + r"\n", f" jmp @oi{head}\n", il, count=1)
        print(f"head {head}: guard disabled ({n})")
    unit["il"] = il
open(out, "w").write(json.dumps(data))
