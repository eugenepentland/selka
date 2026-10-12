#!/usr/bin/env python3
"""Count the exact calibrated runtime inputs, separately from the pinned census."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import time

import measure


def module(name, relative):
    path = measure.ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def group(args, cases, census, audit):
    first = cases[0]
    directory = args.output / first["id"]
    directory.mkdir(parents=True)
    source = Path(first["source"])
    assert measure.source_inputs(source) == first["source_inputs_sha256"]
    binary, llvm = directory / "program", directory / "program.ll"
    flags = ["--experimental-zero-rc"] if args.ownership == "opt-in" else []
    command = [args.compiler, "build", source, *flags, "--release", "--counters",
               "--zig", args.zig, "--cache-dir", args.output / "cache",
               "-o", binary, "--emit-llvm", llvm]
    env = measure.clean_env()
    built = census.invoke(command, directory / "build", env, timeout=120)
    built["wall_ns_excludes_admission_wait"] = True
    result = {"build": built, "cases": [], "status": "build_failed"}
    structural = None
    if built["exit"] == 0:
        result.update(binary=str(binary), binary_sha256=measure.digest(binary))
        structural = census.structural(binary, llvm, directory, env)
        result["structural"] = structural
    elif "error[E_" in built["stderr"]:
        result["status"] = "refused"
    for case in cases:
        row = {"id": case["id"], "source": case["source"],
               "source_inputs_sha256": case["source_inputs_sha256"],
               "args": case.get("args", []), "env": case.get("env", {}),
               "cpus": case["cpus"], "expected": case["expected"],
               "matched_uncounted_binary_sha256": case["binary_sha256"],
               "status": result["status"]}
        if built["exit"] == 0:
            counts = directory / (case["id"] + "-counts.json")
            command = ["taskset", "-c", ",".join(map(str, case["cpus"])), binary, *row["args"]]
            run_env = dict(env, **row["env"], MYLANG_COUNTERS=str(counts))
            ran = census.invoke(command, directory / (case["id"] + "-run"), run_env, timeout=120)
            ran["wall_ns_excludes_admission_wait"] = True
            row["run"] = ran
            row["output_matches"] = ran["exit"] == 0 and ran["stdout"] == case["expected"] and not ran["stderr"]
            if counts.exists():
                try:
                    row["audit"] = audit.audit(counts)
                    row["whole_program_managed_totals"] = json.loads(counts.read_text())["totals"]
                except (ValueError, KeyError, TypeError) as error:
                    row["counter_error"] = str(error)
            okay = (row["output_matches"] and structural["passed"] and
                    row.get("audit", {}).get("observed_rc_free", False) and
                    row.get("audit", {}).get("managed_leak_free", False))
            row["status"] = "passed" if okay else "failed"
        result["cases"].append(row)
        print(row["id"], row["status"], flush=True)
    assert measure.source_inputs(source) == first["source_inputs_sha256"]
    if built["exit"] == 0:
        result["status"] = "passed" if all(row["status"] == "passed" for row in result["cases"]) else "failed"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds", type=lambda p: Path(p).resolve(), nargs="+", required=True)
    parser.add_argument("--compiler", type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--zig", type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--ownership", choices=("opt-in", "default"), default="opt-in")
    parser.add_argument("--output", type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("refusing to overwrite existing supplement")
    if os.environ.get("MYLANG_ADMISSION_KIND"):
        parser.error("invoke directly; one bounded build lease per distinct source")
    census = module("a09_census", "experiments/memory-closeout-20261012/A03/census.py")
    audit = module("a09_audit", "experiments/zero-rc-20261011/audit.py")
    admission = module("a09_admission", "scripts/build_admission.py")
    groups = {}
    for path in args.builds:
        for case in json.loads(path.read_text())["cases"]:
            assert measure.digest(case["binary"]) == case["binary_sha256"]
            assert measure.source_inputs(Path(case["source"])) == case["source_inputs_sha256"]
            groups.setdefault(case["source"], []).append(case)
    report = {"schema": "memory-closeout-size-aligned-counters-v1", "scope": __doc__,
              "source_commit": args.source_commit, "compiler": str(args.compiler),
              "compiler_sha256": measure.digest(args.compiler), "ownership": args.ownership,
              "zig_sha256": measure.digest(args.zig), "harness_sha256": measure.digest(__file__),
              "counter_audit_sha256": measure.digest(audit.__file__),
              "structural_helper_sha256": measure.digest(census.__file__),
              "input_builds": {str(path): measure.digest(path) for path in args.builds},
              "distinct_builds": len(groups), "case_denominator": sum(map(len, groups.values())),
              "limitations": ["Whole-program managed counters; not RSS or timing evidence.",
                              "No arbitrary kernel subtraction for these multi-module inputs.",
                              "Separate from the original30/pinned81+6 census; preserves every failed case.",
                              "Recursive copy telemetry differs after the later instrumentation correction; allocation/peak fields are separate."],
              "groups": []}
    for cases in groups.values():
        started = time.monotonic_ns()
        with admission.admission("build"):
            admitted = time.monotonic_ns()
            result = group(args, cases, census, audit)
            result["admitted_work_ns"] = time.monotonic_ns() - admitted
        result["queue_wait_ns"] = admitted - started
        report["groups"].append(result)
        measure.save(args.output / "results.json", report)
    report["passed"] = all(item["status"] == "passed" for item in report["groups"])
    measure.save(args.output / "results.json", report)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
