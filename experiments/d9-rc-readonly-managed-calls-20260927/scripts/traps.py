from pathlib import Path
import hashlib,json,os,subprocess
R=Path.cwd();W=R/'.tmp-managed-readonly';S=W/'traps.my';C={'before':W/'install-before/bin/mylang','after':W/'install-bytes/bin/mylang'}
E={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};E.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(W/'guest-zig-cache'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();D={'builds':[],'runs':[],'driver_sha256':sha(__file__)}
def save():(W/'traps.json').write_text(json.dumps(D,indent=2)+'\n')
for side,c in C.items():
 for backend in ('qbe','llvm'):
  binary=W/'bin'/f'trap-{side}-{backend}'
  cmd=[R/'scripts/build-slot.sh','build',c,'build',S,'--mode=Debug','--backend='+backend,'--rc-runtime=stats','--cache-dir='+str(W/('cache-traps-'+side)),'-o',binary]
  if backend=='llvm':cmd+=['--llvm-opt=0']
  p=subprocess.run(list(map(str,cmd)),env=E,text=True,capture_output=True,timeout=600);row={'command':list(map(str,cmd)),'side':side,'backend':backend,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'compiler_sha256':sha(c),'source_sha256':sha(S)};D['builds'].append(row);save();assert p.returncode==0,row
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend;row.update(binary_sha256=sha(binary),manifest=manifest);save()
  for case,args,options,code in [('upper',['x'],'','R_LIST_BOUNDS'),('lower',['x','y'],'','R_LIST_BOUNDS'),('steps54',[],'--max-steps=54','R_STEP_LIMIT'),('steps55',[],'--max-steps=55','R_STEP_LIMIT'),('frames',[],'--max-frames=2','R_FRAME_LIMIT'),('success',[],'--max-frames=3','')]:
   cmd=[str(binary),*args];p=subprocess.run(cmd,env=dict(E,MYLANG_OPTIONS=options),capture_output=True,text=True,timeout=60);row={'side':side,'backend':backend,'case':case,'command':cmd,'options':options,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'expected_trap':code};D['runs'].append(row);save()
   assert p.returncode==(1 if code else 97) and (not code or code in p.stderr),row
   counts=[json.loads(s.split(' ',1)[1]) for s in p.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,row;n=counts[0];row['counts']=n
   assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],row
   save();print('passed',side,backend,case,flush=True)
for backend in ('qbe','llvm'):
 for case in ('upper','lower','steps54','steps55','frames','success'):
  rows=[r for r in D['runs'] if r['backend']==backend and r['case']==case]
  cleaned=['\n'.join(x for x in r['stderr'].splitlines() if not x.startswith('MYLANG_RC_COUNTS ')) for r in rows];assert len(rows)==2 and cleaned[0]==cleaned[1] and rows[0]['stdout']==rows[1]['stdout'],rows
D['complete']=True;save()
