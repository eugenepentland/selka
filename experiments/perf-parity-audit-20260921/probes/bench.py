#!/usr/bin/env python3
"""Interleaved wall-clock timing: bench.py --cpu N --rounds R --warmups W name=cmd... ; stdout to /dev/null, checks stdout hash equality."""
import argparse, hashlib, random, statistics, subprocess, sys, time, shlex, json
p=argparse.ArgumentParser(); p.add_argument("--cpu",type=int,default=8); p.add_argument("--rounds",type=int,default=15); p.add_argument("--warmups",type=int,default=3); p.add_argument("--json"); p.add_argument("arms",nargs="+")
a=p.parse_args()
arms=[(x.split("=",1)[0], shlex.split(x.split("=",1)[1])) for x in a.arms]
hashes={}
for name,cmd in arms:
    out=subprocess.run(["taskset","-c",str(a.cpu)]+cmd,capture_output=True,check=True).stdout
    hashes[name]=hashlib.md5(out).hexdigest()
samples={n:[] for n,_ in arms}
def run(cmd):
    s=time.perf_counter(); subprocess.run(["taskset","-c",str(a.cpu)]+cmd,stdout=subprocess.DEVNULL,check=True); return (time.perf_counter()-s)*1000
order=list(range(len(arms)))
for r in range(a.warmups+a.rounds):
    random.shuffle(order)
    for i in order:
        t=run(arms[i][1])
        if r>=a.warmups: samples[arms[i][0]].append(t)
ref=arms[0][0]; refmed=statistics.median(samples[ref])
print(f"{'arm':22s} {'median':>9s} {'min':>9s} {'x/'+ref:>9s}  md5")
res={}
for name,_ in arms:
    med=statistics.median(samples[name]); mn=min(samples[name])
    res[name]={"median_ms":med,"min_ms":mn,"ratio":med/refmed,"md5":hashes[name],"samples":samples[name]}
    print(f"{name:22s} {med:9.3f} {mn:9.3f} {med/refmed:9.2f}  {hashes[name][:8]}")
if a.json: json.dump(res,open(a.json,"w"),indent=1)
