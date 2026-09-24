"""Interleaved interface-edit builds for two warmed ladder work dirs (item 5 A/B).

usage: ab_iface.py TIER_DIR ROUNDS LABEL=COMPILER LABEL=COMPILER
Each round appends a new public function to the middle module of each work dir and
builds it with --report, recording wall time, codegen/link seconds and metadata_reused.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

tier = Path(sys.argv[1]).resolve()
rounds = int(sys.argv[2])
pairs = [p.split("=", 1) for p in sys.argv[3:]]
env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
M = len(list((tier / "mylang").glob("m*.my")))
rows = []
for r in range(rounds):
    for label, compiler in pairs:
        work = tier / f"work-{label}"
        cache = tier / f"work-{label}-cache"
        with (work / f"m{M // 2:03d}.my").open("a") as f:
            f.write(f"\n\npublic def ab_{r}(n: int) -> int:\n    return n + {r}\n")
        cmd = ["taskset", "-c", "0-11", compiler, "build", "main.my", "--project", "-o", str(cache / "bin" / "big"),
               f"--cache-dir={cache / 'mylang'}", "--report"]
        load = os.getloadavg()[0]
        t = time.perf_counter()
        p = subprocess.run(cmd, cwd=work, env=env, capture_output=True, text=True)
        wall = time.perf_counter() - t
        get = lambda key: (re.search(rf'"{key}":([^,}}]+)', p.stdout) or [None, None])[1]
        row = {"round": r, "label": label, "ok": p.returncode == 0, "wall": round(wall, 3), "load": round(load, 1),
               "metadata_reused": get("metadata_reused"), "frontend": get("frontend_seconds"),
               "codegen": get("codegen_seconds"), "link": get("link_seconds")}
        rows.append(row)
        print(json.dumps(row), flush=True)
for label, _ in pairs:
    mine = [x for x in rows if x["label"] == label and x["ok"]]
    print(label, "min wall", min(x["wall"] for x in mine), "min codegen", min(float(x["codegen"]) for x in mine),
          "reused", sum(x["metadata_reused"] == "true" for x in mine), "of", len(mine))
