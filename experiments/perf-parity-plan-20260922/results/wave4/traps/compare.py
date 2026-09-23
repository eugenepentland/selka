#!/usr/bin/env python3
"""Compare trap output between two compilers, byte for byte.

usage: compare.py BEFORE_MYLANG AFTER_MYLANG CASE.my... [--modes build,qbe,run,debug]

For each case and mode, build (or run) with both compilers and compare the
executable's stdout, stderr and exit status. Modes:
  build   mylang build (ReleaseFast, LLVM O3 + LTO default)       then run
  qbe     mylang build --backend qbe (ReleaseFast, QBE)            then run
  nolto   mylang build --backend llvm --llvm-opt 3 (no LTO)        then run
  run     mylang run (QBE fast protocol)
  gc      mylang build, run with --gc-stress
Prints one line per (case, mode) and the differing outputs.
"""
import os
os.environ.setdefault("TMPDIR", os.path.expanduser("~/.cache/mylang-tmp"))
import subprocess
import sys
import tempfile
from pathlib import Path

MODES = {
    "build": (["build"], []),
    "qbe": (["build", "--backend", "qbe"], []),
    "nolto": (["build", "--backend", "llvm", "--llvm-opt", "3"], []),
    "gc": (["build"], ["--gc-stress"]),
    "steps": (["build"], ["--max-steps=5"]),
    "qbegc": (["build", "--backend", "qbe"], ["--gc-stress"]),
}


def outcome(mylang, case, mode, work):
    env = dict(os.environ)
    env.setdefault("MYLANG_MEMORY_LIMIT", "256M")
    if mode == "run":
        p = subprocess.run([mylang, "run", str(case)], capture_output=True, env=env, cwd=case.parent, timeout=600)
        return (p.returncode, p.stdout, p.stderr)
    flags, run_args = MODES[mode]
    exe = work / f"{case.stem}.{mode}"
    b = subprocess.run([mylang, *flags[:1], str(case), "-o", str(exe), *flags[1:], "--cache-dir", str(work / "cache")],
                       capture_output=True, env=env, cwd=case.parent, timeout=900)
    if b.returncode != 0:
        return ("BUILD", b.returncode, b.stderr[-3000:])
    p = subprocess.run([str(exe), *run_args], capture_output=True, env=env, timeout=600)
    return (p.returncode, p.stdout, p.stderr)


def main():
    args = sys.argv[1:]
    modes = ["build", "qbe", "run", "gc"]
    if "--modes" in args:
        i = args.index("--modes")
        modes = args[i + 1].split(",")
        del args[i:i + 2]
    before, after, cases = str(Path(args[0]).resolve()), str(Path(args[1]).resolve()), [Path(c).resolve() for c in args[2:]]
    root = Path(tempfile.mkdtemp(prefix="fmcmp-", dir=os.environ.get("TMPDIR")))
    (root / "b").mkdir()
    (root / "a").mkdir()
    bad = 0
    for case in cases:
        for mode in modes:
            x = outcome(before, case, mode, root / "b")
            y = outcome(after, case, mode, root / "a")
            same = x == y
            bad += not same
            print(f"{'SAME' if same else 'DIFF'} {case.name} {mode} status={x[0]}", flush=True)
            if not same or os.environ.get("SHOW"):
                print("  before:", x)
                print("  after: ", y)
    print(f"{bad} differences")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
