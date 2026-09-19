#!/usr/bin/env python3
"""Benchmark the mylang sexpr port against the Zig implementation.

Measures, for each implementation and optimize mode:

  * compile time with every cache empty ("cold")
  * compile time with the project cache empty but the shared toolchain cache
    warm ("cold_local" — the number a developer sees on a clean checkout)
  * compile time with nothing changed ("warm" — a cache hit)
  * compile time after a one-constant tweak ("tweak" — incremental rebuild)
  * execution time of the produced binary on the same ~1 MiB input, in both
    workloads the two drivers share (node census and canonical rendering)

The Zig side is a minimal standalone project (`zig-bench/`) that vendors only
the sexpr closure, so its build time is comparable to building the mylang port
instead of the whole EDA application. Both sides use their own cache directory
and the installed Zig (`zig` on PATH, 0.17.0-dev.1683+5ceec001b); the Zig
project additionally gets its own `ZIG_GLOBAL_CACHE_DIR` so "cold" really is
cold and the user's shared cache is untouched.

Usage:
  python3 experiments/sexpr-port/bench/bench.py [--reps N] [--runs N] [--quick]

Writes experiments/sexpr-port/evidence/bench.json and prints a table.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
REPO = PORT.parents[1]
ZIG_BENCH = PORT / "zig-bench"
EVIDENCE = PORT / "evidence"
WORK = Path("/tmp/sexpr-bench")
EDA = Path("/home/epentland/ai/canopy/eda")
FIXTURE = EDA / "projects/designs/lib/modules/poe-pd-flyback-tps23757.sexp"

MYLANG = REPO / "zig-out/bin/mylang"
ZIG = shutil.which("zig") or "zig"
TASKSET = shutil.which("taskset")

# Zig exposes ReleaseFast and ReleaseSafe; mylang's guest build accepts only
# Debug and ReleaseFast (`--mode ReleaseSafe` is rejected), so its second point
# is Debug and is labelled as such.
ZIG_MODES = ["ReleaseFast", "ReleaseSafe"]
MY_MODES = ["ReleaseFast", "Debug"]

TWEAK_OLD = "short_list_max_width: int = 72"
TWEAK_NEW = "short_list_max_width: int = 73"
ZIG_TWEAK_OLD = "const short_list_max_width: usize = 72;"
ZIG_TWEAK_NEW = "const short_list_max_width: usize = 73;"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_timed(cmd: list[str], cwd: Path | None = None, cpu: int | None = None,
              env: dict | None = None) -> tuple[float, subprocess.CompletedProcess]:
    argv = ([TASKSET, "-c", str(cpu)] if (cpu is not None and TASKSET) else []) + cmd
    start = time.perf_counter()
    proc = subprocess.run(argv, cwd=str(cwd) if cwd else None, capture_output=True, text=True, env=env)
    return time.perf_counter() - start, proc


def ensure_input(target_bytes: int = 1 << 20) -> Path:
    """A deterministic ~1 MiB input: the real 185 kB EDA module repeated.

    Repeating whole files keeps every form well-formed (top-level forms are
    independent), and the result is a parse workload both readers accept.
    """
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / "input.sexp"
    source = FIXTURE.read_bytes()
    reps = max(1, target_bytes // len(source))
    if not out.exists() or out.stat().st_size < target_bytes:
        with out.open("wb") as handle:
            for _ in range(reps):
                handle.write(source)
                handle.write(b"\n")
    return out


def toolchain_facts() -> dict:
    facts = {
        "zig": ZIG,
        "zig_version": subprocess.run([ZIG, "version"], capture_output=True, text=True).stdout.strip(),
        "mylang": str(MYLANG),
        "cpus": os.cpu_count(),
        "python": platform.python_version(),
    }
    for name, path in (("eda", EDA), ("mylang", REPO)):
        proc = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True)
        facts[f"{name}_revision"] = proc.stdout.strip() if proc.returncode == 0 else "unknown"
    return facts


# ── mylang ────────────────────────────────────────────────────────────

def my_build(mode: str, cache: Path, out: Path, mylang: Path = MYLANG) -> dict:
    cmd = [str(mylang), "build", "experiments/sexpr-port/main.my", "-o", str(out),
           "--mode", mode, f"--cache-dir={cache}", "--report"]
    seconds, proc = run_timed(cmd, cwd=REPO)
    if proc.returncode != 0:
        raise SystemExit(f"mylang build failed ({mode}):\n{proc.stdout}\n{proc.stderr}")
    report = json.loads(proc.stdout.strip().splitlines()[-1]) if proc.stdout.strip() else {}
    return {
        "seconds": seconds,
        "frontend_seconds": report.get("frontend_seconds"),
        "codegen_seconds": report.get("codegen_seconds"),
        "link_seconds": report.get("link_seconds"),
        "compiled_functions": report.get("compiled_functions"),
        "reused_functions": report.get("reused_functions"),
    }


def my_series(mode: str, reps: int, mylang: Path = MYLANG, tag: str = "") -> dict:
    cache = WORK / f"my-cache-{tag}{mode}"
    out = WORK / f"my-{tag}{mode}"
    printer = PORT / "sexpr/printer.my"
    original = printer.read_text()
    assert TWEAK_OLD in original, "mylang tweak anchor missing"
    cold, cold_local, warm, tweak = [], [], [], []
    for _ in range(reps):
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)
        cold.append(my_build(mode, cache, out / "bin", mylang))
        warm.append(my_build(mode, cache, out / "bin", mylang))
        printer.write_text(original.replace(TWEAK_OLD, TWEAK_NEW, 1))
        try:
            tweak.append(my_build(mode, cache, out / "bin", mylang))
        finally:
            printer.write_text(original)
        # Project-cold with the toolchain already warm. mylang has no shared
        # toolchain cache for guest builds, so this repeats the cold path.
        shutil.rmtree(cache, ignore_errors=True)
        cold_local.append(my_build(mode, cache, out / "bin", mylang))
    assert printer.read_text() == original, "mylang tweak did not revert"
    final = my_build(mode, cache, out / "bin", mylang)
    return {
        "cold": cold, "cold_local": cold_local, "warm": warm, "tweak": tweak, "final": final,
        "binary": str(out / "bin"),
        "source_lines": sum(len(p.read_text().splitlines()) for p in sorted((PORT / "sexpr").glob("*.my"))),
    }


# ── zig ───────────────────────────────────────────────────────────────

def zig_build(mode: str, cache: Path, global_cache: Path, out: Path) -> dict:
    # Zig 0.17's `zig build` takes no `--cache-dir`; the cache roots are the
    # documented `ZIG_LOCAL_CACHE_DIR` / `ZIG_GLOBAL_CACHE_DIR` environment
    # variables.
    env = dict(os.environ, ZIG_LOCAL_CACHE_DIR=str(cache), ZIG_GLOBAL_CACHE_DIR=str(global_cache))
    cmd = [ZIG, "build", f"-Doptimize={mode}", "-p", str(out)]
    seconds, proc = run_timed(cmd, cwd=ZIG_BENCH, env=env)
    if proc.returncode != 0:
        raise SystemExit(f"zig build failed ({mode}):\n{proc.stdout}\n{proc.stderr}")
    return {"seconds": seconds}


def zig_series(mode: str, reps: int) -> dict:
    cache = WORK / f"zig-cache-{mode}"
    global_cache = WORK / f"zig-global-{mode}"
    out = WORK / f"zig-{mode}"
    printer = ZIG_BENCH / "src/sexpr/printer.zig"
    original = printer.read_text()
    assert ZIG_TWEAK_OLD in original, "zig tweak anchor missing"
    cold, cold_local, warm, tweak = [], [], [], []
    for _ in range(reps):
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(global_cache, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)
        cold.append(zig_build(mode, cache, global_cache, out))
        warm.append(zig_build(mode, cache, global_cache, out))
        printer.write_text(original.replace(ZIG_TWEAK_OLD, ZIG_TWEAK_NEW, 1))
        try:
            tweak.append(zig_build(mode, cache, global_cache, out))
        finally:
            printer.write_text(original)
        # Project-cold, toolchain warm: drop only the local cache, so std stays
        # in the global one. This is the clean-checkout build a developer sees.
        shutil.rmtree(cache, ignore_errors=True)
        cold_local.append(zig_build(mode, cache, global_cache, out))
    assert printer.read_text() == original, "zig tweak did not revert"
    final = zig_build(mode, cache, global_cache, out)
    return {
        "cold": cold, "cold_local": cold_local, "warm": warm, "tweak": tweak, "final": final,
        "binary": str(out / "bin/zig-bench"),
        "source_lines": sum(len(p.read_text().splitlines())
                            for p in sorted((ZIG_BENCH / "src").rglob("*.zig"))),
    }


# ── execution ─────────────────────────────────────────────────────────

def execute_series(binary: Path, workloads: list[tuple[str, list[str]]], input_path: Path, runs: int) -> dict:
    result = {}
    for label, args in workloads:
        samples = []
        for _ in range(runs):
            seconds, proc = run_timed([str(binary), str(input_path), *args], cpu=6)
            if proc.returncode != 0:
                raise SystemExit(f"run failed: {binary} {args}\n{proc.stderr}")
            samples.append(seconds)
        result[label] = {
            "samples": samples,
            "median": statistics.median(samples),
            "min": min(samples),
            "max": max(samples),
        }
    return result


def summarize(series: dict) -> dict:
    def median(key):
        return {"median": statistics.median([s["seconds"] for s in series[key]]), "samples": series[key]}
    return {
        "cold": median("cold"),
        "cold_local": median("cold_local"),
        "warm": median("warm"),
        "tweak": median("tweak"),
        "final": series["final"],
        "binary": series["binary"],
        "source_lines": series["source_lines"],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=3, help="compile repetitions per measurement (median)")
    ap.add_argument("--runs", type=int, default=25, help="execution repetitions per workload")
    ap.add_argument("--quick", action="store_true", help="1 rep, 5 runs")
    args = ap.parse_args()
    if args.quick:
        args.reps, args.runs = 1, 5

    WORK.mkdir(parents=True, exist_ok=True)
    input_path = ensure_input()
    facts = toolchain_facts()
    facts["input"] = {"path": str(input_path), "bytes": input_path.stat().st_size, "sha256": sha256(input_path)}
    facts["loadavg"] = os.getloadavg()

    results: dict = {"facts": facts, "zig": {}, "mylang": {}, "reps": args.reps, "runs": args.runs}
    workloads = [("stats", []), ("render", ["--render"])]

    for mode in ZIG_MODES:
        print(f"[zig {mode}] cold/cold_local/warm/tweak x{args.reps} ...", flush=True)
        series = zig_series(mode, args.reps)
        summary = summarize(series)
        summary["execute"] = execute_series(Path(series["binary"]), workloads, input_path, args.runs)
        results["zig"][mode] = summary

    for mode in MY_MODES:
        print(f"[mylang {mode}] cold/cold_local/warm/tweak x{args.reps} ...", flush=True)
        series = my_series(mode, args.reps)
        summary = summarize(series)
        summary["execute"] = execute_series(Path(series["binary"]), workloads, input_path, args.runs)
        results["mylang"][mode] = summary

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    out = EVIDENCE / "bench.json"
    out.write_text(json.dumps(results, indent=2) + "\n")

    print(f"\nwrote {out}")
    print(f"input: {facts['input']['bytes']} bytes  ({facts['input']['sha256'][:12]})")
    print(f"toolchain: zig {facts['zig_version']}  cpus={facts['cpus']}  loadavg={tuple(round(x, 2) for x in facts['loadavg'])}\n")
    header = (f"{'impl':<8}{'mode':<13}{'cold':>9}{'cold_local':>12}{'warm':>9}{'tweak':>9}"
              f"{'stats ms':>10}{'render ms':>11}{'lines':>7}")
    print(header)
    print("-" * len(header))
    for impl in ("zig", "mylang"):
        for mode, s in results[impl].items():
            print(f"{impl:<8}{mode:<13}{s['cold']['median']:>9.3f}{s['cold_local']['median']:>12.3f}"
                  f"{s['warm']['median']:>9.3f}{s['tweak']['median']:>9.3f}"
                  f"{s['execute']['stats']['median'] * 1000:>10.2f}"
                  f"{s['execute']['render']['median'] * 1000:>11.2f}{s['source_lines']:>7}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
