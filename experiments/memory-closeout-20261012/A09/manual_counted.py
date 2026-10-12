#!/usr/bin/env python3
"""Run size-aligned counters through the approved exact-source native adapter.

This preserves the original compiler command's status, reconstructs no LLVM,
and produces only counter evidence. It never replaces timing binaries.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

import counted_inputs
import measure

ADAPTER_COMMIT = "44a9ccbbc5a179d15b057a369f22f22afb115c06"
ADAPTER_PATH = "experiments/memory-closeout-20261012/A10/manual-native/manual_native.py"


def adapter(path):
    expected = subprocess.check_output(["git", "show", f"{ADAPTER_COMMIT}:{ADAPTER_PATH}"], cwd=measure.ROOT)
    if measure.digest(path) != hashlib.sha256(expected).hexdigest():
        raise ValueError("adapter differs from approved commit")
    spec = importlib.util.spec_from_file_location("a10_manual_native", path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def execute(case, binary, directory, census, audit):
    row = {key: case[key] for key in ("id", "source", "source_inputs_sha256", "args", "env",
                                     "cpus", "expected", "matched_uncounted_binary_sha256")}
    row["original_case_status"] = case["status"]
    counts = directory / (case["id"] + "-counts.json")
    env = dict(measure.clean_env(case["env"]), MYLANG_COUNTERS=str(counts))
    command = ["taskset", "-c", ",".join(map(str, case["cpus"])), binary, *case["args"]]
    ran = census.invoke(command, directory / (case["id"] + "-run"), env, timeout=120)
    ran["wall_ns_excludes_admission_wait"] = True
    row["run"] = ran
    row["output_matches"] = ran["exit"] == 0 and ran["stdout"] == case["expected"] and not ran["stderr"]
    if counts.exists():
        try:
            row["audit"] = audit.audit(counts)
            row["whole_program_managed_totals"] = json.loads(counts.read_text())["totals"]
        except (ValueError, KeyError, TypeError) as error:
            row["counter_error"] = str(error)
    okay = (row["output_matches"] and row.get("audit", {}).get("observed_rc_free", False)
            and row.get("audit", {}).get("managed_leak_free", False))
    row["status"] = "passed" if okay else "failed"
    print(case["id"], row["status"], flush=True)
    return row


def prepare_group(args, original, archive):
    name = original["cases"][0]["id"]
    directory = args.output / name
    directory.mkdir(parents=True)
    relative = name + "/program.ll.gz"
    packed = args.archive / relative
    identity = archive["files"][relative]
    if measure.digest(packed) != identity["compressed_sha256"]:
        raise ValueError("archived LLVM container changed")
    raw = gzip.decompress(packed.read_bytes())
    if hashlib.sha256(raw).hexdigest() != identity["uncompressed_sha256"]:
        raise ValueError("archived compiler LLVM changed")
    llvm = directory / "program.ll"
    llvm.write_bytes(raw)
    return directory, llvm


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("adapter", "runtime-dir", "archive", "output"):
        parser.add_argument("--" + name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("refusing to overwrite supplemental evidence")
    if os.environ.get("MYLANG_ADMISSION_KIND"):
        parser.error("invoke directly; harness owns bounded source-group build admission")
    manual = adapter(args.adapter)
    runtime = json.loads((args.runtime_dir / "runtime.json").read_text())
    original = json.loads((args.archive / "results.json").read_text())
    archive = json.loads((args.archive / "archive.json").read_text())
    if runtime["compiler_sha256"] != original["compiler_sha256"] or runtime["source_revision"] != original["source_commit"]:
        raise ValueError("manual runtime and original compiler do not match")
    if measure.digest(runtime["compiler"]) != runtime["compiler_sha256"]:
        raise ValueError("frozen compiler changed")
    census = counted_inputs.module("a09_census_manual", "experiments/memory-closeout-20261012/A03/census.py")
    audit = counted_inputs.module("a09_audit_manual", "experiments/zero-rc-20261011/audit.py")
    admission = counted_inputs.module("a09_admission_manual", "scripts/build_admission.py")
    report = {"method": manual.METHOD, "scope": __doc__, "adapter_commit": ADAPTER_COMMIT,
              "adapter_sha256": measure.digest(args.adapter), "harness_sha256": measure.digest(__file__),
              "compiler_sha256": runtime["compiler_sha256"], "source_commit": runtime["source_revision"],
              "runtime_receipt": runtime, "original_results": str(args.archive / "results.json"),
              "original_results_sha256": measure.digest(args.archive / "results.json"),
              "counter_audit_sha256": measure.digest(audit.__file__),
              "structural_helper_sha256": measure.digest(census.__file__),
              "case_denominator": original["case_denominator"], "groups": [],
              "limitations": original["limitations"] + ["Manual native replay is separate from original compiler command success.",
                                                         "Final candidate must use this same adapter and repeat normal/manual equivalence controls."]}
    for item in original["groups"]:
        directory, llvm = prepare_group(args, item, archive)
        binary = directory / "program"
        result = {"original_build_status": item["status"], "cases": []}
        waiting = time.monotonic_ns()
        with admission.admission("build"):
            admitted = time.monotonic_ns()
            try:
                result["artifact"] = manual.link(args.runtime_dir, llvm, binary, directory / "native")
                result["structural"] = census.structural(binary, llvm, directory, measure.clean_env())
                result["cases"] = [execute(case, binary, directory, census, audit) for case in item["cases"]]
                result["status"] = "passed" if result["structural"]["passed"] and all(c["status"] == "passed" for c in result["cases"]) else "failed"
            except (RuntimeError, ValueError, OSError) as error:
                result.update(status="manual_build_failed", error=str(error))
                result["cases"] = [{"id": case["id"], "status": "manual_build_failed"} for case in item["cases"]]
            result["admitted_work_ns"] = time.monotonic_ns() - admitted
        result["queue_wait_ns"] = admitted - waiting
        report["groups"].append(result)
        measure.save(args.output / "results.json", report)
    report["passed"] = all(item["status"] == "passed" for item in report["groups"])
    measure.save(args.output / "results.json", report)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
