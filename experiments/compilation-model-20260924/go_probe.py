#!/usr/bin/env python3
"""Where Go spends an edit -> build on the same generated tier (the per-package model).

usage: go_probe.py TIER_DIR WORK_DIR [--samples 3]

Copies TIER_DIR/go, builds it cold with a private GOCACHE, then for a body edit and an
interface edit in the middle package runs `go build -debug-actiongraph` and reports, per
edit: wall time, the packages actually compiled (and their summed compile time), the link
time, and the actions that were cache hits.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

GO = "/home/epentland/.local/bin/go"


def ts(s):
    # 2026-09-24T11:30:01.123456789-06:00 -> seconds (ignoring the date)
    m = re.match(r".*T(\d+):(\d+):([\d.]+)", s)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))


def build(work, env, graph):
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", "0-11", "/usr/bin/time", "-f", "__RSS__ %M", GO, "build", f"-debug-actiongraph={graph}", "-o",
                        str(work / "big"), "./cmd"], cwd=work, env=env, capture_output=True, text=True)
    wall = time.perf_counter() - t
    rss = re.search(r"__RSS__ (\d+)", p.stderr)
    acts = json.load(open(graph))
    compiled, link, hits = [], None, 0
    for a in acts:
        if "TimeStart" not in a or "TimeDone" not in a:
            continue
        d = ts(a["TimeDone"]) - ts(a["TimeStart"])
        if a.get("Mode") == "build" and a.get("Cmd"):
            compiled.append((a.get("Package"), round(d, 4)))
        elif a.get("Mode") == "build":
            hits += 1
        if a.get("Mode") == "link":
            link = round(d, 4)
    return {"wall_s": round(wall, 3), "rc": p.returncode, "max_rss_kb": int(rss.group(1)) if rss else None,
            "compiled": len(compiled), "compile_sum_s": round(sum(c[1] for c in compiled), 3),
            "compiled_pkgs": [c for c in compiled if not c[0].startswith(("runtime", "internal"))][:6],
            "link_s": link, "cache_hits": hits, "load": round(os.getloadavg()[0], 2)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tier")
    ap.add_argument("work")
    ap.add_argument("--samples", type=int, default=3)
    a = ap.parse_args()
    tier, work = Path(a.tier).resolve(), Path(a.work).resolve()
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(tier / "go", work / "src")
    src = work / "src"
    env = dict(os.environ, GOCACHE=str(work / "gocache"), GOFLAGS="-mod=mod", TMPDIR="/home/epentland/.cache/mylang-tmp")
    M = len([p for p in src.iterdir() if p.name.startswith("m")])
    mid = src / f"m{M // 2:03d}" / f"m{M // 2:03d}.go"
    print(json.dumps({"step": "cold", **build(src, env, work / "g-cold.json")}), flush=True)
    print(json.dumps({"step": "noop", **build(src, env, work / "g-noop.json")}), flush=True)
    tok = 7000
    for s in range(a.samples):
        tok += 1
        text = mid.read_text()
        text = re.sub(r"(\+)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{tok}{m.group(3)}", text, count=1)
        mid.write_text(text)
        print(json.dumps({"step": "edit", **build(src, env, work / f"g-edit{s}.json")}), flush=True)
        tok += 1
        with mid.open("a") as f:
            f.write(f"\nfunc Extra{tok}(n int) int {{\n\treturn n + {tok}\n}}\n")
        print(json.dumps({"step": "iface", **build(src, env, work / f"g-iface{s}.json")}), flush=True)


if __name__ == "__main__":
    main()
