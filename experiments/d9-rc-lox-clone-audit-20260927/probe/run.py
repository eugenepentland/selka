from pathlib import Path
import hashlib,json,os,subprocess,signal
root=Path.cwd();w=root/'.tmp-probe';previous=root.parent/'d9-rc-plain-replace-astra/.tmp-lox';port=previous/'port';compiler=w/'install/bin/mylang';baseline=json.loads((root.parent/'d9-rc-argv-astra/.tmp-argv/lox.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'base':'66054aab08b0fafa2b36b10c2df20bfac152e220','compiler':str(compiler),'compiler_sha256':sha(compiler),'instrumented_source_sha256':sha(root/'src/native_rc_transfer.c'),'runs':[]}
binary=w/'lox-probe-qbe'
command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/'cache'),'--backend=qbe','--rc-runtime=stats','--keep-symbols']
built=subprocess.run(command,cwd=port,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
r['build']={'command':command,'cwd':str(port),'exit':built.returncode,'stdout':built.stdout,'stderr':built.stderr}
def save(): (w/'probe.json').write_text(json.dumps(r,indent=2)+'\n')
save();assert built.returncode==0,built.stderr
r['binary_sha256']=sha(binary);r['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());r['runtime_sha256']=sha(Path(r['manifest']['runtime_object']))
subprocess.run(['nm','-an',str(binary)],stdout=(w/'symbols.txt').open('w'),check=True)
for n in (4,5):
 command=['taskset','-c','3',str(binary),'--engine=vm',str(previous/f'binary_trees_n{n}.lox')]
 p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env,start_new_session=True);expired=False
 try:out,err=p.communicate(timeout=15)
 except subprocess.TimeoutExpired:
  expired=True;os.killpg(p.pid,signal.SIGTERM)
  try:out,err=p.communicate(timeout=1)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
 row={'n':n,'command':command,'exit':p.returncode,'stdout':out,'stderr':err,'timeout':expired}
 if not expired:
  row['counts']=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in err.splitlines() if s.startswith('MYLANG_RC_COUNTS ')))
  row['probe']=json.loads(next(s.removeprefix('RC_CLONE_PROBE ') for s in err.splitlines() if s.startswith('RC_CLONE_PROBE ')))
 r['runs'].append(row);save()
 ref=next(x for x in baseline['runs'] if x['arm']=='after' and x['backend']=='qbe' and x['case']==f'n{n}')
 assert not expired and p.returncode==0 and out==ref['stdout'] and row['counts']==ref['counts'],row
 data=row['probe'];assert not data['rows_overflow'] and not data['operations_overflow']
 assert sum(x['created'] for x in data['rows'])==row['counts']['clone_shell']
 assert sum(x['committed']+x['rolled_back'] for x in data['rows'])==row['counts']['clone_shell']
 print('n',n,'rows',len(data['rows']),'shells',row['counts']['clone_shell'],'complete',flush=True)
 for entry in data['rows']:print(entry,flush=True)
