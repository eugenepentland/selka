import hashlib,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent;root=p.parents[1]
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/d9-physical-borrow-after-astra/.tmp-physical/install-accepted/bin/mylang')
sha=lambda x:hashlib.sha256(Path(x).read_bytes()).hexdigest()
assert sha(compiler)=='8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478'
r={'source_sha256':sha(p/'live-view-divergence.my'),'compiler_sha256':sha(compiler),'compiler_revision':'f6bea5d9','cases':{}}
for backend in ('qbe','llvm'):
 binary=p/f'divergence-accepted-{backend}'
 cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(p/'live-view-divergence.my'),'-o',str(binary),'--cache-dir',str(p/('cache-divergence-accepted-'+backend))]
 if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
 d=subprocess.run(cmd,text=True,capture_output=True)
 assert d.returncode==0,d.stderr
 d=subprocess.run([str(binary)],text=True,capture_output=True)
 r['cases'][backend]={'command':cmd,'exit':d.returncode,'stdout':d.stdout,'stderr':d.stderr}
 (p/'accepted-divergence.json').write_text(json.dumps(r,indent=2)+'\n')
 assert d.returncode==0,r['cases'][backend]
 print(backend,d.stdout.strip(),flush=True)
