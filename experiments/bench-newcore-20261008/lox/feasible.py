"""Rough feasibility: each script x engine at its timed size, new-core mylang and Zig,
one run each with a timeout; checks output against the expected file when one exists."""
import json, subprocess, sys, time, concurrent.futures as cf
from pathlib import Path
ROOT = Path(sys.argv[1]); C = ROOT / ".tmp/lox-bench/cache"; T = float(sys.argv[2])
bins = {"mylang": C / "mylang-release/lox-release", "zig": C / "zig-release/out-release/bin/lox"}
sizes = {k: v for k, v in json.loads((ROOT / "bench/sizes.json").read_text()).items() if not k.startswith("_")}
work = ROOT / ".tmp/timed"; jobs = []
for name, tiers in sizes.items():
    body = (ROOT / f"bench/scripts/{name}.lox").read_text().split("\n", 1)[1]
    for engine in ("vm", "tree"):
        script = work / f"{name}.{engine}.lox"; script.write_text(f"var N = {tiers[engine]};\n{body}")
        want = ROOT / f"bench/expected/{name}.{engine}.out"
        for label, b in bins.items(): jobs.append((name, engine, label, b, script, want))
def one(j):
    name, engine, label, b, script, want = j
    t = time.perf_counter()
    try:
        p = subprocess.run([str(b), f"--engine={engine}", str(script)], capture_output=True, timeout=T)
        ok = (p.stdout == want.read_bytes()) if want.exists() else None
        return name, engine, label, time.perf_counter() - t, p.returncode, ok
    except subprocess.TimeoutExpired:
        return name, engine, label, None, "timeout", None
with cf.ThreadPoolExecutor(4) as pool:
    for r in pool.map(one, jobs):
        print(r[0], r[1], r[2], "TIMEOUT" if r[3] is None else f"{r[3]:.2f}", r[4], r[5], flush=True)
