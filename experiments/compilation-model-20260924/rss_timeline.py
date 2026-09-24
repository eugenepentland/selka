#!/usr/bin/env python3
"""Run a command and sample the resident memory of its process tree over time.

usage: rss_timeline.py OUT.json [--interval 0.02] [--cwd DIR] -- CMD...

Every interval, reads VmRSS of the command and of each descendant (by walking
/proc/*/stat parents), recording per-process name and RSS. Writes the samples and,
per process name, the peak RSS and the time of the peak. With `--timings=json` on a
compiler command, the phase lines on stderr are kept too, so phase boundaries can be
lined up with the memory curve (phases are printed in execution order).
"""
import argparse
import json
import os
import subprocess
import sys
import time


def children_map():
    kids = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                s = f.read()
            ppid = int(s[s.rindex(")") + 2:].split()[1])
            kids.setdefault(ppid, []).append(int(pid))
        except (OSError, ValueError):
            pass
    return kids


def rss_of(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            name, rss = None, 0
            for line in f:
                if line.startswith("Name:"):
                    name = line.split()[1]
                elif line.startswith("VmRSS:"):
                    rss = int(line.split()[1])
            with open(f"/proc/{pid}/cmdline", "rb") as c:
                argv = c.read().split(b"\0")
            if len(argv) > 1 and name in ("mylang", "zig"):
                name = name + " " + argv[1].decode(errors="replace")
            return name, rss
    except OSError:
        return None, 0


def main():
    argv = sys.argv[1:]
    split = argv.index("--")
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--interval", type=float, default=0.02)
    ap.add_argument("--cwd", default=".")
    a = ap.parse_args(argv[:split])
    cmd = ["taskset", "-c", os.environ.get("SCALE_CPUS", "0-11")] + argv[split + 1:]
    env = dict(os.environ)
    env.setdefault("TMPDIR", "/home/epentland/.cache/mylang-tmp")
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd, cwd=a.cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    samples, peaks = [], {}
    import threading
    out_err = {}

    def drain(name, stream):
        out_err[name] = stream.read()
    th = [threading.Thread(target=drain, args=(n, s)) for n, s in (("out", p.stdout), ("err", p.stderr))]
    for t in th:
        t.start()
    while p.poll() is None:
        kids = children_map()
        todo, seen, row = [p.pid], set(), []
        while todo:
            q = todo.pop()
            if q in seen:
                continue
            seen.add(q)
            name, rss = rss_of(q)
            if name:
                row.append((name, rss))
            todo.extend(kids.get(q, []))
        now = round(time.perf_counter() - t0, 3)
        total = sum(r for _, r in row)
        samples.append([now, total, row])
        for name, rss in row:
            if rss > peaks.get(name, (0, 0))[0]:
                peaks[name] = (rss, now)
        time.sleep(a.interval)
    for t in th:
        t.join()
    wall = time.perf_counter() - t0
    phases = []
    for line in (out_err.get("err", b"") + out_err.get("out", b"")).decode(errors="replace").splitlines():
        if line.startswith('{"version":"phase-timings-v1"'):
            d = json.loads(line)
            phases.append([d["name"], round(d["duration_ns"] / 1e9, 4), d.get("counts", {})])
    res = {"cmd": argv[split + 1:], "rc": p.returncode, "wall_s": round(wall, 3), "load": os.getloadavg()[0],
           "peak_total_kb": max((s[1] for s in samples), default=0),
           "peaks_kb": {k: {"rss_kb": v[0], "at_s": v[1]} for k, v in sorted(peaks.items(), key=lambda kv: -kv[1][0])},
           "phases": phases, "samples": [[s[0], s[1]] for s in samples]}
    json.dump(res, open(a.out, "w"))
    print(json.dumps({k: res[k] for k in ("rc", "wall_s", "load", "peak_total_kb", "peaks_kb")}))
    if out_err.get("out") and len(out_err["out"]) < 200:
        print(out_err["out"].decode(errors="replace"))


if __name__ == "__main__":
    main()
