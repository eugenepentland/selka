#!/usr/bin/env python3
"""Self-PC profile of a dynamically linked binary with the repository's SIGPROF sampler.

usage: prof.py BINARY [--runs N] [--cpu C] [--top K] [--json OUT] [--asm K]

Hardware counters are unavailable here (perf_event_paranoid=4), so this uses
`experiments/perf-parity-audit-20260921/profiles/sample_dense.c` via LD_PRELOAD:
self-PC samples of process CPU time at the 1 ms kernel tick, no call stacks, and
samples inside shared libraries (libc memcpy/memset/malloc, the loader) counted as
`outside`. Symbols come from `nm -n`, so build mylang binaries with
`--keep-symbols`; under LTO an inlined guest function is attributed to the
surviving caller. `--asm K` prints the disassembly around the K hottest PCs.
"""
from __future__ import annotations

import argparse
import bisect
import collections
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAMPLER_SRC = HERE.parent / "perf-parity-audit-20260921/profiles/sample_dense.c"
WORK = HERE.parents[1].parents[0] / "work/prof"


def sampler() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    so = WORK / "sample_dense.so"
    if not so.exists() or so.stat().st_mtime < SAMPLER_SRC.stat().st_mtime:
        subprocess.run(["cc", "-O2", "-shared", "-fPIC", "-o", so, SAMPLER_SRC], check=True)
    return so


def symbols(binary: Path):
    out = subprocess.run(["nm", "-n", "--defined-only", binary], capture_output=True, text=True).stdout
    addrs, names = [], []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tTwW":
            addrs.append(int(parts[0], 16))
            names.append(parts[2])
    return addrs, names


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("binary", type=Path)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--cpu", type=int, default=6)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--asm", type=int, default=0)
    ap.add_argument("--json", type=Path)
    opts = ap.parse_args()
    so = sampler()
    samples_file = WORK / f"{opts.binary.name}.samples"
    samples_file.unlink(missing_ok=True)
    env = dict(os.environ, LD_PRELOAD=str(so), MYLANG_AUDIT_SAMPLES=str(samples_file))
    for _ in range(opts.runs):
        subprocess.run(["taskset", "-c", str(opts.cpu), str(opts.binary.resolve())], env=env,
                       stdout=subprocess.DEVNULL, check=False)
    pcs = collections.Counter()
    total = outside = 0
    for line in samples_file.read_text().splitlines():
        if line.startswith("run "):
            f = line.split()
            total += int(f[3])
            outside += int(f[5])
            continue
        pc, n = line.split()
        pcs[int(pc, 16)] += int(n)
    addrs, names = symbols(opts.binary)
    by_fn = collections.Counter()
    for pc, n in pcs.items():
        i = bisect.bisect_right(addrs, pc) - 1
        by_fn[names[i] if i >= 0 else "?"] += n
    by_fn["<outside: shared libraries>"] = outside
    rows = [{"function": fn, "samples": n, "share": n / total if total else 0} for fn, n in by_fn.most_common(opts.top)]
    print(f"{opts.binary.name}: {total} samples over {opts.runs} runs, {outside} outside ({outside / max(total, 1):.1%})")
    for r in rows:
        print(f"  {r['share']:6.1%}  {r['samples']:6d}  {r['function']}")
    hot = [{"pc": hex(pc), "samples": n, "share": n / total} for pc, n in pcs.most_common(max(opts.asm, 20))]
    if opts.asm:
        dis = subprocess.run(["objdump", "-d", "--no-show-raw-insn", opts.binary], capture_output=True, text=True).stdout.splitlines()
        index = {}
        for i, line in enumerate(dis):
            s = line.strip()
            if s and s[0] in "0123456789abcdef" and ":" in s:
                try:
                    index[int(s.split(":")[0], 16)] = i
                except ValueError:
                    pass
        for h in hot[:opts.asm]:
            pc = int(h["pc"], 16)
            i = index.get(pc)
            print(f"--- {h['pc']} {h['share']:.1%}")
            if i is not None:
                for line in dis[max(0, i - 12):i + 4]:
                    marker = ">>" if line.strip().startswith(f"{pc:x}:") else "  "
                    print(f"{marker} {line}")
    if opts.json:
        opts.json.write_text(json.dumps({"binary": str(opts.binary), "runs": opts.runs, "samples": total,
                                         "outside": outside, "functions": rows, "hot_pcs": hot}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
