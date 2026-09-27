from pathlib import Path
import hashlib,json,os,subprocess
R=Path.cwd();W=R/'.tmp-borrowed-frame';C={'before':R.parent/'d9-rc-integration/.tmp-rc/install-helpers-word/bin/mylang','after':W/'install-immortal-initial/bin/mylang'}
E={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};E.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(R/'.zig-cache-borrowed-frame-guests'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
D={'compilers':{s:{'path':str(c),'sha256':sha(c)} for s,c in C.items()},'builds':[],'runs':[]}
def save(): (W/'controls.json').write_text(json.dumps(D,indent=2)+'\n')
def execute(cmd,options=''):
 e=dict(E)
 if options:e['MYLANG_OPTIONS']=options
 p=subprocess.run(list(map(str,cmd)),env=e,text=True,capture_output=True,timeout=600)
 return dict(command=list(map(str,cmd)),options=options,status=p.returncode,stdout=p.stdout,stderr=p.stderr)
def counts(row):
 n=[json.loads(s.split(' ',1)[1]) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')];assert len(n)==1,row;n=n[0];row['counts']=n
 assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'] and not n['saturated'],row
for side,c in C.items():
 for backend in ('qbe','llvm'):
  for mode in ('rc','gc'):
   b=W/'bin'/f'controls-{side}-{backend}-{mode}'
   cmd=[R/'scripts/build-slot.sh','build',c,'build',R/'tests/lang/rc_borrowed_readonly_entries.my','--mode=ReleaseFast','--backend='+backend,'--cache-dir='+str(W/('cache-controls-'+side)),'-o',b]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   row=execute(cmd);row.update(side=side,backend=backend,runtime=mode);D['builds'].append(row);save();assert row['status']==0,row
   row.update(manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text()),binary_sha256=sha(b));assert row['manifest']['backend']==backend
   run=execute([b],'--gc-stress' if mode=='gc' else '');run.update(side=side,backend=backend,runtime=mode);D['runs'].append(run)
   if mode=='rc':counts(run)
   save();assert run['status']==0 and run['stdout']=='True\nTrue\nTrue\n',run
   print(side,backend,mode,'passed',flush=True)
D['complete']=True;save()
