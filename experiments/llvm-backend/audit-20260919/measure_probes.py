#!/usr/bin/env python3
"""Paired wall samples, separate perf samples; retain ALL raw observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from measure import bootstrap_ratio


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--work', required=True)
    p.add_argument('--arms', default='control,memset,words,stack,stack-memset,whole,whole-memset,whole-words,whole-stack-memset-words')
    p.add_argument('--out', required=True)
    p.add_argument('--rounds', type=int, default=31)
    p.add_argument('--counter-rounds', type=int, default=7)
    p.add_argument('--cpu', type=int, default=6)
    p.add_argument('--input', default='/tmp/rt2x')
    p.add_argument('--baseline', default='/tmp/final-measure')
    p.add_argument('--zig', default='/tmp/zb-out/bin/zig-bench')
    a = p.parse_args()
    os.sched_setaffinity(0, {a.cpu})
    arms = {'qbe': Path(a.baseline)/'qbe', 'original-llvm': Path(a.baseline)/'llvm-o2', 'zig': Path(a.zig)}
    arms.update({n: Path(a.work)/(n+'.bin') for n in a.arms.split(',')})
    workloads = {n+s: [str(Path(a.input)/f)] + (['--render'] if n=='render' else [])
                 for n in ['census','render'] for s,f in [('', 'input.sexp'), ('-large','input8.sexp')]}
    report = {'cpu':a.cpu, 'rounds':a.rounds, 'counter_rounds':a.counter_rounds,
              'arms':{n:{'path':str(f.resolve()),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for n,f in arms.items()},
              'inputs':{f:{'sha256':hashlib.sha256((Path(a.input)/f).read_bytes()).hexdigest()} for f in ['input.sexp','input8.sexp']},
              'workloads':{}, 'order':[], 'counter_order':[]}
    expected = {}
    for w,args in workloads.items():
        expected[w] = subprocess.check_output([str(arms['qbe']), *args])
        report['workloads'][w]={'output_bytes':len(expected[w]),'output_sha256':hashlib.sha256(expected[w]).hexdigest(),'arms':{}}
        for arm,b in arms.items():
            for _ in range(2):
                done = subprocess.run([str(b),*args],capture_output=True)
                assert done.returncode == 0 and not done.stderr and done.stdout == expected[w], (arm,w,done.stderr)
            report['workloads'][w]['arms'][arm]={'wall_ms':[], 'perf':[]}
    rng=random.Random(20260919)
    for i in range(a.rounds):
        order=[(w,n) for w in workloads for n in arms];rng.shuffle(order);report['order'].append(order)
        for w,n in order:
            t=time.perf_counter_ns();done=subprocess.run([str(arms[n]),*workloads[w]],capture_output=True)
            elapsed=(time.perf_counter_ns()-t)/1e6
            assert done.returncode==0 and not done.stderr and done.stdout==expected[w], (n,w)
            report['workloads'][w]['arms'][n]['wall_ms'].append(elapsed)
        if (i+1)%5==0: print('wall',i+1,flush=True)
    for i in range(a.counter_rounds):
        order=[(w,n) for w in workloads for n in arms];rng.shuffle(order);report['counter_order'].append(order)
        for w,n in order:
            done=subprocess.run(['perf','stat','-x;','-e','cpu_core/instructions/u,cpu_core/cycles/u,minor-faults,task-clock','--',str(arms[n]),*workloads[w]],capture_output=True)
            assert done.returncode==0 and done.stdout==expected[w], (n,w,done.stderr)
            vals={}
            for line in done.stderr.decode().splitlines():
                parts=line.split(';')
                if len(parts)>3 and parts[0].replace('.','',1).isdigit(): vals[parts[2]]=float(parts[0])
            assert 'cpu_core/instructions/u' in vals and 'cpu_core/cycles/u' in vals
            report['workloads'][w]['arms'][n]['perf'].append({'values':vals,'raw':done.stderr.decode()})
        print('counters',i+1,flush=True)
    for w,data in report['workloads'].items():
        print(w,flush=True)
        for n,bucket in data['arms'].items():
            bucket['median_ms']=statistics.median(bucket['wall_ms'])
            bucket['control_over_arm']=statistics.median(data['arms']['control']['wall_ms'])/bucket['median_ms']
            bucket['control_over_arm_ci95']=bootstrap_ratio(data['arms']['control']['wall_ms'],bucket['wall_ms'])
            bucket['counter_medians']={k:statistics.median(r['values'][k] for r in bucket['perf']) for k in bucket['perf'][0]['values']} if bucket['perf'] else {}
            print(n,round(bucket['median_ms'],3),round(bucket['control_over_arm'],3),flush=True)
    Path(a.out).write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
