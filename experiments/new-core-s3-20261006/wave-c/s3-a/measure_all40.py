#!/usr/bin/env python3
"""Measure all 40 S3 rows with the accepted S1 interleaved CPU-10 method.

Three one-iteration startup samples are subtracted from the median of shuffled
rounds. Old/new core, Rust and Zig ReleaseSafe must all print exactly two integer
fields (checksum and native elapsed nanoseconds), exit successfully, and agree
on checksums at each size/iteration count. Cycle counters and normalized measures
must be positive and finite. Performance misses are reported separately from
measurement validity; binary_search's layout noise requires the plan's IR review.

Run under scripts/build-slot.sh build and the shared CPU-10 flock. --build saves
new-core LLVM for audit_all40.py. All writable paths must stay in this worktree.
--smoke-test exercises Python parsers/registry only; it never runs a benchmark.
"""
import argparse
import csv
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import sys
from unittest import mock

ROOT = Path(__file__).resolve().parents[4]
S1_SPEC = importlib.util.spec_from_file_location("s1_rows", ROOT / "experiments/new-core-s1-20261005/measure_rows.py")
S1 = importlib.util.module_from_spec(S1_SPEC)
S1_SPEC.loader.exec_module(S1)
UNITS = dict(S1.UNITS)
UNITS.update({
    "bytes_scan": ("text", "element", 4000, 250000),
    "string_equal": ("text", "iteration", 200000, 200000),
    "string_search": ("text", "iteration", 40000, 40000),
    "string_split": ("text", "element", 400, 25000),
    "string_join": ("text", "element", 1000, 60000),
    "dict_lookup": ("collections", "element", 4000, 250000),
    "dict_lookup_str": ("collections", "element", 4000, 250000),
    "dict_update": ("collections", "element", 1000, 60000),
    "dict_update_str": ("collections", "element", 1000, 60000),
    "set_dedup": ("collections", "element", 4000, 250000),
    "int_parse": ("text", "iteration", 4000000, 4000000),
    "int_format": ("text", "iteration", 4000000, 4000000),
    "call_indirect": ("compute", "element", 4000, 250000),
    "sort_int": ("collections", "element", 400, 25000),
    "sort_records": ("collections", "element", 400, 25000),
    "int_math": ("compute", "element", 4000, 250000),
    "float_math": ("compute", "element", 4000, 250000),
    "call_direct": ("compute", "element", 4000, 250000),
    "branch_predictable": ("compute", "element", 4000, 250000),
    "branch_mixed": ("compute", "element", 4000, 250000),
    "binary_search": ("compute", "element", 400, 25000),
})
APPLICATIONS = {"word_count", "csv_aggregate", "json_transform", "packet_decode", "lox_eval"}
UNITS.update({
    "word_count": ("text", "element", 400, 25000),
    "csv_aggregate": ("text", "element", 40, 2500),
    "json_transform": ("text", "element", 20, 1250),
    "packet_decode": ("compute", "element", 400, 25000),
    "lox_eval": ("collections", "element", 40, 2500),
})
S0 = {"int_math", "float_math", "call_direct", "branch_predictable", "branch_mixed", "binary_search"}
REFERENCE_NAMES = {"int_math": "integer_math"}
SIZES = (4096, 64)
SEED = 7
EVENT = "cpu_core/cycles/u"
CPU_FLAGS = ("-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6")
DEFAULT_BIN = ROOT / ".mylang-cache/s3-a/all40"


class InvalidMeasurement(RuntimeError):
    pass


def row_names(value):
    names = value.split(",")
    if not names or len(names) != len(set(names)) or any(name not in UNITS for name in names):
        raise InvalidMeasurement(f"unknown or duplicate rows: {value}")
    return names


def stem(row):
    return row if row in S0 else f"row_{row}"


def inside(path):
    path = Path(path).resolve()
    if not path.is_relative_to(ROOT):
        raise InvalidMeasurement(f"writable path must be inside {ROOT}: {path}")
    return path


