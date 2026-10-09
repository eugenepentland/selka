#!/usr/bin/env python3
"""Run `mylang interfaces oracle` over every entry of a corpus and summarize.

usage: interface_oracle.py MYLANG ENTRY_OR_DIR... [--jobs N] [--json OUT]

A directory contributes every `*.my` file under it (recursively) as an entry.
Each entry's oracle checks every module of its project against its imports'
interfaces and compares the result with the whole-program check. The summary
counts entries, modules, functions and contexts compared, stand-ins, and every
mismatch; the exit status is 1 when any entry differs or fails to run.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import tempfile
import subprocess
import sys
import time
from pathlib import Path


def entries(paths):
    out = []
    for path in paths:
        p = Path(path)
        if p.is_dir():
            out += sorted(q for q in p.rglob("*.my") if ".mylang-cache" not in q.parts)
        else:
            out.append(p)
    return out


def run(mylang, entry):
    source = entry.read_text()
    temporary = None
    target = entry.resolve()
    if not re.search(r"^module\s", source, re.M):
        temporary = tempfile.TemporaryDirectory(prefix="interface-oracle-")
        mirror = Path(temporary.name) / "src"
        shutil.copytree(entry.parent, mirror, ignore=shutil.ignore_patterns(".mylang-cache"))
        target = mirror / entry.name
        target.write_text(source)
    started = time.perf_counter()
    proc = subprocess.run([mylang, "interfaces", "oracle", str(target)], capture_output=True, text=True,
                          env=dict(os.environ))
    wall = time.perf_counter() - started
    if temporary is not None:
        temporary.cleanup()
    try:
        report = json.loads(proc.stdout)
    except json.JSONDecodeError:
        report = None
    return {"entry": str(entry), "status": proc.returncode, "wall": wall, "report": report, "stderr": proc.stderr[-2000:]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--json")
    args = parser.parse_args()
    todo = entries(args.paths)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda e: run(args.mylang, e), todo))
    totals = {"entries": len(results), "entries_equal": 0, "entries_not_checked": 0, "modules": 0, "functions": 0,
              "contexts": 0, "stood_in": 0, "whole_program_diagnostics": 0, "mismatching_entries": []}
    for result in results:
        report = result["report"]
        if report is None:
            totals["entries_not_checked"] += 1
            totals["mismatching_entries"].append({"entry": result["entry"], "status": result["status"], "stderr": result["stderr"]})
            continue
        totals["modules"] += report["modules"]
        totals["functions"] += report["functions_compared"]
        totals["contexts"] += report["contexts_compared"]
        totals["stood_in"] += report["stood_in"]
        totals["whole_program_diagnostics"] += report["whole_program_diagnostics"]
        if report["equal"]:
            totals["entries_equal"] += 1
            continue
        bad = [r for r in report["results"] if r["status"] != "checked" or any(r["mismatches"].values())]
        totals["mismatching_entries"].append({"entry": result["entry"], "missing": report["missing_diagnostics"], "modules": bad[:5]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    return 0 if not totals["mismatching_entries"] else 1


if __name__ == "__main__":
    sys.exit(main())
