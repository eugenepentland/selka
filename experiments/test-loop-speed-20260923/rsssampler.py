#!/usr/bin/env python3
"""rsssampler.py OUT WORKTREE: while the worktree's `zig build` runs, record for every
direct child of the build runner (one build step) the peak summed RSS of its process
tree, and the peak summed RSS of the whole build."""
import os, sys, time, re

out, root = sys.argv[1], sys.argv[2]

def snapshot():
    procs = {}
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/stat') as f:
                st = f.read().rsplit(')', 1)[1].split()
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='replace').strip()
            procs[int(pid)] = (int(st[1]), int(st[21]) * 4096, cmd)
        except Exception:
            pass
    return procs

def label(cmd):
    m = re.search(r'--guardian-shard=(\S+)', cmd)
    if m:
        return 'shard ' + m.group(1) + (' ' + cmd.split('/')[-1].split(' ')[0] if False else '') + ' ' + cmd.split(' ')[0][-40:]
    return cmd[:140]

build = None
peaks = {}
whole = 0
start = time.time()
while True:
    ps = snapshot()
    if build is None:
        for p, (pp, r, c) in ps.items():
            parts = c.split(' ')
            if len(parts) > 1 and parts[0].endswith(('zig', 'maker')) and parts[1] == 'build':
                try:
                    if os.readlink(f'/proc/{p}/cwd') == root:
                        build = p
                except Exception:
                    pass
        if build is None:
            if time.time() - start > 3600:
                break
            time.sleep(0.2)
            continue
    if build not in ps:
        break
    kids = {}
    for p, (pp, r, c) in ps.items():
        kids.setdefault(pp, []).append(p)
    total_all = 0
    for step in kids.get(build, []):
        total, stack = 0, [step]
        while stack:
            p = stack.pop()
            total += ps.get(p, (0, 0, ''))[1]
            stack.extend(kids.get(p, []))
        total_all += total
        key = label(ps[step][2])
        peaks[key] = max(peaks.get(key, 0), total)
    whole = max(whole, total_all)
    time.sleep(0.2)

with open(out, 'w') as f:
    f.write(f'whole build peak tree RSS: {whole/2**20:.0f} MiB\n')
    for k, v in sorted(peaks.items(), key=lambda kv: -kv[1]):
        f.write(f'{v/2**20:8.0f} MiB  {k}\n')
