#!/usr/bin/env python3
"""Emit diagnostic IL for exact frozen source; frame/step drops are IL-only."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('label',choices=['control','equal','equal-qualified'])
a=p.parse_args()
lane=Path(__file__).resolve().parents[2]
work=lane/'.tmp-lox-vm-stack-read-20261003'
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
source=work/a.label
sha=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
env=dict(os.environ,TMPDIR=str(work/'tmp'))
argv=[str(lane/'scripts/build-slot.sh'),'build',str(compiler),'emit-project-qbe',str(source/'main.my'),'--rc-runtime','--drop-step-checks','--drop-frame-checks','--cache-dir='+str(work/('cache-emission-'+a.label))]
stdout,stderr=work/(a.label+'-emission.json'),work/(a.label+'-emission.stderr')
with stdout.open('xb') as out,stderr.open('xb') as err:
    run=subprocess.run(argv,cwd=lane,env=env,stdout=out,stderr=err,timeout=900)
receipt={'argv':argv,'cwd':str(lane),'environment':{'TMPDIR':env['TMPDIR']},'status':run.returncode,'compiler_sha256':sha(compiler),'qbe_sha256':sha(compiler.with_name('qbe')),'source_sha256':{str(f.relative_to(source)):sha(f) for f in sorted(source.rglob('*')) if f.is_file()},'stdout':str(stdout),'stdout_sha256':sha(stdout),'stderr':str(stderr),'stderr_sha256':sha(stderr),'scope':'Diagnostic IL only; production builds retain native frame/bounds/overflow/COW checks.'}
(work/(a.label+'-emission-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
assert run.returncode==0,stderr.read_text()
