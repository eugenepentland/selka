#!/usr/bin/env python3
"""Layout sweep (docs/design/new-core-s1.md §13): build a kernel's emitted LLVM with K bytes of padding placed before
its functions (shifting every program address), under several code-layout flag sets,
and measure user cycles on CPU 10 (median of R runs).
usage: shift.py KERNEL.ll RUNTIME.o CLOCK.c ARGS... (env: SHIFTS, POLICIES, RUNS)"""
import os, statistics, subprocess, sys
ll, rt, clock, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
shifts = [int(x) for x in os.environ.get("SHIFTS", "0,64,128,192,256,320,384,448,512,576,640,704,768,832,896,960").split(",")]
base = ["-O3", "-march=native", "-Wno-override-module"]
policies = {
    "current": ["-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6"],
    "func64": ["-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6", "-falign-functions=64"],
    "loops64": ["-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6", "-falign-loops=64"],
    "func4k": ["-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6", "-falign-functions=4096"],
}
chosen = os.environ.get("POLICIES", ",".join(policies)).split(",")
runs = int(os.environ.get("RUNS", "5"))
text = open(ll).read()
name = os.path.basename(ll)[:-3]
print("| shift | " + " | ".join(chosen) + " |")
results = {p: [] for p in chosen}
for shift in shifts:
    padded = text.replace("define internal", "define void @myl.pad() noinline { call void asm sideeffect \".skip %d, 0x90\", \"\"() ret void }\ndefine internal" % shift, 1) if shift else text
    src = "%s_%d.ll" % (name, shift)
    open(src, "w").write(padded)
    row = []
    for policy in chosen:
        exe = "%s_%d_%s" % (name, shift, policy)
        subprocess.run(["zig", "cc"] + base + policies[policy] + ["-o", exe, src, rt, clock], check=True, stderr=subprocess.DEVNULL)
        cycles = []
        for _ in range(runs):
            done = subprocess.run(["taskset", "-c", "10", "perf", "stat", "-x,", "-e", "cpu_core/cycles/u", "./" + exe] + args, capture_output=True, text=True)
            cycles.append(int(done.stderr.strip().splitlines()[-1].split(",")[0]))
        value = statistics.median(cycles) / 1e6
        results[policy].append(value)
        row.append("%.1f" % value)
    print("| %d | %s |" % (shift, " | ".join(row)), flush=True)
print("| min–max (spread) | " + " | ".join("%.1f–%.1f (%.0f%%)" % (min(v), max(v), 100 * (max(v) - min(v)) / min(v)) for v in results.values()) + " |")
