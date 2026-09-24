#!/usr/bin/env python3
"""cmp.py TAG_A TAG_B [N] [kernel...] — paired interleaved timing of kernels built under
.tmp/census-TAG_A and .tmp/census-TAG_B on CPU 8: median ms, ratio (B/A, median of per-round
ratios), instruction/branch ratios and branch misses, stdout equality."""
import os
import statistics
import subprocess
import sys
import time

root = str(__import__("pathlib").Path(__file__).resolve().parents[2] / ".tmp")
a, b = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 5
only = sys.argv[4:]
cpu = os.environ.get("CPU", "8")


def counters(path):
    r = subprocess.run(["taskset", "-c", cpu, "perf", "stat", "-x,", "-e",
                        "cpu_core/instructions/,cpu_core/branches/,cpu_core/branch-misses/", path], capture_output=True, text=True)
    out = {}
    for line in r.stderr.splitlines():
        parts = line.split(",")
        if len(parts) > 2 and parts[0].strip().isdigit():
            key = parts[2].split("/")[1] if "/" in parts[2] else parts[2]
            out[key] = out.get(key, 0) + int(parts[0])
    return out


def run(path):
    t0 = time.perf_counter()
    r = subprocess.run(["taskset", "-c", cpu, path], capture_output=True)
    return time.perf_counter() - t0, r.stdout, r.returncode


kernels = sorted(os.listdir(f"{root}/census-{a}"))
print(f"{'kernel':16s} {a+' ms':>9s} {b+' ms':>9s} {'B/A':>6s} {'ins B/A':>8s} {'br B/A':>7s} "
      f"{'missA K':>8s} {'missB K':>8s} out")
for k in kernels:
    if only and k not in only:
        continue
    pa, pb = f"{root}/census-{a}/{k}/prog", f"{root}/census-{b}/{k}/prog"
    if not (os.path.exists(pa) and os.path.exists(pb)):
        continue
    ta, tb, ratios = [], [], []
    same = True
    for i in range(n):
        order = [(pa, ta), (pb, tb)] if i % 2 == 0 else [(pb, tb), (pa, ta)]
        outs = {}
        for path, acc in order:
            t, out, rc = run(path)
            acc.append(t)
            outs[path] = (out, rc)
        same = same and outs[pa] == outs[pb]
        ratios.append(tb[-1] / ta[-1])
    ca, cb = counters(pa), counters(pb)
    ma, mb = statistics.median(ta) * 1000, statistics.median(tb) * 1000
    print(f"{k:16s} {ma:9.1f} {mb:9.1f} {statistics.median(ratios):6.3f} "
          f"{cb.get('instructions', 1) / max(1, ca.get('instructions', 1)):8.3f} "
          f"{cb.get('branches', 1) / max(1, ca.get('branches', 1)):7.3f} "
          f"{ca.get('branch-misses', 0) / 1e3:8.1f} {cb.get('branch-misses', 0) / 1e3:8.1f} "
          f"{'same' if same else 'DIFF'}", flush=True)
