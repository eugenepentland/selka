#!/usr/bin/env python3
"""Resumable three-arm fib diagnostic; requires an authorized CPU8 timing lease."""
import hashlib,json,os,signal,statistics,subprocess,sys,time
from pathlib import Path
root=Path.cwd();chunk=int(sys.argv[1]);assert 1<=chunk<=3 and sorted(os.sched_getaffinity(0))==[8]
folder=root/'experiments/lox-eda-parity-20261013/P2/inline-fib-001';out=folder/'samples.json'
compiler=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang')
bins={'baseline':root/'.tmp/lox-eda-parity/P2/reader-inline-001/baseline','short':root/'.tmp/lox-eda-parity/P2/read-short-001/candidate','inline':root/'.tmp/lox-eda-parity/P2/reader-inline-001/inline','zig':Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/reference-binaries/lox-zig-fast')}
pins={'baseline':'e656cbc57054a12fa06edd29e2ac2e1507f57ff920064d0ec0de96a5b3f64719','short':'64895849dbe5a723eae4fff1838f6f781af243b3b187ae6349ad24b1deeda5b0','inline':'60c570bc7c384c7dba9e61b29d6ade32dfc13008469159969884cc3c2c937c22','zig':'0c884acc8e3e2c0e7930910f0f21e89de7078b932368f19f11dc72fb3e3924da'}
source=Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p2/experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-fib.lox')
expected=Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p2/experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-fib.expected.stdout').read_bytes()
assert hashlib.sha256(expected).hexdigest()=='3e01be60139c8e55182a9388e0133537d417649b097c820c766aaf403dcdfc11'
assert hashlib.sha256(compiler.read_bytes()).hexdigest()=='955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='e5c412ecb35cb4bcda97ac05f47f7cd8267f23deb0403bc5dd31126980216f45'
for arm,path in bins.items():assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[arm]
def run_guest(cmd,capture_output,timeout):
 p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:
  stdout,stderr=p.communicate(timeout=timeout)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);p.communicate();raise
 return subprocess.CompletedProcess(cmd,p.returncode,stdout,stderr)
if out.exists():receipt=json.loads(out.read_text());assert receipt['binary_sha256']==pins
else:receipt={'label':'bounded LLVM-only inlining diagnostic against matching unchanged relink; full identical fib input; no all-case Zig parity claim','script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'expected_stdout_sha256':hashlib.sha256(expected).hexdigest(),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'binary_sha256':pins,'calibrations':[],'warmups':[],'samples':[],'status':'running'}
if any(c['chunk']==chunk for c in receipt['calibrations']):
 calibration=next(c for c in receipt['calibrations'] if c['chunk']==chunk)
else:
 calibration={'chunk':chunk,'cpu_affinity':[8],'warmup_pairs_per_comparison':2,'measured_pairs_per_comparison':3,'zig_samples':[]}
 receipt['calibrations'].append(calibration)
if 'guest_cutoff_seconds' not in calibration:
 zig=calibration['zig_samples']
 for i in range(len(zig),7):
  begin=time.perf_counter();p=run_guest([str(bins['zig']),'--engine=vm',str(source)],capture_output=True,timeout=120);elapsed=time.perf_counter()-begin
  assert p.returncode==0 and p.stdout==expected and p.stderr==b'',(p.returncode,p.stdout,p.stderr)
  zig.append({'stage':'warmup' if i<2 else 'measured','elapsed_seconds':elapsed,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest()})
  out.write_text(json.dumps(receipt,indent=2)+'\n')
 median=statistics.median(r['elapsed_seconds'] for r in zig if r['stage']=='measured')
 calibration.update(fresh_zig_median_seconds=median,guest_cutoff_seconds=min(120,3*median))
 out.write_text(json.dumps(receipt,indent=2)+'\n')
for stage,pairs in [('warmups',range(2)),('samples',range((chunk-1)*3,chunk*3))]:
 for pair in pairs:
  comparisons=['inline']
  for comparison in comparisons:
   order=['baseline',comparison] if pair%2==0 else [comparison,'baseline']
   for arm in order:
    key=(chunk,comparison,pair,arm)
    if any((r['chunk'],r['comparison'],r['pair'],r['arm'])==key for r in receipt[stage]):continue
    assert hashlib.sha256(bins[arm].read_bytes()).hexdigest()==pins[arm]
    begin=time.perf_counter()
    try:
     p=run_guest([str(bins[arm]),'--engine=vm',str(source)],capture_output=True,timeout=calibration['guest_cutoff_seconds']);elapsed=time.perf_counter()-begin
     assert p.returncode==0 and p.stdout==expected and p.stderr==b'',(arm,p.returncode,p.stdout,p.stderr)
     r={'chunk':chunk,'comparison':comparison,'pair':pair,'arm':arm,'elapsed_seconds':elapsed,'status':'complete','stdout_sha256':hashlib.sha256(p.stdout).hexdigest()}
    except subprocess.TimeoutExpired:
     r={'chunk':chunk,'comparison':comparison,'pair':pair,'arm':arm,'elapsed_seconds':time.perf_counter()-begin,'status':'relative_timeout','guest_cutoff_seconds':calibration['guest_cutoff_seconds']}
    receipt[stage].append(r);out.write_text(json.dumps(receipt,indent=2)+'\n')
receipt['status']='complete' if all(any(c['chunk']==i for c in receipt['calibrations']) for i in [1,2,3]) and len(receipt['samples'])==18 else 'partial'
out.write_text(json.dumps(receipt,indent=2)+'\n');print('chunk',chunk,'complete; diagnostic',receipt['status'])
