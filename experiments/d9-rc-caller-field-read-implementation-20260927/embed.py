from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd();w=r/'.tmp-mut-argument/caller-field-read/controls';source=r/'tests/lang/rc_caller_field_reads.my'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
compilers={'before':r/'.tmp-mut-argument/field-list-read/install-proof-final/bin/mylang','after':r/'.tmp-mut-argument/caller-field-read/install-prototype/bin/mylang'}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(r.parent/'.d9-rc-mut-argument-tmp'),MYLANG_MEMORY_LIMIT='8G')
d={'source':str(source),'source_sha256':sha(source),'builds':[],'runs':[]}
def save():(w/'embedding.json').write_text(json.dumps(d,indent=2)+'\n')
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  binary=w/('embed-'+side+'-'+backend+'.so')
  cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(source),'--library','--rc-runtime=stats','--backend='+backend,'--mode=ReleaseFast','-o',str(binary),'--cache-dir='+str(r/'.tmp-mut-argument/lox-post-record/current/cache')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  p=subprocess.run(cmd,env=env,capture_output=True,text=True);b={'side':side,'backend':backend,'command':cmd,'exit':p.returncode,'stderr':p.stderr,'compiler_sha256':sha(c)};d['builds'].append(b);save();assert not p.returncode,b
  b.update(binary=str(binary),sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert b['manifest']['backend']==backend;save()
  names={f['name']:f['symbol'] for f in b['manifest']['functions']}
  for mode in range(1,17):
   cmd=[str(w/'embedding'),str(binary),*[names[n] for n in ('read_only_inout','advance','forward','overflow_after','heap_frame','replace_after')],str(mode)]
   p=subprocess.run(cmd,env=env,capture_output=True,text=True);row={'side':side,'backend':backend,'mode':mode,'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(row);save();assert not p.returncode,row
   print(side,backend,p.stdout.strip(),flush=True)
for a in d['runs']:
 if a['side']!='before' or a['mode']==13:continue
 b=next(x for x in d['runs'] if x['side']=='after' and x['backend']==a['backend'] and x['mode']==a['mode']);assert a['stdout']==b['stdout'],(a,b)
print('30 matched status/output/trace/allocator controls, plus4 explicit temporary-H admission runs',flush=True)
