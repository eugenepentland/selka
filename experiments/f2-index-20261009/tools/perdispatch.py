#!/usr/bin/env python3
"""Per-dispatch check counters of a Lox VM counting run.

usage: perdispatch.py COUNTS.json [--kinds bounds_check,overflow_check,unique_test]
Dispatches are the executions of `read_byte`'s opcode fetch in `vm::run` (the
`frame.code[frame.ip]` read at vm.my:253 inlined into vm::run's top of loop),
counted as the vm::run-origin list_get at the loop's first frames write (line 433).
"""
import argparse, json
p = argparse.ArgumentParser(); p.add_argument("counts"); p.add_argument("--kinds", default="bounds_check,overflow_check,unique_test")
p.add_argument("--min", type=float, default=0.01)
a = p.parse_args()
d = json.load(open(a.counts))
kinds = a.kinds.split(",")
tot = {}
for s in d["sites"]:
    if s["kind"] in kinds:
        k = (s["kind"], s["origin"], s["line"], s["detail"])
        tot[k] = tot.get(k, 0) + s["count"]
# One opcode fetch per dispatch: read_byte's list_get inlined into vm::run's first block.
fetch = [s for s in d["sites"] if s["kind"] == "bounds_check" and s["function"] == "vm::run" and s["origin"] == "vm::read_byte"]
disp = max(s["count"] for s in fetch) if fetch else 1
print(f"dispatches {disp}")
for kind in kinds:
    print(f"{kind}: {sum(v for k, v in tot.items() if k[0] == kind) / disp:.3f} per dispatch")
for k, v in sorted(tot.items(), key=lambda x: -x[1]):
    if v / disp >= a.min: print(f"  {v / disp:6.3f} {k[0]:15} {k[1]:24} {k[2]:4} {k[3]}")
