#!/usr/bin/env python3
"""xlate_time.py ADAPTER_DIR SSA... — total seconds to translate every unit (no LLVM compile)."""
import glob
import sys
import time

sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import qbe_llvm  # noqa: E402

paths = []
for a in sys.argv[2:]:
    paths.extend(sorted(glob.glob(a)))
start = time.perf_counter()
size = 0
worst = (0, "")
for p in paths:
    text = open(p).read()
    size += len(text)
    t0 = time.perf_counter()
    qbe_llvm.translate_text(text, p)
    dt = time.perf_counter() - t0
    worst = max(worst, (dt, p.split("/")[-1][:20]))
print(f"{len(paths)} units, {size / 1e6:.1f} MB IL, {time.perf_counter() - start:.2f} s, slowest {worst[0]:.2f} s {worst[1]}")
