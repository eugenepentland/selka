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
def save(): (HERE/'qualification-commands.json').write_text(json.dumps(records,indent=2)+'\n')
def run(name,cmd,env,check=True):
    r=subprocess.run(list(map(str,cmd)),env=env,capture_output=True,timeout=1200)
    (HERE/(name+'.stdout')).write_bytes(r.stdout);(HERE/(name+'.stderr')).write_bytes(r.stderr)
    row={'name':name,'command':list(map(str,cmd)),'status':r.returncode};records.append(row);save()
    print(name,r.returncode,flush=True)
    if check: assert r.returncode==0,r.stderr.decode(errors='replace')
    return r
modes={'rc-debug':[],'rc-release':['--release'],'zero-debug':['--experimental-zero-rc'],'zero-release':['--experimental-zero-rc','--release'],'zero-verify':['--experimental-zero-rc','--release','--verify-facts']}
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
    run(arm+'-lox-build',[compiler,'build',HERE/'guest/lox/main.my','--experimental-zero-rc','--release','--cache-dir',WORK/arm/'cache','-o',WORK/arm/'lox','--emit-llvm',WORK/arm/'lox.ll'],env)
    if arm=='candidate':
        result=run('candidate-all103',[compiler,'test',HERE/'guest/lox','--experimental-zero-rc','--release','--verify-facts','--jobs','4','--max-steps','1000000000','--max-frames','40000','--max-memory','2G','--timeout-ms','120000','--cache-dir',WORK/'test-cache','--json'],env)
        data=json.loads(result.stdout)
        (HERE/'candidate-all103.json').write_text(json.dumps(data,indent=2)+'\n')
        print('TEST_JSON',data.get('summary',data.get('counts')),flush=True)
print('PASS matched fixtures across five modes; full Lox declarations JSON retained',flush=True)
