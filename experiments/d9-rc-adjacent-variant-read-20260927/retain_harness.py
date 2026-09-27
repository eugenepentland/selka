from pathlib import Path
import os,subprocess,json,hashlib,re
root=Path.cwd();w=root/'.tmp-variant-read';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'runs':[]}
def save():(w/'retain-harness.json').write_text(json.dumps(r,indent=2)+'\n')
cmd=['cc','-O2','-I',str(root/'src'),str(w/'retain_harness.c'),'-ldl','-o',str(w/'retain_harness')];d=subprocess.run(cmd,capture_output=True,text=True);assert d.returncode==0,d.stderr
for arm,compiler in [('before',root.parent/'d9-rc-integration/.tmp-rc/install-snapshot-joined/bin/mylang'),('after',w/'install/bin/mylang')]:
 for backend in ('qbe','llvm'):
  library=w/f'retain-{arm}-{backend}.so';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(w/'retain-budget.my'),'--library','--mode=Debug','--rc-runtime=stats','-o',str(library),'--cache-dir',str(w/'retain-cache'),f'--backend={backend}']
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  d=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(arm=arm,backend=backend,compiler_sha256=sha(compiler),build_command=cmd,build_exit=d.returncode,build_stderr=d.stderr);r['runs'].append(row);save();assert d.returncode==0,row
  manifest=json.loads(Path(str(library)+'.qbe-manifest.json').read_text());row['manifest']=manifest;assert manifest['backend']==backend
  symbols={f['name']:f['symbol'] for f in manifest['functions']}
  cmd=[str(w/'retain_harness'),str(library),symbols['make'],symbols['probe']];d=subprocess.run(cmd,env=env,text=True,capture_output=True,timeout=30);row.update(run_command=cmd,exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=sha(library));save();assert d.returncode==0,row
  c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
  if arm=='after':
   cmd=[str(compiler),'emit-qbe',str(w/'retain-budget.my'),'--rc-runtime=stats'];emitted=subprocess.run(cmd,env=env,text=True,capture_output=True);assert emitted.returncode==0,emitted.stderr
   il=next(x['il'] for x in json.loads(emitted.stdout)['functions'] if x['name']=='probe');row['admitted']=il.count('# RC-ADJACENT-VARIANT-READ-1');assert row['admitted']==1
   row['emitted_sha256']=hashlib.sha256(emitted.stdout.encode()).hexdigest();(w/f'retain-{backend}-emitted.json').write_text(emitted.stdout)
  save();print('PASS',arm,backend,d.stdout.strip(),flush=True)
