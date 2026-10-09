#!/usr/bin/env python3
"""Build and measure the rungs of one ideal-C ladder (PM-3).

usage: ladder.py SOURCE.c --expected FILE --rung N[:EXTRA_FLAGS] ... [--rounds 5] [--cpu 8]
          [--args ...] [--stdin FILE] [--reference LABEL=BINARY ...]

Each rung is SOURCE.c compiled with `zig cc -O3 -march=native` (the guest
build's -mllvm loop-alignment flag included) and -DRUNG=N plus any extra flags.
Every rung's stdout must equal --expected (the mylang program's output). The
binaries are then run interleaved (shuffled per round) on --cpu under perf stat;
the table gives the median instructions and cycles of each rung and references.
"""
import argparse, json, random, statistics, subprocess, sys
from pathlib import Path

FLAGS = ["-O3", "-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6"]

def main():
    p = argparse.ArgumentParser()
    p.add_argument("source")
    p.add_argument("--expected", required=True)
    p.add_argument("--rung", action="append", required=True)
    p.add_argument("--reference", action="append", default=[])
    p.add_argument("--rounds", type=int, default=5)
    p.add_argument("--cpu", type=int, default=8)
    p.add_argument("--work", required=True)
    p.add_argument("--json", required=True)
    p.add_argument("--arg", action="append", default=[])
    a = p.parse_args()
    work = Path(a.work); work.mkdir(parents=True, exist_ok=True)
    expected = Path(a.expected).read_bytes()
    arms = {}
    for spec in a.rung:
        rung, _, extra = spec.partition(":")
        label = f"rung{rung}" + (f"[{extra}]" if extra else "")
        exe = work / f"{Path(a.source).stem}.r{rung}{abs(hash(extra)) % 10000 if extra else ''}"
        subprocess.run(["zig", "cc", *FLAGS, f"-DRUNG={rung}", *extra.split(), "-o", str(exe), a.source, "-lm"], check=True)
        arms[label] = [str(exe)]
    for ref in a.reference:
        label, _, binary = ref.partition("=")
        arms[label] = binary.split()
    ok = {}
    for label, argv in arms.items():
        out = subprocess.run(["taskset", "-c", str(a.cpu), *argv, *a.arg], stdout=subprocess.PIPE).stdout
        ok[label] = out == expected
    rng = random.Random(11)
    samples = {k: [] for k in arms}
    for _ in range(a.rounds):
        order = list(arms); rng.shuffle(order)
        for label in order:
            r = subprocess.run(["taskset", "-c", str(a.cpu), "perf", "stat", "-x,", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "--", *arms[label], *a.arg],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            row = {}
            for line in r.stderr.splitlines():
                f = line.split(",")
                if len(f) > 2 and f[2].startswith("cpu_core/"):
                    row[f[2][9:].rsplit("/", 1)[0]] = int(f[0])
            samples[label].append(row)
    result = {}
    first = None
    print("| rung | Minstr | Mcycles | instr ÷ rung 0 | cycles ÷ rung 0 | checksum |")
    print("|---|---:|---:|---:|---:|---|")
    for label in arms:
        i = statistics.median(s["instructions"] for s in samples[label])
        c = statistics.median(s["cycles"] for s in samples[label])
        if first is None: first = (i, c)
        result[label] = {"instructions": i, "cycles": c, "output_ok": ok[label], "samples": samples[label]}
        print(f"| {label} | {i/1e6:.0f} | {c/1e6:.0f} | {i/first[0]:.3f} | {c/first[1]:.3f} | {'ok' if ok[label] else 'MISMATCH'} |")
    Path(a.json).write_text(json.dumps(result, indent=1))

if __name__ == "__main__":
    main()
