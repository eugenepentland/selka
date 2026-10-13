#!/usr/bin/env python3
"""Pinned diagnostic; run only inside coordinator-authorized CPU8 timing lease."""
import hashlib,json,os,signal,statistics,subprocess,time
from pathlib import Path
os.environ['DEBUGINFOD_URLS']=''
root=Path.cwd(); folder=root/'experiments/lox-eda-parity-20261013/P2/scalar-profile-001';assert sorted(os.sched_getaffinity(0))==[8]
r=json.loads((root/'experiments/lox-eda-parity-20261013/P2/reader-comparison-001/samples.json').read_text())
bins={'C1':Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-001/lox/zero-rc'),'scalar':root/'.tmp/lox-eda-parity/P2/scalar-ip-001/candidate','zig':Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/reference-binaries/lox-zig-fast')}
source=root/'experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-fib.lox';compiler=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang')
assert hashlib.sha256(source.read_bytes()).hexdigest()==r['input_sha256']
assert hashlib.sha256(compiler.read_bytes()).hexdigest()==r['compiler_sha256']
for arm,p in bins.items():assert hashlib.sha256(p.read_bytes()).hexdigest()==r['binary_sha256'][arm]
receipt={'label':'diagnostic CPU attribution, not timing benefit','compiler_sha256':r['compiler_sha256'],'input_sha256':r['input_sha256'],'binary_sha256':r['binary_sha256'],'cpu':[8],'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'DEBUGINFOD_URLS':'','zig':[],'profiles':[]}
def save(): (folder/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
for i in range(7):
 begin=time.perf_counter();p=subprocess.run([str(bins['zig']),'--engine=vm',str(source)],capture_output=True,timeout=120)
 assert (p.returncode,p.stdout,p.stderr)==(0,b'5702887\n',b'')
 receipt['zig'].append({'stage':'warmup' if i<2 else 'measured','seconds':time.perf_counter()-begin});save()
cutoff=min(120,3*statistics.median(x['seconds'] for x in receipt['zig'][2:]));receipt['guest_cutoff_seconds']=cutoff;save()
for arm in ['C1','scalar']:
 perf_log=(folder/(arm+'.perf.log')).open('wb')
 guest_stderr=folder/(arm+'.guest.stderr')
 guest_wrapper="import os,sys; f=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o644); os.dup2(f,2); os.close(f); os.execv(sys.argv[2],sys.argv[2:])"
 cmd=['perf','record','-e','cycles:u','-F','997','-o',str(folder/(arm+'.data')),'--','python3','-c',guest_wrapper,str(guest_stderr),str(bins[arm]),'--engine=vm',str(source)]
 begin=time.perf_counter()
 p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=perf_log,start_new_session=True)
 try:
  stdout,stderr=p.communicate(timeout=cutoff)
  stderr=guest_stderr.read_bytes() if guest_stderr.exists() else b'guest did not launch'
  item={'arm':arm,'command':cmd,'elapsed_seconds':time.perf_counter()-begin,'status':p.returncode,'stdout_sha256':hashlib.sha256(stdout).hexdigest(),'output_matches':stdout==b'5702887\n' and stderr==b'','guest_stderr_sha256':hashlib.sha256(stderr).hexdigest()}
  receipt['profiles'].append(item);save()
  assert p.returncode==0 and item['output_matches'],(arm,p.returncode,stdout,stderr)
 except subprocess.TimeoutExpired as e:
  os.killpg(p.pid,signal.SIGKILL)
  stdout,stderr=p.communicate()
  stderr=guest_stderr.read_bytes() if guest_stderr.exists() else b'guest did not launch'
  receipt['profiles'].append({'arm':arm,'status':'relative_timeout','elapsed_seconds':time.perf_counter()-begin});save();raise
 finally:
  perf_log.close()
print('pinned profiles completed; perf logs and raw data retained')
