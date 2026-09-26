import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-init'
baseline=root.parent/'d9-rc-flat-destruction-astra/.tmp-flat/cumulative-19e'
compiler=root/'zig-out/bin/mylang'
source=root/'experiments/d9-rc-flat-destruction-20260926/binary_trees_n12.my'
expected=(root/'experiments/d9-rc-flat-destruction-20260926/expected.stdout').read_text()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source)==sha(baseline/'binary_trees_n12.my')
result={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'compiler_sha256':sha(compiler),'source_sha256':sha(source),'patch':subprocess.check_output(['git','diff'],text=True),'builds':[],'backends':{}}
def save(): (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for mode in ('rc','stats'):
  binary=work/f'{backend}-{mode}-n12'
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(work/f'cache-{backend}'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
  if backend=='llvm': command+=['--backend=llvm','--llvm-opt=3','--lto']
  done=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work/'tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-init')))
  result['builds'].append({'command':command,'status':done.returncode,'stdout':done.stdout,'stderr':done.stderr});save()
  assert done.returncode==0,result['builds'][-1]
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
  assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
  result['builds'][-1].update(sha256=sha(binary),manifest=manifest);save()
 binaries={'before':baseline/f'{backend}-rc-n12','after':work/f'{backend}-rc-n12'}
 samples=[];counts={}
 for i in range(5):
  for arm in (('before','after') if i%2==0 else ('after','before')):
   command=['taskset','-c','11','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
   done=subprocess.run(command,text=True,capture_output=True,check=True)
   assert done.stdout==expected,(arm,done.stdout,done.stderr)
   fields=[line.split(',') for line in done.stderr.splitlines()]
   instructions=[int(f[0]) for f in fields if len(f)>2 and f[0].isdigit() and 'instructions' in f[2]]
   assert len(instructions)==1
   samples.append({'arm':arm,'command':command,'instructions':instructions[0],'stderr':done.stderr})
 for arm,binary in [('before',baseline/f'{backend}-stats-n12'),('after',work/f'{backend}-stats-n12')]:
  done=subprocess.run(['taskset','-c','11',str(binary)],text=True,capture_output=True,check=True)
  assert done.stdout==expected
  rows=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
  assert len(rows)==1 and rows[0]['runtime']=='rc-v3-counting'
  counts[arm]=rows[0]
 assert counts['before']==counts['after']
 medians={arm:statistics.median(row['instructions'] for row in samples if row['arm']==arm) for arm in binaries}
 result['backends'][backend]={'samples':samples,'medians':medians,'counts':counts,'ratio':medians['after']/medians['before'],'binary_sha256':{arm:sha(p) for arm,p in binaries.items()}}
 save();print(backend,result['backends'][backend]['ratio'],medians,flush=True)
assert sha(compiler)==result['compiler_sha256']
