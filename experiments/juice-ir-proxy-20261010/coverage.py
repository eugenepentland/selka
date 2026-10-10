#!/usr/bin/env python3
"""Compile-only coverage probe against five existing runtime benchmark kernels."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ir_eval", Path(__file__).with_name("evaluate.py"))
evaluation = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = evaluation
spec.loader.exec_module(evaluation)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    cases = [("list_scan", "batch_result"), ("bytes_scan", "bytes_job"),
             ("dict_lookup", "batch_result"), ("tree_build_walk", "walk"), ("list_filter", "batch_result")]
    for name, function in cases:
        source = ROOT / f"test/core/row_{name}.my"
        start = time.perf_counter_ns()
        dump = subprocess.run([str(args.compiler), "dump-ir", str(source), "--facts"],
                              capture_output=True, text=True, check=True, timeout=120).stdout
        compile_ns = time.perf_counter_ns() - start
        (args.output / f"{name}.ir").write_text(dump)
        result = evaluation.estimator.estimate(dump, function)
        result.update(source=str(source.relative_to(ROOT)), source_sha256=evaluation.bench.digest(source),
                      compiler_sha256=evaluation.bench.digest(args.compiler), compile_ir_ns=compile_ns)
        results.append(result)
        print(name, result["status"], result.get("reason"))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
