#!/usr/bin/env python3
"""Sweep directories of programs with the ownership validator and count what it says.

    python3 scripts/verify_ownership_sweep.py PATH... [--release] [--jobs N] [--json] [--verbose]

Every `.selka` file under each PATH that defines `main` is built with `selka build --verify-ownership`, and every file
with `test_` functions is run with `selka test --verify-ownership --force`; a file with both is built and tested. A
project directory (one with a `selka.json`) is swept the same way: its `main.selka` is built and its tests are run as a
whole. The validator checks the ownership certificate of every function the passes finish
(docs/design/ownership-certificates.md section 5): a rejection is an internal compiler error that the build or test
reports as `E_OWNERSHIP_VALIDATION`, naming the function, the block, the instruction, the check and the nearest rule.

The script prints, per PATH, the programs swept, the functions validated and left `unchecked` (task groups), the
rejections with their reasons, and the programs that stopped for another reason (a link that needs a C helper, a test
that fails on purpose). It exits 1 when any program was rejected by the validator, 2 when none could be swept.

Python is allowed in developer scripts: nothing here is part of the install graph or of `src/`.
"""
import argparse
import collections
import concurrent.futures
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = re.compile(r"^(public\s+)?(func|def)\s+main\s*\(", re.M)
TEST = re.compile(r"^\s*(public\s+)?(func|def)\s+test_", re.M)
SUMMARY = re.compile(r"selka: ownership: (\d+) functions validated, (\d+) unchecked")
REJECTION = re.compile(r"E_OWNERSHIP_VALIDATION\]: (.*)")


def compiler(args):
    path = pathlib.Path(args.compiler) if args.compiler else ROOT / "zig-out" / "bin" / "selka"
    if not path.exists():
        sys.exit(f"verify_ownership_sweep: no compiler at {path}; run `zig build` first")
    return str(path)


def run(command, cwd, timeout):
    try:
        done = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    return done.returncode, done.stdout, done.stderr


def programs(root):
    """(path, kinds) for each file under `root` that can be built or tested; a project directory counts as its main."""
    found = []
    base = pathlib.Path(root).resolve()
    files = [base] if base.is_file() else sorted(base.rglob("*.selka"))
    for path in files:
        text = path.read_text(errors="replace")
        kinds = []
        if MAIN.search(text):
            kinds.append("build")
        if TEST.search(text):
            kinds.append("test")
        if kinds:
            found.append((path, kinds))
    return found


def sweep_one(selka, path, kind, release, timeout, scratch):
    """Build or test one program under `scratch`; returns a record of what the validator and the build said."""
    cache = pathlib.Path(scratch) / ("cache-" + re.sub(r"\W", "_", str(path)) + "-" + kind)
    mode = ["--release"] if release else []
    cwd = path.parent
    if kind == "build":
        binary = pathlib.Path(scratch) / ("bin-" + re.sub(r"\W", "_", str(path)))
        command = [selka, "build", str(path), "-o", str(binary), "--verify-ownership", "--cache-dir", str(cache)] + mode
    else:
        command = [selka, "test", str(path), "--verify-ownership", "--force", "--cache-dir", str(cache)] + mode
    code, stdout, stderr = run(command, cwd, timeout)
    text = stderr + stdout
    record = {"program": str(path), "kind": kind, "exit": code, "validated": 0, "unchecked": 0, "rejections": [], "note": ""}
    for found in SUMMARY.finditer(text):
        record["validated"] += int(found.group(1))
        record["unchecked"] += int(found.group(2))
    record["rejections"] = sorted(set(m.group(1)[:400] for m in REJECTION.finditer(text)))
    if code != 0 and not record["rejections"]:
        lines = [line.strip() for line in text.splitlines() if "error" in line.lower() or "failed" in line]
        record["note"] = (lines[0] if lines else text.strip().splitlines()[0] if text.strip() else "")[:240]
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="directories or files to sweep")
    parser.add_argument("--compiler", help="selka binary (default zig-out/bin/selka)")
    parser.add_argument("--release", action="store_true", help="sweep the release build instead of the default")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument("--timeout", type=int, default=1800, help="seconds per program")
    parser.add_argument("--json", action="store_true", help="print the records as JSON")
    parser.add_argument("--verbose", action="store_true", help="list every program that stopped for another reason, not the first five")
    args = parser.parse_args()
    selka = compiler(args)
    report = {}
    swept = 0
    with tempfile.TemporaryDirectory(prefix="verify-ownership-") as scratch:
        for given in args.paths:
            work = programs(given)
            records = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
                futures = [pool.submit(sweep_one, selka, path, kind, args.release, args.timeout, scratch) for path, kinds in work for kind in kinds]
                records = [future.result() for future in futures]
            swept += len(records)
            report[given] = records
    rejected = 0
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    for given, records in report.items():
        validated = sum(r["validated"] for r in records)
        unchecked = sum(r["unchecked"] for r in records)
        bad = [r for r in records if r["rejections"]]
        stopped = [r for r in records if r["exit"] != 0 and not r["rejections"]]
        rejected += len(bad)
        if not args.json:
            print(f"{given}: {len(records)} programs swept, {validated} functions validated in builds, {unchecked} unchecked, {len(bad)} rejected, {len(stopped)} stopped for another reason")
            for record in bad:
                print(f"  REJECTED {record['program']} ({record['kind']}):")
                for reason in record["rejections"]:
                    print(f"    {reason}")
            shown = stopped if args.verbose else stopped[:5]
            for record in shown:
                print(f"  stopped {record['program']} ({record['kind']}, exit {record['exit']}): {record['note']}")
            if len(shown) < len(stopped):
                print(f"  ... {len(stopped) - len(shown)} more stopped programs (--verbose lists them)")
    if swept == 0:
        sys.exit(2)
    sys.exit(1 if rejected else 0)


if __name__ == "__main__":
    main()
