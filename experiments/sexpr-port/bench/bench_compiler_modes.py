#!/usr/bin/env python3
"""How much does the mylang compiler's own optimize mode matter?

`zig build` installs the mylang compiler in Debug by default, which is what the
main benchmark's first pass used. This script installs the compiler in Debug,
ReleaseFast and ReleaseSafe in turn and measures the same guest compile series
(cold / project-cold / warm / after-tweak) with each, so the compile-time
comparison is not silently charging mylang for a debug host compiler.

The compiler is always exercised in place at `zig-out/bin/mylang`: mylang finds
its bundled `qbe` relative to its own executable, so a copy under /tmp cannot
build anything (`ToolNotFound`).

Usage:
  python3 experiments/sexpr-port/bench/bench_compiler_modes.py [--reps N]

Writes experiments/sexpr-port/evidence/bench-compiler.json and leaves the
default Debug install in place.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bench  # noqa: E402

BIN = bench.REPO / "zig-out/bin/mylang"
COMPILERS = [("Debug", None), ("ReleaseFast", "ReleaseFast"), ("ReleaseSafe", "ReleaseSafe")]


def install_compiler(mode: str | None) -> float:
    """Install `zig-out/bin/mylang` at `mode`; return the wall time.

    The time is informational only: Zig's own build cache usually makes the
    second and later installs of a mode incremental, so it is not a cold-build
    figure.
    """
    cmd = [bench.ZIG, "build"] + ([f"-Doptimize={mode}"] if mode else [])
    seconds, proc = bench.run_timed(cmd, cwd=bench.REPO)
    if proc.returncode != 0:
        raise SystemExit(f"compiler install failed ({mode}):\n{proc.stdout}\n{proc.stderr}")
    return seconds


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()
    if args.quick:
        args.reps = 1

    bench.WORK.mkdir(parents=True, exist_ok=True)
    results: dict = {"guest_compile": {}, "install_seconds": {}, "reps": args.reps}

    for label, mode in COMPILERS:
        print(f"[compiler {label}] installing (in place) ...", flush=True)
        results["install_seconds"][label] = install_compiler(mode)
        print(f"[guest compile via mylang {label}] cold/cold_local/warm/tweak x{args.reps} ...", flush=True)
        series = bench.my_series("ReleaseFast", args.reps, mylang=BIN, tag=f"{label}-")
        results["guest_compile"][label] = bench.summarize(series)

    print("[compiler Debug] restoring default install ...", flush=True)
    results["install_seconds"]["Debug (restore)"] = install_compiler(None)

    out = bench.EVIDENCE / "bench-compiler.json"
    out.write_text(json.dumps(results, indent=2) + "\n")
    print(f"\nwrote {out}\n")

    header = f"{'compiler mode':<16}{'cold':>9}{'cold_local':>12}{'warm':>9}{'tweak':>9}"
    print(header)
    print("-" * len(header))
    for label, _ in COMPILERS:
        g = results["guest_compile"][label]
        print(f"{label:<16}{g['cold']['median']:>9.3f}{g['cold_local']['median']:>12.3f}"
              f"{g['warm']['median']:>9.3f}{g['tweak']['median']:>9.3f}")
    debug = results["guest_compile"]["Debug"]
    fast = results["guest_compile"]["ReleaseFast"]
    print(f"\nDebug -> ReleaseFast compiler: cold {debug['cold']['median']:.2f}s -> {fast['cold']['median']:.2f}s "
          f"({debug['cold']['median'] / fast['cold']['median']:.2f}x), "
          f"warm {debug['warm']['median']:.3f}s -> {fast['warm']['median']:.3f}s "
          f"({debug['warm']['median'] / fast['warm']['median']:.2f}x)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
