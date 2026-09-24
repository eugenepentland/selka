#!/usr/bin/env python3
"""Interleaved A/B of body and interface edits between two compilers on one tier.

usage: ab_iface.py TIER_DIR WORK_DIR --a BIN --b BIN [--rounds 3] [--mode default|Debug]

Each compiler gets its own copy of the project and its own cache. Both are built cold
(untimed for the comparison), then each round applies the same body edit and then the
same interface edit (append a public function) to both copies, alternating which
compiler goes first, and records the build's wall time, its frontend/codegen/link
phases and whether the shared metadata object was reused.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def build(bin_, src, cache, out, mode):
    cmd = ["taskset", "-c", "0-11", bin_, "build", "main.my", "--project", "-o", str(out), f"--cache-dir={cache}", "--report"]
    if mode == "Debug":
        cmd += ["--mode", "Debug"]
    t = time.perf_counter()
    p = subprocess.run(cmd, cwd=src, capture_output=True, text=True, env=dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp"))
    dt = time.perf_counter() - t
    rep = next((json.loads(line) for line in p.stdout.splitlines() if line.startswith('{"version":"qbe-build-v1"')), {})
    return {"wall_s": round(dt, 3), "rc": p.returncode, "frontend": round(rep.get("frontend_seconds") or 0, 3),
            "codegen": round(rep.get("codegen_seconds") or 0, 3), "link": round(rep.get("link_seconds") or 0, 3),
            "metadata_reused": rep.get("metadata_reused"), "compiled_objects": rep.get("compiled_function_objects"),
            "load": round(os.getloadavg()[0], 2), "err": p.stderr[-300:] if p.returncode else ""}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tier")
    ap.add_argument("work")
    ap.add_argument("--a", required=True)
    ap.add_argument("--b", required=True)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--mode", default="default")
    a = ap.parse_args()
    tier, work = Path(a.tier).resolve(), Path(a.work).resolve()
    sides = {}
    for name, bin_ in (("a", a.a), ("b", a.b)):
        d = work / name
        shutil.rmtree(d, ignore_errors=True)
        shutil.copytree(tier / "mylang", d / "src")
        sides[name] = {"bin": bin_, "src": d / "src", "cache": d / "cache", "out": d / "big"}
        r = build(bin_, d / "src", d / "cache", d / "big", a.mode)
        print(json.dumps({"side": name, "step": "cold", **r}), flush=True)
        r = build(bin_, d / "src", d / "cache", d / "big", a.mode)
        print(json.dumps({"side": name, "step": "noop", **r}), flush=True)
    M = len(list((tier / "mylang").glob("m[0-9]*.my")))
    mid = f"m{(M + 1) // 2:03d}.my"
    tok = 7000
    for rnd in range(a.rounds):
        order = ["a", "b"] if rnd % 2 == 0 else ["b", "a"]
        tok += 1
        for name in order:
            s = sides[name]
            f = s["src"] / mid
            f.write_text(re.sub(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{tok}{m.group(3)}", f.read_text(), count=1))
            print(json.dumps({"side": name, "step": "edit", "round": rnd, **build(s["bin"], s["src"], s["cache"], s["out"], a.mode)}), flush=True)
        tok += 1
        for name in order:
            s = sides[name]
            with (s["src"] / mid).open("a") as fh:
                fh.write(f"\n\npublic def extra_{tok}(n: int) -> int:\n    return n + {tok}\n")
            print(json.dumps({"side": name, "step": "iface", "round": rnd, **build(s["bin"], s["src"], s["cache"], s["out"], a.mode)}), flush=True)
    outs = {}
    for name, s in sides.items():
        p = subprocess.run([str(s["out"])], capture_output=True, text=True)
        outs[name] = p.stdout.strip()
    print(json.dumps({"program_outputs": outs, "equal": outs["a"] == outs["b"]}))


if __name__ == "__main__":
    main()
