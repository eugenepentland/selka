#!/usr/bin/env python3
"""Run one frontend command with --timings=json and report resident memory at each phase end.

usage: phase_rss.py OUT.json -- CMD... (the command must accept --timings=json)
Samples VmRSS/VmSize every 20 ms, then aligns the phase records (disjoint, in end order)
from the process start, and prints, per phase: its seconds, resident and address space
at its end, and the largest resident value seen during it.
"""
import json
import subprocess
import sys
import time


def status(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            text = f.read()
    except OSError:
        return None
    get = lambda key: int(text.split(key + ":")[1].split()[0]) if key + ":" in text else 0
    return get("VmRSS"), get("VmSize")


def main():
    out = sys.argv[1]
    cmd = sys.argv[sys.argv.index("--") + 1:] + ["--timings=json"]
    start = time.perf_counter()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    samples = []
    import threading
    err = []
    t = threading.Thread(target=lambda: err.append(proc.stderr.read()))
    t.start()
    while proc.poll() is None:
        s = status(proc.pid)
        if s:
            samples.append((time.perf_counter() - start, s[0], s[1]))
        time.sleep(0.02)
    t.join()
    phases = []
    for line in err[0].splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("kind") == "timing" and not d.get("inclusive"):
            phases.append((d["name"], d["duration_ns"] / 1e9))
    rows, clock = [], 0.0
    for name, seconds in phases:
        begin, clock = clock, clock + seconds
        during = [s for s in samples if begin <= s[0] <= clock]
        at_end = min(samples, key=lambda s: abs(s[0] - clock)) if samples else (0, 0, 0)
        rows.append({"phase": name, "s": round(seconds, 2), "rss_end_mb": at_end[1] // 1024, "vm_end_mb": at_end[2] // 1024,
                     "rss_max_mb": max((s[1] for s in during), default=at_end[1]) // 1024})
    peak_rss = max(s[1] for s in samples) // 1024
    peak_vm = max(s[2] for s in samples) // 1024
    json.dump({"command": cmd, "status": proc.returncode, "wall_s": round(time.perf_counter() - start, 2),
               "peak_rss_mb": peak_rss, "peak_vm_mb": peak_vm, "phases": rows, "samples": samples[::10]}, open(out, "w"))
    for r in rows:
        if r["s"] >= 0.05:
            print(f'{r["phase"]:32} {r["s"]:7.2f} s  rss_end {r["rss_end_mb"]:6} MB  vm_end {r["vm_end_mb"]:6} MB  rss_max {r["rss_max_mb"]:6} MB')
    print(f"status {proc.returncode}  peak rss {peak_rss} MB  peak vm {peak_vm} MB  wall {round(time.perf_counter() - start, 2)} s")
    if proc.returncode != 0:
        print(err[0][-600:])


if __name__ == "__main__":
    main()
