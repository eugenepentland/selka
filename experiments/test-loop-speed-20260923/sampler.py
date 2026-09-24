#!/usr/bin/env python3
"""usage: sampler.py OUT WORKTREE

Wait for a `zig build` whose working directory is WORKTREE, sample its process
tree every 0.5 s until it exits, and write a timeline to OUT: first seen, last
seen, duration and a label for every process."""
import os, sys, time, re

out = sys.argv[1]
root_pat = sys.argv[2]

def procs():
    res = {}
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/stat') as f:
                st = f.read()
            ppid = int(st.rsplit(')', 1)[1].split()[1])
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='replace').strip()
            res[int(pid)] = (ppid, cmd)
        except Exception:
            pass
    return res

def label(cmd):
    c = cmd
    if '--guardian-shard' in c:
        m = re.search(r'/([^/ ]+) .*--guardian-shard=(\S+)', c)
        return f'shard {m.group(1)} {m.group(2)}' if m else c[:120]
    if ' build-exe ' in c or ' test ' in c and '/zig ' in c or ' build-obj' in c or ' build-lib' in c:
        m = re.search(r'--name (\S+)', c)
        kind = 'zig-test' if ' test ' in c else 'zig-build'
        return f'{kind} {m.group(1) if m else c[:80]}'
    return c[:160]

seen = {}
start = time.time()
build_pid = None
while True:
    ps = procs()
    if build_pid is None or build_pid not in ps:
        cands = []
        for p, (pp, c) in ps.items():
            parts = c.split(' ')
            if len(parts) > 1 and parts[0].endswith(('zig', 'maker')) and parts[1] == 'build':
                try:
                    if os.readlink(f'/proc/{p}/cwd') == root_pat:
                        cands.append(p)
                except Exception:
                    pass
        if build_pid is not None and build_pid not in ps:
            break
        if cands:
            build_pid = min(cands)
            start = time.time()
        else:
            time.sleep(0.2)
            if time.time() - start > 3600:
                break
            continue
    # descendants of build_pid
    kids = {}
    for p, (pp, c) in ps.items():
        kids.setdefault(pp, []).append(p)
    stack = list(kids.get(build_pid, []))
    now = time.time() - start
    while stack:
        p = stack.pop()
        if True:
            key = (p, label(ps[p][1]))
            if key not in seen:
                seen[key] = [now, now]
            else:
                seen[key][1] = now
        stack.extend(kids.get(p, []))
    time.sleep(0.5)

with open(out, 'w') as f:
    for (p, lab), (a, b) in sorted(seen.items(), key=lambda kv: kv[1][0]):
        f.write(f'{a:7.1f} {b:7.1f} {b-a:6.1f}  {lab}\n')
