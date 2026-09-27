from pathlib import Path
import subprocess,json,hashlib,os
r=Path.cwd();w=r/'.tmp-rc/append-room';c=r/'.tmp-rc/install-append-room/bin/mylang'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
result={'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runs':[]}
for backend in ['qbe','llvm']:
 for mode in ['rc','gc']:
  for name in ["rc_plain_appends","rc_fresh_loop_roots","rc_inert_receivers","rc_read_loans","iteration_identity","rc_mut_uniqueness","field_augmented","array_places","rc_semantic_history","rc_field_transfers"]:
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'test',str(r/'tests/lang'/f'{name}.my'),'--force','--json','--jobs','2','--cache-dir='+str(w/'test-cache')]
   cmd+=['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress']
   if backend=='llvm':cmd+=['--release']
   p=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(backend=backend,mode=mode,name=name,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);result['runs'].append(row);(w/'guests.json').write_text(json.dumps(result,indent=2)+'\n')
   assert p.returncode==0,row
   a=json.loads(p.stdout);assert a['failed']==0;print(backend,mode,name,a['passed'],flush=True)
