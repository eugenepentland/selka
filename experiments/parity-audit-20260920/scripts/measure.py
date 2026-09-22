#!/usr/bin/env python3
"""perf-stat counters for a set of binaries on census8/render8, with output verification.
usage: measure.py out.json name=path [name=path ...]"""
import json, os, subprocess, sys
S = "/tmp/claude-1000/-home-epentland-ai-canopy-mylang/6108061e-40b0-485a-852b-53c35cd1760e/scratchpad"
INPUT = "/home/epentland/ai/canopy/mylang/.tmp/runtime-audit-20260919/input8.sexp"
EVENTS = "task-clock,cpu_core/cycles/u,cpu_core/cycles/k,cpu_core/instructions/u,page-faults,cpu_core/L1-dcache-load-misses/u,cpu_core/LLC-load-misses/u"
ROUNDS = int(os.environ.get("ROUNDS", "9"))
out_path = sys.argv[1]
arms = [a.split("=", 1) for a in sys.argv[2:]]
results = {}
for name, path in arms:
    results[name] = {}
    for mode, args in (("census", []), ("render", ["--render"])):
        expect = open(f"{S}/z-{mode}.txt", "rb").read()
        got = subprocess.run([path, INPUT, *args], capture_output=True).stdout
        ok = got == expect
        cmd = ["taskset", "-c", "6", "perf", "stat", "-x,", "-r", str(ROUNDS), "-e", EVENTS, "--", path, INPUT, *args]
        p = subprocess.run(cmd, capture_output=True, text=True)
        row = {"output_identical": ok}
        for line in p.stderr.splitlines():
            parts = line.split(",")
            if len(parts) < 3 or not parts[0].replace(".", "").isdigit():
                continue
            key = parts[2].replace("cpu_core/", "").replace("/u", "_u").replace("/k", "_k")
            row[key] = float(parts[0])
        results[name][mode] = row
json.dump(results, open(out_path, "w"), indent=1)
keys = ["task-clock", "cycles_u", "cycles_k", "instructions_u", "page-faults", "L1-dcache-load-misses_u", "LLC-load-misses_u"]
for mode in ("census", "render"):
    print(f"== {mode}: " + " ".join(f"{k:>14}" for k in keys) + "  identical")
    for name, _ in arms:
        r = results[name][mode]
        print(f"{name:>12} " + " ".join(f"{r.get(k, float('nan')):>14,.0f}" for k in keys) + f"  {r['output_identical']}")
