#!/usr/bin/env python3
"""Strict old/new fixture supplement: status, JSON verdicts, stdout and leaks."""
import argparse, hashlib, json, os, shlex, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--old',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True);a=p.parse_args()
area=a.evidence.resolve();area.mkdir(parents=True,exist_ok=False)
records=[]
summary={'qualified':False,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'old_sha256':hashlib.sha256(a.old.read_bytes()).hexdigest(),'core_sha256':hashlib.sha256((root/'zig-out/bin/mylang-core').read_bytes()).hexdigest(),'commands':records}
try:
 for fixture in ('v_dynamic_repeat','v_nested_places','v_buffer_format','v_inline_loops','v_nested_lengths'):
  outputs=[]
  for role,compiler in (('old',a.old.resolve()),('new',root/'zig-out/bin/mylang-core')):
   modes=(('debug',[]),('release',['--release'])) if role=='old' else (('debug',[]),('release',['--release']),('verify',['--release','--verify-facts']))
   for mode,flags in modes:
    argv=[str(compiler),'test',str(root/f'test/core/{fixture}.my'),'--json','--cache-dir',str(root/f'.mylang-cache/s4-v/supplement/{area.name}/{role}-{mode}'),*flags]
    env={**os.environ,'MYL_CORE_LEAKCHECK':'1'}
    done=subprocess.run(argv,text=True,capture_output=True,env=env,timeout=120)
    log=area/f'command-{len(records)+1:04d}.log';log.write_text('$ '+shlex.join(argv)+'\nstdout='+repr(done.stdout)+'\nstderr='+repr(done.stderr)+f'\nexit={done.returncode}\n')
    report=json.loads(done.stdout)
    normalized=[(test['name'],test['status'],test.get('reason','')) for test in report['tests']]
    valid=done.returncode==0 and done.stderr=='' and report.get('passed')==1 and report.get('failed')==0 and report.get('unsupported',0)==0 and all(t[1]=='passed' for t in normalized)
    records.append({'fixture':fixture,'role':role,'mode':mode,'valid':valid,'outputs':normalized,'log':log.name})
    if not valid:raise RuntimeError(f'invalid supplement: {fixture}/{role}/{mode}')
    outputs.append(normalized)
  if any(out!=outputs[0] for out in outputs):raise RuntimeError('fixture verdict mismatch '+fixture)
  print(f'{fixture}: old debug/release and new debug/release/verify agree',flush=True)
 summary['qualified']=True
finally:(area/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
