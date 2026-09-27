from pathlib import Path
import hashlib,json,os,signal,subprocess,time
root=Path.cwd();w=root/'.tmp-lox';binary=w/'lox-before-qbe';compiler=root/'.tmp-plain/install-before/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['MYLANG_MEMORY_LIMIT']='8G'
r={'compiler_commit':'2d41fb4f49eda4dbf318cabc78fe497361cf1ca9','compiler_sha256':sha(compiler),'binary_sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()),'runs':[]}
def bounded(command,seconds=15):
 start=time.monotonic();p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env,start_new_session=True);expired=False
 try:out,err=p.communicate(timeout=seconds)
 except subprocess.TimeoutExpired:
  expired=True;os.killpg(p.pid,signal.SIGTERM)
  try:out,err=p.communicate(timeout=1)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
 return {'command':command,'exit':p.returncode,'timeout':expired,'stdout':out,'stderr':err,'wall_seconds':time.monotonic()-start}
def save(): (w/'profile.json').write_text(json.dumps(r,indent=2)+'\n')
for n in (4,5):
 script=w/f'binary_trees_n{n}.lox'
 reference=json.loads((w/('initial-controls.json' if n==4 else 'size-controls.json')).read_text())['runs']
 expected=next(row['stdout'] for row in reference if row['side']=='gc' and (n==4 or row['n']==n))
 command=['taskset','-c','3','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binary),'--engine=vm',str(script)]
 row=bounded(command);row['n']=n;r['runs'].append(row);save();print(n,row['exit'],row['wall_seconds'],flush=True)
 assert row['exit']==0 and row['stdout']==expected
 command=['perf','record','-q','-e','cpu_core/instructions/u','-c','10000000','--call-graph','fp','-o',str(w/f'n{n}.data'),'--','taskset','-c','3',str(binary),'--engine=vm',str(script)]
 row=bounded(command);row.update(n=n,kind='profile');r['runs'].append(row);save();assert row['exit']==0 and row['stdout']==expected
 for suffix,args in [('samples.txt',['script','-F','ip,sym,dso,period']),('report.txt',['report','--stdio','--no-children','--sort','symbol,dso','--percent-limit','0.2']),('callers.txt',['report','--stdio','--children','--sort','symbol,dso','--percent-limit','1']),('stats.txt',['report','--stdio','--stats'])]:
  done=subprocess.run(['perf']+args+['-i',str(w/f'n{n}.data')],text=True,capture_output=True,check=True)
  (w/f'n{n}.{suffix}').write_text(done.stdout+done.stderr)
 print('profiled',n,flush=True)
