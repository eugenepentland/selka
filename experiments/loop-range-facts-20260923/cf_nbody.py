#!/usr/bin/env python3
"""Counterfactual: nbody's `bodies[i].f = v` written in place.

Emits the release manifest of nbody with MYLANG, and in `advance` rewrites
each element field write's `copy %aggN; blit elem, agg, 56` into naming the
element itself and drops the copy back (`blit agg, elem, 56`), which is then a
copy of the element onto itself. Writes the manifest to OUT.
usage: cf_nbody.py MYLANG SOURCE OUT
"""
import json
import re
import subprocess
import sys

mylang, source, out = sys.argv[1:]
p = subprocess.run([mylang, "emit-qbe", source, "--drop-debug", "--drop-step-checks", "--drop-frame-checks"],
                   capture_output=True, text=True, check=True)
data = json.loads(p.stdout)
for unit in data["functions"]:
    if unit["name"] != "advance":
        continue
    il = unit["il"]
    il, first = re.subn(r" %v(\d+) =l copy %agg\d+\n blit %v(\d+), %v\1, 56\n", r" %v\1 =l copy %v\2\n", il)
    il, second = re.subn(r" blit %v\d+, %v\d+, 56\n", "", il)
    unit["il"] = il
    print(f"advance: {first} scratch copies renamed, {second} copies back dropped")
open(out, "w").write(json.dumps(data))
