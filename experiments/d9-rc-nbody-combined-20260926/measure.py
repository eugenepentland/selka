import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-nbody';compiler=root.parent/'d9-rc-integration/.tmp-rc/install-nbody/bin/mylang'
source=root/'bench/parity/suite/nbody.my';expected=(root/'bench/parity/suite/nbody.expected').read_text()
control=root.parent/'d9-rc-performance/.tmp-rc-performance/bin/gc'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
accepted=json.loads((root.parent/'d9-rc-performance/.tmp-rc-performance/gc-builds.json').read_text())
assert accepted['compiler_sha256']=='8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478'
assert accepted['inputs'][str(root.parent/'d9-rc-performance/bench/parity/suite/nbody.my')]==sha(source)
result={'compiler_source_commit':'685e26311935cea0697726614a3897baff4f286f','gc_compiler_sha256':accepted['compiler_sha256'],'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'compiler_sha256':sha(compiler),'source_sha256':sha(source),'workload_steps':5000000,'backends':{},'builds':[]}
def save(): (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for mode in ('rc','stats'):
  binary=work/f'nbody-{backend}-{mode}'
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir='+str(work/'cache-guests'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
  if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
  run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work/'tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-nbody')))
  result['builds'].append({'command':command,'status':run.returncode,'stdout':run.stdout,'stderr':run.stderr});save()
  assert run.returncode==0,result['builds'][-1]
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
  result['builds'][-1].update(sha256=sha(binary),manifest=manifest);save()
 binaries={'gc':control/f'parity-suite-nbody.{backend}','rc':work/f'nbody-{backend}-rc'}
 assert sha(binaries['gc'])==accepted['builds'][f'parity-suite-nbody.{backend}']['sha256']
 samples=[]
 for iteration in range(3):
  for arm in (('gc','rc') if iteration%2==0 else ('rc','gc')):
   command=['taskset','-c','11','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
   run=subprocess.run(command,text=True,capture_output=True,timeout=240)
   assert run.returncode==0 and run.stdout==expected,(arm,run.returncode,run.stdout,run.stderr)
   fields=[line.split(',') for line in run.stderr.splitlines()]
   instructions=[int(f[0]) for f in fields if len(f)>2 and f[0].isdigit() and 'instructions' in f[2]];assert len(instructions)==1
   samples.append({'arm':arm,'command':command,'instructions':instructions[0],'stdout':run.stdout,'stderr':run.stderr})
   result['backends'][backend]={'samples':samples};save()
 run=subprocess.run(['taskset','-c','11',str(work/f'nbody-{backend}-stats')],text=True,capture_output=True,timeout=240)
 assert run.returncode==0 and run.stdout==expected
 counts=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1
 c=counts[0];assert c['runtime']=='rc-v3-counting' and not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release']
 medians={arm:statistics.median(row['instructions'] for row in samples if row['arm']==arm) for arm in binaries}
 result['backends'][backend].update(medians=medians,ratio=medians['rc']/medians['gc'],counts=c,binary_sha256={arm:sha(p) for arm,p in binaries.items()});save()
 print(backend,medians,result['backends'][backend]['ratio'],c,flush=True)
assert sha(compiler)==result['compiler_sha256']
