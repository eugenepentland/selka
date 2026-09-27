from pathlib import Path
import os,json,subprocess,hashlib
r=Path.cwd();w=r/'.tmp-bytes';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
cs={'before':r.parent/'d9-rc-integration/.tmp-rc/install-loops-fixed/bin/mylang','after':w/'install-after/bin/mylang'};e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(r/'.zig-cache-bytes-guests'),MYLANG_MEMORY_LIMIT='128M');result={'source_sha256':sha(w/'trap.my'),'rows':[]}
def save():(w/'traps.json').write_text(json.dumps(result,indent=2)+'\n')
for arm,c in cs.items():
 for backend in ['qbe','llvm']:
  for mode in ['fast','steps']:
   b=w/f'trap-{arm}-{backend}-{mode}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'trap.my'),'-o',str(b),'--cache-dir',str(w/f'guest-cache-{arm}'),f'--backend={backend}','--rc-runtime=stats']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='steps':cmd+=['--mode=Debug']
   p=subprocess.run(cmd,env=e,capture_output=True,text=True);row=dict(arm=arm,backend=backend,mode=mode,compiler_sha256=sha(c),command=cmd,build_exit=p.returncode,build_stderr=p.stderr,runs=[]);result['rows'].append(row);save();assert p.returncode==0,row
   row['binary_sha256']=sha(b);row['manifest']=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
   cases=[('ok','',None),('negative','',None),('upper','','R_LIST_BOUNDS'),('lower','','R_LIST_BOUNDS'),('overflow','','R_OVERFLOW')] if mode=='fast' else [('ok','--max-steps=100','R_STEP_LIMIT'),('ok','',None)]
   for case,options,expected in cases:
    p=subprocess.run([str(b),case],env=e|{'MYLANG_OPTIONS':options},capture_output=True,text=True,timeout=20);entry=dict(case=case,options=options,exit=p.returncode,stdout=p.stdout,stderr=p.stderr);row['runs'].append(entry);save();assert p.returncode==(1 if expected else 0),entry
    if expected:assert expected in p.stderr,entry
    else:assert p.stdout=='before\n210\n',entry
    cts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));entry['counts']=cts;assert not cts['saturated'] and cts['heap_allocate']==cts['retire'] and cts['owner_acquire']+cts['heap_allocate']==cts['owner_release'] and cts['hold_acquire']==cts['hold_release'],entry;save()
   print('PASS',arm,backend,mode,flush=True)
for backend in ['qbe','llvm']:
 for mode in ['fast','steps']:
  a,b=[x for x in result['rows'] if x['backend']==backend and x['mode']==mode]
  assert [(x['exit'],x['stdout'],x['counts']) for x in a['runs']]==[(x['exit'],x['stdout'],x['counts']) for x in b['runs']]
print('MATCHED',flush=True)
