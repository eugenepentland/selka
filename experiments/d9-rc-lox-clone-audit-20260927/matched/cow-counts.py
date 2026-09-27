from pathlib import Path
import hashlib,json,os,subprocess,signal
root=Path.cwd();w=root/'.tmp-argv';previous=root.parent/'d9-rc-plain-replace-astra/.tmp-lox';port=previous/'port';compiler=w/'install/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'cow-zig-cache'),MYLANG_MEMORY_LIMIT='8G',MYLANG_COW_COUNTING='1')
r={'compiler':str(compiler),'compiler_sha256':sha(compiler),'source_commit':'66054aab08b0fafa2b36b10c2df20bfac152e220','builds':[],'runs':[]}
def save(): (w/'cow-counts.json').write_text(json.dumps(r,indent=2)+'\n')
references=json.loads((w/'lox.json').read_text())['runs']
for backend in ('qbe','llvm'):
 binary=w/f'lox-gc-counts-{backend}'
 command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/'cow-cache'),f'--backend={backend}']
 if backend=='llvm':command+=['--llvm-opt=3','--lto']
 built=subprocess.run(command,cwd=port,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
 r['builds'].append(dict(backend=backend,command=command,cwd=str(port),environment={'MYLANG_COW_COUNTING':'1'},exit=built.returncode,stdout=built.stdout,stderr=built.stderr));save();assert built.returncode==0,built.stderr
 manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
 for n in (4,5):
  cmd=['taskset','-c','3',str(binary),'--engine=vm',str(previous/f'binary_trees_n{n}.lox')]
  p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env,start_new_session=True);expired=False
  try:out,err=p.communicate(timeout=15)
  except subprocess.TimeoutExpired:
   expired=True;os.killpg(p.pid,signal.SIGTERM)
   try:out,err=p.communicate(timeout=1)
   except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
  row=dict(backend=backend,n=n,command=cmd,exit=p.returncode,timeout=expired,stdout=out,stderr=err,binary_sha256=sha(binary),manifest_backend=manifest['backend'])
  if not expired:row['counts']=json.loads(next(s.removeprefix('cow-stats ') for s in err.splitlines() if s.startswith('cow-stats ')))
  r['runs'].append(row);save();print(backend,n,row,flush=True)
  ref=next(x for x in references if x['arm']=='after' and x['backend']==backend and x['case']==f'n{n}')
  assert not expired and p.returncode==0 and out==ref['stdout'],row
