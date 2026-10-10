#!/usr/bin/env python3
"""Compare guest runtime and invoice rebuilds in Debug, optimized Debug and Release."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import time


REPO = Path(__file__).resolve().parents[1]
MODES = {"debug": ["--unoptimized"], "optimized_debug": [], "release": ["--release"]}
SOURCES = [
    REPO / "bench/parity" / group / f"{name}.my"
    for group, name in [
        ("micro", "intloop"), ("micro", "calls"), ("micro", "bytes_scan"),
        ("micro", "list_append_sum"), ("micro", "dict_count"), ("suite", "matmul"),
    ]
]


def run(argv, environment):
    start = time.perf_counter()
    result = subprocess.run(argv, env=environment, capture_output=True, timeout=180)
    return result, time.perf_counter() - start


def build(args, environment, source, directory, mode):
    command = [str(args.compiler), "build", str(source), "-o", str(directory / "program"),
               "--cache-dir", str(directory / "cache"), "--zig", str(args.zig),
               "--report", *MODES[mode]]
    result, elapsed = run(command, environment)
    if result.returncode:
        raise RuntimeError(result.stderr.decode())
    reports = [json.loads(line) for line in result.stderr.decode().splitlines()
               if line.startswith('{"version":"cache-report-v1"')]
    if len(reports) != 1:
        raise RuntimeError(f"missing cache report: {result.stderr!r}")
    return {"seconds": elapsed, "cache": reports[0], "command": command}


def guest(args, directory):
    binary = [str(directory / "program")]
    return ["taskset", "-c", str(args.cpu), *binary] if args.cpu is not None else binary


def runtimes(args, environment):
    rows = {}
    rng = random.Random(517)
    checking = dict(environment, MYL_CORE_LEAKCHECK="1")
    for source in SOURCES:
        name = source.stem
        expected = source.with_suffix(".expected").read_bytes()
        builds, samples = {}, {mode: [] for mode in MODES}
        for mode in MODES:
            directory = args.output / "runtime" / name / mode
            directory.mkdir(parents=True)
            builds[mode] = build(args, environment, source, directory, mode)
            result, _ = run(guest(args, directory), checking)
            if result.returncode or result.stdout != expected or result.stderr:
                raise RuntimeError(f"{name}/{mode}: incorrect output or leak: {result!r}")
        # Run prebuilt binaries in interleaved order, after an untimed warmup.
        for _ in range(args.repeats):
            order = list(MODES)
            rng.shuffle(order)
            for mode in order:
                directory = args.output / "runtime" / name / mode
                result, elapsed = run(guest(args, directory), environment)
                if result.returncode or result.stdout != expected or result.stderr:
                    raise RuntimeError(f"{name}/{mode}: timed run changed its result")
                samples[mode].append(elapsed)
        release = statistics.median(samples["release"])
        rows[name] = {
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "expected_stdout": expected.decode(),
            "modes": {mode: {"samples_s": values, "median_s": statistics.median(values),
                             "ratio_to_release": statistics.median(values) / release,
                             "build": builds[mode]} for mode, values in samples.items()},
        }
        print(name, {mode: round(row["ratio_to_release"], 3)
                     for mode, row in rows[name]["modes"].items()}, flush=True)
    return rows


def rebuilds(args, environment):
    """A nine-module corpus: cold guest objects, identical replay, then a leaf body edit."""
    samples = {mode: {phase: [] for phase in ("cold", "replay", "edit")} for mode in MODES}
    outputs = {}
    rng = random.Random(518)
    # Runtime and guest objects normally share a per-user directory. Seed only
    # runtime objects, never units-v1, so later trials really compile guest code.
    warmup = args.output / "warmup"
    warmup.mkdir()
    seed = warmup / "native"
    (warmup / "main.my").write_text("func main(out: Stream) -> int:\n    out.print(0)\n    return 0\n")
    build(args, dict(environment, MYLANG_CORE_RUNTIME_CACHE=str(seed)), warmup / "main.my", warmup, "debug")
    runtime_objects = list(seed.glob("*.o"))
    if not runtime_objects:
        raise RuntimeError("runtime warmup published no objects")
    for trial in range(args.repeats):
        order = list(MODES)
        rng.shuffle(order)
        for mode in order:
            directory = args.output / "invoice" / str(trial) / mode
            source = directory / "src"
            shutil.copytree(REPO / "examples/corpus/invoice", source)
            native = directory / "native"
            native.mkdir()
            for runtime in runtime_objects:
                shutil.copy2(runtime, native / runtime.name)
            isolated = dict(environment, MYLANG_CORE_RUNTIME_CACHE=str(native))
            for phase in ("cold", "replay", "edit"):
                if phase == "edit":
                    leaf = source / "handling.my"
                    original = leaf.read_text()
                    assert original.count("mut cents = 100") == 1
                    leaf.write_text(original.replace("mut cents = 100", "mut cents = 101"))
                measured = build(args, isolated, source / "main.my", directory, mode)
                counts = measured["cache"]
                if phase == "cold" and (counts["reused"] or counts["compiled"] != counts["units"]):
                    raise RuntimeError("cold build reused guest objects")
                if phase == "edit" and counts["compiled"] == 0:
                    raise RuntimeError("leaf edit reused a previously compiled object")
                samples[mode][phase].append(measured)
                result, _ = run(guest(args, directory), environment)
                outcome = (result.returncode, result.stdout, result.stderr)
                if phase in outputs and outcome != outputs[phase]:
                    raise RuntimeError(f"invoice {mode}/{phase}: modes disagree")
                outputs[phase] = outcome
                if result.stderr:
                    raise RuntimeError(f"invoice {mode}/{phase}: unexpected diagnostic")
                if phase == "replay" and measured["cache"]["program"] != "replayed":
                    raise RuntimeError("identical build did not replay")
    if outputs["cold"] != outputs["replay"] or outputs["cold"] == outputs["edit"]:
        raise RuntimeError("invoice edit or replay did not produce the expected change")
    return {mode: {phase: {"median_s": statistics.median(row["seconds"] for row in rows),
                          "samples": rows} for phase, rows in phases.items()}
            for mode, phases in samples.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/mylang"))
    parser.add_argument("--zig", type=Path, default=Path(shutil.which("zig") or "zig"))
    parser.add_argument("--output", type=Path, required=True, help="new artifact directory")
    parser.add_argument("--host-mode", choices=["Debug", "ReleaseFast", "ReleaseSafe", "unknown"], default="unknown")
    parser.add_argument("--cpu", type=int, help="pin prebuilt guests to this CPU")
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("repeats must be positive")
    args.compiler = args.compiler.resolve(strict=True)
    args.zig = args.zig.resolve(strict=True)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("MYLANG_", "MYL_CORE_"))}
    environment["MYLANG_JOBS"] = "2"
    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "machine": platform.platform(), "cpu": args.cpu, "repeats": args.repeats,
        "host_mode_declared": args.host_mode,
        "compiler_sha256": hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
        "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "source_diff_sha256": hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"], cwd=REPO)).hexdigest(),
        "zig": subprocess.check_output([str(args.zig), "version"], text=True).strip(),
        "runtime_scope": "prebuilt guest process wall time, including startup, excluding compilation; output checked on every run; untimed leak check",
        "build_scope": "caller-supplied compiler; fresh local program and isolated guest-object caches per trial; prewarmed runtime objects and toolchain caches; invoice leaf edit 100 -> 101",
    }
    report["runtime"] = runtimes(args, environment)
    report["rebuild"] = rebuilds(args, environment)
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(args.output / "results.json")


if __name__ == "__main__":
    main()
