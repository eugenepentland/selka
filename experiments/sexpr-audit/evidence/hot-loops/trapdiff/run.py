#!/usr/bin/env python3
"""Differential trap check: build every `*.my` here with two compilers, run both
binaries and both `mylang run` forms, and compare stdout, stderr and exit status
byte for byte.

A change to the root protocol, the inliner or the position stores can move a trap
pc, drop a sticky-trap test or reorder a frame chain without changing any value a
test would print, so the check compares the *whole* observable trap surface:
bounds (inline, list and negative index), checked overflow (add, sub, mul, neg),
division and remainder by zero, a narrowing and a float-to-int cast, `assert`
text, an out-of-range shift, a trap inside an inlined callee, a trap inside a
non-inlined callee, a deep call chain, `--max-frames` and `--max-steps`, each in
a ReleaseFast binary, a Debug binary (step accounting) and through `mylang run`
with and without `--gc-stress`.

Usage:
  MYLANG_BASE=<compiler> MYLANG_NEW=<compiler> python3 run.py

`MYLANG_BASE` defaults to a baseline worktree, which is not kept checked out:

  git worktree add ../mylang-base <baseline ref>
  (cd ../mylang-base && zig build)
"""
import os, subprocess, sys

BASE = os.environ.get("MYLANG_BASE", "/home/epentland/ai/canopy/mylang-base/zig-out/bin/mylang")
NEW = os.environ.get("MYLANG_NEW", "/home/epentland/ai/canopy/mylang/zig-out/bin/mylang")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

PROGRAMS = [f[:-3] for f in sorted(os.listdir(HERE)) if f.endswith(".my")]

RUNS = [
    ("fast", "ReleaseFast", []),
    ("fast-frames", "ReleaseFast", ["--max-frames=3"]),
    ("fast-steps", "ReleaseFast", ["--max-steps=5"]),
    ("debug", "Debug", []),
    ("debug-steps", "Debug", ["--max-steps=20"]),
    ("debug-frames", "Debug", ["--max-frames=3"]),
]

RUN_COMMANDS = [
    ("run", []),
    ("run-frames", ["--max-frames=2"]),
    ("run-steps", ["--max-steps=5"]),
    ("run-stress", ["--gc-stress"]),
    ("run-stress-frames", ["--gc-stress", "--max-frames=2"]),
]


def build(compiler, source, binary, mode):
    os.makedirs(OUT, exist_ok=True)
    return subprocess.run(
        [compiler, "build", source, "-o", binary, "--mode", mode],
        capture_output=True, text=True, timeout=300,
    )


def run(command, args):
    result = subprocess.run(command + args, capture_output=True, text=True, timeout=300)
    return result.returncode, result.stdout, result.stderr


def main():
    failures = 0
    checks = 0
    for program in PROGRAMS:
        source = os.path.join(HERE, program + ".my")
        for label, mode, arguments in RUNS:
            base_bin = os.path.join(OUT, f"{program}.{label}.base")
            new_bin = os.path.join(OUT, f"{program}.{label}.new")
            b = build(BASE, source, base_bin, mode)
            n = build(NEW, source, new_bin, mode)
            if b.returncode != 0 or n.returncode != 0:
                if (b.returncode == 0) != (n.returncode == 0):
                    print(f"FAIL {program} [{label}]: build status {b.returncode} vs {n.returncode}")
                    failures += 1
                continue
            br = run([base_bin], arguments)
            nr = run([new_bin], arguments)
            checks += 1
            if br != nr:
                failures += 1
                print(f"FAIL {program} [{label}] args={arguments}")
                print(f"  base: status={br[0]} out={br[1]!r} err={br[2]!r}")
                print(f"  new : status={nr[0]} out={nr[1]!r} err={nr[2]!r}")
        for label, arguments in RUN_COMMANDS:
            b = run([BASE, "run", source], arguments)
            n = run([NEW, "run", source], arguments)
            checks += 1
            if b != n:
                failures += 1
                print(f"FAIL {program} [{label}]")
                print(f"  base: status={b[0]} out={b[1]!r} err={b[2]!r}")
                print(f"  new : status={n[0]} out={n[1]!r} err={n[2]!r}")
    print(f"{checks} comparisons, {failures} mismatches")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
