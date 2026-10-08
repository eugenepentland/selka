#!/usr/bin/env python3
"""S4-X dev-loop target: `mylang-core check` after a one-function edit at 96k lines.

Generates the synthetic project with gen_program.py (2400 modules is about 96k lines),
checks it once to warm the check cache, then edits three modules in turn and times
each check on CPU 10. Run under `flock /run/user/1000/mylang-slots/cpu10.lock`.
"""
import argparse
import glob
import json
import os
import shutil
import statistics
import subprocess
import sys
import time

GEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "new-core-s4-20261006", "gen_program.py")


def timed(argv):
    started = time.perf_counter()
    done = subprocess.run(["taskset", "-c", "10"] + argv, capture_output=True, text=True)
    seconds = time.perf_counter() - started
    if done.returncode != 0:
        sys.exit(f"failed ({done.returncode}): {' '.join(argv)}\n{done.stderr[-2000:]}")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("core")
    parser.add_argument("workdir")
    parser.add_argument("--size", type=int, default=2400)
    parser.add_argument("--edits", type=int, default=3)
    args = parser.parse_args()
    work = os.path.abspath(args.workdir)
    shutil.rmtree(work, ignore_errors=True)
    project = os.path.join(work, "project")
    os.makedirs(work)
    subprocess.run([sys.executable, GEN, str(args.size), project], check=True)
    lines = sum(sum(1 for _ in open(p)) for p in glob.glob(os.path.join(project, "*.my")))
    check = [args.core, "check", os.path.join(project, "main.my"), "--cache-dir=" + os.path.join(work, "cache")]
    result = {"lines": lines, "core": args.core, "cold_s": round(timed(check), 3)}
    result["unchanged_s"] = round(statistics.median(timed(check) for _ in range(3)), 4)
    edits = []
    for index in range(args.edits):
        module = args.size // 2 + index
        subprocess.run([sys.executable, GEN, str(args.size), project, "--edit", str(module)], check=True)
        edits.append({"module": module, "s": round(timed(check), 3)})
    result["edits"] = edits
    result["edit_median_s"] = statistics.median(e["s"] for e in edits)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
