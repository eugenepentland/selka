"""Paired GC/RC plain appends plus the established 54-assertion runtime driver."""
import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/loan-validation';work.mkdir(exist_ok=True)
compilers={'before':root/'.tmp-mut-argument/retain-final/bin/mylang','after':root/'.tmp-mut-argument/loan-candidate/bin/mylang'}
result={'compilers':{a:hashlib.sha256(p.read_bytes()).hexdigest() for a,p in compilers.items()},'runs':[]}
for backend in ('qbe','llvm'):
 for arm,compiler in compilers.items():
  for name,source in [('plain','tests/lang/rc_plain_retains.my'),('broad','experiments/d9-rc-inert-return-20260926/direct/driver.my')]:
   for mode in ('gc','rc'):
    command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',source,'--cache-dir='+str(work/'cache')]
    if backend=='llvm':command+=['--release']
    command+=['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress']
    run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
    counts=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    row=dict(backend=backend,arm=arm,name=name,mode=mode,command=command,exit=run.returncode,stdout=run.stdout,stderr=run.stderr,counts=counts)
    result['runs'].append(row);(work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    assert run.returncode==0,row
    for c in counts:assert c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
    print(backend,arm,name,mode,counts,flush=True)
 for name in ('plain','broad'):
  rows=[r for r in result['runs'] if r['backend']==backend and r['name']==name and r['mode']=='rc']
  assert rows[0]['counts']==rows[1]['counts'] and rows[0]['stdout']==rows[1]['stdout'],rows
