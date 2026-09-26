import hashlib,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent;root=p.parents[1]
sha=lambda x:hashlib.sha256(Path(x).read_bytes()).hexdigest()
r={'source_sha256':sha(p/'live-view-divergence.my'),'before_revision':'6f7a3a94','cases':{}}
for backend in ('qbe','llvm'):
 for arm,mode in [('publish-before','gc'),('publish-before','stats'),('publish','stats')]:
  compiler=p/f'install-{arm}/bin/mylang';binary=p/f'divergence-{arm}-{backend}-{mode}'
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(p/'live-view-divergence.my'),'-o',str(binary),'--cache-dir',str(p/('cache-divergence-'+backend))]
  if mode=='stats':cmd+=['--rc-runtime=stats']
  if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
  d=subprocess.run(cmd,text=True,capture_output=True)
  assert d.returncode==0,d.stderr
  d=subprocess.run([str(binary)],text=True,capture_output=True)
  row={'command':cmd,'compiler_sha256':sha(compiler),'exit':d.returncode,'stdout':d.stdout,'stderr':d.stderr}
  r['cases'][f'{arm}/{backend}/{mode}']=row
  (p/'publish-divergence.json').write_text(json.dumps(r,indent=2)+'\n')
  assert d.returncode==0,row
  print(arm,backend,mode,d.stdout.strip(),flush=True)
