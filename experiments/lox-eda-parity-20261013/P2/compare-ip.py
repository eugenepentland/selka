import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd(); out=root/'experiments/lox-eda-parity-20261013/P2/ip-diagnostic.json'
binaries={name:root/'.tmp/lox-eda-parity/P2'/name for name in ['api','ip']}
source=root/'experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-fib.lox'
compiler=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
receipt={'label':'bounded diagnostic; full identical fib input; not full application qualification or Zig parity claim','cpu_affinity':sorted(os.sched_getaffinity(0)),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'binary_sha256':{n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in binaries.items()},'warmups':[],'samples':[],'status':'running'}
for stage,pairs in [('warmups',2),('samples',9)]:
 for pair in range(pairs):
  order=['api','ip'] if pair%2==0 else ['ip','api']
  for name in order:
   begin=time.perf_counter(); p=subprocess.run([str(binaries[name]),'--engine=vm',str(source)],capture_output=True,timeout=8);elapsed=time.perf_counter()-begin
   assert p.returncode==0 and p.stdout==b'5702887\n' and p.stderr==b'',(name,p.returncode,p.stdout,p.stderr)
   receipt[stage].append({'pair':pair,'arm':name,'elapsed_seconds':elapsed,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'status':p.returncode})
   out.write_text(json.dumps(receipt,indent=2)+'\n')
receipt['status']='complete';out.write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
