#!/usr/bin/env python3
"""Reanalyse retained captures with paired statistics; never execute the workloads.

Usage: python3 reanalyse.py CAPTURE_ROOT --compiler MYLANG --output NEW_DIRECTORY
CAPTURE_ROOT is qualification-01 or qualification-02 from raw-evidence.tar.gz.
The paired estimator was added after these exploratory measurements; this is
not a held-out evaluation. Every original observation is retained.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("bench", ROOT / "scripts/juice_runtime_bench.py")
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_root", type=Path)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.capture_root.resolve()
    method = source / "method.json"
    policy = bench.read(method)["scheduling_policy"] if method.exists() else None
    results = []
    for case in bench.read(source / "suite.json")["cases"]:
        name = case["name"]
        prior = source / name
        destination = args.output / name
        destination.mkdir()
        paths = {arm: [prior / "cache" / name / "records" / f"{arm}-{index}" / "record.json"
                       for index in range(1, 6)] for arm in ("base", "candidate")}
        identities = "".join(bench.digest(path) for files in paths.values() for path in files)
        pairing = dict(id=hashlib.sha256(identities.encode()).hexdigest(),
                       samples_per_pair=2, method="alternating-captures-v1")
        records = {arm: bench.combine(files, destination / arm, policy, pairing)
                   for arm, files in paths.items()}
        comparison = destination / "comparison.json"
        bench.native(args.compiler, ["compare", records["base"], records["candidate"],
                                     "--output", comparison], destination / "compare")
        report = bench.read(comparison)
        evidence = bench.read(prior / "timing.json")
        evidence.update({key: report[key] for key in ("base_id", "candidate_id", "context_id")})
        evidence["reanalysis_of_sha256"] = bench.digest(prior / "timing.json")
        timing = destination / "timing.json"
        bench.write(timing, evidence)
        validation = destination / "validation.json"
        bench.native(args.compiler, ["validate-runtime", comparison, timing, "--output", validation],
                     destination / "validate", codes=(0, 1))
        result = bench.read(validation)
        proxy = report["workloads"]["work"]["runtime_proxy"]
        result.update(name=name, family=case["family"], counter_proxy=proxy,
                      instruction_ratio=report["workloads"]["work"]["instruction_ratio"],
                      diagnostic_relative_error=abs(proxy["reference_cycles"]["ratio"] / result["timing_ratio"] - 1))
        results.append(result)
        print(name, result["status"], result["diagnostic_relative_error"], flush=True)
    errors = [row["diagnostic_relative_error"] for row in results]
    summary = dict(cases=results, passed=sum(row["passed"] for row in results), total=len(results),
                   uncertain=sum(row["status"] == "uncertain" for row in results),
                   diagnostic_median_relative_error=statistics.median(errors),
                   diagnostic_max_relative_error=max(errors), compiler_sha256=bench.digest(args.compiler),
                   source_suite_sha256=bench.digest(source / "suite.json"),
                   scope="exploratory paired reanalysis of all observations, not held-out validation; diagnostic errors include uncertain cases")
    bench.write(args.output / "results.json", summary)


if __name__ == "__main__":
    main()