def parse_stdout(stdout):
    match = re.fullmatch(r"(0|-?[1-9][0-9]*) (0|[1-9][0-9]*)\n", stdout)
    if not match:
        raise InvalidMeasurement(f"expected exactly 'checksum elapsed_ns\\n', got {stdout!r}")
    return int(match[1]), int(match[2])


def parse_perf(stderr):
    cycles = []
    for fields in csv.reader(io.StringIO(stderr)):
        if not fields or not any(field.strip() for field in fields):
            continue
        fields = [field.strip() for field in fields]
        if len(fields) >= 3 and fields[2].rstrip("/") == EVENT.rstrip("/"):
            if not re.fullmatch(r"[0-9]+", fields[0]):
                raise InvalidMeasurement(f"unavailable cycle counter: {fields}")
            cycles.append(int(fields[0]))
        elif len(fields) >= 3 and fields[1] == "seconds" and fields[2] in ("time elapsed", "user", "sys"):
            continue
        else:
            raise InvalidMeasurement(f"unexpected native/perf stderr: {','.join(fields)!r}")
    if len(cycles) != 1 or cycles[0] <= 0:
        raise InvalidMeasurement(f"expected one positive {EVENT} counter: {stderr!r}")
    try:
        finite = math.isfinite(float(cycles[0]))
    except OverflowError:
        finite = False
    if not finite:
        raise InvalidMeasurement("non-finite cycle count")
    return cycles[0]


