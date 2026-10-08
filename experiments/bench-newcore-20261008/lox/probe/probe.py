#!/usr/bin/env python3
"""Untimed-quality probe: every script x engine at smoke size for several binaries.
Records wall time, exit status and whether stdout equals bench/expected/<script>.smoke.out."""
import json, subprocess, sys, time, concurrent.futures as cf
from pathlib import Path
ROOT = Path(sys.argv[1]); out_path = Path(sys.argv[2]); timeout = float(sys.argv[3])
bins = dict(a.split("=", 1) for a in sys.argv[4:])
sizes = {k: v for k, v in json.loads((ROOT / "bench/sizes.json").read_text()).items() if not k.startswith("_")}
work = out_path.parent / "scripts"; work.mkdir(exist_ok=True)
jobs = []
for name, tiers in sizes.items():
    body = (ROOT / f"bench/scripts/{name}.lox").read_text().split("\n", 1)[1]
    script = work / f"{name}.smoke.lox"; script.write_text(f"var N = {tiers['smoke']};\n{body}")
    want = (ROOT / f"bench/expected/{name}.smoke.out").read_bytes()
    for engine in ("vm", "tree"):
        for label, b in bins.items():
            jobs.append((name, engine, label, b, script, want))
def one(j):
    name, engine, label, b, script, want = j
    t = time.perf_counter()
    try:
        p = subprocess.run([b, f"--engine={engine}", "--stats", str(script)], capture_output=True, timeout=timeout)
        wall = time.perf_counter() - t
        return dict(script=name, engine=engine, binary=label, wall=wall, status=p.returncode,
                    stdout_ok=p.stdout == want, stats=p.stderr.decode(errors="replace").strip().splitlines()[-1:])
    except subprocess.TimeoutExpired:
        return dict(script=name, engine=engine, binary=label, wall=None, status="timeout", stdout_ok=None, stats=None)
with cf.ThreadPoolExecutor(6) as pool:
    res = list(pool.map(one, jobs))
out_path.write_text(json.dumps(res, indent=1))
for r in res:
    print(r["script"], r["engine"], r["binary"], "TIMEOUT" if r["wall"] is None else f"{r['wall']:.2f}s", r["status"], r["stdout_ok"], r["stats"])
