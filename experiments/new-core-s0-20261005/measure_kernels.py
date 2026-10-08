#!/usr/bin/env python3
"""Cycles per element for every S0 kernel: old core, new core, spike, C ladder, Rust, Zig ReleaseSafe.

The method is the WP-8 spike's (measure.py): `perf stat` user cycles with the
process pinned to one CPU, the start-up cycles of a one-iteration run
subtracted, the median of interleaved rounds (a fresh random order of every
configuration each round), and every configuration's checksum compared.

usage: measure_kernels.py --bin DIR --runner DIR [--kernels a,b] [--rounds 7] [--cpu 10]
--bin holds <kernel>_old, <kernel>_new (single-kernel programs from test/core),
compute_spike_l2 (the spike compiler's MYLANG_LLVM_DIRECT=2 build of the
unmodified compute benchmark) and the C ladder builds int_math_c, float_math_c,
branch_mixed_c. --runner holds compute-rust and compute-zig-safe.
"""
import argparse, os, random, statistics, subprocess

SEED = 7
SIZES = {4096: 4000, 64: 250000}
# C ladder rungs: the best compiler-derived (plain C) rung and the hand-AVX2 rung.
LADDER = {"integer_math": ("int_math_c", "5", "7"), "float_math": ("float_math_c", "5", "8"), "branch_mixed": ("branch_mixed_c", "8", "7")}
SPIKE = {"integer_math", "float_math", "call_direct"}
FILES = {"integer_math": "int_math"}


def run(cpu, argv):
    cmd = ["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", "cpu_core/cycles/u"] + argv
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit("failed: %s\n%s" % (" ".join(argv), done.stderr))
    checksum = done.stdout.split()[0]
    for line in done.stderr.splitlines():
        fields = line.split(",")
        if len(fields) > 2 and fields[0].isdigit():
            return checksum, int(fields[0])
    raise SystemExit("no cycle count: %s" % done.stderr)


KINDS = {"integer_math": "0", "float_math": "1", "branch_predictable": "2", "branch_mixed": "3", "call_direct": "6", "binary_search": "10"}


def configurations(args, kernel):
    b, r = args.bin, args.runner
    if args.multi:
        # test/core/compute_s0.my: every S0 kind in one program, dispatching on `kind` per element.
        kind = KINDS[kernel]
        return [
            ("old core --release", lambda s, i: [f"{b}/compute_s0_old", kind, str(s), str(i), str(SEED)]),
            ("new core release", lambda s, i: [f"{b}/compute_s0_new", kind, str(s), str(i), str(SEED)]),
        ]
    name = FILES.get(kernel, kernel)
    rows = [
        ("old core --release", lambda s, i: [f"{b}/{name}_old", str(s), str(i), str(SEED)]),
        ("new core release", lambda s, i: [f"{b}/{name}_new", str(s), str(i), str(SEED)]),
    ]
    if kernel in SPIKE:
        rows.append(("spike L2 (compute)", lambda s, i: [f"{b}/compute_spike_l2", kernel, str(s), str(i), str(SEED)]))
    if kernel in LADDER:
        exe, auto, hand = LADDER[kernel]
        rows.append((f"C ladder v{auto} (plain C)", lambda s, i: [f"{b}/{exe}", auto, str(s), str(i), str(SEED)]))
        rows.append((f"C ladder v{hand} (hand AVX2)", lambda s, i: [f"{b}/{exe}", hand, str(s), str(i), str(SEED)]))
    rows.append(("Rust", lambda s, i: [f"{r}/compute-rust", kernel, str(s), str(i), str(SEED)]))
    rows.append(("Zig ReleaseSafe", lambda s, i: [f"{r}/compute-zig-safe", kernel, str(s), str(i), str(SEED)]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--runner", required=True)
    ap.add_argument("--kernels", default="integer_math,float_math,call_direct,branch_predictable,branch_mixed,binary_search")
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--multi", action="store_true", help="measure compute_s0_old/_new (the multi-kind program) instead")
    args = ap.parse_args()
    if args.cpu in (2, 3, 11):
        raise SystemExit("never run on CPUs 2, 3 or 11")
    for kernel in args.kernels.split(","):
        configs = configurations(args, kernel)
        print(f"\n### {kernel} (cycles/element, median of {args.rounds} interleaved rounds, CPU {args.cpu})")
        print("| configuration | 4096 x 4000 | 64 x 250000 | checksum |")
        print("|---|---:|---:|---|")
        table = {name: {} for name, _ in configs}
        checks = {name: set() for name, _ in configs}
        for size, iterations in SIZES.items():
            iterations = iterations // 10 if kernel == "binary_search" else iterations
            startup = {name: statistics.median(run(args.cpu, make(size, 1))[1] for _ in range(3)) for name, make in configs}
            cycles = {name: [] for name, _ in configs}
            for _ in range(args.rounds):
                order = list(configs)
                random.shuffle(order)
                for name, make in order:
                    checksum, count = run(args.cpu, make(size, iterations))
                    checks[name].add((size, checksum))
                    cycles[name].append(count)
            for name, _ in configs:
                table[name][size] = (statistics.median(cycles[name]) - startup[name]) / (size * iterations)
        reference = {size: {c for (s, c) in checks[configs[0][0]] if s == size} for size in SIZES}
        for name, _ in configs:
            same = all({c for (s, c) in checks[name] if s == size} == reference[size] for size in SIZES)
            print(f"| {name} | {table[name][4096]:.3f} | {table[name][64]:.3f} | {'same' if same else 'DIFFERENT'} |")


if __name__ == "__main__":
    main()
