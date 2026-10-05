#!/usr/bin/env python3
"""Cycles and branch misses per search for binary_search builds against Rust and Zig.

The method of ../../new-core-s0-20261005/measure_kernels.py: `perf stat` user
cycles (here also user branch misses) with the process pinned to one CPU, the
start-up counts of a one-iteration run subtracted, the median of interleaved
rounds (a fresh random order of every configuration each round), and every
configuration's checksum compared.

usage: measure_search.py --runner DIR [--rounds 7] [--cpu 10] NAME=PATH...
Each NAME=PATH is a single-kernel program taking `SIZE ITERATIONS SEED`
(test/core/binary_search.my built by some compiler). --runner holds the frozen
compute-rust, compute-zig-safe and compute-zig-fast binaries.
"""
import argparse, random, statistics, subprocess

SEED = 7
SIZES = {4096: 400, 64: 25000}


def run(cpu, argv):
    cmd = ["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", "cpu_core/cycles/u,cpu_core/branch-misses/u"] + argv
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit("failed: %s\n%s" % (" ".join(argv), done.stderr))
    checksum = done.stdout.split()[0]
    counts = {}
    for line in done.stderr.splitlines():
        fields = line.split(",")
        if len(fields) > 2 and fields[0].isdigit():
            counts[fields[2].split("/")[1]] = int(fields[0])
    return checksum, counts["cycles"], counts["branch-misses"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner", required=True)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--no-zig-fast", action="store_true")
    ap.add_argument("builds", nargs="+")
    args = ap.parse_args()
    if args.cpu in (2, 3, 11):
        raise SystemExit("never run on CPUs 2, 3 or 11")
    configs = [(b.split("=", 1)[0], (lambda p: lambda s, i: [p, str(s), str(i), str(SEED)])(b.split("=", 1)[1])) for b in args.builds]
    configs.append(("Rust", lambda s, i: [f"{args.runner}/compute-rust", "binary_search", str(s), str(i), str(SEED)]))
    configs.append(("Zig ReleaseSafe", lambda s, i: [f"{args.runner}/compute-zig-safe", "binary_search", str(s), str(i), str(SEED)]))
    if not args.no_zig_fast:
        configs.append(("Zig ReleaseFast", lambda s, i: [f"{args.runner}/compute-zig-fast", "binary_search", str(s), str(i), str(SEED)]))
    table = {name: {} for name, _ in configs}
    checks = {name: {} for name, _ in configs}
    for size, iterations in SIZES.items():
        start = {}
        for name, make in configs:
            runs = [run(args.cpu, make(size, 1)) for _ in range(3)]
            start[name] = (statistics.median(r[1] for r in runs), statistics.median(r[2] for r in runs))
        samples = {name: [] for name, _ in configs}
        for _ in range(args.rounds):
            order = list(configs)
            random.shuffle(order)
            for name, make in order:
                checksum, cycles, misses = run(args.cpu, make(size, iterations))
                checks[name].setdefault(size, set()).add(checksum)
                samples[name].append((cycles, misses))
        searches = size * iterations
        for name, _ in configs:
            cyc = (statistics.median(s[0] for s in samples[name]) - start[name][0]) / searches
            mis = (statistics.median(s[1] for s in samples[name]) - start[name][1]) / searches
            table[name][size] = (cyc, mis)
    ref = checks[configs[-2 if args.no_zig_fast else -3][0]]
    print(f"cycles / branch misses per search, median of {args.rounds} interleaved rounds, CPU {args.cpu}")
    print("| build | 4096 x 400 cycles | misses | 64 x 25000 cycles | misses | checksum |")
    print("|---|---:|---:|---:|---:|---|")
    for name, _ in configs:
        same = checks[name] == ref
        c4, m4 = table[name][4096]
        c6, m6 = table[name][64]
        print(f"| {name} | {c4:.1f} | {m4:.3f} | {c6:.1f} | {m6:.3f} | {'same' if same else 'DIFFERENT'} |")


if __name__ == "__main__":
    main()
