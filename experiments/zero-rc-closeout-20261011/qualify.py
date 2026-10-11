#!/usr/bin/env python3
"""Qualify migrated standard fixtures and source tasks against a frozen compiler."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as common
spec = importlib.util.spec_from_file_location('prior_matrix', HERE.parent/'zero-rc-final-20261011/measure.py')
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)

def call(argv, env, directory, label, expected=0):
    start=time.perf_counter_ns()
    result=subprocess.run(list(map(str,argv)),cwd=ROOT,env=env,capture_output=True,text=True,timeout=300)
    (directory/(label+'.stderr')).write_text(result.stderr)
    (directory/(label+'.stdout')).write_text(result.stdout)
    record={'argv':list(map(str,argv)), 'status':result.returncode,'elapsed_ns':time.perf_counter_ns()-start,'stdout':result.stdout,'stderr':result.stderr}
    (directory/(label+'.json')).write_text(json.dumps(record,indent=2)+'\n')
    assert result.returncode==expected,record
    return record

def lane(a,env,name,source,flags,mode,expected,answer=None,threads=('1',)):
    d=a.output/name/mode;d.mkdir(parents=True,exist_ok=True)
    main=d/'main.my';main.write_bytes(source.read_bytes())
    binary=d/'program';llvm=d/'program.ll'
    zero='--experimental-zero-rc' in flags
    sanitized=mode=='tsan'
    local=dict(env,**({'MYLANG_CORE_SANITIZE':'thread'} if sanitized else {}))
    build=call([a.compiler,'build',main,'--zig',a.zig,'--cache-dir',a.output/'cache',*flags,*([] if sanitized else ['--counters']),'-o',binary,'--emit-llvm',llvm],local,d,'build')
    if zero:
        prior.clean_ir(llvm)
        symbols=subprocess.run(['nm',binary],capture_output=True,text=True,check=True).stdout
        assert not any(s in symbols for s in ('myl_core_retain','myl_core_release','myl_core_share')),name
    runs={}
    for thread in threads:
        counts=d/('counts-'+thread+'.json')
        ran=call([binary],dict(local,MYLANG_THREADS=thread,MYLANG_COUNTERS=str(counts)),d,'run-'+thread,expected)
        assert not ran['stderr'],ran
        if answer is not None:assert ran['stdout']==answer,ran
        if not sanitized:
            audit=common.audit.audit(counts)
            assert audit['managed_leak_free'] and (not zero or audit['observed_rc_free']),audit
            ran['audit']=audit
            ran['memory']=common.census.summarize(json.loads(counts.read_text()))['whole_program']
        runs[thread]=ran
    return {'compiler_sha256':common.digest(a.compiler),'source_sha256':common.digest(main),'binary_sha256':common.digest(binary),'llvm_sha256':common.digest(llvm),'build_ns':build['elapsed_ns'],'runs':runs}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('compiler','zig','output'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--suite',choices=('library','tasks','regression'),required=True)
    a=p.parse_args()
    for name in ('compiler','zig','output'):setattr(a,name,getattr(a,name).resolve())
    a.output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,ZIG=str(a.zig),MYLANG_ZIG=str(a.zig),MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS','MYLANG_OPTIONS','MYLANG_CORE_SANITIZE'):env.pop(key,None)
    result={'compiler_sha256':common.digest(a.compiler),'harness_sha256':common.digest(__file__),'cases':{}}
    if a.suite=='regression':
        for name,source,answers in prior.sources():
            result['cases'][name]={mode:prior.lane(a,env,source,answers,name,mode,flags) for mode,flags in common.MODES.items()}
            common.save(a.output/'results.json',result);print('pass',name,flush=True)
    elif a.suite=='library':
        for original in sorted((ROOT/'src/stdlib/fixtures').glob('*.my')):
            name=original.stem
            if name=='time_random_provider':continue
            migrated=HERE/'samples'/original.name
            source=migrated if migrated.exists() else original
            expected=0 if name=='time_random' else 42
            modes={mode:lane(a,env,name,source,['--experimental-zero-rc',*flags],mode,expected) for mode,flags in common.MODES.items()}
            modes['rc']=lane(a,env,name,original,['--release'],'rc',expected)
            result['cases'][name]=modes
            common.save(a.output/'results.json',result);print('pass',name,flush=True)
    else:
        for name,answer in [('parallel_map','2016 item-0! 16\n'),('parallel_outcome','416\n')]:
            source=HERE/'samples'/(name+'.my')
            modes={mode:lane(a,env,name,source,['--experimental-zero-rc',*flags],mode,0,answer,('1','2','8')) for mode,flags in common.MODES.items()}
            modes['tsan']=lane(a,env,name,source,['--experimental-zero-rc','--release'],'tsan',0,answer,('1','2','8'))
            modes['rc']=lane(a,env,name,source,['--release'],'rc',0,answer)
            result['cases'][name]=modes
            common.save(a.output/'results.json',result);print('pass',name,flush=True)
    assert result['compiler_sha256']==common.digest(a.compiler)
    common.save(HERE/(a.suite+'.json'),result)
if __name__=='__main__':main()
