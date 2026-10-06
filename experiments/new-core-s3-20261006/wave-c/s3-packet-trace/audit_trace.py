#!/usr/bin/env python3
"""Retain complete LLVM and prove the trace-only definition delta on all40 rows."""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location("rows", ROOT / "experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py")
ROWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROWS)
BEFORE_CALL = "call void @myl_core_err_trace("
AFTER_CALL = r"call preserve_mostcc void @myl_core_err_trace_(?:origin|append)_preserve_most\("


def specialize(match):
    action = "origin" if match[2] == "0" else "append"
    return f"call preserve_mostcc void @myl_core_err_trace_{action}_preserve_most(i32 {match[1]})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--area", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.core = args.core.resolve()
    for path in (args.area, args.evidence):
        if path.exists() or not path.resolve().is_relative_to(ROOT):
            raise ValueError("use fresh private output paths")
        path.mkdir(parents=True)
    report = dict(source=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(), foundation="0a5dd8794faaf330ab411900d1eaf4e2a00ba0e8",
                  core_sha256=hashlib.sha256(args.core.read_bytes()).hexdigest(), rows={})
    for row in ROWS.UNITS:
        stem = ROWS.stem(row)
        llvm = args.area / f"{stem}.ll"
        before_path = args.before / f"{stem}.ll"
        command = list(map(str, [args.core, "build", ROOT / f"test/core/{stem}.my", "-o", args.area / stem,
                                "--release", "--emit-llvm", llvm, "--cache-dir", args.area / "cache",
                                "--link", ROOT / "benchmarks/runtime/ports/native_clock.c"]))
        done = subprocess.run(command, capture_output=True, text=True)
        (args.evidence / f"{row}-build.json").write_text(json.dumps(dict(command=command, status=done.returncode,
                     stdout=done.stdout, stderr=done.stderr), indent=2) + "\n")
        if done.returncode:
            raise RuntimeError(f"{row}: {done.returncode}: {done.stderr}")
        before = before_path.read_text()
        after = llvm.read_text()
        (args.evidence / f"{row}-before.ll").write_text(before)
        (args.evidence / f"{row}.raw.diff").write_text("".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile="0a5", tofile="trace-twins")))
        before_defs = "\n".join(re.findall(r"^define .*?^\}", before, re.M | re.S))
        after_defs = "\n".join(re.findall(r"^define .*?^\}", after, re.M | re.S))
        exact = before_defs == after_defs
        trace_only = re.sub(r"call void @myl_core_err_trace\(i32 (-?\d+), i32 ([01])\)", specialize, before_defs) == after_defs
        old_sites = before_defs.count(BEFORE_CALL)
        new_sites = len(re.findall(AFTER_CALL, after_defs))
        report["rows"][row] = dict(identical_definitions=exact, only_trace_call_delta=trace_only,
                    trace_calls_before=old_sites, trace_calls_after=new_sites,
                    before_sha256=hashlib.sha256(before.encode()).hexdigest(), after_sha256=hashlib.sha256(after.encode()).hexdigest(),
                    before_path=str(before_path), justification="unchanged definitions" if exact else "explicit err_trace calls retain sites, arguments and inline-cost; only symbol and preserve_mostcc change")
        print(f"{row}: identical={exact} trace_only={trace_only} calls={old_sites}/{new_sites}", flush=True)
    report["qualified"] = all(row["only_trace_call_delta"] and row["trace_calls_before"] == row["trace_calls_after"] for row in report["rows"].values())
    report["old35_identical"] = sum(row["identical_definitions"] for name, row in report["rows"].items() if name not in ROWS.APPLICATIONS)
    (args.evidence / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
