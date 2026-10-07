#!/usr/bin/env python3
"""Strict startup-adjusted, interleaved CPU-10 split/whole comparisons for S4-E."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import random
import re
import shlex
import statistics
import subprocess
from pathlib import Path
from split_apps import generate

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("rows", ROOT / "experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py")
rows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rows)
CASES = ("packet_decode", "lox_eval", "word_count", "csv_aggregate", "json_transform", "result_propagate")


def unique(directory, pattern):
    matches = list(directory.glob(pattern))
    if len(matches) != 1:
        raise ValueError(f"need exactly one {pattern} in {directory}, found {matches}")
    return matches[0]


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def compile_whole(args, case):
    llvm = args.bin / "llvm" / f"row_{case}.ll"
    cache = args.bin / "cache/new"
    if args.core:
        source = generate(case, args.evidence / "sources" / case) if case != "result_propagate" else ROOT / "test/core/row_result_propagate.my"
        llvm = args.evidence / f"whole-{case}.ll"
        cache = args.evidence / "cache" / case
        output = args.evidence / f"split-{case}"
        command = [str(args.core), "build", str(source), "--release", "-o", str(output), "--cache-dir", str(cache), "--emit-llvm", str(llvm),
                   "--link", str(ROOT / "benchmarks/runtime/ports/native_clock.c")]
        run_build(command, args.evidence / f"build-split-{case}.log")
        # Preserve all actual module inputs as proof of source ownership.
        paths = sorted(cache.glob("program-*/*.ll"))
        modules = [path for path in paths if path.name.startswith("module-")]
        if case != "result_propagate" and sum(re.search(r'^define[^@\n]*@"my\.app::main"', path.read_text(), re.MULTILINE) is not None for path in modules) != 1:
            raise ValueError(f"{case}: main source module absent or repeated: {paths}")
        if case != "result_propagate" and sum('source_filename = "workload.my"' in path.read_text() for path in modules) != 1:
            raise ValueError(f"{case}: workload source module absent or repeated: {paths}")
        (args.evidence / f"units-{case}.json").write_text(json.dumps([identity(path) for path in paths], indent=2) + "\n")
    output = args.whole / f"row_{case}"
    text = llvm.read_text()
    command = ["zig", "cc", "-O3", *rows.CPU_FLAGS, "-Wno-override-module", "-o", str(output), str(llvm), str(unique(cache, "core_rt-*.o"))]
    needed = ("myl_core_str_from_f64", "myl_core_format_number", "myl_core_format_float", "myl_core_format_text", "myl_core_parse_float_range", "myl_core_round_float")
    if any(name in text for name in needed):
        command += [str(unique(cache, "core_number_text-*.o"))]
    command += [str(ROOT / "benchmarks/runtime/ports/native_clock.c")]
    if "llvm.sin.f64" in text or "llvm.cos.f64" in text:
        command += ["-lm"]
    log = args.evidence / f"compile-{case}.log"
    run_build(command, log)
    return output


def run_build(command, log):
    with log.open("x") as stream:
        stream.write("$ " + shlex.join(command) + "\n")
        stream.flush()
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
        stream.write(f"\nexit={result.returncode}\n")
    if result.returncode:
        raise ValueError(f"native build failed: {log}")


def comparison(args, case, alternatives, rng):
    _, unit, big, small = rows.UNITS[case]
    result = {"unit": unit, "binaries": {label: identity(binary) for label, binary in alternatives.items()}, "sizes": {}}
    for size, iterations in zip(rows.SIZES, (big, small)):
        def sample(label, count):
            return rows.sample([alternatives[label], str(size), str(count), str(rows.SEED)])
        startup = {label: [sample(label, 1) for _ in range(3)] for label in alternatives}
        check = next(iter(startup.values()))[0]["checksum"]
        if any(item["checksum"] != check for group in startup.values() for item in group):
            raise ValueError(f"{case}/{size}: startup checksum mismatch")
        runs = {label: [] for label in alternatives}
        for _ in range(args.rounds):
            order = list(alternatives)
            rng.shuffle(order)
            for label in order:
                runs[label].append(sample(label, iterations))
        check = next(iter(runs.values()))[0]["checksum"]
        if any(item["checksum"] != check for group in runs.values() for item in group):
            raise ValueError(f"{case}/{size}: checksum mismatch")
        normalized = {}
        for label in alternatives:
            overhead = statistics.median(item["cycles"] for item in startup[label])
            divisor = size * iterations if unit == "element" else iterations
            values = [(item["cycles"] - overhead) / divisor for item in runs[label]]
            if any(value <= 0 or not math.isfinite(value) for value in values):
                raise ValueError(f"{case}/{size}: invalid normalized cycles")
            normalized[label] = values
        baseline = "whole"
        comparisons = {}
        for label in alternatives:
            if label == baseline:
                continue
            ratios = [a / b for a, b in zip(normalized[label], normalized[baseline])]
            ratio = statistics.median(normalized[label]) / statistics.median(normalized[baseline])
            bootstrap = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(10000))
            interval = [bootstrap[250], bootstrap[9749]]
            comparisons[label] = {"over_whole": ratio, "paired_ratios": ratios, "paired_median_bootstrap95": interval,
                                  "within_noise": interval[0] <= 1 <= interval[1]}
        result["sizes"][str(size)] = {"iterations": iterations, "checksum": check, "startup": startup, "runs": runs,
                                     "cycles_per_unit": normalized, "comparisons": comparisons}
        print(case, size, {label: item["over_whole"] for label, item in comparisons.items()}, flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", type=Path, required=True, help="E all46 build directory")
    parser.add_argument("--whole", type=Path, required=True, help="fresh whole-unit binary directory")
    parser.add_argument("--evidence", type=Path, required=True, help="fresh retained logs and samples")
    parser.add_argument("--index-base", type=Path, help="V qualified binary directory, for pointer/index trace cost")
    parser.add_argument("--core", type=Path, help="E compiler: build real two-source-module application variants")
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=False)
    args.whole.mkdir(parents=True, exist_ok=False)
    report = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "rounds": args.rounds, "startup_samples": 3, "cpu": 10, "cases": {}, "complete": False}
    rng = random.Random(4406)
    try:
        for case in args.cases:
            whole = compile_whole(args, case)
            split = args.evidence / f"split-{case}" if args.core else args.bin / f"row_{case}_new"
            alternatives = {"whole": whole, "split": split}
            if args.core and case != "result_propagate":
                alternatives["original_row"] = args.bin / f"row_{case}_new"
            if args.index_base and case == "result_propagate":
                alternatives["index_base"] = args.index_base / f"row_{case}_new"
            with Path("/run/user/1000/mylang-slots/cpu10.lock").open("a") as slot:
                fcntl.flock(slot, fcntl.LOCK_EX)
                report["cases"][case] = comparison(args, case, alternatives, rng)
        report["complete"] = True
    finally:
        (args.evidence / "samples.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
