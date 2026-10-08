#!/usr/bin/env python3
"""Record Wave A's required checks after each package merge.

Every compiling command acquires a build slot. The row runner pins its timing
children to CPU 10; the slot wrapper keeps all other work off reserved CPUs.
"""
import argparse
import importlib.util
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[3]
WAVE_A_PIN_FILES = ("mut_rebinding", "mut_rebind_caller", "mut_rebind_modules", "live_place_iteration")


def pin_sections(report):
    """Read generated sections while rejecting duplicate files or malformed pins."""
    sections = {}
    for section in re.split(r"^file ", report, flags=re.MULTILINE)[1:]:
        name, _, body = section.partition("\n")
        if name in sections or not name:
            raise ValueError("duplicate or empty pinned file")
        if any(line and not line.startswith(("pass ", "known-fail ")) for line in body.splitlines()):
            raise ValueError(f"{name}: malformed pin contract")
        sections[name] = "file " + section
    return sections


def append_wave_a_pins(candidate, target):
    """Preserve existing contracts byte-for-byte and append qualified Wave A files."""
    original = target.read_text()
    previous = pin_sections(original)
    additions = pin_sections(candidate.read_text())
    if set(additions) != set(WAVE_A_PIN_FILES):
        raise ValueError("pin candidate must contain exactly the four Wave A files")
    if any("known-fail " in section for section in additions.values()):
        raise ValueError("Wave A pins may not excuse a new-core failure")
    for name in set(previous) & set(additions):
        old_passes = {line for line in previous[name].splitlines() if line.startswith("pass ")}
        new_passes = {line for line in additions[name].splitlines() if line.startswith("pass ")}
        if not old_passes <= new_passes:
            raise ValueError(f"{name}: previously pinned passing contract lost")
    appended = [additions[name] for name in WAVE_A_PIN_FILES if name not in previous]
    if appended:
        target.write_text(original + ("" if original.endswith("\n") else "\n") + "".join(appended))
    print(f"pins: preserved {len(previous)} files; appended {len(appended)} Wave A files", flush=True)


def rows_module():
    spec = importlib.util.spec_from_file_location("rows", ROOT / "experiments/new-core-s1-20261005/measure_rows.py")
    rows = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rows)
    return rows


def measure_rows(stage):
    """Retain the S1 method while requiring deterministic checksums on CPU 10."""
    rows = rows_module()
    original_run = rows.run
    checksums = {}

    def run(cpu, argv):
        if cpu != 10:
            raise SystemExit("Wave A timing requires CPU 10")
        checksum, cycles = original_run(cpu, argv)
        key = tuple(argv)
        if key in checksums and checksums[key] != checksum:
            raise SystemExit(f"unstable row checksum: {argv!r}")
        checksums[key] = checksum
        return checksum, cycles

    rows.run = run
    sys.argv = [__file__, "--build", "--bin", str(ROOT / ".mylang-cache/wave-a" / stage / "rows"),
                "--rounds", "7", "--cpu", "10"]
    return rows.main()


