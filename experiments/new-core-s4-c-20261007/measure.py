#!/usr/bin/env python3
"""Dev-loop timings for S4-C (unit cache, program cache, whole-build replay).

usage: measure.py CORE WORKDIR SIZE MODE [--edits N] [--label L] [--old]

SIZE is a module count for gen_program.py (1200 is ~48k lines, 4800 ~192k).
MODE is debug or release. WORKDIR holds the generated project, its cache and a
private object store (MYLANG_CORE_RUNTIME_CACHE), pre-warmed with the runtime
objects from the default store so "cold" means cold program units.

Single-process timings (unchanged rebuilds, edits) run under `taskset -c 10`
while holding the CPU-10 lock; cold builds and the `unpinned` edit runs use the
caller's CPU mask (run the script under scripts/build-slot.sh). Prints one JSON
object. `--old` measures a core without --cache-report (the S4-C base).
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

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "new-core-s4-20261006", "gen_program.py")
LOCK = "/run/user/1000/mylang-slots/cpu10.lock"


def run(argv, env, pinned):
    if pinned:
        argv = ["flock", LOCK, "taskset", "-c", "10"] + argv
    start = time.perf_counter()
    done = subprocess.run(argv, env=env, capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if done.returncode != 0:
        sys.exit(f"failed ({done.returncode}): {' '.join(argv)}\n{done.stderr}")
    return elapsed, done.stderr


def processes(argv, env, scratch):
    trace = os.path.join(scratch, "execve.txt")
    subprocess.run(["strace", "-f", "-qq", "-e", "trace=execve", "-o", trace] + argv, env=env, capture_output=True, check=True)
    with open(trace) as handle:
        calls = [line for line in handle if "execve(" in line and "= 0" in line]
    return len(calls) - 1  # the compiler itself


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("core")
    parser.add_argument("workdir")
    parser.add_argument("size", type=int)
    parser.add_argument("mode", choices=["debug", "release"])
    parser.add_argument("--edits", type=int, default=3)
    parser.add_argument("--repeat", type=int, default=7)
    parser.add_argument("--old", action="store_true")
    args = parser.parse_args()
    work = os.path.abspath(args.workdir)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    project = os.path.join(work, "project")
    store = os.path.join(work, "store")
    os.makedirs(store)
    default = os.path.expanduser("~/.cache/mylang/core-runtime")
    for path in glob.glob(os.path.join(default, "core_rt-*.o")) + glob.glob(os.path.join(default, "number-tool-v2-*")):
        target = os.path.join(store, os.path.basename(path))
        (shutil.copytree if os.path.isdir(path) else shutil.copy2)(path, target)
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=store)
    subprocess.run([sys.executable, GEN, str(args.size), project], check=True)
    lines = sum(sum(1 for _ in open(p)) for p in glob.glob(os.path.join(project, "*.my")))
    cache = os.path.join(work, "cache")
    base = [args.core, "build", os.path.join(project, "main.my"), "-o", os.path.join(work, "program"), "--cache-dir", cache]
    if args.mode == "release":
        base.append("--release")
    report = [] if args.old else ["--cache-report"]
    result = {"lines": lines, "mode": args.mode, "core": args.core}
    elapsed, stderr = run(base + report, env, False)
    result["cold_s"] = round(elapsed, 3)
    result["cold_report"] = stderr.strip()
    output = subprocess.run([os.path.join(work, "program")], capture_output=True, text=True).stdout.strip()
    result["output"] = output
    times = [run(base, env, True)[0] for _ in range(args.repeat)]
    result["unchanged_s"] = {"median": round(statistics.median(times), 4), "min": round(min(times), 4), "max": round(max(times), 4)}
    result["unchanged_processes"] = processes(base, env, work)
    if not args.old:
        quiet = []
        for _ in range(max(3, args.repeat // 2)):
            shutil.rmtree(os.path.join(cache, "replay-v1"), ignore_errors=True)
            elapsed, stderr = run(base + report, env, True)
            quiet.append(elapsed)
        result["unchanged_no_replay_s"] = round(statistics.median(quiet), 3)
        result["unchanged_no_replay_report"] = stderr.strip()
    edits = []
    first = args.size // 2
    for index in range(args.edits):
        module = first + index
        subprocess.run([sys.executable, GEN, str(args.size), project, "--edit", str(module)], check=True)
        pinned = index % 2 == 0 or args.mode == "release"
        elapsed, stderr = run(base + report, env, pinned)
        edits.append({"module": module, "pinned": pinned, "s": round(elapsed, 3), "report": stderr.strip()})
    result["edits"] = edits
    times = [run(base, env, True)[0] for _ in range(3)]
    result["unchanged_after_edit_s"] = round(statistics.median(times), 4)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
