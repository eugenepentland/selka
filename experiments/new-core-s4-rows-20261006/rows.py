#!/usr/bin/env python3
"""S4 benchmark rows: build, verify, calibrate and measure the six new rows.

Each case lives in CASE/ beside this file:
  test/core/row_CASE.my (in the repository) takes `SIZE ITERATIONS SEED`
  main.rs    Rust reference:  args `CASE SIZE ITERATIONS SEED`
  main.zig   Zig reference (ReleaseSafe), same arguments
  main.go    Go reference, same arguments
  oracle.py  `checksum(size, iterations, seed) -> int`, the independent Python spec
  case.json  {"unit": "element", "iterations": {"4096": N, "64": M}}
Every program prints exactly `CHECKSUM ELAPSED_NS\\n` (CONTRACT.md has the rules).

Commands (run from anywhere):
  rows.py build CASE...       compile every arm into .mylang-cache/s4-rows/bin/CASE/
  rows.py verify CASE...      every built arm agrees with the oracle at the probes
  rows.py calibrate CASE...   Zig iterations reaching ~40 ms per size (CPU 12, not a measurement)
  rows.py measure CASE...     CPU-10 cycles per unit, old/new core, Rust, Zig ReleaseSafe
                              (coordinator only; holds the CPU-10 lock)
Builds go through scripts/build-slot.sh build. A new-core refusal is recorded in
CASE/new-core-refusal.txt and is not an error for `build`; `verify` reports it.
"""
import argparse
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CACHE = ROOT / ".mylang-cache/s4-rows"
OLD = CACHE / "old/bin/mylang"
CORE = CACHE / "core/bin/mylang-core"
CLOCK = ROOT / "benchmarks/runtime/ports/native_clock.c"
SLOT = ROOT / "scripts/build-slot.sh"
CASES = ("tree_build_walk", "record_pass", "grid_dp", "union_find", "float_format", "buffer_write")
PROBES = ((2, 1, 1), (3, 42, 7), (17, 999983, 31), (64, 3, 7), (4096, 2, 7))
SIZES = (4096, 64)
SEED = 7
ARMS = ("old", "new", "rust", "zig-safe", "go")
LABELS = {"old": "old core --release", "new": "new core release", "rust": "Rust", "zig-safe": "Zig ReleaseSafe"}
CPU10_LOCK = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "mylang-slots/cpu10.lock"


