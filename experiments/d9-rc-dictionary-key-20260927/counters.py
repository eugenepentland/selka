from pathlib import Path
import os,json,subprocess,hashlib
r=Path.cwd();w=r/'.tmp-rc/dict-key';out=w/'counted';out.mkdir(exist_ok=True)
source=(r/'bench/parity/micro/dict_count.my').read_text();source=source.replace('2000000','20000');s=w/'dict-count-20000.my';s.write_text(source)
cs={k:r/f'.tmp-rc/install-dict-key-{k}/bin/mylang' for k in ['before','prototype']}
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
d={'source':{'path':str(s),'sha256':sha(s)},'compilers':{},'builds':[],'runs':[]}
def save():(w/'counters-initial.json').write_text(json.dumps(d,indent=2)+'\n')
for side,c in cs.items():d['compilers'][side]={'path':str(c),'sha256':sha(c)}
for backend in ['qbe','llvm']:
 for side,c in cs.items():
  b=out/f'{side}-{backend}'
  cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(s),'-o',str(b),'--rc-runtime=stats','--cache-dir='+str(w/f'count-cache-{side}'),'--keep-symbols']
  cmd+=['--release'] if backend=='llvm' else ['--mode=ReleaseFast']
  p=subprocess.run(cmd,env=e,capture_output=True,text=True);row={'side':side,'backend':backend,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['builds'].append(row);save();assert p.returncode==0,row
  m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert m['backend']==backend;msha=sha(Path(str(b)+'.qbe-manifest.json'));row.update(binary_sha256=sha(b),manifest=m,manifest_sha256=msha);save()
  cmd=[str(r/'scripts/build-slot.sh'),'build',str(b)];p=subprocess.run(cmd,env=e,capture_output=True,text=True);row={'side':side,'backend':backend,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(row);save();assert p.returncode==0,row
  counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts;save();assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release'],row
  print(side,backend,row['stdout'].strip(),counts,flush=True)
assert len({x['stdout'] for x in d['runs']})==1
