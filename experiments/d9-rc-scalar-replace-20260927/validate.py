"""Compare canonical scalar replacement and located failures on both backends."""
import hashlib, json, os, subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-mut-argument/scalar-validation'; work.mkdir(exist_ok=True)
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-argv-return/bin/mylang',
           'after':root/'.tmp-mut-argument/scalar-candidate/bin/mylang'}
result={'compilers':{arm:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for arm,p in compilers.items()},'runs':[]}
def record(command,backend,arm,mode,expected,trap=None):
 run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
 counts=[json.loads(l.removeprefix('MYLANG_RC_COUNTS ')) for l in run.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')]
 row=dict(command=command,backend=backend,arm=arm,mode=mode,exit=run.returncode,stdout=run.stdout,stderr=run.stderr,counts=counts)
 result['runs'].append(row); (work/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
 assert run.returncode==expected,row
 if trap: assert trap in run.stderr,row
 for c in counts: assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
 print(backend,arm,mode,run.returncode,counts,flush=True)
for backend in ('qbe','llvm'):
 for arm,compiler in compilers.items():
  for mode in ('gc','rc'):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run','tests/lang/rc_scalar_replacements.my','--cache-dir='+str(work/'cache')]
   command+=([] if backend=='qbe' else ['--release'])+(['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress'])
   record(command,backend,arm,mode,0)
  for name,trap in [('bounds','R_LIST_BOUNDS'),('arithmetic','R_DIVISION_BY_ZERO')]:
   source=f'experiments/d9-rc-scalar-replace-20260927/{name}.my'
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',source,'--rc-runtime=stats','--cache-dir='+str(work/'cache')]
   if backend=='llvm':command+=['--release']
   record(command,backend,arm,name,1,trap)
 for mode in ('rc','bounds','arithmetic'):
  rows=[r for r in result['runs'] if r['backend']==backend and r['mode']==mode]
  assert rows[0]['counts']==rows[1]['counts'] and rows[0]['stdout']==rows[1]['stdout'],rows
