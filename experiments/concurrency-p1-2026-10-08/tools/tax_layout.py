#!/usr/bin/env python3
"""R10 paired-layout tax: CE-X's 46 rows, sizes, startup samples and 3 x 7 rounds.

Only the base/package arms are needed. The gate uses the row's CLOCK_MONOTONIC
wall time, subtracting the median one-iteration startup as CE-X does for cycles.
Keep cycles and the Python/perf process wall time as diagnostics; launcher time
must not dilute a short kernel's tax. No compiler runs while cpu10.lock is held.
Build commands use the shared build-slot wrapper.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

import ce

ROOT, AREA = ce.ROOT, ce.AREA / "r3"
BIN = ROOT / ".mylang-cache/concurrency-p1/tax-layout"
ROWS = ce.row_registry()


FIVE = {("json_transform", 4096), ("json_transform", 64), ("bytes_scan", 64), ("string_search", 64), ("binary_search", 4096)}


def build_one(compiler, tag, name, layout):
    output = BIN / tag / str(layout) / name
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), "build", str(ce.row_sources()[name]), "--release", "-o", str(output),
               "--cache-dir", str(BIN / tag / str(layout) / "cache"), "--link", str(ROOT / "benchmarks/runtime/ports/native_clock.c")]
    status, stdout, stderr = ce.run(command, slot=True, extra_env={"MYLANG_CORE_LAYOUT": str(layout), "MYLANG_SLOT_SETTLE": "0"})
    logs = AREA / "logs" / ("tax-build-" + tag + "-" + str(layout))
    logs.mkdir(exist_ok=True)
    (logs / (name + ".log")).write_text(json.dumps(command) + "\n" + stdout.decode() + stderr.decode() + f"\nexit={status}\n")
    if status != 0:
        raise RuntimeError(f"{tag}/{name}: build failed; see {logs}")
    print("built", tag, name, flush=True)


def sample(tag, name, size, iterations, layout):
    argv = [str(BIN / tag / str(layout) / name), str(size), str(iterations), str(ROWS.SEED)]
    load = os.getloadavg()
    start = time.monotonic_ns()
    result = ROWS.sample(argv)
    result["process_wall_ns"] = time.monotonic_ns() - start
    result["load_before"] = load
    result["load_after"] = os.getloadavg()
    return result


def measure(tags, output, five):
    if tags[0] != "base":
        raise ValueError("the first arm must be base")
    report = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "cpu": 10, "batches": 3, "layouts": [4, 5, 6], "rounds": 7, "tags": tags,
              "gate_metric": "elapsed_ns: CLOCK_MONOTONIC kernel wall, median startup subtracted",
              "load_start": os.getloadavg(), "binary_sha256": {}, "rows": {}, "valid": False}
    output.parent.mkdir(parents=True, exist_ok=True)
    for tag in tags:
        report["binary_sha256"][tag] = {f"{layout}/{name}": hashlib.sha256((BIN / tag / str(layout) / name).read_bytes()).hexdigest() for layout in (4, 5, 6) for name in ROWS.UNITS if not five or name in {n for n, _ in FIVE}}
    rng = random.Random(ROWS.SEED)
    lock = Path("/run/user/1000/mylang-slots/cpu10.lock")
    with lock.open("a") as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        os.sched_setaffinity(0, {10})
        for batch, layout in enumerate((4, 5, 6)):
            for name, (_, unit, big, small) in ROWS.UNITS.items():
                for size, iterations in zip(ROWS.SIZES, (big, small)):
                    if five and (name, size) not in FIVE:
                        continue
                    key = f"{name}/{size}"
                    row = report["rows"].setdefault(key, {"unit": unit, "iterations": iterations, "batches": []})
                    startup = {tag: [sample(tag, name, size, 1, layout) for _ in range(3)] for tag in tags}
                    runs = {tag: [] for tag in tags}
                    assert len({r["checksum"] for samples in startup.values() for r in samples}) == 1, key
                    for _ in range(7):
                        order = list(tags)
                        rng.shuffle(order)
                        for tag in order:
                            runs[tag].append(sample(tag, name, size, iterations, layout))
                    assert len({r["checksum"] for samples in runs.values() for r in samples}) == 1, key
                    medians = {tag: {metric: statistics.median(r[metric] for r in runs[tag])
                                     for metric in ("process_wall_ns", "elapsed_ns", "cycles")} for tag in tags}
                    for tag in tags:
                        for metric in ("elapsed_ns", "cycles"):
                            medians[tag][metric] -= statistics.median(r[metric] for r in startup[tag])
                            if medians[tag][metric] <= 0:
                                raise RuntimeError(f"{key}/{tag}: nonpositive normalized {metric}")
                    row["batches"].append({"layout": layout, "startup": startup, "runs": runs, "medians": medians})
                print(f"batch {batch + 1}/3 {name} done load={os.getloadavg()}", flush=True)
                output.write_text(json.dumps(report, separators=(",", ":")) + "\n")
    report["load_end"] = os.getloadavg()
    report["valid"] = True
    report["summary"] = {}
    for tag in tags[1:]:
        comparisons = {}
        for key, row in report["rows"].items():
            comparisons[key] = {metric: statistics.median(b["medians"][tag][metric] / b["medians"]["base"][metric]
                                                         for b in row["batches"])
                                for metric in ("process_wall_ns", "elapsed_ns", "cycles")}
        walls = [r["elapsed_ns"] for r in comparisons.values()]
        geomean = math.exp(statistics.mean(math.log(r) for r in walls))
        failures = {key: r["elapsed_ns"] for key, r in comparisons.items() if r["elapsed_ns"] > 1.03}
        report["summary"][tag] = {"geomean": geomean, "rows_over_1_03": failures,
                                  "pass": geomean <= 1.010 and not failures, "ratios": comparisons}
        print(tag, "geomean", geomean, "rows over 1.03", failures, flush=True)
    output.write_text(json.dumps(report, separators=(",", ":")) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "measure"))
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--tag")
    parser.add_argument("--tags", default="base,p1")
    parser.add_argument("--output", type=Path, default=AREA / "results/tax-rows.json")
    parser.add_argument("--five", action="store_true")
    args = parser.parse_args()
    if args.action == "build":
        assert args.compiler and args.tag
        with ThreadPoolExecutor(max_workers=2) as pool:
            jobs = [(name, layout) for layout in (4, 5, 6) for name in ROWS.UNITS if not args.five or name in {n for n, _ in FIVE}]
            list(pool.map(lambda job: build_one(args.compiler, args.tag, *job), jobs))
    else:
        measure(args.tags.split(","), args.output, args.five)


if __name__ == "__main__":
    main()
