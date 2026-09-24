"""Body edit then `mylang test`, N samples, on a warmed ladder work dir.

usage: edit_test.py TIER_DIR WORK_LABEL COMPILER TEST_CACHE SAMPLES
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

tier, label, compiler, cache, samples = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
work = tier / f"work-{label}"
M = len(list((tier / "mylang").glob("m*.my")))
target = work / f"m{M // 2:03d}.my"
env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
for s in range(samples):
    text = target.read_text()
    text, n = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{8100 + s}{m.group(3)}", text, count=1)
    assert n == 1
    target.write_text(text)
    load = os.getloadavg()[0]
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", "0-11", "/usr/bin/time", "-f", "__RSS__ %M", compiler, "test", "main.my", "--cache-dir", cache],
                       cwd=work, env=env, capture_output=True, text=True)
    wall = time.perf_counter() - t
    rss = int(re.search(r"__RSS__ (\d+)", p.stderr).group(1)) // 1024
    summary = (re.search(r"\d+ passed, \d+ cached, \d+ failed, \d+ skipped", p.stdout + p.stderr) or [None])[0]
    frame = (p.stdout + p.stderr).count("R_FRAME_LIMIT")
    print(json.dumps({"step": "edit_test", "sample": s, "s": round(wall, 3), "rss_mb": rss, "code": p.returncode,
                      "load": round(load, 1), "summary": summary, "frame_limit_failures": frame}), flush=True)
