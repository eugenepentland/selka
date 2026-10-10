#!/usr/bin/env python3
"""Freeze compile-only predictions, then test against independent native timing.

The two calibration kernels only fit a scalar nanoseconds/score conversion.
All relative predictions are frozen before any execution. No perf counters.
"""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import platform
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


estimator = load_module("juice_ir_estimate", ROOT / "scripts/juice_ir_estimate.py")
bench = load_module("juice_runtime_bench", ROOT / "scripts/juice_runtime_bench.py")
MASK = (1 << 64) - 1
SHIFTS = [("left", 13), ("right", 7), ("left", 17), ("right", 11)]


def scalar_step(x, depth):
    for direction, count in SHIFTS[:depth]:
        if direction == "left":
            shifted = x << count
        else:
            signed = x if x < 1 << 63 else x - (1 << 64)
            shifted = signed >> count
        x = (x ^ shifted) & MASK
    return x


def apply_matrix(columns, x):
    result = 0
    while x:
        bit = x & -x
        result ^= columns[bit.bit_length() - 1]
        x ^= bit
    return result


def oracle(arm):
    """Independent GF(2) matrix exponentiation, no billion-step Python loops."""
    spec = arm["oracle"]
    columns = [scalar_step(1 << bit, spec["depth"]) for bit in range(64)]
    values = [arm["seed"] ^ lane for lane in range(spec["lanes"])]
    count = spec["steps"]
    while count:
        if count & 1:
            values = [apply_matrix(columns, x) for x in values]
        columns = [apply_matrix(columns, x) for x in columns]
        count >>= 1
    result = 0
    for value in values:
        result ^= value
    return result if result < 1 << 63 else result - (1 << 64)


def identity(arm):
    return f"{arm['function']}-{arm['n']}-{arm['seed']}"


