#!/usr/bin/env python3
"""Cycles per unit for every S1 microbenchmark row: old core, new core, Rust, Zig ReleaseSafe.

The method is measure_kernels.py's (itself the WP-8 spike's): `perf stat` user cycles with the
process pinned to one CPU, the start-up cycles of a one-iteration run subtracted, the median of
interleaved rounds (a fresh random order of every configuration each round), and every
configuration's checksum compared. A row's unit is one element of the work it repeats
(`size * iterations`) or one iteration, whichever the row's cost scales with (UNITS below).

  old core   `mylang build --release` of test/core/row_<row>.my
  new core   `mylang-core build --release` of the same file (a row the new core still refuses is
             listed with the construct that blocks it, and measured without it)
  Rust, Zig  the baseline runners of benchmarks/runtime (`<suite>-rust`, `<suite>-zig-safe`),
             which take the row name first; the ports suite is named `legacy` in the runner directory

usage: measure_rows.py --runner DIR [--bin DIR] [--build] [--rows a,b] [--rounds 7] [--cpu 10]
  --build compiles the row programs into --bin first (default: a fresh directory under TMPDIR)
Only run this on CPU 10 or another quiet CPU, never 2, 3 or 11.
"""
import argparse, os, random, re, shutil, statistics, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLOCK = os.path.join(ROOT, "benchmarks/runtime/ports/native_clock.c")
SEED = 7
DEFAULT_RUNNER = "/home/epentland/ai/canopy/mylang-worktrees/runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin"

# row -> (runner suite, unit, iterations at size 4096, iterations at size 64)
UNITS = {
    "record_reads": ("ports", "iteration", 4000000, 4000000),
    "tagged_stack": ("ports", "iteration", 4000000, 4000000),
    "mutate_unique": ("ports", "iteration", 4000000, 4000000),
    "mutate_shared": ("ports", "element", 400, 25000),
    "record_construct": ("compute", "element", 4000, 250000),
    "record_update": ("compute", "element", 4000, 250000),
    "option_handle": ("compute", "element", 4000, 250000),
    "result_propagate": ("compute", "element", 4000, 250000),
    "list_scan": ("collections", "element", 4000, 250000),
    "list_append": ("collections", "element", 4000, 250000),
    "list_filter": ("collections", "element", 4000, 250000),
    "alloc_short": ("collections", "element", 1000, 60000),
    "alloc_retained": ("collections", "element", 1000, 60000),
    "mutate_nested": ("collections", "element", 400, 25000),
}
SIZES = (4096, 64)


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


def build_programs(args, rows):
    """Compile every row program with both cores into args.bin; returns row -> reason for rows the new core refuses."""
    refused = {}
    cache = tempfile.mkdtemp(prefix="rows-cache.")
    try:
        build_all(args, rows, cache, refused)
    finally:
        shutil.rmtree(cache, ignore_errors=True)
    return refused


def build_all(args, rows, cache, refused):
    for row in rows:
        source = os.path.join(ROOT, "test/core/row_%s.my" % row)
        subprocess.run([args.mylang, "build", source, "-o", os.path.join(args.bin, "row_%s_old" % row), "--release", "--link", CLOCK, "--cache-dir", cache + "/old"], check=True)
        done = subprocess.run([args.core, "build", source, "-o", os.path.join(args.bin, "row_%s_new" % row), "--release", "--link", CLOCK, "--cache-dir", cache + "/core"], capture_output=True, text=True)
        if done.returncode != 0:
            found = re.search(r"does not support (.*?) yet", done.stderr)
            refused[row] = found.group(1) if found else done.stderr.strip().splitlines()[-1]
            try:
                os.remove(os.path.join(args.bin, "row_%s_new" % row))
            except FileNotFoundError:
                pass


def runner_binary(args, suite, kind):
    for prefix in ([suite, "legacy"] if suite == "ports" else [suite]):
        path = os.path.join(args.runner, "%s-%s" % (prefix, kind))
        if os.path.exists(path):
            return path
    return None


def configurations(args, row, refused):
    suite = UNITS[row][0]
    rows = [("old core --release", lambda s, i: [os.path.join(args.bin, "row_%s_old" % row), str(s), str(i), str(SEED)])]
    new = os.path.join(args.bin, "row_%s_new" % row)
    if os.path.exists(new) and row not in refused:
        rows.append(("new core release", lambda s, i: [new, str(s), str(i), str(SEED)]))
    for label, kind in (("Rust", "rust"), ("Zig ReleaseSafe", "zig-safe")):
        binary = runner_binary(args, suite, kind)
        if binary:
            rows.append((label, lambda s, i, b=binary: [b, row, str(s), str(i), str(SEED)]))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runner", default=DEFAULT_RUNNER)
    ap.add_argument("--bin", default=None)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--rows", default=",".join(UNITS))
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--mylang", default=os.path.join(ROOT, "zig-out/bin/mylang"))
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    args = ap.parse_args()
    if args.cpu in (2, 3, 11):
        raise SystemExit("never run on CPUs 2, 3 or 11")
    rows = args.rows.split(",")
    scratch = None
    if args.bin is None:
        args.bin = scratch = tempfile.mkdtemp(prefix="rows-bin.")
        args.build = True
    os.makedirs(args.bin, exist_ok=True)
    refused = build_programs(args, rows) if args.build else {}
    for row in rows:
        suite, unit, big, small = UNITS[row]
        configs = configurations(args, row, refused)
        print("\n### %s (cycles per %s, median of %d interleaved rounds, CPU %d)" % (row, unit, args.rounds, args.cpu))
        if row in refused:
            print("new core: refused (%s)" % refused[row])
        print("| configuration | 4096 | 64 | checksum |")
        print("|---|---:|---:|---|")
        counts = {4096: big, 64: small}
        table = {name: {} for name, _ in configs}
        checks = {name: set() for name, _ in configs}
        for size in SIZES:
            iterations = counts[size]
            per = size * iterations if unit == "element" else iterations
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
                table[name][size] = (statistics.median(cycles[name]) - startup[name]) / per
        reference = {size: {c for (s, c) in checks[configs[0][0]] if s == size} for size in SIZES}
        for name, _ in configs:
            same = all({c for (s, c) in checks[name] if s == size} == reference[size] for size in SIZES)
            print("| %s | %.3f | %.3f | %s |" % (name, table[name][4096], table[name][64], "same" if same else "DIFFERENT"))
    if scratch:
        shutil.rmtree(scratch, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
