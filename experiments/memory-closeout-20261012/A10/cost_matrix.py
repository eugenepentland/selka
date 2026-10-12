#!/usr/bin/env python3
"""Cost source-refusal/cache checks, under shared admission."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

p=argparse.ArgumentParser()
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--scratch',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--default',action='store_true')
a=p.parse_args()
compiler=a.compiler.resolve()
compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
root=Path(__file__).resolve().parent
cache=a.scratch.resolve()/'cache'
rows=[]
def run(name, source, flags, expected=0, owned=True):
    args=[str(compiler),'cost',str(root/'fixtures'/source),'--json','--cache-dir',str(cache),*flags]
    if owned and not a.default: args.append('--experimental-zero-rc')
    r=subprocess.run(args,text=True,capture_output=True)
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_hash:
        raise RuntimeError("compiler changed during qualification")
    passed=r.returncode==expected
    if expected==1: passed=passed and 'E_SINGLE_OWNER_MOVED' in r.stderr
    if expected==0:
        j=json.loads(r.stdout)
        passed=passed and bool(j['functions'])
    rows.append(dict(name=name,argv=args,status=r.returncode,expected=expected,passed=passed,stdout=r.stdout,stderr=r.stderr))
for name,flags in [('debug',['--debug']),('release',[]),('no-facts',['--no-facts']),('verified',['--verify-facts'])]:
    run(name,'guest_tests.my',flags)
run('warm','guest_tests.my',[])
if not a.default: run('prior-rc-control','invalid_move.my',[],owned=False)
run('invalid-cold','invalid_move.my',[],expected=1)
run('invalid-warm','invalid_move.my',[],expected=1)
result=dict(default=a.default,compiler=str(compiler),compiler_sha256=compiler_hash,results=rows,success=all(r['passed'] for r in rows))
a.output.write_text(json.dumps(result,indent=2)+'\n')
for row in rows: print(row['name'],row['status'],'PASS' if row['passed'] else 'FAIL',flush=True)
raise SystemExit(0 if result['success'] else 1)
