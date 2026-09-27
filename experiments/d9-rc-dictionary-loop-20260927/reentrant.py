from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd();w=r/'.tmp-rc/dict-loop';e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
cmd=['cc','-O2','-I',str(r/'src'),str(w/'reentrant.c'),'-ldl','-o',str(w/'reentrant')];p=subprocess.run(cmd,text=True,capture_output=True);assert p.returncode==0,p.stderr
d={'harness_command':cmd,'runs':[]}
for side in ('before','after'):
 c=r/('.tmp-rc/install-dict-key-prototype/bin/mylang' if side=='before' else '.tmp-rc/install-dict-loop/bin/mylang')
 for backend in ('qbe','llvm'):
  b=w/f'reentrant-{side}-{backend}.so';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'reentrant.my'),'--library','--rc-runtime=stats','--backend='+backend,'--mode=Debug','-o',str(b),'--cache-dir='+str(w/f'embed-cache-{side}')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  p=subprocess.run(cmd,env=e,text=True,capture_output=True);row=dict(side=side,backend=backend,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),build=cmd,build_status=p.returncode,build_stderr=p.stderr);d['runs'].append(row);(w/'reentrant.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
  manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend;row['manifest']=manifest
  symbol=next(x['symbol'] for x in manifest['functions'] if x['name']=='update');cmd=[str(w/'reentrant'),str(b),symbol];p=subprocess.run(cmd,env=e,text=True,capture_output=True,timeout=30)
  row.update(command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest());(w/'reentrant.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
  counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts;assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],row
  (w/'reentrant.json').write_text(json.dumps(d,indent=2)+'\n');print(side,backend,p.stdout,flush=True)
