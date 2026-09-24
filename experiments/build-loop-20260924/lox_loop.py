#!/usr/bin/env python3
"""Edit loop on the real Lox port: a body edit in heap.my (imported by the VM, compiler,
driver and several tests), then check / build / test; minimum of N samples."""
import os, re, shutil, subprocess, sys, time
M, N, WORK = sys.argv[1], int(sys.argv[2]), sys.argv[3]
SRC = "/home/epentland/ai/trials/devspeed-20260923-private/lox-mylang-full"
shutil.rmtree(WORK, ignore_errors=True); shutil.copytree(SRC, WORK + "/t")
T = WORK + "/t"; C = WORK + "/cache"
ENV = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
H = T + "/heap.my"
os.remove(T + "/driver_tests.my")  # needs the unmerged test-capabilities lane
open(H, "a").write("\n\npublic def zz_edit_marker(n: int) -> int:\n    return n + 1\n")
CMDS = {"check": [M, "check", "main.my", f"--cache-dir={C}"],
        "build": [M, "build", "main.my", "--project", "-o", WORK + "/lox", f"--cache-dir={C}"],
        "test": [M, "test", ".", "--cache-dir", C + "/t"]}
def run(cmd):
    t = time.perf_counter(); p = subprocess.run(["taskset", "-c", "0-11"] + cmd, cwd=T, env=ENV, capture_output=True)
    return time.perf_counter() - t, p.returncode, (p.stdout + p.stderr).decode()[-300:]
counter = [1]
def edit():
    counter[0] += 1
    s = open(H).read()
    s = re.sub(r"return n \+ \d+\n$", f"return n + {counter[0]}\n", s)
    open(H, "w").write(s)
for step in CMDS:
    first = run(CMDS[step])
    if first[1] != 0:
        print(step, "FAILED", first[2]); continue
    noop = min(run(CMDS[step])[0] for _ in range(N))
    times = []
    for _ in range(N):
        edit(); times.append(run(CMDS[step]))
    bad = [x[2] for x in times if x[1] != 0]
    print(f"{step:6s} cold {first[0]:.3f}  no-op {noop:.3f}  edit {min(x[0] for x in times):.3f}" + (f"  FAIL {bad[0]}" if bad else ""))
