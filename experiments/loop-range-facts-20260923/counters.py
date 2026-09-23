#!/usr/bin/env python3
"""Instructions, branches and cycles (P-core events, `perf stat`, one CPU,
median of runs) for the lane's, the before compiler's and Zig's binary of each
program, and their ratios to Zig.
usage: counters.py CPU RUNS NAME=LANE_BIN,BEFORE_BIN,ZIG_BIN..."""
import statistics
import subprocess
import sys

EVENTS = ["cpu_core/instructions/", "cpu_core/branches/", "cpu_core/cycles/"]


def stat(binary, cpu):
    r = subprocess.run(["perf", "stat", "-x,", "-e", ",".join(EVENTS), "taskset", "-c", str(cpu), binary],
                       capture_output=True, text=True)
    values = {}
    for line in r.stderr.splitlines():
        parts = line.split(",")
        if len(parts) > 2 and parts[2] in EVENTS and parts[0].replace(".", "").isdigit():
            values[parts[2]] = float(parts[0])
    return values


cpu, runs, *entries = sys.argv[1:]
print("| program | instr lane/Zig | instr before/Zig | branches lane/Zig | branches before/Zig | cycles lane/Zig | cycles before/Zig |")
print("|---|---:|---:|---:|---:|---:|---:|")
for entry in entries:
    name, binaries = entry.split("=", 1)
    lane, before, zig = binaries.split(",")
    medians = {}
    for label, binary in (("lane", lane), ("before", before), ("zig", zig)):
        samples = [stat(binary, cpu) for _ in range(int(runs))]
        medians[label] = {e: statistics.median(s[e] for s in samples) for e in EVENTS}
    cells = []
    for event in EVENTS:
        for label in ("lane", "before"):
            cells.append(f"{medians[label][event] / medians['zig'][event]:.2f}")
    print(f"| {name} | " + " | ".join(cells) + " |")
