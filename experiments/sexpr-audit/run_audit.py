#!/usr/bin/env python3
"""Phase-decomposition audit of the mylang/Zig execution gap.

Runs a purpose-built driver per phase on both sides over the same input:

  read      read the file only
  tokens    read + tokenize
  parse     read + tokenize + parse (no tree walk)
  census    parse + walk the tree (mylang main.my, zig-bench default)
  render    parse + render (mylang main.my --render, zig-bench --render)

plus micro-drivers that isolate the per-operation cost of generated code
(empty loop, byte index, byte scan, call, decode, append).

Each phase's own cost is the difference between consecutive cumulative timings,
so the table attributes the total run to read / tokenize / parse / walk / render.

Usage:
  python3 experiments/sexpr-audit/run_audit.py [--runs N] [--input FILE]

Writes experiments/sexpr-audit/evidence/audit.json.
"""

from __future__ import annotations

import argparse
import json
import shutil
import statistics
import subprocess
import time
from pathlib import Path

AUDIT = Path(__file__).resolve().parent
REPO = AUDIT.parents[1]
PORT = REPO / "experiments/sexpr-port"
EVIDENCE = AUDIT / "evidence"
WORK = Path("/tmp/sexpr-audit")
MYLANG = REPO / "zig-out/bin/mylang"
ZIG_BENCH = Path("/tmp/zb-out/bin/zig-bench")
TASKSET = shutil.which("taskset") or "taskset"

# driver name -> source file (all in this directory, except main.my)
DRIVERS = {name: AUDIT / f"{name}.my" for name in
           ("a_read", "b_tokens", "c_parse", "d_decode", "e_scan", "f_calls",
            "g_append", "h_loop", "i_index", "j_one", "k_three", "l_calls2")}
DRIVERS["census"] = PORT / "main.my"

PHASES = [("read", "a_read", []), ("tokens", "b_tokens", []), ("parse", "c_parse", []),
          ("census", "census", []), ("render", "census", ["--render"])]
MICRO = [("loop (empty)", "h_loop", []), ("index (read+add)", "i_index", []),
         ("scan (2 compares)", "e_scan", []), ("1M calls", "f_calls", []),
         ("19k decode", "d_decode", []), ("19k decode+append", "g_append", [])]
ZIG_MICRO = {"loop (empty)": "--loop", "index (read+add)": None,
             "scan (2 compares)": "--scan", "1M calls": None,
             "19k decode": None, "19k decode+append": None}


def build_mylang_drivers() -> dict:
    WORK.mkdir(parents=True, exist_ok=True)
    cache = WORK / "cache"
    out = {}
    for name, source in DRIVERS.items():
        target = WORK / name
        proc = subprocess.run(
            [str(MYLANG), "build", str(source.relative_to(REPO)), "-o", str(target),
             "--mode", "ReleaseFast", f"--cache-dir={cache}"],
            cwd=REPO, capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(f"building {name} failed:\n{proc.stdout}\n{proc.stderr}")
        out[name] = target
    return out


def measure(binary: Path, args: list[str], runs: int) -> dict:
    samples = []
    for _ in range(runs):
        start = time.perf_counter()
        proc = subprocess.run([TASKSET, "-c", "6", str(binary), *args], capture_output=True, text=True)
        samples.append(time.perf_counter() - start)
        if proc.returncode != 0:
            raise SystemExit(f"{binary} {args} failed: {proc.stderr}")
    return {"median_ms": statistics.median(samples) * 1000, "samples": samples, "output": proc.stdout.strip()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=25)
    ap.add_argument("--input", default="/tmp/sexpr-bench/input.sexp")
    args = ap.parse_args()
    if not ZIG_BENCH.exists():
        raise SystemExit(f"missing {ZIG_BENCH}; build experiments/sexpr-port/zig-bench first")

    mine = build_mylang_drivers()
    inp = args.input

    phases = {"mylang": {}, "zig": {}}
    for label, driver, extra in PHASES:
        phases["mylang"][label] = measure(mine[driver], [inp, *extra], args.runs)
    zig_phase_modes = {"read": "--read", "tokens": "--tokens", "parse": "--parse",
                       "census": None, "render": "--render"}
    for label, mode in zig_phase_modes.items():
        phases["zig"][label] = measure(ZIG_BENCH, [inp] + ([mode] if mode else []), args.runs)

    micro = {"mylang": {}, "zig": {}}
    for label, driver, extra in MICRO:
        micro["mylang"][label] = measure(mine[driver], [inp, *extra], args.runs)
        mode = ZIG_MICRO[label]
        if mode is not None:
            micro["zig"][label] = measure(ZIG_BENCH, [inp, mode], args.runs)

    attribution = {}
    for impl in ("mylang", "zig"):
        p = phases[impl]
        attribution[impl] = {
            "read": p["read"]["median_ms"],
            "tokenize": p["tokens"]["median_ms"] - p["read"]["median_ms"],
            "parse": p["parse"]["median_ms"] - p["tokens"]["median_ms"],
            "walk": p["census"]["median_ms"] - p["parse"]["median_ms"],
            "render_extra": p["render"]["median_ms"] - p["parse"]["median_ms"],
            "census_total": p["census"]["median_ms"],
            "render_total": p["render"]["median_ms"],
        }

    result = {"input": inp, "runs": args.runs,
              "check": {impl: {k: v["output"] for k, v in phases[impl].items()} for impl in phases},
              "phases": phases, "micro": micro, "attribution": attribution}
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "audit.json").write_text(json.dumps(result, indent=2) + "\n")

    print(f"input {inp}   runs {args.runs} (median, taskset -c 6)\n")
    print(f"{'phase':<14}{'mylang ms':>11}{'zig ms':>10}{'ratio':>9}")
    print("-" * 46)
    for phase in ("read", "tokenize", "parse", "walk", "render_extra"):
        my = attribution["mylang"][phase]
        z = attribution["zig"][phase]
        ratio = my / z if z > 1e-9 else float("inf")
        print(f"{phase:<14}{my:>11.3f}{z:>10.3f}{ratio:>8.1f}x")
    for total in ("census_total", "render_total"):
        my = attribution["mylang"][total]
        z = attribution["zig"][total]
        print(f"{total:<14}{my:>11.3f}{z:>10.3f}{my / z:>8.1f}x")

    print(f"\n{'micro workload':<20}{'mylang ms':>11}{'zig ms':>10}{'ratio':>9}")
    print("-" * 52)
    for label, _, _ in MICRO:
        my = micro["mylang"][label]["median_ms"]
        if label in micro["zig"]:
            z = micro["zig"][label]["median_ms"]
            print(f"{label:<20}{my:>11.3f}{z:>10.3f}{my / z:>8.1f}x")
        else:
            print(f"{label:<20}{my:>11.3f}{'n/a':>10}{'n/a':>9}")
    print(f"\nwrote {EVIDENCE / 'audit.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
