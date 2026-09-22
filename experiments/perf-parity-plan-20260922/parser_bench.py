#!/usr/bin/env python3
"""Interleaved S-expression parser timing (census and render) for several mylang compilers against zig-bench.

usage: parser_bench.py --arm NAME=MYLANG_PATH[:extra,flags] ... --json OUT [--rounds N] [--cpu C]

Adapted from `.tmp/roadmap-verify/parser_ab.py`: builds `experiments/sexpr-port/main.my`
with each named compiler (`--project`, default ReleaseFast = LLVM O3 + LTO, plus any
extra flags), builds the in-repo Zig reference `experiments/sexpr-port/zig-bench`
ReleaseFast, asserts every arm prints byte-identical output for census and render on
the 7.42 MB `input8.sexp`, then times fresh pinned processes with the arm order
shuffled inside each round. Ratios are paired per round against zig.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import statistics
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TREE = HERE.parents[1]
REPO = Path("/home/epentland/ai/canopy/mylang")
INPUT = REPO / ".tmp/input8.sexp"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", action="append", default=[])
    ap.add_argument("--bin", action="append", default=[], help="NAME=PATH of a prebuilt parser binary")
    ap.add_argument("--source", type=Path, default=TREE.parent / "work/sexpr-port-mut/main.my",
                    help="parser entry; the in-tree experiments/sexpr-port still spells the removed `mutates(...)`")
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--rounds", type=int, default=11)
    ap.add_argument("--cpu", type=int, default=6)
    ap.add_argument("--work", type=Path, default=TREE.parent / "work/parser")
    opts = ap.parse_args()
    opts.work.mkdir(parents=True, exist_ok=True)
    bins = {}
    for spec in opts.arm:
        name, rest = spec.split("=", 1)
        compiler, _, flags = rest.partition(":")
        out = opts.work / f"parser-{name}"
        cmd = [compiler, "build", str(opts.source), "--project", "-o", str(out),
               "--cache-dir", str(opts.work / f"cache-{name}"), *[f for f in flags.split(",") if f]]
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode != 0:
            raise SystemExit(f"{name}: build failed\n{p.stderr[-3000:]}")
        bins[name] = out
    for spec in opts.bin:
        name, path = spec.split("=", 1)
        bins[name] = Path(path)
    zig_dir = TREE / "experiments/sexpr-port/zig-bench"
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(opts.work / "zig-global"))
    p = subprocess.run(["zig", "build", "-Doptimize=ReleaseFast", "--cache-dir", str(opts.work / "zig-local")],
                       cwd=zig_dir, capture_output=True, text=True, env=env)
    if p.returncode != 0:
        raise SystemExit("zig-bench build failed:\n" + p.stderr[-3000:])
    zig_bin = sorted((zig_dir / "zig-out/bin").iterdir())[0]
    bins["zig"] = zig_bin
    modes = {"census": [], "render": ["--render"]}
    report = {"input": str(INPUT), "cpu": opts.cpu, "rounds": opts.rounds, "arms": {n: str(b) for n, b in bins.items()},
              "load_start": os.getloadavg(), "modes": {}}
    for mode, extra in modes.items():
        digests = {}
        for name, b in bins.items():
            out = subprocess.run(["taskset", "-c", str(opts.cpu), str(b), str(INPUT), *extra], capture_output=True)
            if out.returncode != 0:
                raise SystemExit(f"{name} {mode} exited {out.returncode}")
            digests[name] = hashlib.sha256(out.stdout).hexdigest()
        if len(set(digests.values())) != 1:
            raise SystemExit(f"{mode}: outputs differ: {digests}")
        samples = {n: [] for n in bins}
        rng = random.Random(20260922)
        order = list(bins)
        for r in range(opts.rounds + 2):
            rng.shuffle(order)
            for name in order:
                t0 = time.perf_counter()
                subprocess.run(["taskset", "-c", str(opts.cpu), str(bins[name]), str(INPUT), *extra],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                if r >= 2:
                    samples[name].append((time.perf_counter() - t0) * 1000)
        ratios = {n: statistics.median(a / z for a, z in zip(samples[n], samples["zig"])) for n in bins}
        report["modes"][mode] = {"digest": digests["zig"], "samples_ms": samples,
                                 "median_ms": {n: statistics.median(s) for n, s in samples.items()},
                                 "ratio_to_zig": ratios}
        print(mode, {n: f"{statistics.median(s):.1f} ms ({ratios[n]:.2f}x)" for n, s in samples.items()})
    report["load_end"] = os.getloadavg()
    opts.json.write_text(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
