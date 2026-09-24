#!/usr/bin/env python3
"""Run a captured ld.lld link with --time-trace and print lld's own phase totals.

usage: lldtrace.py LINK.json OUT_DIR [extra lld args...]
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path


def main():
    link = json.load(open(sys.argv[1]))["link"]
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    a = list(link)
    a[a.index("-o") + 1] = str(out / "tt-program")
    trace = out / "tt.json"
    a += [f"--time-trace={trace}"] + sys.argv[3:]
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", os.environ.get("SCALE_CPUS", "0-11")] + a, capture_output=True, text=True)
    wall = time.perf_counter() - t
    if p.returncode != 0:
        print("link failed:", p.stderr[-500:])
        return
    t = json.load(open(trace))
    tot = {}
    for e in t["traceEvents"]:
        if e.get("ph") == "X" and e["name"].startswith("Total "):
            tot[e["name"][6:]] = e["dur"] / 1000
    print(json.dumps({"wall_ms": round(wall * 1000, 1), "load": os.getloadavg()[0]}))
    for k, v in sorted(tot.items(), key=lambda kv: -kv[1])[:22]:
        print(f"{v:8.1f} ms  {k}")


if __name__ == "__main__":
    main()
