import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/fresh-validation';result=[]
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-history-flat/bin/mylang','after':root/'.tmp-mut-argument/fresh-candidate/bin/mylang'}
for backend in ('qbe','llvm'):
 for arm,compiler in compilers.items():
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','experiments/d9-rc-fresh-constructor-20260926/arithmetic-trap.my','--run','--rc-runtime=stats','--cache-dir',str(work/'cache')]
  if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
  run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
  counts=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
  row={'backend':backend,'arm':arm,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'command':command,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'counts':counts}
  result.append(row);(work/'arithmetic.json').write_text(json.dumps(result,indent=2)+'\n')
  assert run.returncode==1 and 'R_DIVISION_BY_ZERO' in run.stderr and len(counts)==1,row
  c=counts[0];assert c['heap_allocate']>0 and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
  print(backend,arm,c,flush=True)
 assert result[-1]['counts']==result[-2]['counts']
