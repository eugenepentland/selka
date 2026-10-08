#!/usr/bin/env python3
"""S5-0: record the old core's verdict for every tests/lang test as a frozen reference.

Runs the archived old core (`mylang test FILE --json`) on every `.my` file under
tests/lang, arena files included, and keeps what conformance.py compares: each
test's name, status and trap code (`R_...`, or "" for a plain failure). A file the
old core reports nothing for keeps its problem text instead.
Usage: freeze_conformance.py --mylang ORACLE --output references/conformance-v1.json
(MYLANG_QBE must name the oracle's QBE.)
"""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("conformance", ROOT / "experiments/new-core-s1-20261005/conformance.py")
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)


def trap(reason):
    found = re.match(r"(R_[A-Z_]+)", reason or "")
    return found.group(1) if found else ""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mylang", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("output exists; keep it and choose a new path")
    tool = sweep.Tool(argparse.Namespace(mylang=args.mylang, core=None, cache_dir=None))
    names = sorted(sweep.short(os.path.join(dp, f)) for dp, _, fs in os.walk(sweep.LANG) for f in fs if f.endswith(".my"))

    def one(name):
        report = tool.old(sweep.resolve(name))
        if isinstance(report, str):
            return name, {"problem": report}
        return name, {"tests": [[t["name"], t["status"], trap(t.get("reason", ""))] for t in report["tests"]]}

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        files = dict(pool.map(one, names))
    oracle = Path(args.mylang).resolve()
    document = {"version": "s5-conformance-references-v1",
                "oracle": {"path": str(oracle), "sha256": hashlib.sha256(oracle.read_bytes()).hexdigest()},
                "files": files}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=0, sort_keys=True) + "\n")
    tests = sum(len(v.get("tests", [])) for v in files.values())
    problems = [k for k, v in files.items() if "problem" in v]
    print(json.dumps({"files": len(files), "tests": tests, "problems": problems}))


if __name__ == "__main__":
    main()