def oracle(case):
    spec = importlib.util.spec_from_file_location(f"oracle_{case}", HERE / case / "oracle.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def binary(case, arm):
    return CACHE / "bin" / case / arm


def argv(case, arm, size, iterations, seed):
    head = [str(binary(case, arm))]
    if arm not in ("old", "new"):
        head.append(case)
    return head + [str(size), str(iterations), str(seed)]


def build(case):
    out = CACHE / "bin" / case
    out.mkdir(parents=True, exist_ok=True)
    source = HERE / case
    refusal = source / "new-core-refusal.txt"
    refusal.unlink(missing_ok=True)
    go_env = {**os.environ, "GOMAXPROCS": "1", "GOTOOLCHAIN": "local", "GOFLAGS": "", "GOAMD64": "v1"}
    commands = {
        "old": [str(OLD), "build", str(ROOT / "test/core" / f"row_{case}.my"), "-o", str(out / "old"), "--release",
                "--cache-dir", str(CACHE / "cache/old"), "--link", str(CLOCK)],
        "new": [str(CORE), "build", str(ROOT / "test/core" / f"row_{case}.my"), "-o", str(out / "new"), "--release",
                "--cache-dir", str(CACHE / "cache/new"), "--link", str(CLOCK), "--emit-llvm", str(out / "new.ll")],
        "rust": ["rustc", "-O", "--edition", "2021", str(source / "main.rs"), "-o", str(out / "rust")],
        "zig-safe": ["zig", "build-exe", str(source / "main.zig"), "-lc", "-O", "ReleaseSafe",
                     f"-femit-bin={out / 'zig-safe'}", "--cache-dir", str(CACHE / "cache/zig")],
        "go": ["go", "build", "-o", str(out / "go"), str(source / "main.go")],
    }
    ok = True
    for arm, command in commands.items():
        binary(case, arm).unlink(missing_ok=True)
        env = go_env if arm == "go" else {**os.environ, "PATH": os.environ["PATH"] + os.pathsep + str(Path.home() / ".cargo/bin")}
        done = subprocess.run([str(SLOT), "build", "--", *command], capture_output=True, text=True, env=env, cwd=out)
        status = "ok" if done.returncode == 0 and binary(case, arm).is_file() else f"FAILED ({done.returncode})"
        print(f"build {case} {arm}: {status}", flush=True)
        if status != "ok":
            text = (done.stdout + done.stderr).strip()
            if arm == "new" and "E_CORE_UNSUPPORTED" in text:
                refusal.write_text(text + "\n")
                print(f"  new core refused; recorded in {refusal.relative_to(ROOT)}")
            else:
                ok = False
                print("  " + text.replace("\n", "\n  ")[-4000:])
    return ok


def run(command):
    done = subprocess.run(command, capture_output=True, text=True, timeout=600)
    fields = done.stdout.split()
    valid = (done.returncode == 0 and not done.stderr and done.stdout.endswith("\n") and
             done.stdout.count("\n") == 1 and len(fields) == 2 and all(f.lstrip("-").isdigit() for f in fields) and
             int(fields[0]) >= 0 and int(fields[1]) > 0)
    return valid, done, (int(fields[0]) if valid else None), (int(fields[1]) if valid else None)


def verify(case):
    spec = oracle(case)
    ok = True
    for size, iterations, seed in PROBES:
        expected = spec.checksum(size, iterations, seed)
        for arm in ARMS:
            if not binary(case, arm).is_file():
                if arm == "new" and (HERE / case / "new-core-refusal.txt").is_file():
                    continue
                print(f"verify {case} {arm}: not built")
                ok = False
                continue
            valid, done, checksum, _ = run(argv(case, arm, size, iterations, seed))
            if not valid or checksum != expected:
                ok = False
                print(f"verify {case} {arm} size={size} iterations={iterations} seed={seed}: expected {expected}, "
                      f"status={done.returncode} stdout={done.stdout!r} stderr={done.stderr[-2000:]!r}")
    refused = (HERE / case / "new-core-refusal.txt").is_file()
    print(f"verify {case}: {'PASS' if ok else 'FAIL'}{' (new core refused; see new-core-refusal.txt)' if refused else ''}")
    return ok


def calibrate(case):
    result = {}
    for size in SIZES:
        iterations = 1
        while True:
            valid, done, _, elapsed = run(["taskset", "-c", "12", *argv(case, "zig-safe", size, iterations, SEED)])
            if not valid:
                raise SystemExit(f"calibrate {case}: invalid run {done.stdout!r} {done.stderr!r}")
            if elapsed >= 40_000_000 or iterations >= 50_000_000:
                break
            iterations = max(iterations * 2, int(iterations * 40_000_000 / max(elapsed, 1) * 1.1))
        result[str(size)] = iterations
        print(f"calibrate {case} size={size}: {iterations} iterations, Zig {elapsed / 1e6:.1f} ms (CPU 12)")
    print(f"suggested case.json iterations: {json.dumps(result)}")
    return True


def sample(command):
    perf = ["taskset", "-c", "10", "perf", "stat", "-x,", "-e", "cpu_core/cycles/u", *command]
    done = subprocess.run(perf, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"}, timeout=600)
    fields = done.stdout.split()
    if done.returncode != 0 or len(fields) != 2:
        raise SystemExit(f"sample failed: {perf}\n{done.stdout!r}\n{done.stderr!r}")
    counted = [line.split(",")[0] for line in done.stderr.splitlines() if "cycles" in line]
    if len(counted) != 1 or not counted[0].isdigit():
        raise SystemExit(f"perf counter missing: {done.stderr!r}")
    return int(fields[0]), int(counted[0])


def measure(cases, rounds, output):
    CPU10_LOCK.parent.mkdir(parents=True, exist_ok=True)
    report = {"cpu": 10, "rounds": rounds, "seed": SEED, "rows": {}}
    with open(CPU10_LOCK, "a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        rng = random.Random(20261006)
        for case in cases:
            meta = json.loads((HERE / case / "case.json").read_text())
            arms = [arm for arm in LABELS if binary(case, arm).is_file()]
            row = {"unit": meta["unit"], "sizes": {}}
            for size in SIZES:
                iterations = meta["iterations"][str(size)]
                expected = oracle(case).checksum(size, iterations, SEED)
                startup = {arm: statistics.median(sample(argv(case, arm, size, 1, SEED))[1] for _ in range(3)) for arm in arms}
                cycles = {arm: [] for arm in arms}
                for _ in range(rounds):
                    for arm in rng.sample(arms, len(arms)):
                        checksum, count = sample(argv(case, arm, size, iterations, SEED))
                        if checksum != expected:
                            raise SystemExit(f"{case}/{size}/{arm}: checksum {checksum} != oracle {expected}")
                        cycles[arm].append(count)
                per = size * iterations if meta["unit"] in ("element", "cell") else iterations
                values = {arm: (statistics.median(cycles[arm]) - startup[arm]) / per for arm in arms}
                if any(not math.isfinite(v) or v <= 0 for v in values.values()):
                    raise SystemExit(f"{case}/{size}: nonpositive normalized value {values}")
                ratios = {}
                if "new" in values:
                    ratios = {"new_over_zig": values["new"] / values["zig-safe"], "new_over_rust": values["new"] / values["rust"],
                              "new_over_old": values["new"] / values["old"]}
                row["sizes"][str(size)] = {"iterations": iterations, "checksum": expected,
                                           "cycles_per_unit": values, "ratios": ratios}
            report["rows"][case] = row
            print(f"\n### {case} (cycles per {meta['unit']}, median of {rounds} interleaved rounds, CPU 10)")
            print("| configuration | 4096 | 64 |\n|---|---:|---:|")
            for arm in arms:
                print(f"| {LABELS[arm]} | {row['sizes']['4096']['cycles_per_unit'][arm]:.3f} | {row['sizes']['64']['cycles_per_unit'][arm]:.3f} |")
            for key in ("new_over_zig", "new_over_rust", "new_over_old"):
                if key in row["sizes"]["4096"]["ratios"]:
                    print(f"| {key.replace('_', ' ')} | {row['sizes']['4096']['ratios'][key]:.3f} | {row['sizes']['64']['ratios'][key]:.3f} |")
    if output:
        Path(output).write_text(json.dumps(report, indent=1) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("build", "verify", "calibrate", "measure"))
    parser.add_argument("cases", nargs="+", choices=CASES)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--json")
    args = parser.parse_args()
    if args.command == "measure":
        measure(args.cases, args.rounds, args.json)
        return 0
    action = {"build": build, "verify": verify, "calibrate": calibrate}[args.command]
    return 0 if all([action(case) for case in args.cases]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
