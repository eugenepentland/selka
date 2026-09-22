#!/usr/bin/env python3
"""Time suite/repro/arena_store_quadratic.my at 1M, 2M and 4M stores, before and after.

usage: arena_scaling.py BEFORE_MYLANG AFTER_MYLANG WORK_DIR OUT.json [--rounds N] [--cpu C]

Builds the repro at each size with both compilers (the default ReleaseFast
build), checks both print the store count, then times every binary as a fresh
process pinned to one CPU, shuffling the six binaries inside every round. It
prints the median per size and the 2M/1M and 4M/2M growth for each compiler.
Linear stores grow 2x per doubling; the chunk-walk barrier grew about 4x.
"""
import argparse
import json
import random
import statistics
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPRO = HERE.parents[1] / "suite/repro/arena_store_quadratic.my"
SIZES = {"1m": 1000000, "2m": 2000000, "4m": 4000000}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("before", type=Path)
    ap.add_argument("after", type=Path)
    ap.add_argument("work", type=Path)
    ap.add_argument("json", type=Path)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    opts = ap.parse_args()
    opts.work.mkdir(parents=True, exist_ok=True)
    text = REPRO.read_text()
    binaries = {}
    for size, count in SIZES.items():
        source = opts.work / f"arena_store_{size}.my"
        source.write_text(text.replace("keep(2000000)", f"keep({count})"))
        for arm, compiler in (("before", opts.before), ("after", opts.after)):
            out = opts.work / f"arena_store_{size}.{arm}"
            subprocess.run([str(compiler), "build", str(source), "-o", str(out), "--cache-dir", str(opts.work / f"cache-{arm}")], check=True)
            printed = subprocess.run([str(out)], capture_output=True, text=True, check=True).stdout.strip()
            if printed != str(count):
                raise SystemExit(f"{out} printed {printed!r}, expected {count}")
            binaries[(arm, size)] = out
    samples = {f"{arm}:{size}": [] for arm, size in binaries}
    rng = random.Random(20260922)
    for _ in range(opts.rounds):
        order = list(binaries.items())
        rng.shuffle(order)
        for (arm, size), binary in order:
            start = time.perf_counter()
            subprocess.run(["taskset", "-c", str(opts.cpu), str(binary)], stdout=subprocess.DEVNULL, check=True)
            samples[f"{arm}:{size}"].append(time.perf_counter() - start)
    medians = {key: statistics.median(values) for key, values in samples.items()}
    for arm in ("before", "after"):
        one, two, four = (medians[f"{arm}:{size}"] for size in SIZES)
        print(f"{arm:6}  1M {one * 1000:7.1f} ms  2M {two * 1000:7.1f} ms  4M {four * 1000:7.1f} ms  "
              f"2M/1M {two / one:4.2f}x  4M/2M {four / two:4.2f}x")
    opts.json.write_text(json.dumps({"repro": str(REPRO), "cpu": opts.cpu, "rounds": opts.rounds,
                                     "before": str(opts.before), "after": str(opts.after),
                                     "samples_s": samples, "median_s": medians}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
