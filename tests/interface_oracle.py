#!/usr/bin/env python3
"""Run `selka interfaces oracle` over every entry of a corpus and summarize.

usage: interface_oracle.py SELKA ENTRY_OR_DIR... [--jobs N] [--json OUT]

A directory contributes every `*.selka` file under it (recursively) as an entry.
Each entry's oracle checks every module of its project against its imports'
interfaces and compares the result with the whole-program check: the front
end's results, and Core's ownership and allocation-contract refusals (W9, goal
G7). The summary counts entries, modules, functions, contexts and refusals
compared, stand-ins, every mismatch, and every difference the oracle names as a
known exception of goal G7; the exit status is 1 when any entry differs (known
exceptions apart) or fails to run.
"""
import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import time
from pathlib import Path


def entries(paths):
    out = []
    for path in paths:
        p = Path(path)
        if p.is_dir():
            out += sorted(q for q in p.rglob("*.selka") if ".selka-cache" not in q.parts)
        else:
            out.append(p)
    return out


def run(selka, entry):
    """Run the oracle over one entry, in place.

    An entry that declares no `module` used to be copied, with its whole directory, to a temporary one and rewritten with a
    `module NAME;` header. The header is gone from the language and the rewrite had become the identity, so the copy
    (every file of `tests/lang`, once per entry) was left as 28 CPU seconds of a run and the oracle's report is the same
    in place: 497 entries gave identical reports both ways (9 November 2026).
    """
    target = entry.resolve()
    started = time.perf_counter()
    proc = subprocess.run([selka, "interfaces", "oracle", str(target)], capture_output=True, text=True,
                          env=dict(os.environ))
    wall = time.perf_counter() - started
    try:
        report = json.loads(proc.stdout)
    except json.JSONDecodeError:
        report = None
    return {"entry": str(entry), "status": proc.returncode, "wall": wall, "report": report, "stderr": proc.stderr[-2000:]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("selka")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--json")
    args = parser.parse_args()
    todo = entries(args.paths)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda e: run(args.selka, e), todo))
    totals = {"entries": len(results), "entries_equal": 0, "entries_not_checked": 0, "modules": 0, "functions": 0,
              "contexts": 0, "stood_in": 0, "whole_program_diagnostics": 0, "refusals": 0,
              "whole_program_refusals": 0, "known_differences": [], "mismatching_entries": []}
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
        totals["refusals"] += report["refusals_compared"]
        totals["whole_program_refusals"] += report["whole_program_refusals"]
        totals["known_differences"] += [dict(entry=result["entry"], **known) for known in report["known_differences"]]
        if report["equal"]:
            totals["entries_equal"] += 1
            continue
        bad = [r for r in report["results"] if r["status"] != "checked" or any(r["mismatches"].values())]
        totals["mismatching_entries"].append({"entry": result["entry"], "missing": report["missing_diagnostics"],
                                              "missing_refusals": report["missing_refusals"], "modules": bad[:5]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    return 0 if not totals["mismatching_entries"] else 1


if __name__ == "__main__":
    sys.exit(main())
