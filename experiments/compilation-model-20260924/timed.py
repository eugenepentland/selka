#!/usr/bin/env python3
"""Run one command pinned to the P-cores under /usr/bin/time and print one JSON line.

usage: timed.py [--cwd DIR] [--cpus 0-11] [--out FILE] [--err FILE] -- CMD...

The line holds wall seconds, peak RSS (KB, the largest single process in the tree as
/usr/bin/time reports it for the waited child), user/sys CPU of the whole tree, the
1-minute load average before and after, and the exit status. stdout/stderr of the
command go to --out/--err (default: discarded / kept in the JSON tail on failure).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

TIME = "/usr/bin/time"


def main():
    argv = sys.argv[1:]
    if "--" not in argv:
        sys.exit("usage: timed.py [opts] -- CMD...")
    split = argv.index("--")
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--cpus", default=os.environ.get("SCALE_CPUS", "0-11"))
    ap.add_argument("--out")
    ap.add_argument("--err")
    ap.add_argument("--label", default="")
    a = ap.parse_args(argv[:split])
    cmd = argv[split + 1:]
    env = dict(os.environ)
    env.setdefault("TMPDIR", "/home/epentland/.cache/mylang-tmp")
    fmt = "__T__ %e %M %U %S"
    wrapped = ["taskset", "-c", a.cpus, TIME, "-f", fmt] + cmd
    load0 = os.getloadavg()[0]
    t = time.perf_counter()
    p = subprocess.run(wrapped, cwd=a.cwd, env=env, capture_output=True)
    wall = time.perf_counter() - t
    load1 = os.getloadavg()[0]
    err = p.stderr.decode(errors="replace")
    m = re.search(r"__T__ ([\d.]+) (\d+) ([\d.]+) ([\d.]+)", err)
    err_clean = re.sub(r"__T__ [^\n]*\n?", "", err)
    if a.out:
        with open(a.out, "wb") as f:
            f.write(p.stdout)
    if a.err:
        with open(a.err, "w") as f:
            f.write(err_clean)
    rec = {
        "label": a.label,
        "wall_s": round(wall, 4),
        "max_rss_kb": int(m.group(2)) if m else None,
        "user_s": float(m.group(3)) if m else None,
        "sys_s": float(m.group(4)) if m else None,
        "rc": p.returncode,
        "load": [round(load0, 2), round(load1, 2)],
    }
    if p.returncode != 0:
        rec["tail"] = (p.stdout.decode(errors="replace") + err_clean)[-1200:]
    print(json.dumps(rec), flush=True)


if __name__ == "__main__":
    main()
