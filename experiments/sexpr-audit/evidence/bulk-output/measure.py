#!/usr/bin/env python3
"""Matched A/B measurement for a native-runtime change.

    measure.py --a BINARY --b BINARY [--input DIR] [--rounds N] [--out result.json]

Runs census and render on two input sizes with both binaries, requires
byte-identical stdout from every pair, then samples `perf stat
instructions:u,cycles:u` in randomly interleaved rounds with the parent and
children pinned to one CPU.  Instructions are load-independent; cycles and wall
time are not, so only the ratios inside one invocation are comparable, and a
workload the change cannot affect (census here) doubles as the noise estimate.
"""
import argparse
import hashlib
import json
import os
import random
import statistics
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--a", required=True)
parser.add_argument("--b", required=True)
parser.add_argument("--input", default="/tmp/rt2x")
parser.add_argument("--rounds", type=int, default=9)
parser.add_argument("--out", default=str(Path(__file__).with_name("result.json")))
options = parser.parse_args()

os.sched_setaffinity(0, {6})
directory = Path(options.input)
workloads = {
    "census": ("input.sexp", []),
    "render": ("input.sexp", ["--render"]),
    "census8": ("input8.sexp", []),
    "render8": ("input8.sexp", ["--render"]),
}


def command_for(binary, label):
    """The binary, the fixture path and its guest flags, in that order."""
    name, flags = workloads[label]
    return [binary, str(directory / name), *flags]
binaries = {"A": options.a, "B": options.b}
report = {
    "binaries": {side: {"path": path, "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest()}
                 for side, path in binaries.items()},
    "inputs": {name: {"bytes": (directory / name).stat().st_size,
                      "sha256": hashlib.sha256((directory / name).read_bytes()).hexdigest()}
               for name in ("input.sexp", "input8.sexp")},
    "cpu": 6,
    "rounds": options.rounds,
    "outputs": {},
    "results": {},
}

outputs = {}
for label in workloads:
    for side, binary in binaries.items():
        result = subprocess.run(command_for(binary, label), capture_output=True, check=True)
        outputs[(label, side)] = result.stdout
    a, b = outputs[(label, "A")], outputs[(label, "B")]
    if a != b:
        raise SystemExit(f"OUTPUT MISMATCH on {label}")
    report["outputs"][label] = {"sha256": hashlib.sha256(a).hexdigest(), "bytes": len(a)}

counters = {key: [] for key in outputs}
wall = {key: [] for key in outputs}
rng = random.Random(23)
for _ in range(options.rounds):
    order = list(outputs)
    rng.shuffle(order)
    for key in order:
        label, side = key
        command = command_for(binaries[side], label)
        start = time.perf_counter_ns()
        result = subprocess.run(["perf", "stat", "-x,", "-e", "instructions:u,cycles:u", "--", *command],
                                capture_output=True, text=True, check=True)
        wall[key].append((time.perf_counter_ns() - start) / 1e6)
        if result.stdout.encode() != outputs[key]:
            raise SystemExit(f"output changed during measurement: {key}")
        values = {}
        for line in result.stderr.splitlines():
            fields = line.split(",")
            if len(fields) > 2 and fields[0].strip().replace(".", "", 1).isdigit():
                if "instructions" in fields[2]:
                    values["instructions"] = float(fields[0])
                elif "cycles" in fields[2]:
                    values["cycles"] = float(fields[0])
        if not values:
            raise SystemExit(f"no hardware counters for {key}: {result.stderr}")
        counters[key].append(values)

for label in workloads:
    entry = {}
    for side in binaries:
        key = (label, side)
        entry[side] = {
            "instructions": min(v["instructions"] for v in counters[key]),
            "cycles": min(v["cycles"] for v in counters[key]),
            "wall_ms_median": statistics.median(wall[key]),
            "samples": options.rounds,
        }
    for metric in ("instructions", "cycles", "wall_ms_median"):
        first, second = entry["A"][metric], entry["B"][metric]
        entry[f"{metric}_change_pct"] = (second - first) / first * 100.0
    report["results"][label] = entry

Path(options.out).write_text(json.dumps(report, indent=2) + "\n")
for label, entry in report["results"].items():
    print(f"{label}: instructions {entry['A']['instructions']:.0f} -> {entry['B']['instructions']:.0f} "
          f"({entry['instructions_change_pct']:+.2f}%)  cycles {entry['A']['cycles']:.0f} -> "
          f"{entry['B']['cycles']:.0f} ({entry['cycles_change_pct']:+.2f}%)  "
          f"wall {entry['A']['wall_ms_median']:.2f} -> {entry['B']['wall_ms_median']:.2f} ms "
          f"({entry['wall_ms_median_change_pct']:+.2f}%)")
