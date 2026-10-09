#!/usr/bin/env python3
"""Build every parity program's `my` arm (suite, lib, micro) with one compiler and
check its output against `<name>.expected`.

usage: build_arms.py COMPILER OUTDIR [--counters] [--only NAME,...] [--jobs N]
Writes OUTDIR/<program> binaries and OUTDIR/build.json (status per program).
"""
from __future__ import annotations
import argparse, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GROUPS = ["suite", "lib", "micro"]


def programs(only):
    out = []
    for group in GROUPS:
        for expected in sorted((ROOT / "bench/parity" / group).glob("*.expected")):
            name = expected.stem
            src = expected.with_suffix(".my")
            if src.exists() and (not only or name in only):
                out.append((name, src, expected))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("compiler"); p.add_argument("outdir")
    p.add_argument("--counters", action="store_true")
    p.add_argument("--only", default="")
    p.add_argument("--jobs", type=int, default=4)
    a = p.parse_args()
    out = Path(a.outdir); out.mkdir(parents=True, exist_ok=True)
    cache = out / "cache"
    only = set(x for x in a.only.split(",") if x)
    results = {}

    def one(item):
        name, src, expected = item
        exe = out / name
        cmd = [a.compiler, "build", str(src), "-o", str(exe), "--release", "--cache-dir", str(cache)]
        if a.counters:
            cmd.append("--counters")
        b = subprocess.run(cmd, capture_output=True, text=True)
        if b.returncode != 0:
            return name, {"build": b.returncode, "stderr": b.stderr[-2000:]}
        env = dict(os.environ)
        if a.counters:
            env["MYLANG_COUNTERS"] = str(out / f"{name}.counters.json")
        r = subprocess.run(["taskset", "-c", "0,1,4,5,7,8,9,12-19", str(exe)], capture_output=True, env=env, timeout=600)
        same = r.stdout == expected.read_bytes()
        return name, {"build": 0, "status": r.returncode, "same": same}

    with ThreadPoolExecutor(a.jobs) as pool:
        for name, res in pool.map(one, programs(only)):
            results[name] = res
            print(name, res, flush=True)
    (out / "build.json").write_text(json.dumps(results, indent=1))
    bad = [n for n, r in results.items() if r.get("build") or r.get("status") or not r.get("same")]
    print("FAILED:" if bad else "all ok", bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
