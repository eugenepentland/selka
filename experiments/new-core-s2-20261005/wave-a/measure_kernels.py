#!/usr/bin/env python3
"""Measure Wave A's S0 kernels with the frozen base interleaved on CPU 10.

Run after compare_code.py has built the named stage. The baseline directory
holds the old-core and new-core executables captured before any package merge.
Rust and Zig use the frozen runtime-baseline-20261003 runners.
"""
import argparse
import importlib.util
import io
from pathlib import Path
import sys
from contextlib import redirect_stdout


ROOT = Path(__file__).resolve().parents[3]
RUNNER = "/home/epentland/ai/canopy/mylang-worktrees/runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--rounds", type=int, default=7)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("kernels", ROOT / "experiments/new-core-s0-20261005/measure_kernels.py")
    kernels = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(kernels)
    original_run = kernels.run
    checksums = {}

    def run(cpu, argv):
        if cpu != 10:
            raise SystemExit("Wave A timing requires CPU 10")
        checksum, cycles = original_run(cpu, argv)
        key = tuple(argv)
        if key in checksums and checksums[key] != checksum:
            raise SystemExit(f"unstable kernel checksum: {argv!r}")
        checksums[key] = checksum
        return checksum, cycles

    kernels.run = run
    baseline = ROOT / ".mylang-cache/wave-a/baseline"
    stage = ROOT / ".mylang-cache/wave-a" / args.stage

    def configurations(options, kernel):
        name = kernels.FILES.get(kernel, kernel)
        def program(executable):
            return lambda size, iterations: [str(executable), str(size), str(iterations), str(kernels.SEED)]
        return [
            ("old core base --release", program(baseline / f"{name}_old")),
            ("new core base release", program(baseline / name)),
            ("new core Wave A release", program(stage / name)),
            ("Rust", lambda size, iterations: [f"{RUNNER}/compute-rust", kernel, str(size), str(iterations), str(kernels.SEED)]),
            ("Zig ReleaseSafe", lambda size, iterations: [f"{RUNNER}/compute-zig-safe", kernel, str(size), str(iterations), str(kernels.SEED)]),
        ]

    kernels.configurations = configurations
    sys.argv = [__file__, "--bin", str(stage), "--runner", RUNNER,
                "--rounds", str(args.rounds), "--cpu", "10"]
    output = io.StringIO()
    with redirect_stdout(output):
        kernels.main()
    report = output.getvalue()
    print(report, end="")
    if "DIFFERENT" in report:
        raise SystemExit("kernel checksum mismatch")


if __name__ == "__main__":
    main()
