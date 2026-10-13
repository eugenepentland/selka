#!/usr/bin/env python3
"""Approved bounded prototype diagnostics; each chunk owns one timing lease."""
import hashlib,json,os,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
MEASURE=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/lox-eda-parity-20261013/measure.py')
identity=json.loads((HERE/'identity.json').read_text())
assert hashlib.sha256(Path(identity['compiler']).read_bytes()).hexdigest()==identity['compiler_sha256']
for file,sha in identity['guest_files'].items():assert hashlib.sha256((HERE/'guest/lox'/file).read_bytes()).hexdigest()==sha
for arm,sha in identity['guest_binaries'].items():assert hashlib.sha256((ROOT/'.tmp/lox-eda-parity/P4/compact-sret-002'/arm/'lox').read_bytes()).hexdigest()==sha
counts=json.loads((HERE/'candidate-all103.json').read_text());assert counts['passed']==103 and all(counts[k]==0 for k in ('failed','skipped','unsupported','cached'))
dest=HERE/'diagnostics';dest.mkdir(exist_ok=False)
commands=[]
for case in ('fib','binary_trees','string_equality','vm_fib'):
 base=json.loads((HERE/'diagnostic-specs'/(case+'.json')).read_text())
 prior=None
 for chunk in range(3):
  spec=dict(base)
  if prior:spec['prior_receipt']=str(prior)
  frozen=dest/f'{case}.chunk{chunk}.spec.json';frozen.write_text(json.dumps(spec,indent=2)+'\n')
  output=dest/f'{case}.chunk{chunk}.json'
  command=[str(ROOT/'scripts/build-slot.sh'),'timing',sys.executable,'-B',str(MEASURE),str(frozen),str(output),'--cpu','8','--rounds','3','--round-start',str(chunk*3),'--warmups','2' if chunk==0 else '0','--rss-rounds','0','--guest-timeout','120','--zig-factor','3','--calibration-warmups','2','--calibration-rounds','5']
  with (dest/f'{case}.chunk{chunk}.log').open('x') as log:
   result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
  commands.append({'case':case,'chunk':chunk,'command':command,'returncode':result.returncode})
  (HERE/'timing-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
  assert result.returncode==0,(case,chunk)
  receipt=json.loads(output.read_text())
  for file,sha in receipt['identities'].items():assert hashlib.sha256(Path(file).read_bytes()).hexdigest()==sha
  prior=output
print('COMPLETE all12 approved diagnostic chunks; failed/censored statuses retained')