def validate_rows(report):
    """Require all 14 rows at both sizes, equal checksums and the 1.10 Zig bound."""
    expected = set(rows_module().UNITS)
    sections = re.findall(r"^### (\w+) .*?\n(.*?)(?=^### |\Z)", report, re.MULTILINE | re.DOTALL)
    if len(sections) != len(expected) or {name for name, _ in sections} != expected:
        raise ValueError("row qualification must contain all 14 rows exactly once")
    labels = {"old core --release", "new core release", "Rust", "Zig ReleaseSafe"}
    for name, section in sections:
        if "| configuration | 4096 | 64 | checksum |" not in section or "refused" in section:
            raise ValueError(f"{name}: missing sizes or refused compilation")
        table = {}
        for label, big, small, checksum in re.findall(r"^\| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$", section, re.MULTILINE):
            if label == "configuration":
                continue
            if label in table or checksum != "same":
                raise ValueError(f"{name}: duplicate configuration or checksum mismatch")
            values = (float(big), float(small))
            if any(not math.isfinite(value) or value <= 0 for value in values):
                raise ValueError(f"{name}: invalid cycle measurement")
            table[label] = values
        if set(table) != labels:
            raise ValueError(f"{name}: requires old core, new core, Rust and Zig")
        for size, core, zig in zip((4096, 64), table["new core release"], table["Zig ReleaseSafe"]):
            if core > 1.10 * zig:
                raise ValueError(f"{name}, size {size}: new core/Zig={core / zig:.4f} exceeds 1.10")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--pin", action="store_true", help="append qualified Wave A files to the existing conformance pins")
    parser.add_argument("--nonregression-evidence", action="append", default=[], type=Path,
                        help="reviewable evidence for changed definitions (repeatable)")
    parser.add_argument("--measure-rows", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.measure_rows:
        raise SystemExit(measure_rows(args.stage))
    for path in args.nonregression_evidence:
        if not path.is_file() or not path.stat().st_size:
            raise SystemExit(f"nonregression evidence must be a nonempty file: {path}")
    evidence = ROOT / "experiments/new-core-s2-20261005/wave-a/integration"
    cache = ROOT / ".mylang-cache/wave-a" / args.stage
    evidence.mkdir(parents=True, exist_ok=True)
    (cache / "tmp").mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(TMPDIR=str(cache / "tmp"),
               ZIG_LOCAL_CACHE_DIR=str(ROOT / ".zig-cache"),
               ZIG_GLOBAL_CACHE_DIR="/home/epentland/ai/canopy/.zig-global-cache")
    commands = [
        ("build", ["zig", "build", "core", "--summary", "all"]),
        ("old-build", ["zig", "build", "--summary", "all"]),
        ("test-core", ["zig", "build", "test-core", "--summary", "all"]),
        ("code", ["python3", "experiments/new-core-s2-20261005/wave-a/compare_code.py", "--stage", args.stage]),
        ("conformance", ["python3", "experiments/new-core-s1-20261005/conformance.py", "--set", "all", "--jobs", "4", "--why"]),
        ("combined-conformance", ["python3", "experiments/new-core-s1-20261005/conformance.py",
                                  "experiments/new-core-s2-20261005/wave-a/s2-lb/mut_callee_rebinding.my",
                                  "--jobs", "1", "--why", "--leakcheck", "--verify"]),
        ("rows", ["python3", str(Path(__file__).resolve()), "--stage", args.stage, "--measure-rows"]),
    ]
    pin_candidate = cache / "wave-a.pins"
    if args.pin:
        commands.append(("pins", ["python3", "experiments/new-core-s1-20261005/conformance.py",
                                 *WAVE_A_PIN_FILES, "--modes", "debug,release", "--jobs", "4", "--why",
                                 "--pin", str(pin_candidate)]))
    changed_definitions = False
    for label, command in commands:
        log = evidence / f"{args.stage}-{label}.txt"
        duration = cache / f"{label}-seconds.txt"
        duration.unlink(missing_ok=True)
        wrapped = ["scripts/build-slot.sh", "build", "--",
                   "/usr/bin/time", "-f", "%e", "-o", str(duration), *command]
        if label == "test-core":
            # The full old gate made even the unchanged baseline ~3x slower.
            # Hold the single gate slot as well when measuring this stop limit.
            # A waiting parent retains gate fd9 when the inner wrapper opens
            # its own fd9 for the build slot. Direct exec nesting drops gate.
            wrapped = ["scripts/build-slot.sh", "gate", "--", "bash", "-c",
                       '"$@"; result=$?; exit "$result"', "--", *wrapped]
        started = time.monotonic()
        with log.open("w") as output:
            output.write("$ " + shlex.join(wrapped) + "\n")
            if args.nonregression_evidence:
                output.write("nonregression evidence: " + ", ".join(str(path.resolve()) for path in args.nonregression_evidence) + "\n")
            output.flush()
            result = subprocess.run(wrapped, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
            elapsed = time.monotonic() - started
            measured = float(duration.read_text().splitlines()[-1]) if duration.exists() else elapsed
            output.write(f"\nexit={result.returncode} command={measured:.2f}s wall_including_admission={elapsed:.2f}s\n")
        print(f"{args.stage}: {label}: exit={result.returncode}, command={measured:.2f}s; {log}", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)
        if label == "build" and measured > 10:
            raise SystemExit("core rebuild exceeded the plan's ten-second stop threshold; isolate and inspect the compiler step")
        if label == "test-core" and measured > 300:
            raise SystemExit("test-core exceeded the plan's five-minute stop threshold; inspect admission wait and log")
        report = log.read_text()
        if label == "code":
            changed_definitions = "changed definitions" in report
        if label == "rows":
            try:
                validate_rows(report)
            except ValueError as error:
                raise SystemExit(f"row qualification failed: {error}; inspect {log}")
        if label == "pins":
            try:
                append_wave_a_pins(pin_candidate, ROOT / "test/core/conformance.pins")
            except ValueError as error:
                raise SystemExit(f"pin qualification failed: {error}; inspect {log}")
    if changed_definitions and not args.nonregression_evidence:
        raise SystemExit("changed definitions need nonregression evidence; inspect stage .diff files and supply --nonregression-evidence")


if __name__ == "__main__":
    main()
