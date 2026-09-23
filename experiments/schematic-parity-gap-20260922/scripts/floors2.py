#!/usr/bin/env python3
"""Interleaved timing of arbitrary commands with one shared environment (no exec wrapper).
usage: floors2.py --out f.json --rounds 31 --env K=V ... -- name=cmd name=cmd ..."""
import argparse, json, os, random, shlex, statistics, subprocess, time

ap = argparse.ArgumentParser(); ap.add_argument('--out', required=True); ap.add_argument('--rounds', type=int, default=31)
ap.add_argument('--warmups', type=int, default=3); ap.add_argument('--cpu', type=int, default=6); ap.add_argument('--env', action='append', default=[])
ap.add_argument('arms', nargs='+')
a = ap.parse_args()
arms = [(x.split('=', 1)[0], shlex.split(x.split('=', 1)[1])) for x in a.arms]
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_')}
env['MYLANG_MEMORY_LIMIT'] = '268435456'
for item in a.env:
    k, v = item.split('=', 1); env[k] = v


def run(cmd):
    s = time.perf_counter_ns()
    r = subprocess.run(['taskset', '-c', str(a.cpu), *cmd], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env)
    t = (time.perf_counter_ns() - s) / 1e6
    assert r.returncode == 0, (cmd, r.returncode, r.stderr[:300])
    return t


samples = {n: [] for n, _ in arms}
rng = random.Random(20260922)
order = list(range(len(arms)))
for r in range(a.warmups + a.rounds):
    rng.shuffle(order)
    for i in order:
        t = run(arms[i][1])
        if r >= a.warmups:
            samples[arms[i][0]].append(t)
res = {}
for name, cmd in arms:
    s = sorted(samples[name])
    res[name] = {'median_ms': statistics.median(s), 'min_ms': s[0], 'p10_ms': s[int(0.1 * (len(s) - 1))], 'p90_ms': s[int(0.9 * (len(s) - 1))], 'cmd': cmd, 'samples': samples[name]}
    print(f"{name:26s} median {res[name]['median_ms']:7.3f}  min {res[name]['min_ms']:7.3f}  p10 {res[name]['p10_ms']:7.3f}  p90 {res[name]['p90_ms']:7.3f}")
json.dump(res, open(a.out, 'w'), indent=1)
