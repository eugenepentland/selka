import subprocess,json,hashlib,os,statistics
from pathlib import Path
root=Path.cwd();work=root/'.tmp-schematic';env=dict(os.environ,TMPDIR=str(work/'tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-schematic'))
expected=0
for index in range(1000000):expected=(expected*17+index)%104729
expected=str(expected+2)+'\n'
result={'source':(work/'plain-loop.my').read_text(),'expected':expected,'compilers':{},'cases':{}}
for label,compiler in [('before',work/'install-before-plain/bin/mylang'),('after',root/'zig-out/bin/mylang')]:
 result['compilers'][label]=hashlib.sha256(compiler.read_bytes()).hexdigest()
 for backend in ['qbe','llvm']:
  binary=work/('plain-loop-'+label+'-'+backend)
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(work/'plain-loop.my'),'-o',str(binary),'--rc-runtime','--cache-dir='+str(work/'plain-bench-cache')]
  if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
  subprocess.run(command,env=env,check=True,capture_output=True)
  check=subprocess.run([str(binary)],capture_output=True,text=True,check=True);assert check.stdout==expected,(label,backend,check)
  result['cases'][label+'-'+backend]={'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'instructions':[]}
for repetition in range(3):
 for label in (['before','after'] if repetition%2==0 else ['after','before']):
  for backend in ['qbe','llvm']:
   binary=work/('plain-loop-'+label+'-'+backend)
   run=subprocess.run(['taskset','-c','2','perf','stat','-x,','-e','instructions:u','--',str(binary)],capture_output=True,text=True,check=True)
   assert run.stdout==expected
   rows=[l.split(',') for l in run.stderr.splitlines() if 'instructions' in l and l.split(',')[0].strip().isdigit()];assert len(rows)==1,run.stderr
   result['cases'][label+'-'+backend]['instructions'].append(int(rows[0][0]))
result['ratios']={b:statistics.median(result['cases']['after-'+b]['instructions'])/statistics.median(result['cases']['before-'+b]['instructions']) for b in ['qbe','llvm']}
(work/'plain-operand-perf.json').write_text(json.dumps(result,indent=2)+'\n');print(result['ratios'])
