#!/usr/bin/env python3
"""Interleaved wall-clock A/B of two sexpr-port binaries on one corpus.

Usage: bench_port.py BEFORE AFTER INPUT [ROUNDS]

Both binaries are run alternately inside every round, so a machine that drifts
during the run moves both sides together; the report gives the minimum and the
median of each side for the census mode (parse and count nodes) and the render
mode (parse and emit the canonical bytes). Exit statuses are printed, and a
failing run is reported rather than timed as if it had passed, because a port
that rejects the corpus does less work than one that accepts it.

Build both sides with the same compiler and the same flags, for example:

    mylang build SIDE/main.my -o SIDE.bin --cache-dir=CACHE
    python3 bench_port.py BEFORE.bin AFTER.bin CORPUS 15
"""
import statistics
import subprocess
import sys
import time


def run(binary, target, render):
    args = [binary, target] + (["--render"] if render else [])
    start = time.perf_counter()
    proc = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return time.perf_counter() - start, proc.returncode, proc.stderr.decode()[:200]


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: bench_port.py BEFORE AFTER INPUT [ROUNDS]")
    before, after, target = sys.argv[1], sys.argv[2], sys.argv[3]
    rounds = int(sys.argv[4]) if len(sys.argv) > 4 else 9
    for render in (False, True):
        times = {before: [], after: []}
        codes = {}
        errors = {}
        for _ in range(rounds):
            for binary in (before, after):
                elapsed, code, err = run(binary, target, render)
                times[binary].append(elapsed)
                codes[binary] = code
                if code != 0:
                    errors[binary] = err
        mode = "render" if render else "census"
        for binary in (before, after):
            label = "before" if binary == before else "after"
            samples = sorted(times[binary])
            median = statistics.median(samples)
            print(f"{mode} {label}: min {samples[0] * 1000:8.1f} ms  median {median * 1000:8.1f} ms"
                  f"  exit {codes[binary]}  samples {[round(sample * 1000) for sample in samples]}")
            if binary in errors:
                print(f"  stderr: {errors[binary]!r}")
        old_min = min(times[before])
        old_median = statistics.median(times[before])
        new_min = min(times[after])
        new_median = statistics.median(times[after])
        print(f"{mode} delta: {(old_min - new_min) / old_min * 100:+.1f}% on minima, "
              f"{(old_median - new_median) / old_median * 100:+.1f}% on medians")


main()
