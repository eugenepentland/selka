import hashlib,json,os,subprocess,sys,time
from pathlib import Path
root=Path.cwd();lease=int(sys.argv[1]);out=root/'experiments/lox-eda-parity-20261013/P2/equality-diagnostic.json'
binaries={name:root/'.tmp/lox-eda-parity/P2'/name for name in ['api','fused']}
source=root/'experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-equality.lox'
compiler=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
if lease==1:
 receipt={'label':'bounded diagnostic; full identical equality input; not full application qualification or Zig parity claim','cpu_affinity':sorted(os.sched_getaffinity(0)),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'binary_sha256':{n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in binaries.items()},'warmups':[],'samples':[],'leases':[],'status':'running'}
else: receipt=json.loads(out.read_text())
receipt['leases'].append({'lease':lease,'warmup_pairs':2,'measured_pairs':5 if lease==1 else 4,'cpu_affinity':sorted(os.sched_getaffinity(0))})
for stage,pairs in [('warmups',list(range(2))),('samples',list(range(5)) if lease==1 else list(range(5,9)))]:
 for pair in pairs:
  order=['api','fused'] if pair%2==0 else ['fused','api']
  for name in order:
   assert hashlib.sha256(binaries[name].read_bytes()).hexdigest()==receipt['binary_sha256'][name]
   begin=time.perf_counter();p=subprocess.run([str(binaries[name]),'--engine=vm',str(source)],capture_output=True,timeout=8);elapsed=time.perf_counter()-begin
   assert p.returncode==0 and p.stdout==b'3000000\n' and p.stderr==b'',(name,p.returncode,p.stdout,p.stderr)
   receipt[stage].append({'lease':lease,'pair':pair,'arm':name,'elapsed_seconds':elapsed,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'status':p.returncode})
   out.write_text(json.dumps(receipt,indent=2)+'\n')
receipt['status']='complete' if lease==2 else 'lease1_complete';out.write_text(json.dumps(receipt,indent=2)+'\n');print(receipt['status'])
