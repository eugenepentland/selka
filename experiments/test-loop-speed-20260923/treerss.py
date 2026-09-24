#!/usr/bin/env python3
"""treerss.py CMD...: run CMD and report the peak summed RSS of its whole process tree."""
import os, subprocess, sys, time

def tree_rss(root):
    kids = {}
    rss = {}
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/stat') as f:
                st = f.read().rsplit(')', 1)[1].split()
            kids.setdefault(int(st[1]), []).append(int(pid))
            rss[int(pid)] = int(st[21]) * 4096
        except Exception:
            pass
    total, count, stack = 0, 0, [root]
    while stack:
        p = stack.pop()
        total += rss.get(p, 0)
        count += 1
        stack.extend(kids.get(p, []))
    return total, count

start = time.time()
proc = subprocess.Popen(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
peak, peak_n = 0, 0
while proc.poll() is None:
    t, n = tree_rss(proc.pid)
    if t > peak:
        peak, peak_n = t, n
    time.sleep(0.05)
err = proc.stderr.read().decode(errors='replace')
print(f'rc={proc.returncode} elapsed={time.time()-start:.1f}s peak_tree_rss={peak/2**20:.0f}MiB procs_at_peak={peak_n} :: {" ".join(sys.argv[1:])[:100]}')
if proc.returncode:
    print(err[-2000:])
