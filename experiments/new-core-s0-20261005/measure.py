#!/usr/bin/env python3
"""Interleaved timing of the new core's integer_math slice against its references.

Adapted from the WP-8 spike's measure.py (claude/llvm-direct-spike-20261004);
only the configuration list differs. Binaries expected in --bin:
  int_math_old        old core, `mylang build --release`
  int_math_new_nofacts  mylang-core build --release --no-facts
  int_math_new        mylang-core build --release
  int_math_spike_l1/_l2 the spike compiler with MYLANG_LLVM_DIRECT=1/2 --release
  int_math_c          experiments/runtime-ideal-ladder-20261004/int_math.c, zig cc -O3 (native)


Every configuration runs once per round in a fresh random order; a round
is one pass over all configurations. Each run is pinned with `taskset -c CPU`
and wrapped in `perf stat` for user-mode cycles and instructions. The elapsed
time is the one the program reports around its own loop. A run with one
iteration measures the start-up cycles that are subtracted from the long
run, so cycles/element describes the loop alone.

usage: measure.py KERNEL [--bin DIR] [--rounds 7] [--cpu 10] [--rust PATH]
KERNEL is int_math, float_math, list_scan or compute (every compute kind).
"""
import argparse, os, random, re, statistics, subprocess, sys

SEED = 7
SIZES = {4096: 4000, 64: 250000}


def run(cpu, argv):
    cmd = ["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e",
           "cpu_core/cycles/u,cpu_core/instructions/u"] + argv
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"failed: {' '.join(argv)}\n{done.stderr}")
    checksum, elapsed = done.stdout.split()
    counters = {}
    for line in done.stderr.splitlines():
        fields = line.split(",")
        if len(fields) > 2 and fields[0].isdigit():
            counters[fields[2].split("/")[1]] = int(fields[0])
    return checksum, int(elapsed), counters["cycles"], counters["instructions"]


def busy(cpu):
    """Cumulative non-idle jiffies of one CPU from /proc/stat."""
    with open("/proc/stat") as stat:
        for line in stat:
            if line.startswith(f"cpu{cpu} "):
                fields = [int(x) for x in line.split()[1:]]
                return sum(fields) - fields[3] - fields[4], sum(fields)
    return 0, 1


def sibling(cpu):
    """The other hardware thread of the core CPU runs on, if any."""
    path = f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list"
    try:
        listed = open(path).read().strip().replace("-", ",").split(",")
        others = [int(x) for x in listed if int(x) != cpu]
        return others[0] if others else None
    except OSError:
        return None


