from pathlib import Path
import os,json,hashlib,subprocess,sys
root=Path.cwd();w=root/'.tmp-mut-argument/read-version';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['TMPDIR']=str(w)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
compilers={'before':root.parent/'d9-rc-read-version-before-astra/.tmp-read-version/install/bin/mylang','after':w/'install/bin/mylang'}
path=w/'validation.json';d=json.loads(path.read_text()) if path.exists() else {'runs':[],'builds':[],'emitted':{}}
def save():path.write_text(json.dumps(d,indent=2)+'\n')
def run(cmd,timeout=600):return subprocess.run(list(map(str,cmd)),env=env,capture_output=True,text=True,timeout=timeout)
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  for name in ('rc_read_list_versions','rc_loop_versions','rc_scalar_loops','rc_borrowed_loops'):
   source=root/'tests/lang'/f'{name}.my';binary=w/f'{name}-{side}-{backend}'
   if any(r['side']==side and r['backend']==backend and r['source']==name for r in d['runs']):continue
   cmd=[root/'scripts/build-slot.sh','build',c,'build',source,'--rc-runtime=stats','--backend='+backend,'--mode=ReleaseFast','-o',binary,'--cache-dir='+str(w/('cache-'+side))]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=run(cmd);row={'side':side,'backend':backend,'source':name,'source_sha256':sha(source),'compiler':str(c),'compiler_sha256':sha(c),'build':list(map(str,cmd)),'status':p.returncode,'stderr':p.stderr};d['builds'].append(row);save();assert p.returncode==0,row
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend;row.update(binary=str(binary),binary_sha256=sha(binary),manifest=manifest);save()
   p=run([binary],60);r={'side':side,'backend':backend,'source':name,'command':[str(binary)],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(r);save();assert p.returncode==0,r
   counts=[json.loads(x.split(' ',1)[1]) for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1,r
   r['counts']=counts[0];n=counts[0];assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release'],r
   save();print(side,backend,name,'pass',flush=True)
 for name in ('rc_read_list_versions',):
  source=root/'tests/lang'/f'{name}.my'
  cmd=[root/'scripts/build-slot.sh','build',c,'emit-qbe',source,'--rc-runtime','--drop-step-checks','--drop-frame-checks']
  p=run(cmd);assert p.returncode==0,p.stderr
  out=w/f'{name}-{side}-emitted.json';out.write_text(p.stdout);d['emitted'][side]={'command':list(map(str,cmd)),'sha256':sha(out),'path':str(out)};save()
for a in d['runs']:
 if a['side']!='before':continue
 b=next(r for r in d['runs'] if r['side']=='after' and r['backend']==a['backend'] and r['source']==a['source'])
 assert a['counts']==b['counts'] and a['stdout']==b['stdout'],(a,b)
print('exact paired counts and outputs',flush=True)
