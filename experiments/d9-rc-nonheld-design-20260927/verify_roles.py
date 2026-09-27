from pathlib import Path
import json,subprocess,hashlib,os
r=Path.cwd();w=r/'.tmp-rc/nonheld-design';c=r/'.tmp-rc/install-append-room/bin/mylang';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
d={'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runs':[]}
for command,file in [('dump-bytecode','bytecode.txt'),('emit-qbe','emitted.json')]:
 cmd=[str(c),command,str(w/'roles.my'),'--rc-runtime'];z=subprocess.run(cmd,env=env,text=True,capture_output=True);assert z.returncode==0,z.stderr;(w/file).write_text(z.stdout);d['runs'].append({'command':cmd,'status':z.returncode,'stdout_sha256':hashlib.sha256(z.stdout.encode()).hexdigest(),'stderr':z.stderr})
for backend in ['qbe','llvm']:
 for mode in ['gc','rc']:
  b=w/f'{backend}-{mode}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'roles.my'),'-o',str(b),'--cache-dir='+str(w/'cache'),'--rc-runtime=stats' if mode=='rc' else '--gc-runtime']
  cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
  z=subprocess.run(cmd,env=env,text=True,capture_output=True);row={'command':cmd,'build_status':z.returncode,'build_stderr':z.stderr};d['runs'].append(row);(w/'verified-roles.json').write_text(json.dumps(d,indent=2)+'\n');assert z.returncode==0,z.stderr
  e=dict(env)
  if mode=='gc':e['MYLANG_OPTIONS']='--gc-stress'
  z=subprocess.run([str(b)],env=e,text=True,capture_output=True);row.update(status=z.returncode,stdout=z.stdout,stderr=z.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest());assert z.returncode==0,row
  if mode=='rc':
   x=json.loads(next(l.removeprefix('MYLANG_RC_COUNTS ') for l in z.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')));assert x['heap_allocate']==x['retire'] and x['owner_acquire']+x['heap_allocate']==x['owner_release'] and x['hold_acquire']==x['hold_release'];row['counts']=x
  (w/'verified-roles.json').write_text(json.dumps(d,indent=2)+'\n');print(backend,mode,'pass',flush=True)
