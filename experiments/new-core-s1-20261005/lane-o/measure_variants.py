#!/usr/bin/env python3
"""Cycles per element of the S0 kernels for several builds of the same programs.

Reuses measure_kernels.py's method (perf stat user cycles pinned to one CPU, a
one-iteration run's start-up subtracted, the median of interleaved rounds in a
fresh random order) and checks every build prints the first build's checksums.

usage: measure_variants.py --variant NAME=DIR [--variant ...] [--kernels a,b] [--rounds 7] [--cpu 10]
DIR holds int_math, float_math, call_direct, branch_predictable, branch_mixed and
binary_search (build_variants.sh). Also prints each variant's binary sizes.
"""
import argparse, importlib.util, os, random, statistics

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mk", os.path.join(HERE, "..", "..", "new-core-s0-20261005", "measure_kernels.py"))
mk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mk)
FILES = {"integer_math": "int_math"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", action="append", required=True)
    ap.add_argument("--kernels", default="integer_math,float_math,call_direct,branch_predictable,branch_mixed,binary_search")
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    args = ap.parse_args()
    if args.cpu in (2, 3, 11):
        raise SystemExit("never run on CPUs 2, 3 or 11")
    variants = [v.split("=", 1) for v in args.variant]
    print("| kernel | size | " + " | ".join(n for n, _ in variants) + " |")
    print("|---|---|" + "---:|" * len(variants))
    for kernel in args.kernels.split(","):
        exe = FILES.get(kernel, kernel)
        for size, iterations in mk.SIZES.items():
            iterations = iterations // 10 if kernel == "binary_search" else iterations
            make = {n: (lambda d: lambda i: [f"{d}/{exe}", str(size), str(i), str(mk.SEED)])(d) for n, d in variants}
            startup = {n: statistics.median(mk.run(args.cpu, make[n](1))[1] for _ in range(3)) for n, _ in variants}
            cycles = {n: [] for n, _ in variants}
            sums = {n: set() for n, _ in variants}
            for _ in range(args.rounds):
                order = list(variants)
                random.shuffle(order)
                for n, _ in order:
                    checksum, count = mk.run(args.cpu, make[n](iterations))
                    sums[n].add(checksum)
                    cycles[n].append(count)
            first = variants[0][0]
            cells = []
            for n, _ in variants:
                per = (statistics.median(cycles[n]) - startup[n]) / (size * iterations)
                cells.append(f"{per:.3f}" + ("" if sums[n] == sums[first] else " DIFFERENT"))
            print(f"| {kernel} | {size} | " + " | ".join(cells) + " |", flush=True)
    print()
    print("| binary bytes | " + " | ".join(n for n, _ in variants) + " |")
    print("|---|" + "---:|" * len(variants))
    for kernel in args.kernels.split(","):
        exe = FILES.get(kernel, kernel)
        print(f"| {exe} | " + " | ".join(str(os.path.getsize(f"{d}/{exe}")) for _, d in variants) + " |")


if __name__ == "__main__":
    main()
