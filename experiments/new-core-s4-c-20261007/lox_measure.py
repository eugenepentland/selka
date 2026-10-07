#!/usr/bin/env python3
"""Dev-loop timings for S4-C on the Lox port (debug builds).

usage: lox_measure.py CORE PORT WORKDIR [--old]

Copies PORT (benchmarks/lox/ports/mylang of the S4-L checkout) into WORKDIR and
builds main.my with `mylang-core build main.my -o OUT --cache-dir C`. The edit
changes one constant in scanner.my's `new_scanner` body (a one-function edit).
Timings as in measure.py: single-process steps pinned to CPU 10 under its lock.
"""
import argparse
import glob
import json
import os
import shutil
import statistics
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure import processes, run  # noqa: E402

ORIGINAL = "return Scanner(source=source, start=0, current=0, line=1)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("core")
    parser.add_argument("port")
    parser.add_argument("workdir")
    parser.add_argument("--old", action="store_true")
    args = parser.parse_args()
    work = os.path.abspath(args.workdir)
    shutil.rmtree(work, ignore_errors=True)
    project = os.path.join(work, "project")
    shutil.copytree(args.port, project, ignore=shutil.ignore_patterns(".mylang-cache*", "*.o"))
    store = os.path.join(work, "store")
    os.makedirs(store)
    default = os.path.expanduser("~/.cache/mylang/core-runtime")
    for path in glob.glob(os.path.join(default, "core_rt-*.o")) + glob.glob(os.path.join(default, "number-tool-v2-*")):
        target = os.path.join(store, os.path.basename(path))
        (shutil.copytree if os.path.isdir(path) else shutil.copy2)(path, target)
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=store)
    base = [args.core, "build", os.path.join(project, "main.my"), "-o", os.path.join(work, "program"), "--cache-dir", os.path.join(work, "cache")]
    report = [] if args.old else ["--cache-report"]
    result = {"core": args.core}
    elapsed, stderr = run(base + report, env, False)
    result["cold_s"] = round(elapsed, 3)
    result["cold_report"] = stderr.strip()
    times = [run(base, env, True)[0] for _ in range(7)]
    result["unchanged_s"] = {"median": round(statistics.median(times), 4), "min": round(min(times), 4), "max": round(max(times), 4)}
    result["unchanged_processes"] = processes(base, env, work)
    scanner = os.path.join(project, "scanner.my")
    text = open(scanner).read()
    assert ORIGINAL in text
    edits = []
    for value in range(2, 6):
        with open(scanner, "w") as handle:
            handle.write(text.replace(ORIGINAL, ORIGINAL.replace("line=1", f"line={value}")))
        pinned = value % 2 == 0
        elapsed, stderr = run(base + report, env, pinned)
        edits.append({"line": value, "pinned": pinned, "s": round(elapsed, 3), "report": stderr.strip()})
    result["edits"] = edits
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
