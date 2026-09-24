#!/usr/bin/env python3
"""Interleaved comparison: a body edit rebuilt by the whole-program build versus the
same edit rebuilt as one module against stub interfaces (module_compile.py's project).

usage: ab_module.py WHOLE_SRC STUB_DIR --mylang BIN --cache-whole DIR --cache-stub DIR --module mNNN [--rounds 5]

Both trees must already be built once with their caches (warm). Each round writes the
same new constant into the module's first body in both trees, then builds both, in
alternating order, and records wall, peak RSS and CPU. No --report, so the build takes
its normal path.
"""
import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path


def build(bin_, src, cache, out):
    cmd = ["taskset", "-c", "0-11", "/usr/bin/time", "-f", "__T__ %M %U %S", bin_, "build", "main.my", "--project", "-o", str(out),
           f"--cache-dir={cache}"]
    t = time.perf_counter()
    p = subprocess.run(cmd, cwd=src, capture_output=True, text=True, env=dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp"))
    dt = time.perf_counter() - t
    m = re.search(r"__T__ (\d+) ([\d.]+) ([\d.]+)", p.stderr)
    return {"wall_s": round(dt, 3), "rc": p.returncode, "rss_mb": round(int(m.group(1)) / 1024) if m else None,
            "cpu_s": round(float(m.group(2)) + float(m.group(3)), 2) if m else None, "load": round(os.getloadavg()[0], 2)}


def edit(path, token):
    s = path.read_text()
    path.write_text(re.sub(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", s, count=1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("whole")
    ap.add_argument("stub")
    ap.add_argument("--mylang", required=True)
    ap.add_argument("--cache-whole", required=True)
    ap.add_argument("--cache-stub", required=True)
    ap.add_argument("--out-whole", required=True)
    ap.add_argument("--module", required=True)
    ap.add_argument("--rounds", type=int, default=5)
    a = ap.parse_args()
    whole, stub = Path(a.whole), Path(a.stub)
    rows = {"whole": [], "module": []}
    for r in range(a.rounds):
        tok = 9500 + r
        order = [("whole", whole, a.cache_whole, a.out_whole), ("module", stub, a.cache_stub, stub / "stub")]
        if r % 2:
            order.reverse()
        for name, src, cache, out in order:
            edit(src / f"{a.module}.my", tok)
            res = build(a.mylang, src, cache, out)
            rows[name].append(res)
            print(json.dumps({"side": name, "round": r, **res}), flush=True)
    print(json.dumps({k: {"min_wall_s": min(x["wall_s"] for x in v), "median_wall_s": sorted(x["wall_s"] for x in v)[len(v) // 2],
                          "max_rss_mb": max(x["rss_mb"] or 0 for x in v)} for k, v in rows.items()}))


if __name__ == "__main__":
    main()
