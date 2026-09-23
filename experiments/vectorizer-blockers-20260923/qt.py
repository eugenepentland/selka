#!/usr/bin/env python3
"""qt.py [-n N] [-c CPU] BIN... — quick interleaved timing: median wall ms per binary, plus
instructions/branches/branch-misses from one perf stat run each. Stdout of each binary is
compared with the first binary's."""
import os
import statistics
import subprocess
import sys
import time

args = sys.argv[1:]
n, cpu = 7, "8"
while args and args[0].startswith("-"):
    if args[0] == "-n":
        n = int(args[1]); args = args[2:]
    elif args[0] == "-c":
        cpu = args[1]; args = args[2:]
bins = args
times = {b: [] for b in bins}
outputs = {}
for _ in range(n):
    for b in bins:
        t0 = time.perf_counter()
        r = subprocess.run(["taskset", "-c", cpu, b], capture_output=True)
        times[b].append(time.perf_counter() - t0)
        outputs.setdefault(b, r.stdout)
base = None
for b in bins:
    r = subprocess.run(["taskset", "-c", cpu, "perf", "stat", "-x,", "-e",
                        "cpu_core/instructions/,cpu_core/branches/,cpu_core/branch-misses/", b], capture_output=True, text=True)
    counters = {}
    for line in r.stderr.splitlines():
        parts = line.split(",")
        if len(parts) > 2 and parts[0].strip().isdigit():
            key = parts[2].split("/")[1] if "/" in parts[2] else parts[2]
            counters[key] = counters.get(key, 0) + int(parts[0])
    med = statistics.median(times[b]) * 1000
    base = base or med
    same = "same" if outputs[b] == outputs[bins[0]] else "DIFF"
    print(f"{med:8.1f} ms  x{med / base:5.2f}  ins {counters.get('instructions', 0)/1e6:8.1f}M "
          f"br {counters.get('branches', 0)/1e6:7.1f}M miss {counters.get('branch-misses', 0)/1e3:8.1f}K "
          f"{same}  {b}")
