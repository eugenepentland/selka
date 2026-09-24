"""Interleaved cold `check` (fresh cache each run) for two compilers on one tier.

usage: ab_check.py TIER_DIR SAMPLES NAME=COMPILER [NAME=COMPILER...] [-- extra args]
"""
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

tier = Path(sys.argv[1]).resolve()
samples = int(sys.argv[2])
rest = sys.argv[3:]
extra = rest[rest.index("--") + 1:] if "--" in rest else []
pairs = [p.split("=", 1) for p in (rest[:rest.index("--")] if "--" in rest else rest)]
work = tier / "ab-work"
env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
results = {name: [] for name, _ in pairs}
for s in range(samples):
    for name, compiler in pairs:
        shutil.rmtree(work, ignore_errors=True)
        shutil.copytree(tier / "mylang", work)
        cmd = ["taskset", "-c", "0-11", "/usr/bin/time", "-f", "__RSS__ %M", compiler, "check", "main.my", "--no-cache"] + extra
        load = os.getloadavg()[0]
        t = time.perf_counter()
        p = subprocess.run(cmd, cwd=work, env=env, capture_output=True, text=True)
        dt = time.perf_counter() - t
        rss = int(re.search(r"__RSS__ (\d+)", p.stderr).group(1)) // 1024
        results[name].append((round(dt, 3), rss, p.returncode, round(load, 1)))
        print(name, s, round(dt, 3), rss, "MB", "status", p.returncode, "load", round(load, 1), flush=True)
for name, rows in results.items():
    good = [r[0] for r in rows if r[2] == 0]
    print(name, "min", min(good) if good else None, "max_rss_mb", max(r[1] for r in rows))
