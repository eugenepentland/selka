#!/usr/bin/env python3
"""Bounded correctness-only controls; no time or RSS comparison."""
import hashlib,json,os,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SCRATCH=ROOT/'.tmp/lox-eda-parity/P4/arithmetic-inline-001'
records=[]
for arm in ('baseline','candidate'):
 binary=SCRATCH/arm/'lox'
 for control in json.loads((HERE/'controls.json').read_text()):
  for stress in (False,True):
   command=[str(binary),'--engine=tree',*(['--gc-stress'] if stress else []),str(ROOT/control['source'])]
   result=subprocess.run(command,env=dict(os.environ,MYL_CORE_LEAKCHECK='1'),capture_output=True,timeout=30)
   name=control['name']+('-stress' if stress else '')
   dest=HERE/'control-results'/arm;dest.mkdir(parents=True,exist_ok=True)
   (dest/(name+'.stdout')).write_bytes(result.stdout);(dest/(name+'.stderr')).write_bytes(result.stderr)
   row={'arm':arm,'control':name,'command':command,'returncode':result.returncode,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256((ROOT/control['source']).read_bytes()).hexdigest(),'passed':result.returncode==control['status'] and result.stdout.decode()==control['stdout'] and result.stderr.decode()==control['stderr']}
   records.append(row);(HERE/'control-results.json').write_text(json.dumps(records,indent=2)+'\n')
   assert row['passed'],row
print('PASS',len(records),'bounded normal/stress correctness runs')
