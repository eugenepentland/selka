from pathlib import Path
import subprocess,json,hashlib,os
r=Path.cwd();w=r/'.tmp-rc/append-room';c=r/'.tmp-rc/install-append-room/bin/mylang';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
d={'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runs':[]}
for backend in ['qbe','llvm']:
 b=w/f'scalar-cases-{backend}'
 cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(r/'tests/lang/rc_plain_appends.my'),'-o',str(b),'--cache-dir='+str(w/'full/cache-after'),'--rc-runtime=stats']
 cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
 p=subprocess.run(cmd,env=env,text=True,capture_output=True);row={'backend':backend,'command':cmd,'build_status':p.returncode,'build_stderr':p.stderr};assert p.returncode==0,row
 p=subprocess.run([str(b)],env=env,text=True,capture_output=True);row.update(status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest());d['runs'].append(row);(w/'standalone.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
 cts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=cts
 assert cts['heap_allocate']==cts['retire'] and cts['owner_acquire']+cts['heap_allocate']==cts['owner_release'] and cts['hold_acquire']==cts['hold_release'],row
 (w/'standalone.json').write_text(json.dumps(d,indent=2)+'\n');print(backend,cts,flush=True)
assert d['runs'][0]['counts']==d['runs'][1]['counts']
