#!/usr/bin/env python3
"""Compare owned-payload transfer against the merged compiler on identical sources."""
import argparse, importlib.util, json, os, statistics, subprocess, sys, time
from pathlib import Path
from types import SimpleNamespace
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('closeout', HERE.parent/'zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('before','after','zig','output'):
        p.add_argument('--'+key,type=Path,required=True)
    args = p.parse_args()
    for key in ('before','after','zig','output'):
        setattr(args,key,getattr(args,key).resolve())
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS','MYLANG_OPTIONS','MYLANG_CORE_SANITIZE'):
        env.pop(key,None)
    result = {'harness_sha256':q.common.digest(__file__), 'compilers':{}, 'cases':{}}
    for phase in ('before','after'):
        compiler = getattr(args,phase)
        result['compilers'][phase] = {'path':str(compiler),'sha256':q.common.digest(compiler)}
        a = SimpleNamespace(compiler=compiler,zig=args.zig,output=args.output/phase)
        cases = [('json',ROOT/'src/stdlib/fixtures/json.my',42,None),
                 ('json_nested',HERE/'samples/json_nested.my',0,'121000\n')]
        for name,source,status,answer in cases:
            lanes = {}
            for mode,flags in q.common.MODES.items():
                lanes[mode] = q.lane(a,env,name,source,['--experimental-zero-rc',*flags],mode,status,answer)
                print('pass',phase,name,mode,flush=True)
            result['cases'].setdefault(name,{})[phase] = lanes
            q.common.save(HERE/'results.json',result)
        # Timing has neither counters nor leak checking; allocation evidence is separate.
        d = a.output/'timing'; d.mkdir(parents=True,exist_ok=True)
        timing_env=dict(env);timing_env.pop('MYL_CORE_LEAKCHECK',None)
        q.call([compiler,'build',HERE/'samples/json_nested.my','--experimental-zero-rc','--release','--zig',args.zig,
                '--cache-dir',a.output/'cache','-o',d/'program'],timing_env,d,'build')
    result['timing']={'method':'2 warmup pairs then 9 alternating pairs, CPU 2, uninstrumented; shared host', 'before':[], 'after':[]}
    for repetition in range(11):
        for phase in (('before','after') if repetition%2==0 else ('after','before')):
            start=time.perf_counter_ns()
            run=subprocess.run(['taskset','-c','2',str(args.output/phase/'timing/program')],env=timing_env,capture_output=True,timeout=120)
            elapsed=time.perf_counter_ns()-start
            assert run.returncode==0 and run.stdout==b'121000\n' and not run.stderr,run
            if repetition>=2:result['timing'][phase].append(elapsed)
    result['summary']={}
    for name,phases in result['cases'].items():
        row={}
        for phase,lanes in phases.items():
            memory=lanes['release']['runs']['1']['memory']
            row[phase]={key:memory[key] for key in ('allocs','reallocs','peak_live_bytes','live_bytes_at_exit')}
            row[phase]['allocated_bytes']=memory['alloc_bytes']+memory['realloc_added_bytes']
        for metric in ('allocs','allocated_bytes','peak_live_bytes'):
            row[metric+'_reduction_percent']=100*(1-row['after'][metric]/row['before'][metric])
        result['summary'][name]=row
    result['timing']['median_ns']={phase:statistics.median(result['timing'][phase]) for phase in ('before','after')}
    result['timing']['speedup']=result['timing']['median_ns']['before']/result['timing']['median_ns']['after']
    for record in result['compilers'].values():assert record['sha256']==q.common.digest(record['path'])
    q.common.save(HERE/'results.json',result)
    print(json.dumps({'summary':result['summary'],'timing':result['timing']['median_ns'],'speedup':result['timing']['speedup']},indent=2),flush=True)

if __name__=='__main__':main()
