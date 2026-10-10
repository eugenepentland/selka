#!/usr/bin/env python3
"""Compare frozen Core/stock-MCA/calibrated-MCA scores on the identical binary."""
from __future__ import annotations
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ir_experiment", ROOT / "experiments/juice-ir-proxy-20261010/evaluate.py")
old = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = old
spec.loader.exec_module(old)
bench = old.bench


def counters(text):
    found = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split(";")
        if len(fields) < 5:
            raise ValueError("invalid perf row")
        name = fields[2]
        if name not in ("cpu_core/cycles/u", "cpu_core/ref-cycles/u") or name in found:
            raise ValueError("unexpected/duplicate counter")
        value = int(fields[0])
        if value <= 0 or float(fields[4]) != 100 or int(fields[3]) <= 0:
            raise ValueError("counter was missing, scaled or multiplexed")
        found[name] = value
    if len(found) != 2:
        raise ValueError("missing counter")
    return dict(cycles=found["cpu_core/cycles/u"], reference_cycles=found["cpu_core/ref-cycles/u"])


def summarize(suite, models, samples):
    output = {}
    for name, predictions in models.items():
        rows = []
        for case in suite["cases"]:
            measurements = [r for r in samples if r["case"] == case["name"]]
            ratios = {metric: bench.stats([r["candidate"][metric] / r["base"][metric] for r in measurements])
                      for metric in ("kernel_ns", "cycles", "reference_cycles")}
            predicted = predictions[old.identity(case["candidate"])]["cycle_score"] / predictions[old.identity(case["base"])]["cycle_score"]
            error = abs(predicted / ratios["kernel_ns"]["median"] - 1)
            cycle_error = abs(predicted / ratios["cycles"]["median"] - 1)
            stable = ratios["kernel_ns"]["spread"] <= suite["timing"]["maximum_pair_spread"]
            status = "uncertain" if not stable else "within-target" if error <= suite["timing"]["target_relative_ratio_error"] else "outside-target"
            rows.append(dict(name=case["name"], predicted_ratio=predicted, ratios=ratios,
                             relative_elapsed_error=error, relative_cycle_error=cycle_error,
                             timing_status=status))
        changes = [r for r in rows if r["name"] != "identity"]
        output[name] = dict(cases=rows, transformation_median_error=statistics.median(r["relative_elapsed_error"] for r in changes),
                            transformation_maximum_error=max(r["relative_elapsed_error"] for r in changes),
                            transformation_median_cycle_error=statistics.median(r["relative_cycle_error"] for r in changes),
                            within_target=sum(r["timing_status"] == "within-target" for r in changes),
                            uncertain=sum(r["timing_status"] == "uncertain" for r in changes))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, default=ROOT / "experiments/juice-ir-proxy-20261010/suite-longer.json")
    parser.add_argument("--stock-model", type=Path, required=True)
    parser.add_argument("--calibrated-model", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=10)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    suite = bench.read(args.suite)
    models, source_methods = {}, {}
    for name, directory in (("llvm_stock", args.stock_model), ("llvm_latency_profile", args.calibrated_model)):
        method = bench.read(directory / "method.json")
        if bench.digest(directory / "predictions.json") != method["predictions_sha256"]:
            raise ValueError("model predictions changed")
        if bench.digest(args.binary) not in method["hashes"].values() or bench.digest(args.suite) not in method["hashes"].values():
            raise ValueError("models do not describe this binary/suite")
        predictions = bench.read(directory / "predictions.json")
        if any(r["status"] != "estimated" for r in predictions.values()):
            raise ValueError("suite has unknown predictions")
        models[name], source_methods[name] = predictions, method
    models["core"] = {key: dict(cycle_score=value["core_cycle_score"]) for key,value in models["llvm_stock"].items()}
    bench.write(args.output / "predictions.json", models)
    bench.write(args.output / "suite.json", suite)
    arms = suite["calibration"] + [c[a] for c in suite["cases"] for a in ("base", "candidate")]
    expected = {old.identity(a): old.oracle(a) for a in arms}
    bench.write(args.output / "oracles.json", expected)
    placement = bench.controller_placement(args.cpu)
    binary = args.binary.resolve()
    method = dict(frozen_at_ns=time.time_ns(), models=source_methods, cpu=args.cpu,
                  binary_sha256=bench.digest(binary), predictions_sha256=bench.digest(args.output / "predictions.json"),
                  evaluator_sha256=bench.digest(__file__), placement=placement, scheduling=bench.scheduling_policy(args.cpu),
                  timing=suite["timing"],
                  notes=["One prospective run; all three predictions frozen before execution.",
                         "perf grouped user cycles/ref-cycles are validation labels only, never estimator inputs.",
                         "perf includes process startup; the program's clock measures the kernel interval.",
                         "Both perf and guest are pinned before event setup. Counters require 100% running."])
    bench.write(args.output / "method.json", method)
    def run(arm, label):
        perf = (args.output / (label + ".perf")).resolve()
        argv = ["taskset", "-c", str(args.cpu), "perf", "stat", "--no-scale", "--no-big-num", "-x", ";",
                "-e", "{cpu_core/cycles/u,cpu_core/ref-cycles/u}", "-o", str(perf), "--", str(binary),
                str(arm["mode"]), str(arm["n"]), str(arm["seed"])]
        command, stdout, _ = bench.command(argv, args.output / label)
        values = stdout.decode().split()
        if command["exit_code"] or len(values) != 2 or int(values[0]) != expected[old.identity(arm)] or int(values[1]) <= 0:
            raise RuntimeError(f"native execution/oracle failure: {label}")
        return dict(arm=old.identity(arm), label=label, kernel_ns=int(values[1]), **counters(perf.read_text()),
                    perf_sha256=bench.digest(perf), command=command)
    lock = Path.home() / ".cache/mylang/runtime-parity-timing.lock"
    with lock.open("a") as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.sched_setaffinity(0, set(placement["controller_affinity"]))
        try:
            calibration, warmups, samples = [], [], []
            for sample in range(suite["timing"]["calibration_samples"] + 1):
                for arm in suite["calibration"][::(-1 if sample % 2 else 1)]:
                    row = run(arm, f"cal-{arm['function']}-{sample}")
                    (calibration if sample else warmups).append(row)
            bench.write(args.output / "calibration.json", calibration)
            for case in suite["cases"]:
                for pair in range(suite["timing"]["pairs"] + 1):
                    rows = {}
                    for side in (("base", "candidate") if pair % 2 == 0 else ("candidate", "base")):
                        rows[side] = run(case[side], f"{case['name']}-{pair}-{side}")
                    if pair:
                        samples.append(dict(case=case["name"], pair=pair, **rows))
                    else:
                        warmups.extend(rows.values())
                bench.write(args.output / "samples.json", samples)
                bench.write(args.output / "warmups.json", warmups)
                print(f"measured {case['name']}", flush=True)
        finally:
            os.sched_setaffinity(0, set(placement["original_affinity"]))
    if bench.digest(binary) != method["binary_sha256"] or bench.digest(__file__) != method["evaluator_sha256"] or bench.digest(args.output / "predictions.json") != method["predictions_sha256"]:
        raise ValueError("measurement inputs changed")
    result = summarize(suite, models, samples)
    bench.write(args.output / "results.json", result)
    print(json.dumps({name:{k:v for k,v in r.items() if k != "cases"} for name,r in result.items()}, indent=2))


if __name__ == "__main__":
    main()
