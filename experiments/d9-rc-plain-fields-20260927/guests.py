from pathlib import Path
import os,json,subprocess,hashlib,signal
root=Path.cwd();w=root/'.tmp-schematic-audit';compiler=w/'install-final/bin/mylang';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save(): (w/'guests-final.json').write_text(json.dumps(r,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  binary=w/f'guests-final-{mode}-{backend}'
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','tests/lang/rc_plain_field_loans.my','-o',str(binary),'--cache-dir',str(w/'guest-cache'),f'--backend={backend}']
  if backend=='llvm':command+=['--llvm-opt=3','--lto']
  if mode=='rc':command+=['--rc-runtime=stats']
  done=subprocess.run(command,env=env,capture_output=True,text=True)
  row={'mode':mode,'backend':backend,'build':{'command':command,'exit':done.returncode,'stdout':done.stdout,'stderr':done.stderr}}
  r['runs'].append(row);save();assert done.returncode==0,row
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
  runenv=dict(env)
  if mode=='gc':runenv['MYLANG_OPTIONS']='--gc-stress'
  done=subprocess.run([str(binary)],env=runenv,capture_output=True,text=True,timeout=30)
  row.update(exit=done.returncode,stdout=done.stdout,stderr=done.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());save()
  assert done.returncode==0 and done.stdout=='True\n'*6,row
  if mode=='rc':
   c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in done.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row['counts']=c
   assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
  save();print(mode,backend,'6 passed',row.get('counts',{}),flush=True)
