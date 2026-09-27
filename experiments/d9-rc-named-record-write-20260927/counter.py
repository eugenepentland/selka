from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-named-record'; sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-ownership-joined-fixed/bin/mylang','after':w/'install-frozen/bin/mylang'}
r={'source_sha256':sha(w/'counter.my'),'rows':[]}
def save():(w/'counter.json').write_text(json.dumps(r,indent=2)+'\n')
for arm,compiler in compilers.items():
 for backend in ('qbe','llvm'):
  binary=w/f'counter-{arm}-{backend}'
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(w/'counter.my'),'-o',str(binary),'--cache-dir',str(w/'counter-cache'),f'--backend={backend}','--rc-runtime=stats']
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  d=subprocess.run(cmd,env=env,capture_output=True,text=True)
  row=dict(arm=arm,backend=backend,compiler_sha256=sha(compiler),command=cmd,build_exit=d.returncode,build_stderr=d.stderr,runs=[]);r['rows'].append(row);save();assert d.returncode==0,row
  row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
  row['binary_sha256']=sha(binary)
  for n in (1,2,10):
   command=[str(binary)]+['x']*n;d=subprocess.run(command,env=env,capture_output=True,text=True,timeout=5)
   c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')))
   entry=dict(n=n,command=command,exit=d.returncode,stdout=d.stdout,stderr=d.stderr,counts=c);row['runs'].append(entry);save();assert d.returncode==0,entry
   assert c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['heap_allocate']==c['retire'] and c['hold_acquire']==c['hold_release'] and not c['saturated']
  print('PASS',arm,backend,flush=True)
for backend in ('qbe','llvm'):
 b=next(x for x in r['rows'] if x['arm']=='before' and x['backend']==backend)
 a=next(x for x in r['rows'] if x['arm']=='after' and x['backend']==backend)
 for br,ar in zip(b['runs'],a['runs']):
  assert br['stdout']==ar['stdout'];commits=int(ar['stdout']);o=br['counts']['owner_acquire']-ar['counts']['owner_acquire'];h=br['counts']['hold_acquire']-ar['counts']['hold_acquire']
  assert (o,h)==(3*commits,6*commits),(backend,commits,o,h)
  print('COUNTER',backend,commits,o,h,flush=True)
