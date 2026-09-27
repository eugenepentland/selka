from pathlib import Path
import os,json,subprocess,hashlib,time
r=Path.cwd();w=r/'.tmp-bytes';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
compilers={'before':r.parent/'d9-rc-integration/.tmp-rc/install-loops-fixed/bin/mylang','after':w/'install-after/bin/mylang'}
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(r/'.zig-cache-bytes-guests'),MYLANG_MEMORY_LIMIT='128M')
result={'compilers':{k:{'path':str(v),'sha256':sha(v)} for k,v in compilers.items()},'source_sha256':sha(r/'tests/lang/rc_byte_loop_versions.my'),'runs':[]}
def save():(w/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
for arm,c in compilers.items():
 for backend in ['qbe','llvm']:
  for mode in ['rc','gc']:
   b=w/f'guest-{arm}-{mode}-{backend}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build','tests/lang/rc_byte_loop_versions.my','-o',str(b),'--cache-dir',str(w/f'guest-cache-{arm}'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   start=time.monotonic();p=subprocess.run(cmd,env=e,capture_output=True,text=True);row=dict(arm=arm,backend=backend,mode=mode,build_command=cmd,build_exit=p.returncode,build_stdout=p.stdout,build_stderr=p.stderr,build_wall_seconds=time.monotonic()-start);result['runs'].append(row);save();assert p.returncode==0,row
   row['manifest']=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
   runenv=e|({'MYLANG_OPTIONS':'--gc-stress'} if mode=='gc' else {});p=subprocess.run([str(b)],env=runenv,capture_output=True,text=True,timeout=20)
   row.update(exit=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=sha(b),run_command=[str(b)],environment={k:v for k,v in runenv.items() if k.startswith('MYLANG_')});save();assert p.returncode==0 and p.stdout=='',row
   if mode=='rc':
    cts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=cts;assert not cts['saturated'] and cts['heap_allocate']==cts['retire'] and cts['owner_acquire']+cts['heap_allocate']==cts['owner_release'] and cts['hold_acquire']==cts['hold_release'],row
   save();print('PASS',arm,backend,mode,flush=True)
for backend in ['qbe','llvm']:
 rows=[x for x in result['runs'] if x['backend']==backend and x['mode']=='rc'];assert rows[0]['counts']==rows[1]['counts'],rows
print('COMPLETE',flush=True)
