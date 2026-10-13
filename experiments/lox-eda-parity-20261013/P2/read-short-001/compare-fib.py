#!/usr/bin/env python3
"""Prepared bounded diagnostic; run only in a coordinator-authorized timing lease."""
import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd();out=root/'experiments/lox-eda-parity-20261013/P2/read-short-001/fib-diagnostic.json'
compiler=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang')
binaries={'baseline':Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-001/lox/zero-rc'),'short':root/'.tmp/lox-eda-parity/P2/read-short-001/candidate'}
pins={'baseline':'8b6cb98665c289b963c8ced786235d9a2023ce5981a3c0cf366c24253fd19ea5','short':'64895849dbe5a723eae4fff1838f6f781af243b3b187ae6349ad24b1deeda5b0'}
source=root/'experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-fib.lox'
assert hashlib.sha256(compiler.read_bytes()).hexdigest()=='955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='e5c412ecb35cb4bcda97ac05f47f7cd8267f23deb0403bc5dd31126980216f45'
assert sorted(os.sched_getaffinity(0))==[8]
receipt={'label':'bounded short-fusion diagnostic; full identical fib input; no Zig parity claim','cpu_affinity':[8],'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'binary_sha256':pins,'candidate_manifest_sha256':hashlib.sha256((root/'experiments/lox-eda-parity-20261013/P2/read-short-001/candidate-source-manifest.json').read_bytes()).hexdigest(),'warmups':[],'samples':[],'status':'running'}
for stage,pairs in [('warmups',2),('samples',9)]:
 for pair in range(pairs):
  order=['baseline','short'] if pair%2==0 else ['short','baseline']
  for arm in order:
   assert hashlib.sha256(binaries[arm].read_bytes()).hexdigest()==pins[arm]
   begin=time.perf_counter();p=subprocess.run([str(binaries[arm]),'--engine=vm',str(source)],capture_output=True,timeout=8);elapsed=time.perf_counter()-begin
   assert p.returncode==0 and p.stdout==b'5702887\n' and p.stderr==b'',(arm,p.returncode,p.stdout,p.stderr)
   receipt[stage].append({'pair':pair,'arm':arm,'elapsed_seconds':elapsed,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'status':p.returncode})
   out.write_text(json.dumps(receipt,indent=2)+'\n')
receipt['status']='complete';out.write_text(json.dumps(receipt,indent=2)+'\n');print('complete')
