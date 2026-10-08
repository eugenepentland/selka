#!/usr/bin/env python3
"""Interleaved `perf stat` of several program arms on one CPU (wave PM, PM-2).

usage: pstat.py ARMS.json --out OUT.json [--rounds N] [--cpu 8]

ARMS.json is a list of {"program": P, "arm": A, "argv": [...], "cwd": optional,
"stdin": optional path}. Every round runs every arm once, in a shuffled order
(seeded), pinned with `taskset -c CPU`, under `perf stat -x,` with user-space
P-core events. The result holds every sample and the per-arm median of each
event. Cycles are only comparable inside one run: the machine is shared.
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import subprocess
from pathlib import Path

EVENTS = [
    "instructions", "cycles", "branches", "branch-misses", "L1-dcache-loads",
    "L1-dcache-load-misses", "LLC-load-misses", "mem_inst_retired.all_stores",
]


def run_once(arm: dict, cpu: int) -> dict:
    events = ",".join(f"cpu_core/{e}/u" for e in EVENTS)
    argv = ["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", events, "--", *arm["argv"]]
    stdin = open(arm["stdin"], "rb") if arm.get("stdin") else subprocess.DEVNULL
    try:
        proc = subprocess.run(argv, cwd=arm.get("cwd"), stdin=stdin, stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, text=True, timeout=600)
    finally:
        if arm.get("stdin"):
            stdin.close()
    sample: dict = {"status": proc.returncode}
    for line in proc.stderr.splitlines():
        parts = line.split(",")
        if len(parts) < 3 or not parts[2].startswith("cpu_core/"):
            continue
        name = parts[2][len("cpu_core/"):].rsplit("/", 1)[0]
        try:
            sample[name] = int(parts[0])
        except ValueError:
            sample[name] = None
    return sample


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("arms")
    parser.add_argument("--out", required=True)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--cpu", type=int, default=8)
    parser.add_argument("--seed", type=int, default=20261008)
    args = parser.parse_args()
    if args.cpu in (2, 3, 10, 11):
        raise SystemExit("pstat: CPUs 2, 3, 10 and 11 are reserved")
    arms = json.loads(Path(args.arms).read_text())
    rng = random.Random(args.seed)
    samples: dict[str, list] = {f"{a['program']}|{a['arm']}": [] for a in arms}
    for _ in range(args.rounds):
        order = list(arms)
        rng.shuffle(order)
        for arm in order:
            samples[f"{arm['program']}|{arm['arm']}"].append(run_once(arm, args.cpu))
    result = []
    for arm in arms:
        key = f"{arm['program']}|{arm['arm']}"
        rows = samples[key]
        median = {}
        for event in EVENTS:
            values = [r[event] for r in rows if isinstance(r.get(event), int)]
            median[event] = statistics.median(values) if values else None
        result.append({"program": arm["program"], "arm": arm["arm"], "status": [r["status"] for r in rows],
                       "median": median, "samples": rows})
    Path(args.out).write_text(json.dumps({"cpu": args.cpu, "rounds": args.rounds, "events": EVENTS, "arms": result}, indent=1))


if __name__ == "__main__":
    main()
