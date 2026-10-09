"""Command-line interface; no commands push, switch branches or modify source."""
from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import subprocess
import sys

from .calibration import fit, predict
from .collectors import Collector
from .common import JuiceError, read_json, write_json
from .engine import analyze, capture
from .manifest import Manifest
from .report import compare_records, differences, load_record, render, validate_scenarios


def parser():
    p = argparse.ArgumentParser(description="Juice: compare optimized work per completed application unit")
    sub = p.add_subparsers(dest="command", required=True)
    doctor = sub.add_parser("doctor", help="check collector availability without running a workload")
    analysis = sub.add_parser("analyze", help="build and inspect static code/remarks without executing the application")
    analysis.add_argument("manifest", type=Path)
    analysis.add_argument("--compiler")
    analysis.add_argument("--cache-dir", default="~/.cache/selka/juice")
    analysis.add_argument("--against", type=Path, help="show static differences from an earlier analysis")
    analysis.add_argument("--output", type=Path, required=True)
    record = sub.add_parser("record", help="build, verify and measure an immutable baseline or candidate")
    record.add_argument("manifest", type=Path)
    record.add_argument("--name", required=True)
    record.add_argument("--cache-dir", default="~/.cache/selka/juice")
    record.add_argument("--compiler", help="override the selka compiler or native {compiler} token")
    record.add_argument("--tier", choices=("quick", "validation", "all"), default="quick")
    record.add_argument("--workload", action="append", help="select a workload; repeat for several")
    record.add_argument("--repeats", type=int, default=3)
    record.add_argument("--static", action="store_true", help="also capture selka cost (extra compile)")
    for command in (doctor, record):
        command.add_argument("--collector", choices=("perf", "cachegrind", "callgrind"), default="perf")
        command.add_argument("--cpu", type=int, help="pin collection to this allowed CPU; default excludes timing CPUs")
        command.add_argument("--perf", default="perf")
        command.add_argument("--valgrind", default=os.environ.get("JUICE_VALGRIND", "valgrind"))
    compare = sub.add_parser("compare", help="compare two compatible completed records")
    compare.add_argument("base", type=Path)
    compare.add_argument("candidate", type=Path)
    compare.add_argument("--mode", choices=("application", "backend", "combined"), default="combined")
    compare.add_argument("--output", type=Path, required=True, help="JSON report; Markdown sibling is also written")
    compare.add_argument("--max-spread", type=float, default=0.005)
    compare.add_argument("--min-change", type=float, default=0.001, help="material change floor, default 0.1%%")
    compare.add_argument("--fail-above", type=float, help="exit 1 for uncertain/mixed cases or juice above this value")
    compare.add_argument("--model", type=Path, help="optional validated runtime model")
    validation = sub.add_parser("validate", help="check quick-scenario trends against larger scenario reports")
    validation.add_argument("quick", type=Path)
    validation.add_argument("larger", type=Path)
    validation.add_argument("--tolerance", type=float, default=0.03)
    validation.add_argument("--output", type=Path, required=True)
    calibration = sub.add_parser("calibrate", help="fit a runtime trend using explicit held-out timing evidence")
    calibration.add_argument("dataset", type=Path)
    calibration.add_argument("--output", type=Path, required=True)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if hasattr(args, "output"):
            if args.output.suffix != ".json":
                raise JuiceError("output must have a .json suffix")
            inputs = [getattr(args, key, None) for key in ("base", "candidate", "quick", "larger", "dataset", "model", "against", "manifest")]
            if any(p and args.output.resolve() == p.resolve() for p in inputs):
                raise JuiceError("output must not overwrite an input record/report")
        if args.command == "analyze":
            manifest = Manifest(args.manifest)
            if args.compiler and manifest.data["adapter"] == "native" and not any(
                    "{compiler}" in arg for arg in manifest.data["build"]["command"]):
                raise JuiceError("native --compiler requires {compiler} in build.command")
            report = analyze(manifest, args)
            if args.against:
                base = read_json(args.against)
                if base.get("version") != "juice-analysis-v1":
                    raise JuiceError("against must name a juice-analysis-v1 report")
                report["changes"] = {"sections": differences(base["build"]["code"]["sections"], report["build"]["code"]["sections"]),
                                     "functions": differences(base["build"]["code"]["functions"], report["build"]["code"]["functions"])}
                a, b = base["build"].get("static_cost"), report["build"].get("static_cost")
                if a and b and a.get("version") == b.get("version") == "cost-v1":
                    report["changes"]["core_totals"] = differences(a["totals"], b["totals"])
            write_json(args.output, report)
            print(f"Static analysis written to {args.output}. No application execution or runtime prediction.")
        elif args.command in ("doctor", "record"):
            collector = Collector(args.collector, args.cpu, args.perf, args.valgrind)
            if args.command == "doctor":
                import json
                print(json.dumps(collector.identity, indent=2))
                print("Tool found. Permissions, ISA support and event validity are checked during recording.")
            else:
                manifest = Manifest(args.manifest)
                if args.compiler and manifest.data["adapter"] == "native" and not any(
                        "{compiler}" in arg for arg in manifest.data["build"]["command"]):
                    raise JuiceError("native --compiler requires {compiler} in build.command")
                path = capture(manifest, collector, args)
                print(path)
        elif args.command == "compare":
            if not 0 <= args.max_spread <= 0.1:
                raise JuiceError("max-spread must be 0..0.1")
            if not 0 <= args.min_change <= 0.1:
                raise JuiceError("min-change must be 0..0.1")
            if args.fail_above is not None and (not math.isfinite(args.fail_above) or args.fail_above <= 0):
                raise JuiceError("fail-above must be finite and positive")
            report = compare_records(load_record(args.base), load_record(args.candidate), args.mode, args.max_spread, args.min_change)
            if args.model:
                predict(report, read_json(args.model))
            write_json(args.output, report)
            text = render(report)
            args.output.with_suffix(".md").write_text(text)
            print(text, end="")
            if args.fail_above is not None:
                return int(any(c["juice"] > args.fail_above or c["assessment"] in ("uncertain", "mixed")
                               for c in report["workloads"].values()))
        elif args.command == "validate":
            if not 0 <= args.tolerance <= 0.25:
                raise JuiceError("tolerance must be 0..0.25")
            result = validate_scenarios(read_json(args.quick), read_json(args.larger), args.tolerance)
            write_json(args.output, result)
            print("Quick-scenario validation: " + ("passed" if result["passed"] else "failed"))
            return int(not result["passed"])
        else:
            model = fit(args.dataset)
            write_json(args.output, model)
            print(f"Validated model written to {args.output}; max held-out error {model['validation']['max_relative_error']:.1%}")
        return 0
    except (JuiceError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"juice: {error}", file=sys.stderr)
        return 2