def configurations(args, kernel):
    b = args.bin
    rust = args.rust
    if kernel == "int_math":
        c = os.path.join(b, "int_math_c")
        return [
            ("old core --release", lambda s, i: [f"{b}/int_math_old", str(s), str(i), str(SEED)]),
            ("new core release, no facts", lambda s, i: [f"{b}/int_math_new_nofacts", str(s), str(i), str(SEED)]),
            ("new core release (facts)", lambda s, i: [f"{b}/int_math_new", str(s), str(i), str(SEED)]),
            ("spike L1 (typed scalar)", lambda s, i: [f"{b}/int_math_spike_l1", str(s), str(i), str(SEED)]),
            ("spike L2 (vector)", lambda s, i: [f"{b}/int_math_spike_l2", str(s), str(i), str(SEED)]),
            ("C v5 (assume ranges)", lambda s, i: [c, "5", str(s), str(i), str(SEED)]),
            ("C v7 (AVX2, u16 storage)", lambda s, i: [c, "7", str(s), str(i), str(SEED)]),
            ("Rust", lambda s, i: [f"{rust}/compute-rust", "integer_math", str(s), str(i), str(SEED)]),
        ]
    if kernel == "float_math":
        return [
            ("mylang flag off", lambda s, i: [f"{b}/float_math_off", str(s), str(i), str(SEED)]),
            ("direct L1 (typed scalar)", lambda s, i: [f"{b}/float_math_l1", str(s), str(i), str(SEED)]),
            ("direct L2 (vector)", lambda s, i: [f"{b}/float_math_l2", str(s), str(i), str(SEED)]),
            ("Rust", lambda s, i: [f"{rust}/compute-rust", "float_math", str(s), str(i), str(SEED)]),
            ("Zig fast", lambda s, i: [f"{rust}/compute-zig-fast", "float_math", str(s), str(i), str(SEED)]),
        ]
    if kernel == "list_scan":
        return [
            ("mylang flag off", lambda s, i: [f"{b}/list_scan_off", str(s), str(i), str(SEED)]),
            ("direct L1 (typed scalar)", lambda s, i: [f"{b}/list_scan_l1", str(s), str(i), str(SEED)]),
            ("direct L2 (vector)", lambda s, i: [f"{b}/list_scan_l2", str(s), str(i), str(SEED)]),
            ("Rust", lambda s, i: [f"{rust}/collections-rust", "list_scan", str(s), str(i), str(SEED)]),
        ]
    kind = kernel.split(":", 1)[1]
    return [
        ("mylang flag off", lambda s, i: [f"{b}/compute_off", kind, str(s), str(i), str(SEED)]),
        ("direct L1", lambda s, i: [f"{b}/compute_l1", kind, str(s), str(i), str(SEED)]),
        ("direct L2", lambda s, i: [f"{b}/compute_l2", kind, str(s), str(i), str(SEED)]),
        ("Rust", lambda s, i: [f"{rust}/compute-rust", kind, str(s), str(i), str(SEED)]),
    ]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("kernel")
    ap.add_argument("--bin", default=os.path.join(here, "bin"))
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--rust", default=os.environ.get("RUNNER_BIN", ""))
    ap.add_argument("--sizes", default="4096,64")
    args = ap.parse_args()
    if args.cpu in (2, 3):
        raise SystemExit("never run on CPUs 2-3")
    kernel = args.kernel
    configs = configurations(args, "compute:" + kernel[8:] if kernel.startswith("compute:") else kernel)
    for size in [int(s) for s in args.sizes.split(",")]:
        iterations = SIZES.get(size, 4000)
        twin = sibling(args.cpu)
        before = busy(twin) if twin is not None else (0, 1)
        elapsed = {n: [] for n, _ in configs}
        cycles = {n: [] for n, _ in configs}
        instructions = {n: [] for n, _ in configs}
        startup = {}
        checks = {}
        for name, make in configs:
            startup[name] = statistics.median(run(args.cpu, make(size, 1))[2] for _ in range(3))
        for _ in range(args.rounds):
            order = list(configs)
            random.shuffle(order)
            for name, make in order:
                checksum, ns, cyc, ins = run(args.cpu, make(size, iterations))
                checks.setdefault(name, set()).add(checksum)
                elapsed[name].append(ns)
                cycles[name].append(cyc)
                instructions[name].append(ins)
        after = busy(twin) if twin is not None else (0, 1)
        twin_share = 100.0 * (after[0] - before[0]) / max(1, after[1] - before[1])
        elements = size * iterations
        reference = min(statistics.median(v) for v in elapsed.values())
        print(f"\n{kernel}, size {size}, {iterations} iterations, {args.rounds} interleaved rounds, CPU {args.cpu} (SMT sibling CPU {twin} {twin_share:.1f}% busy besides these runs)")
        print("| configuration | median ns | spread (min-max) | cycles/elem | instr/elem | vs fastest | checksum |")
        print("|---|---:|---:|---:|---:|---:|---|")
        for name, _ in configs:
            med = statistics.median(elapsed[name])
            cyc = (statistics.median(cycles[name]) - startup[name]) / elements
            ins = statistics.median(instructions[name]) / elements
            same = "ok" if len(checks[name]) == 1 else "UNSTABLE"
            print(f"| {name} | {med:,.0f} | {min(elapsed[name]):,}-{max(elapsed[name]):,} | {cyc:.3f} | {ins:.2f} | {med / reference:.2f}x | {sorted(checks[name])[0]} {same} |")
        distinct = {sorted(c)[0] for c in checks.values()}
        print("checksums agree" if len(distinct) == 1 else f"CHECKSUMS DIFFER: {distinct}")


if __name__ == "__main__":
    main()