def sample(argv):
    command = ["taskset", "-c", "10", "perf", "stat", "-x,", "-e", EVENT, *map(str, argv)]
    done = subprocess.run(command, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    if done.returncode != 0:
        raise InvalidMeasurement(f"status {done.returncode}: {command}\nstdout={done.stdout!r}\nstderr={done.stderr!r}")
    checksum, elapsed = parse_stdout(done.stdout)
    cycles = parse_perf(done.stderr)
    return {"command": command, "status": done.returncode, "stdout": done.stdout,
            "stderr": done.stderr, "checksum": checksum, "elapsed_ns": elapsed, "cycles": cycles}


def build(args, selected):
    cache = args.bin / "cache"
    llvm = args.bin / "llvm"
    llvm.mkdir(parents=True, exist_ok=True)
    for row in selected:
        name = stem(row)
        source = ROOT / f"test/core/{name}.my"
        if not source.is_file():
            raise InvalidMeasurement(f"row source missing (package not integrated): {source}")
        for kind, compiler in (("old", args.mylang), ("new", args.core)):
            output = args.bin / f"{name}_{kind}"
            output.unlink(missing_ok=True)
            command = [str(compiler), "build", str(source), "-o", str(output), "--release",
                       "--cache-dir", str(cache / kind), "--link", str(ROOT / "benchmarks/runtime/ports/native_clock.c")]
            if kind == "new":
                emitted = llvm / f"{name}.ll"
                emitted.unlink(missing_ok=True)
                command += ["--emit-llvm", str(emitted)]
            done = subprocess.run(command, capture_output=True, text=True)
            print(f"build {row} {kind}: status={done.returncode}", flush=True)
            if done.returncode or not output.is_file() or (kind == "new" and not emitted.is_file()):
                raise InvalidMeasurement(f"build failed/refused: {command}\n{done.stdout}{done.stderr}")


def configurations(args, row):
    suite = UNITS[row][0]
    result = {}
    for label, kind in (("old core --release", "old"), ("new core release", "new")):
        binary = args.bin / f"{stem(row)}_{kind}"
        if not binary.is_file():
            raise InvalidMeasurement(f"missing binary: {binary}; run --build")
        result[label] = lambda size, iterations, binary=binary: [str(binary), str(size), str(iterations), str(SEED)]
    reference = REFERENCE_NAMES.get(row, row)
    for label, kind in (("Rust", "rust"), ("Zig ReleaseSafe", "zig-safe")):
        binary = next((args.runner / f"{prefix}-{kind}" for prefix in ((suite, "legacy") if suite == "ports" else (suite,))
                       if (args.runner / f"{prefix}-{kind}").is_file()), None)
        if binary is None:
            raise InvalidMeasurement(f"missing {label} reference for {suite} in {args.runner}")
        result[label] = lambda size, iterations, binary=binary: [str(binary), reference, str(size), str(iterations), str(SEED)]
    return result


def measure_row(args, row, rng):
    suite, unit, big, small = UNITS[row]
    configs = configurations(args, row)
    result = {"suite": suite, "unit": unit, "reference_name": REFERENCE_NAMES.get(row, row), "sizes": {}}
    print(f"\n### {row} (cycles per {unit}, median of {args.rounds} interleaved rounds, CPU 10)", flush=True)
    for size, iterations in zip(SIZES, (big, small)):
        startup = {name: [sample(make(size, 1)) for _ in range(3)] for name, make in configs.items()}
        expected_start = startup["old core --release"][0]["checksum"]
        if any(run["checksum"] != expected_start for runs in startup.values() for run in runs):
            raise InvalidMeasurement(f"{row}/{size}: startup checksum disagreement")
        runs = {name: [] for name in configs}
        for _ in range(args.rounds):
            order = list(configs)
            rng.shuffle(order)
            for name in order:
                runs[name].append(sample(configs[name](size, iterations)))
        expected = runs["old core --release"][0]["checksum"]
        if any(run["checksum"] != expected for values in runs.values() for run in values):
            values = {name: sorted({run["checksum"] for run in values}) for name, values in runs.items()}
            raise InvalidMeasurement(f"{row}/{size}: checksum disagreement: {values}")
        values = {}
        for name in configs:
            per = size * iterations if unit == "element" else iterations
            value = (statistics.median(run["cycles"] for run in runs[name]) -
                     statistics.median(run["cycles"] for run in startup[name])) / per
            if not math.isfinite(value) or value <= 0:
                raise InvalidMeasurement(f"{row}/{size}/{name}: nonpositive/non-finite normalized measure {value}")
            values[name] = {"cycles_per_unit": value, "startup": startup[name], "runs": runs[name]}
        ratio_old = values["new core release"]["cycles_per_unit"] / values["old core --release"]["cycles_per_unit"]
        ratio_zig = values["new core release"]["cycles_per_unit"] / values["Zig ReleaseSafe"]["cycles_per_unit"]
        ratio_rust = values["new core release"]["cycles_per_unit"] / values["Rust"]["cycles_per_unit"]
        if not all(math.isfinite(value) and value > 0 for value in (ratio_old, ratio_zig, ratio_rust)):
            raise InvalidMeasurement(f"{row}/{size}: nonpositive/non-finite comparison ratio")
        result["sizes"][str(size)] = {"iterations": iterations, "checksum": expected, "configurations": values,
                                     "new_over_old": ratio_old, "new_over_zig": ratio_zig, "new_over_rust": ratio_rust,
                                     "within_old_limit": ratio_old <= 1.10, "within_zig_limit": ratio_zig <= 1.10,
                                     "within_both_limits": ratio_old <= 1.10 and ratio_zig <= 1.10}
    print("| configuration | 4096 | 64 | checksum |\n|---|---:|---:|---|")
    for name in configs:
        values = [result["sizes"][str(size)]["configurations"][name]["cycles_per_unit"] for size in SIZES]
        print(f"| {name} | {values[0]:.3f} | {values[1]:.3f} | same |")
    for name, field in (("new / old", "new_over_old"), ("new / Zig", "new_over_zig"), ("new / Rust", "new_over_rust")):
        values = [result["sizes"][str(size)][field] for size in SIZES]
        print(f"| {name} | {values[0]:.3f} | {values[1]:.3f} | same |")
    return result


def smoke():
    assert len(UNITS) == 40 and len(APPLICATIONS) == 5 and len(S0) == 6
    assert stem("int_math") == "int_math" and REFERENCE_NAMES["int_math"] == "integer_math"
    assert UNITS["binary_search"][2:] == (400, 25000)
    assert parse_stdout("-17 102\n") == (-17, 102)
    assert parse_perf("100,,cpu_core/cycles/u,500,100.00,,\n") == 100
    for function, value in ((parse_stdout, "17\n"), (parse_stdout, "17 0\nextra\n"), (parse_stdout, "-0 1\n"),
                            (parse_perf, "<not counted>,,cpu_core/cycles/u,0,0.00,,\n"),
                            (parse_perf, "100,,cpu_core/cycles/u,0,100,,\nnative error\n")):
        try:
            function(value)
        except InvalidMeasurement:
            continue
        raise AssertionError(f"parser admitted invalid input {value!r}")
    with mock.patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], -11, stdout="", stderr="")):
        try:
            sample(["synthetic-native"])
        except InvalidMeasurement:
            pass
        else:
            raise AssertionError("blank-stderr signal exit was admitted")
    print("measure_all40 Python smoke: registry40, S0 names/units, strict stdout/counter/error parsers pass; no native runs")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runner", type=Path, default=Path(S1.DEFAULT_RUNNER))
    parser.add_argument("--bin", type=Path, default=DEFAULT_BIN)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--build-only", action="store_true", help="build selected old/new rows without timing")
    parser.add_argument("--rows", default=",".join(UNITS))
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--cpu", type=int, choices=(10,), default=10)
    parser.add_argument("--mylang", type=Path, default=ROOT / ".mylang-cache/s3-a/oracle/mylang")
    parser.add_argument("--core", type=Path, default=ROOT / "zig-out/bin/mylang-core")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--shuffle-seed", type=int, default=20261006)
    parser.add_argument("--smoke-test", action="store_true")
    args = parser.parse_args(argv)
    if args.smoke_test:
        smoke()
        return 0
    report = {"valid": False, "cpu": 10, "rounds": args.rounds, "rows": {}, "error": None}
    output = None
    try:
        if args.rounds < 1:
            raise InvalidMeasurement("--rounds must be positive")
        selected = row_names(args.rows)
        args.bin = inside(args.bin)
        output = inside(args.json if args.json else args.bin / "measurements.json")
        args.bin.mkdir(parents=True, exist_ok=True)
        if args.build or args.build_only:
            build(args, selected)
        if args.build_only:
            report.update(valid=True, built_rows=selected, build_only=True)
            return 0
        rng = random.Random(args.shuffle_seed)
        for row in selected:
            report["rows"][row] = measure_row(args, row, rng)
        misses = [f"{row}/{size}" for row, result in report["rows"].items()
                  for size, value in result["sizes"].items() if not value["within_both_limits"]]
        old_misses = [f"{row}/{size}" for row, result in report["rows"].items()
                      for size, value in result["sizes"].items() if not value["within_old_limit"]]
        zig_misses = [f"{row}/{size}" for row, result in report["rows"].items()
                      for size, value in result["sizes"].items() if not value["within_zig_limit"]]
        report.update(valid=True, speed_gate_misses=misses, old_gate_misses=old_misses,
                      zig_gate_misses=zig_misses, all_within_old_limit=not old_misses,
                      all_within_zig_limit=not zig_misses, all_within_both_limits=not misses)
        print(f"\nvalid rows: {len(selected)}; speed gate misses: {misses}")
        print("Both new/old and new/Zig must be at most 1.10. binary_search misses require the plan's identical-code/layout-noise review; all other misses require repair.")
        return 0
    except (InvalidMeasurement, OSError, ValueError) as error:
        report["error"] = str(error)
        print(f"measurement INVALID: {error}", file=sys.stderr)
        return 1
    finally:
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
