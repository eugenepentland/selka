#!/usr/bin/env python3
"""Record Wave A's required checks after each package merge.

Every compiling command acquires a build slot. The row runner pins its timing
children to CPU 10; the slot wrapper keeps all other work off reserved CPUs.
"""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import time


ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    args = parser.parse_args()
    evidence = ROOT / "experiments/new-core-s2-20261005/wave-a/integration"
    cache = ROOT / ".mylang-cache/wave-a" / args.stage
    evidence.mkdir(parents=True, exist_ok=True)
    (cache / "tmp").mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(TMPDIR=str(cache / "tmp"),
               ZIG_GLOBAL_CACHE_DIR="/home/epentland/ai/canopy/.zig-global-cache")
    commands = [
        ("build", ["zig", "build", "core", "--summary", "all"]),
        ("old-build", ["zig", "build", "--summary", "all"]),
        ("test-core", ["zig", "build", "test-core", "--summary", "all"]),
        ("code", ["python3", "experiments/new-core-s2-20261005/wave-a/compare_code.py", "--stage", args.stage]),
        ("conformance", ["python3", "experiments/new-core-s1-20261005/conformance.py", "--set", "all", "--jobs", "4", "--why"]),
        ("rows", ["python3", "experiments/new-core-s1-20261005/measure_rows.py", "--build", "--bin", str(cache / "rows"), "--rounds", "7", "--cpu", "10"]),
    ]
    for label, command in commands:
        log = evidence / f"{args.stage}-{label}.txt"
        wrapped = ["scripts/build-slot.sh", "build", "--", *command]
        started = time.monotonic()
        with log.open("w") as output:
            output.write("$ " + shlex.join(wrapped) + "\n")
            output.flush()
            result = subprocess.run(wrapped, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
            elapsed = time.monotonic() - started
            output.write(f"\nexit={result.returncode} wall={elapsed:.2f}s\n")
        print(f"{args.stage}: {label}: exit={result.returncode}, {elapsed:.2f}s; {log}", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)
        if label == "test-core" and elapsed > 300:
            raise SystemExit("test-core exceeded the plan's five-minute stop threshold; inspect admission wait and log")


if __name__ == "__main__":
    main()
