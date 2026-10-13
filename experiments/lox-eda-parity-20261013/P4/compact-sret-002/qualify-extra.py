#!/usr/bin/env python3
"""Correctness qualification only; run under one ordinary build admission."""
import hashlib,json,os,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
WORK=ROOT/'.tmp/lox-eda-parity/P4/compact-sret-002'
BASE=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-002/install')
INSTALL=WORK/'install'
records=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(): (HERE/'extra-mode-commands.json').write_text(json.dumps(records,indent=2)+'\n')
def run(name,cmd,env,check=True):
    r=subprocess.run(list(map(str,cmd)),env=env,capture_output=True,timeout=1200)
    (HERE/(name+'.stdout')).write_bytes(r.stdout);(HERE/(name+'.stderr')).write_bytes(r.stderr)
    row={'name':name,'command':list(map(str,cmd)),'status':r.returncode};records.append(row);save()
    print(name,r.returncode,flush=True)
    if check: assert r.returncode==0,r.stderr.decode(errors='replace')
    return r
modes={'zero-unoptimized':['--experimental-zero-rc','--unoptimized'],'zero-optimize-debug':['--experimental-zero-rc','--optimize-debug'],'zero-release-no-facts':['--experimental-zero-rc','--release','--no-facts']}
controls={}
for arm,install in [('baseline',BASE),('candidate',INSTALL)]:
    env=dict(os.environ,MYLANG_COMPONENT_DIR=str(install/'libexec/mylang/components'),MYLANG_JOBS='4',MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS',None)
    compiler=install/'bin/mylang'
    for mode,flags in modes.items():
        for source in sorted((HERE/'fixtures').glob('*.my')):
            name=f'{arm}-{mode}-{source.stem}'
            out=WORK/'fixtures'/name;out.parent.mkdir(parents=True,exist_ok=True)
            run(name+'-build',[compiler,'build',source,*flags,'--cache-dir',WORK/'cache'/name,'-o',out,'--emit-llvm',str(out)+'.ll'],env)
            for args in ([[],['end']] if source.stem=='bounds' else [[]]):
                tag=name+('-end' if args else '')
                result=run(tag+'-run',[out,*args],env,check=False)
                key=(mode,source.stem,tuple(args))
                outcome=(result.returncode,result.stdout,result.stderr)
                if arm=='baseline': controls[key]=outcome
                else: assert outcome==controls[key],(tag,outcome,controls[key])

counts=json.loads((HERE/'candidate-all103.json').read_text())
assert counts['passed']==103 and all(counts[k]==0 for k in ('failed','skipped','unsupported','cached')),counts
env=dict(os.environ,MYL_CORE_LEAKCHECK='1')
run('candidate-corpus-gc',['python3',ROOT/'experiments/lox-eda-parity-20261013/fixtures/lox/harness/lox_bench.py','conformance','--binary',WORK/'candidate/lox','--engine','both','--stress','--jobs','4'],env)
for arm in ('baseline','candidate'):
    run(arm+'-llvm-verify',[os.environ['ZIG'],'cc','-c','-O0',WORK/arm/'lox.ll','-o',WORK/arm/'llvm-verified.o'],env)
print('PASS required five zero-RC modes plus RC controls;103 verified tests; corpus+GC; LLVM verifier',flush=True)
