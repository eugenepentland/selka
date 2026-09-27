from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd();w=r/'.tmp-rc/dict-key';c=r/'.tmp-rc/install-dict-key-prototype/bin/mylang'
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
d={'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runs':[]}
for backend in ['qbe','llvm']:
 for mode in ['rc','gc']:
  for name in ['rc_dictionary_keys']:
   if not (r/'tests/lang'/f'{name}.my').exists():continue
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'test',str(r/'tests/lang'/f'{name}.my'),'--force','--json','--jobs','2','--cache-dir='+str(w/'guest-cache')]
   cmd+=['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress']
   if backend=='llvm':cmd+=['--release']
   p=subprocess.run(cmd,env=e,text=True,capture_output=True)
   row=dict(source_sha256=hashlib.sha256((r/'tests/lang'/f'{name}.my').read_bytes()).hexdigest(),name=name,backend=backend,mode=mode,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);d['runs'].append(row);(w/'guests-keys-final.json').write_text(json.dumps(d,indent=2)+'\n')
   assert p.returncode==0,row
   a=json.loads(p.stdout);assert a['failed']==0,row
   print(backend,mode,name,a['passed'],flush=True)
