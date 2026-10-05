#!/usr/bin/env python3
"""The S0 kernels before and after a compiler change: cycles per element (binary_search:
per search) with branch misses, against Rust and Zig ReleaseSafe.

Method of ../../new-core-s0-20261005/measure_kernels.py: `perf stat` user counts with
the process pinned to one CPU, a one-iteration run's start-up subtracted, the median
of interleaved rounds, checksums compared across every configuration.

usage: measure_regression.py --before DIR --after DIR --runner DIR [--multi] [--kernels a,b] [--rounds 7] [--cpu 10]
DIR holds <kernel>_new (single-kernel programs from test/core) and compute_s0_new.
"""
import argparse, random, statistics, subprocess

SEED = 7
SIZES = {4096: 4000, 64: 250000}
FILES = {"integer_math": "int_math"}
KINDS = {"integer_math": "0", "float_math": "1", "branch_predictable": "2", "branch_mixed": "3", "call_direct": "6", "binary_search": "10"}


def run(cpu, argv):
    cmd = ["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", "cpu_core/cycles/u,cpu_core/branch-misses/u"] + argv
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit("failed: %s\n%s" % (" ".join(argv), done.stderr))
    counts = {}
    for line in done.stderr.splitlines():
        fields = line.split(",")
        if len(fields) > 2 and fields[0].isdigit():
            counts[fields[2].split("/")[1]] = int(fields[0])
    return done.stdout.split()[0], counts["cycles"], counts["branch-misses"]


def configurations(args, kernel):
    rows = []
    for label, d in (("before", args.before), ("after", args.after)):
        if args.multi:
            rows.append((label, (lambda d: lambda s, i: [f"{d}/compute_s0_new", KINDS[kernel], str(s), str(i), str(SEED)])(d)))
        else:
            name = FILES.get(kernel, kernel)
            rows.append((label, (lambda d, name: lambda s, i: [f"{d}/{name}_new", str(s), str(i), str(SEED)])(d, name)))
    if not args.multi:
        rows.append(("Rust", lambda s, i: [f"{args.runner}/compute-rust", kernel, str(s), str(i), str(SEED)]))
        rows.append(("Zig ReleaseSafe", lambda s, i: [f"{args.runner}/compute-zig-safe", kernel, str(s), str(i), str(SEED)]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--runner", required=True)
    ap.add_argument("--kernels", default="integer_math,float_math,call_direct,branch_predictable,branch_mixed,binary_search")
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--multi", action="store_true")
    args = ap.parse_args()
    if args.cpu in (2, 3, 11):
        raise SystemExit("never run on CPUs 2, 3 or 11")
    print(f"median of {args.rounds} interleaved rounds, CPU {args.cpu}{' (compute_s0, --multi)' if args.multi else ''}")
    print("| kernel | build | 4096 cycles | misses/1000 | 64 cycles | misses/1000 | checksum |")
    print("|---|---|---:|---:|---:|---:|---|")
    for kernel in args.kernels.split(","):
        configs = configurations(args, kernel)
        table, checks = {n: {} for n, _ in configs}, {n: {} for n, _ in configs}
        for size, iterations in SIZES.items():
            iterations = iterations // 10 if kernel == "binary_search" else iterations
            start = {}
            for name, make in configs:
                r = [run(args.cpu, make(size, 1)) for _ in range(3)]
                start[name] = (statistics.median(x[1] for x in r), statistics.median(x[2] for x in r))
            samples = {n: [] for n, _ in configs}
            for _ in range(args.rounds):
                order = list(configs)
                random.shuffle(order)
                for name, make in order:
                    checksum, cycles, misses = run(args.cpu, make(size, iterations))
                    checks[name].setdefault(size, set()).add(checksum)
                    samples[name].append((cycles, misses))
            for name, _ in configs:
                n = size * iterations
                table[name][size] = ((statistics.median(s[0] for s in samples[name]) - start[name][0]) / n,
                                     1000 * (statistics.median(s[1] for s in samples[name]) - start[name][1]) / n)
        ref = checks[configs[0][0]]
        for name, _ in configs:
            c4, m4 = table[name][4096]
            c6, m6 = table[name][64]
            print(f"| {kernel} | {name} | {c4:.3f} | {m4:.1f} | {c6:.3f} | {m6:.1f} | {'same' if checks[name] == ref else 'DIFFERENT'} |")
        b, a = table["before"], table["after"]
        print(f"| {kernel} | after/before | {a[4096][0] / b[4096][0]:.3f} | | {a[64][0] / b[64][0]:.3f} | | |")


if __name__ == "__main__":
    main()
