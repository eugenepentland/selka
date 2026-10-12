#!/usr/bin/env python3
"""Count map allocations at fixed sizes and workers; preserve every raw counter."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('a01_qualify',HERE/'qualify.py')
q=importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('compiler','zig','output'): p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--source-revision',required=True)
    a=p.parse_args()
    for key in ('compiler','zig','output'): setattr(a,key,getattr(a,key).resolve())
    a.output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ, ZIG=str(a.zig), MYLANG_ZIG=str(a.zig), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_CORE_SANITIZE','MYLANG_COUNTERS','MYLANG_OPTIONS'): env.pop(key,None)
    source=HERE/'samples/scaling.my';binary=a.output/'program';llvm=a.output/'program.ll'
    build=q.run([ROOT/'scripts/build-slot.sh','build',a.compiler,'build',source,'--experimental-zero-rc','--release','--counters','--zig',a.zig,'--cache-dir',a.output/'cache','--emit-llvm',llvm,'-o',binary],env)
    results={'source_revision':a.source_revision,'compiler_sha256':q.digest(a.compiler),'source_sha256':q.digest(source),'build':build,'runs':[]}
    def save(): (a.output/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    save()
    if build['status']: raise SystemExit(1)
    results['binary_sha256']=q.digest(binary);results['llvm_sha256']=q.digest(llvm)
    for n in (0,1,8,33,257,4097):
        for threads in (1,2,8):
            counts=a.output/('counts-'+str(n)+'-'+str(threads)+'.json')
            result=q.run([binary,str(n),'1','cheap'],dict(env,MYLANG_THREADS=str(threads),MYLANG_COUNTERS=str(counts)))
            result.update(size=n,threads=threads)
            result['passed']=result['status']==0 and result['stdout']==str(3*n*(n-1)//2+n)+'\n' and not result['stderr']
            if counts.exists():
                result['audit']=q._audit.audit(counts)
                result['counts_path']=counts.name
                result['passed'] &= result['audit']['observed_rc_free'] and result['audit']['managed_leak_free']
                data=json.loads(counts.read_text())
                result['whole_program']=data['totals']
                result['functions']=[{k:v for k,v in f.items() if k in ('name','allocs','alloc_bytes','reallocs','realloc_added_bytes','frees')} for f in data['functions']]
            results['runs'].append(result);save()
    raise SystemExit(not all(r['passed'] for r in results['runs']))

if __name__=='__main__': main()
