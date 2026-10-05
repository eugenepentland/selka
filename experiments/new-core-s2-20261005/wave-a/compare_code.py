#!/usr/bin/env python3
"""Build the S0/S1 programs and compare their emitted functions with Wave A's base.

Run through scripts/build-slot.sh build after installing the current core.
Baseline .ll files are captured before integration in .mylang-cache/wave-a/baseline.
The function comparison excludes added declarations; changed definitions are
reported and retained as diffs for inspection, rather than treated as a timing verdict.
"""
import argparse
import difflib
import hashlib
import importlib.util
from pathlib import Path
import re
import subprocess
import time


ROOT = Path(__file__).resolve().parents[3]
KERNELS = ("int_math", "float_math", "call_direct", "branch_predictable", "branch_mixed", "binary_search")


def definitions(text):
    return "\n".join(re.findall(r"^define .*?^\}", text, re.MULTILINE | re.DOTALL))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("rows", ROOT / "experiments/new-core-s1-20261005/measure_rows.py")
    rows = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rows)
    baseline = ROOT / ".mylang-cache/wave-a/baseline"
    output = ROOT / ".mylang-cache/wave-a" / args.stage
    output.mkdir(parents=True, exist_ok=True)
    for name in [*(f"row_{row}" for row in rows.UNITS), *KERNELS]:
        llvm = output / f"{name}.ll"
        started = time.monotonic()
        subprocess.run([
            str(ROOT / "zig-out/bin/mylang-core"), "build", str(ROOT / f"test/core/{name}.my"),
            "-o", str(output / name), "--release", "--emit-llvm", str(llvm),
            "--cache-dir", str(output / "core-cache"),
            "--link", str(ROOT / "benchmarks/runtime/ports/native_clock.c"),
        ], check=True)
        before = definitions((baseline / f"{name}.ll").read_text())
        after = definitions(llvm.read_text())
        same = before == after
        if not same:
            (output / f"{name}.diff").write_text("".join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True), fromfile="baseline", tofile=args.stage,
            )))
        digest = hashlib.sha256(after.encode()).hexdigest()
        print(name, "identical definitions" if same else "changed definitions; inspect diff", digest,
              f"{time.monotonic() - started:.3f}s", flush=True)


if __name__ == "__main__":
    main()
