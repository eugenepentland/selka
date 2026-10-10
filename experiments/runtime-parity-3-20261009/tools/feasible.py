#!/usr/bin/env python3
"""CE-X Lox feasibility pass (after the morning's feasible.py): the six cells the morning run
left out, at their timed sizes, one run each, 150 s timeout, serially on CPU 10 (run it
under flock cpu10.lock). Only the final compiler's binary runs, with Zig as a reference: the
base did not finish these cells in 150 s this morning, so the coordinator dropped its re-run to
save time (2026-10-08), and the six cells stay out of the timed run. Output is checked against
the expected file. usage: feasible.py LOX_ROOT OUT.json"""
import json, subprocess, sys, time
from pathlib import Path
ROOT = Path(sys.argv[1]); C = ROOT / ".tmp/lox-bench/cache"; T = 150.0
bins = {"final": C / "mylang-release/lox-release", "base": C / "mylang-base-release/lox-release",
        "zig": C / "zig-release/out-release/bin/lox"}
CELLS = [("binary_trees", "tree"), ("binary_trees", "vm"), ("trees", "tree"), ("trees", "vm"),
         ("instantiation", "vm"), ("method_call", "tree")]
sizes = json.loads((ROOT / "bench/sizes.json").read_text())
work = ROOT / ".tmp/timed"; work.mkdir(parents=True, exist_ok=True)
out = []


def one(name, engine, label):
    script = work / f"{name}.{engine}.lox"
    body = (ROOT / f"bench/scripts/{name}.lox").read_text().split("\n", 1)[1]
    script.write_text(f"var N = {sizes[name][engine]};\n{body}")
    want = ROOT / f"bench/expected/{name}.{engine}.out"
    t = time.perf_counter()
    try:
        p = subprocess.run(["taskset", "-c", "10", str(bins[label]), f"--engine={engine}", str(script)], capture_output=True, timeout=T)
        r = {"cell": f"{name}/{engine}", "binary": label, "seconds": round(time.perf_counter() - t, 3), "status": p.returncode,
             "output_ok": (p.stdout == want.read_bytes()) if want.exists() else None}
    except subprocess.TimeoutExpired:
        r = {"cell": f"{name}/{engine}", "binary": label, "seconds": None, "status": "timeout", "output_ok": None}
    print(json.dumps(r), flush=True)
    out.append(r)
    return r


for name, engine in CELLS:
    one(name, engine, "zig")
    one(name, engine, "final")
Path(sys.argv[2]).write_text(json.dumps(out, indent=1) + "\n")