def summarize(suite, predictions, calibration, samples):
    factors = [statistics.median(s["kernel_ns"] for s in calibration if s["arm"] == identity(arm)) /
               predictions[identity(arm)]["cycle_score"]["value"] for arm in suite["calibration"]]
    ns_per_score = statistics.median(factors)
    cases = []
    for case in suite["cases"]:
        rows = [r for r in samples if r["case"] == case["name"]]
        ratios = [r["candidate"]["kernel_ns"] / r["base"]["kernel_ns"] for r in rows]
        measured = bench.stats(ratios)
        base = predictions[identity(case["base"])]
        candidate = predictions[identity(case["candidate"])]
        ratio = candidate["cycle_score"]["value"] / base["cycle_score"]["value"]
        work_ratio = candidate["weighted_work"]["value"] / base["weighted_work"]["value"]
        error = abs(ratio / measured["median"] - 1)
        stable = measured["spread"] <= suite["timing"]["maximum_pair_spread"]
        cases.append(dict(name=case["name"], predicted_ratio=ratio, measured_ratio=measured,
                          relative_ratio_error=error, work_only_ratio=work_ratio,
                          work_only_error=abs(work_ratio / measured["median"] - 1),
                          timing_stable=stable,
                          status=("uncertain" if not stable else "within-target" if error <= .05 else "outside-target"),
                          absolute_prediction_ns={a: predictions[identity(case[a])]["cycle_score"]["value"] * ns_per_score for a in ("base", "candidate")},
                          measured_ns={a: bench.stats([r[a]["kernel_ns"] for r in rows]) for a in ("base", "candidate")}))
    return dict(schema="juice-ir-evaluation-result-v1", calibration_ns_per_score=ns_per_score,
                calibration_factors=factors, cases=cases,
                median_relative_ratio_error=statistics.median(c["relative_ratio_error"] for c in cases),
                maximum_relative_ratio_error=max(c["relative_ratio_error"] for c in cases),
                within_target=sum(c["status"] == "within-target" for c in cases),
                uncertain=sum(c["status"] == "uncertain" for c in cases),
                warning="Six scalar transformations, not representative application coverage; no merge gate.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, default=Path(__file__).with_name("suite.json"))
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--ir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=10)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    suite = bench.read(args.suite)
    ir = args.ir.read_text()
    predictions = {}
    arms = suite["calibration"] + [c[a] for c in suite["cases"] for a in ("base", "candidate")]
    for arm in arms:
        result = estimator.estimate(ir, arm["function"], {0: arm["n"], 1: arm["seed"]})
        if result["status"] != "estimated":
            raise RuntimeError(result)
        predictions[identity(arm)] = result
    abstentions = {name: estimator.estimate(ir, name, {0: 1000, 1: 17}) for name in suite["abstentions"]}
    assert all(r["status"] == "unknown" for r in abstentions.values())
    bench.write(args.output / "predictions.json", predictions)
    bench.write(args.output / "abstentions.json", abstentions)
    source = args.suite.with_name("kernels.my")
    files = [args.binary, args.compiler, args.ir, args.suite, source, Path(__file__),
             ROOT / "scripts/juice_ir_estimate.py", ROOT / "scripts/juice_runtime_bench.py",
             ROOT / "benchmarks/runtime/ports/native_clock.c"]
    placement = bench.controller_placement(args.cpu)
    method = dict(predictions_frozen_at_ns=time.time_ns(),
                  hashes={str(p): bench.digest(p) for p in files},
                  predictions_sha256=bench.digest(args.output / "predictions.json"),
                  cpu=args.cpu, machine=platform.uname()._asdict(),
                  placement=placement, scheduling=bench.scheduling_policy(args.cpu),
                  timing=suite["timing"],
                  timing_scope="clock_gettime around selected function; excludes process startup and argument parsing",
                  model_scope="function Core IR; six transformations within one release binary",
                  ordering="alternating AB/BA; one discarded warmup pair; calibration precedes held-out timing")
    bench.write(args.output / "method.json", method)
    lock_path = Path.home() / ".cache/mylang/runtime-parity-timing.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    expected = {identity(arm): oracle(arm) for arm in arms}
    bench.write(args.output / "oracles.json", expected)
    binary = args.binary.resolve()
    def run(arm, label):
        record, _, _ = bench.command(["taskset", "-c", str(args.cpu), str(binary),
                                str(arm["mode"]), str(arm["n"]), str(arm["seed"])], args.output / label)
        output = (args.output / (label + ".stdout")).read_text().split()
        if record["exit_code"] != 0 or len(output) != 2 or int(output[0]) != expected[identity(arm)]:
            raise RuntimeError(f"oracle/exit failure: {label}: {record}: {output}")
        if int(output[1]) <= 0:
            raise RuntimeError("invalid kernel duration")
        return dict(arm=identity(arm), kernel_ns=int(output[1]), command=record)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.sched_setaffinity(0, set(placement["controller_affinity"]))
        try:
            calibration = []
            for sample in range(suite["timing"]["calibration_samples"] + 1):
                for arm in suite["calibration"][::(-1 if sample % 2 else 1)]:
                    row = run(arm, f"cal-{arm['function']}-{sample}")
                    if sample:
                        calibration.append(row)
            bench.write(args.output / "calibration.json", calibration)
            samples = []
            for case in suite["cases"]:
                for pair in range(suite["timing"]["pairs"] + 1):
                    rows = {}
                    for side in (("base", "candidate") if pair % 2 == 0 else ("candidate", "base")):
                        rows[side] = run(case[side], f"{case['name']}-{pair}-{side}")
                    if pair:
                        samples.append(dict(case=case["name"], pair=pair, **rows))
                bench.write(args.output / "samples.json", samples)
                print(f"measured {case['name']}", flush=True)
        finally:
            os.sched_setaffinity(0, set(placement["original_affinity"]))
    if bench.digest(args.output / "predictions.json") != method["predictions_sha256"]:
        raise RuntimeError("predictions changed during measurement")
    for p in files:
        if bench.digest(p) != method["hashes"][str(p)]:
            raise RuntimeError(f"measurement input changed: {p}")
    results = summarize(suite, predictions, calibration, samples)
    bench.write(args.output / "results.json", results)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
