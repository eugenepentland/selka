#!/usr/bin/env python3
"""Counting on and off give the same output on every parity program (lane U1 gate 7).

usage: parity_counting.py --mylang M --plain DIR --out DIR
Builds each bench/parity/{lib,micro,suite}/*.my that has a plain binary in DIR with
`--release --counters`, runs both off the timing CPUs and compares stdout and status.
"""
import argparse, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPUS = "0,1,4-9,12-19"

p = argparse.ArgumentParser()
p.add_argument("--mylang", required=True); p.add_argument("--plain", required=True); p.add_argument("--out", required=True)
a = p.parse_args()
out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
same = total = 0
for group in ("lib", "micro", "suite"):
    for src in sorted((ROOT / "bench/parity" / group).glob("*.my")):
        plain = Path(a.plain) / src.stem
        if not plain.exists():
            continue
        counted = out / src.stem
        b = subprocess.run([a.mylang, "build", str(src), "-o", str(counted), "--release", "--counters", "--cache-dir", str(out / "cache")], capture_output=True)
        if b.returncode:
            print(f"BUILD FAIL {src.stem}: {b.stderr.decode()[-300:]}"); total += 1; continue
        env = dict(os.environ, MYLANG_COUNTERS=str(out / f"{src.stem}.json"))
        r1 = subprocess.run(["taskset", "-c", CPUS, str(plain)], capture_output=True)
        r2 = subprocess.run(["taskset", "-c", CPUS, str(counted)], capture_output=True, env=env)
        ok = (r1.returncode, r1.stdout) == (r2.returncode, r2.stdout)
        same += ok; total += 1
        print(f"{'same' if ok else 'DIFF'} {group}/{src.stem}", flush=True)
print(f"{same}/{total} programs: counting on and off identical")
sys.exit(0 if same == total else 1)
