#!/usr/bin/env python3
"""What a run beside the detached test seeder pays for the seeder's CPU.

usage: seeder_modes.py MYLANG TIER_DIR WORK_DIR [--repeats N] [--json OUT]

MYLANG is a compiler whose seeder runs at nice 19 and is not paused by a run
beside it (MODULE-TEST-6 before the pause). For each repeat and mode, a cold
`mylang test` of a fresh copy of TIER_DIR starts the seeder; the tool finds it
(a process whose environment has MYLANG_TEST_SEED=1 and this TMPDIR), puts
its process group in the mode, and times an unchanged run and then a run
after a body edit, both started at once:

- `nice19`: as built;
- `idle`: every process of the group moved to SCHED_IDLE (`chrt --idle`);
- `stopped`: the group stopped (SIGSTOP) for the two runs, then continued.

Finally it waits for the seeder (`settle_s`). TMPDIR must be set.
"""
import argparse
import json
import os
import signal
import subprocess
import time
from pathlib import Path

import measure


def seeders():
    scratch = os.environ["TMPDIR"].encode()
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            env = open(f"/proc/{pid}/environ", "rb").read()
        except OSError:
            continue
        if b"MYLANG_TEST_SEED=1\0" in env and scratch in env:
            found.append(int(pid))
    return found


def members(pgid):
    out = []
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                if os.getpgid(int(pid)) == pgid:
                    out.append(int(pid))
            except OSError:
                pass
    return out


def once(mylang, tier, work, mode):
    tree = measure.Tree(tier, work / "test")
    cache = tree.work / "cache"
    trace = tree.work / "trace.txt"
    command = [mylang, "test", "main.my", "--cache-dir", str(cache)]
    measure.run(command, tree.src, trace)
    pids = []
    for _ in range(100):
        pids = seeders()
        if pids:
            break
        time.sleep(0.01)
    group = os.getpgid(pids[0]) if pids else None
    if group and mode == "idle":
        for pid in members(group):
            subprocess.run(["chrt", "-a", "--idle", "-p", "0", str(pid)], capture_output=True)
    if group and mode == "stopped":
        os.killpg(group, signal.SIGSTOP)
    unchanged = measure.run(command, tree.src, trace)
    tree.body_edit()
    edited = measure.run(command, tree.src, trace)
    if group and mode == "stopped":
        os.killpg(group, signal.SIGCONT)
    return {"seeder": bool(pids), "unchanged": unchanged, "edit": edited, "settle_s": measure.settle(cache)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("tier")
    parser.add_argument("work")
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--json")
    args = parser.parse_args()
    mylang = str(Path(args.mylang).resolve())
    work = Path(args.work).resolve()
    results = {}
    for _ in range(args.repeats):
        for mode in ["nice19", "idle", "stopped"]:
            results.setdefault(mode, []).append(once(mylang, args.tier, work, mode))
    text = json.dumps(results, indent=1)
    if args.json:
        Path(args.json).write_text(text)
    print(text)


if __name__ == "__main__":
    main()
