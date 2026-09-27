from pathlib import Path
import os,json,subprocess,hashlib,time,re
root=Path.cwd();w=root/'.tmp-variant-read';compiler=w/'install/bin/mylang';port=root/'.tmp-plain-record/lox-guest'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'builds':[]}
def save():(w/'lox-builds.json').write_text(json.dumps(r,indent=2)+'\n')
for backend in ['qbe','llvm']:
 for counted in [False,True]:
  binary=w/f'lox-{backend}-{int(counted)}'
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/'lox-cache'),f'--backend={backend}','--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  t=time.monotonic();d=subprocess.run(cmd,cwd=port,env=env,text=True,capture_output=True);row=dict(backend=backend,counted=counted,command=cmd,exit=d.returncode,stderr=d.stderr,seconds=time.monotonic()-t);r['builds'].append(row);save();assert d.returncode==0,row
  row['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest();row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend;save();print('BUILD',backend,counted,flush=True)
names={f['symbol']:f['name'] for f in r['builds'][0]['manifest']['functions']};found={}
for p in (w/'lox-cache/frontend/fragments').glob('*/il/*'):
 text=p.read_text();m=re.match(r'dbgfile "([^"]+)"',text)
 if not m or m[1] not in names:continue
 name=names[m[1]];count=text.count('# RC-ADJACENT-VARIANT-READ-1')
 if name in found:assert found[name]['count']==count
 else:found[name]={'count':count,'il':str(p),'sha256':hashlib.sha256(text.encode()).hexdigest()}
r['admission']=found;save()
for name,minimum in [('heap::string_obj',1),('heap::set_object_field',1),('vm::load_frame',2),('vm::get_property',1)]:
 assert found[name]['count']>=minimum,(name,found[name]);print('ADMITTED',name,found[name]['count'],flush=True)
