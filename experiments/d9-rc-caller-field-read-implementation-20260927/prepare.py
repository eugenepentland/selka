from pathlib import Path
import json, gzip, hashlib, os, subprocess
r=Path.cwd(); w=r/'.tmp-mut-argument/caller-field-read/controls'; src=r/'tests/lang/rc_caller_field_reads.my'
s=src.read_text(); tests=[x.split('(')[0] for x in s.splitlines() if x.startswith('public def test_')]; tests=[x.removeprefix('public def ') for x in tests]
s=s.rsplit('def main()',1)[0]+'def main() -> int:\n'+''.join('    assert '+name+'()\n' for name in tests)+'    return 0\n'; (w/'driver.my').write_text(s)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
compilers={'before':r/'.tmp-mut-argument/field-list-read/install-proof-final/bin/mylang','after':r/'.tmp-mut-argument/caller-field-read/install-prototype/bin/mylang'}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(r.parent/'.d9-rc-mut-argument-tmp'),MYLANG_MEMORY_LIMIT='8G')
result={'sources':{str(src):sha(src),str(w/'driver.my'):sha(w/'driver.my')},'compilers':{k:{'path':str(v),'sha256':sha(v)} for k,v in compilers.items()},'rows':[]}
def save(): (w/'guests.json').write_text(json.dumps(result,indent=2)+'\n')
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  for mode in ('rc', 'gc') if side=='after' else ('rc',):
   binary=w/(side+'-'+backend+'-'+mode)
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'driver.my'),'-o',str(binary),'--backend='+backend,'--cache-dir='+str(r/'.tmp-mut-argument/lox-post-record/current/cache')]
   if mode=='rc':cmd+=['--rc-runtime=stats']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=subprocess.run(cmd,env=env,capture_output=True,text=True); row={'side':side,'backend':backend,'mode':mode,'command':cmd,'exit':p.returncode,'stderr':p.stderr};result['rows'].append(row);save();assert not p.returncode,row
   row.update(binary=str(binary),sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert row['manifest']['backend']==backend
   runenv=env.copy()
   if mode=='gc':runenv['MYLANG_GC_STRESS']='1'
   q=subprocess.run([str(binary)],env=runenv,capture_output=True,text=True);row['run']={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr};save();assert not q.returncode,row
   print(side,backend,mode,'passed',len(tests),flush=True)
 for mode in (False,True):
  cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'emit-qbe',str(src),'--rc-runtime']
  if not mode:cmd+=['--drop-step-checks','--drop-frame-checks']
  p=subprocess.run(cmd,env=env,capture_output=True);assert not p.returncode,p.stderr
  (w/(side+('-accounted' if mode else '-plain')+'.json.gz')).write_bytes(gzip.compress(p.stdout,mtime=0))
  m=json.loads(p.stdout);print(side,'emitted',[(f['name'],f['il'].count('RC-CALLER-FIELD-READ-1')) for f in m['functions'] if 'RC-CALLER-FIELD-READ-1' in f['il']],flush=True)
for mode in ('plain','accounted'):
 a=json.loads(gzip.decompress((w/('before-'+mode+'.json.gz')).read_bytes()));b=json.loads(gzip.decompress((w/('after-'+mode+'.json.gz')).read_bytes()));a={f['name']:f for f in a['functions']};b={f['name']:f for f in b['functions']}
 assert a['readonly']['il']==b['readonly']['il'],'rejected floating path changed!'
 assert a['callback']['il']==b['callback']['il'],'callback fallback changed!'
 print(mode,'exact fallback IL identical',flush=True)
