#!/usr/bin/env python3
"""Run a command and sample address space against resident memory for it and its children.

usage: vmprobe.py OUT.json -- CMD...

Every 50 ms: VmSize, VmRSS and VmPeak of each live process in the command's tree.
Whenever a process reaches a new VmSize high, its /proc/PID/smaps is summarized:
the 25 largest mappings by size with their resident bytes, and totals by kind
(anonymous, file-backed, stack), so address space that is reserved but never
touched shows up next to the mapping that holds it.
"""
import json
import os
import subprocess
import sys
import time


def status(pid):
    out = {}
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                key, _, value = line.partition(":")
                if key in ("VmSize", "VmRSS", "VmPeak", "VmHWM", "Threads", "Name"):
                    out[key] = value.strip()
    except OSError:
        return None
    return out


def kb(text):
    return int(text.split()[0]) if text else 0


def children(pid):
    try:
        with open(f"/proc/{pid}/task/{pid}/children") as f:
            return [int(x) for x in f.read().split()]
    except OSError:
        return []


def tree(pid):
    todo, seen = [pid], []
    while todo:
        p = todo.pop()
        seen.append(p)
        todo.extend(children(p))
    return seen


def smaps(pid):
    maps = []
    current = None
    try:
        with open(f"/proc/{pid}/smaps") as f:
            for line in f:
                parts = line.split()
                if "-" in parts[0] and len(parts) >= 5 and ":" not in parts[0]:
                    start, end = (int(x, 16) for x in parts[0].split("-"))
                    current = {"size_kb": (end - start) // 1024, "perm": parts[1], "path": parts[5] if len(parts) > 5 else "[anon]", "rss_kb": 0}
                    maps.append(current)
                elif parts[0] == "Rss:" and current is not None:
                    current["rss_kb"] = int(parts[1])
    except OSError:
        return None
    totals = {}
    for m in maps:
        kind = m["path"] if m["path"].startswith("[") else ("file" if m["path"].startswith("/") else "[anon]")
        t = totals.setdefault(kind, {"size_kb": 0, "rss_kb": 0, "count": 0})
        t["size_kb"] += m["size_kb"]
        t["rss_kb"] += m["rss_kb"]
        t["count"] += 1
    maps.sort(key=lambda m: -m["size_kb"])
    return {"totals": totals, "largest": maps[:25], "count": len(maps)}


def main():
    out_path = sys.argv[1]
    command = sys.argv[sys.argv.index("--") + 1:]
    start = time.perf_counter()
    proc = subprocess.Popen(command)
    samples, peaks, highs = [], {}, {}
    while proc.poll() is None:
        now = round(time.perf_counter() - start, 3)
        for pid in tree(proc.pid):
            s = status(pid)
            if not s:
                continue
            size, rss = kb(s.get("VmSize")), kb(s.get("VmRSS"))
            samples.append([now, pid, s.get("Name"), size, rss])
            if size > highs.get(pid, 0) + 262144:  # re-summarize every 256 MB of growth
                highs[pid] = size
                snap = smaps(pid)
                if snap:
                    peaks[pid] = {"t": now, "name": s.get("Name"), "vmsize_kb": size, "rss_kb": rss, "smaps": snap}
        time.sleep(0.05)
    result = {"command": command, "status": proc.returncode, "wall_s": round(time.perf_counter() - start, 3),
              "max_vmsize_kb": max((s[3] for s in samples), default=0), "max_rss_kb": max((s[4] for s in samples), default=0),
              "peaks": peaks, "samples": samples[::4]}
    with open(out_path, "w") as f:
        json.dump(result, f)
    print(json.dumps({k: result[k] for k in ("status", "wall_s", "max_vmsize_kb", "max_rss_kb")}))
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
