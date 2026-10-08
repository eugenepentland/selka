# Pre-warm: build every arm exactly as `bench_parity.py run` would, off the timing CPUs, no timing.
import sys, concurrent.futures
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import bench_parity as bp
mylang, work = sys.argv[2], Path(sys.argv[3])
(work / "bin").mkdir(parents=True, exist_ok=True)
rustc = bp.find_rustc(None)
tools = {"mylang": mylang, "zig": "zig", "rustc": rustc}
jobs = []
for b in bp.discover([]):
    for j in bp.arms_for(b["ports"]):
        j["bench"] = b["name"]; j["bin"] = work / "bin" / f"{b['name']}.{j['arm']}"; j["expected"] = b["expected"]
        jobs.append(j)
print(len(jobs), "arms; rustc", rustc, flush=True)
with bp.OffTimingCpus(), concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    res = list(pool.map(lambda j: bp.build(j, tools, work), jobs))
for j, r in zip(jobs, res):
    if not r["ok"]:
        print("BUILD FAIL", j["bench"], j["arm"], r["stderr"][-1500:], flush=True); continue
    out, st = bp.run_captured(j["bin"])
    ok = st == 0 and out == j["expected"]
    print(("OK      " if ok else f"MISMATCH status={st} ") + f"{j['bench']} {j['arm']} build {r['seconds']}s", flush=True)
