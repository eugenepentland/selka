from pathlib import Path
import os,subprocess,json,hashlib
r=Path.cwd();w=r/'.tmp-rc/dict-loop';s=w/'controls/arena-heap-keys.my'
s.write_text('''def work(source: list[str]) -> int:
    keys = source
    counts: dict[str, int] = {}
    for i in range(1000):
        key = keys[i]
        counts[key] = counts.get(key, 0) + 1
    assert len(keys) == 1000
    return len(counts)

def main(out: Stream) -> int:
    keys: list[str] = []
    for i in range(1000):
        keys.append("key" + str(i))
    out.print("before")
    with arena():
        out.print(work(keys))
    return 0
''')
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
cs={'before':r/'.tmp-rc/install-dict-key-prototype/bin/mylang','after':r/'.tmp-rc/install-dict-loop/bin/mylang'}
d={'source_sha256':hashlib.sha256(s.read_bytes()).hexdigest(),'builds':[],'runs':[]}
p=subprocess.run([str(cs['after']),'emit-qbe',str(s),'--rc-runtime'],env=e,text=True,capture_output=True);assert p.returncode==0,p.stderr
il=next(x['il'] for x in json.loads(p.stdout)['functions'] if x['name']=='work');(w/'controls/arena-heap-keys.ssa').write_text(il);assert '\n@ce' in il
for backend in ['qbe','llvm']:
 for side,c in cs.items():
  b=w/f'arena-heap-keys-{side}-{backend}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(s),'-o',str(b),'--rc-runtime=stats','--backend='+backend,'--mode=Debug','--cache-dir='+str(w/f'control-cache-{side}')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  p=subprocess.run(cmd,env=e,text=True,capture_output=True);d['builds'].append(dict(side=side,backend=backend,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==0,p.stderr
  m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert m['backend']==backend;d['builds'][-1].update(manifest=m,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest())
  for budget in ['320K','384K','448K','512K']:
   env=dict(e);env['MYLANG_MEMORY_LIMIT']=budget
   p=subprocess.run([str(b)],env=env,text=True,capture_output=True,timeout=60);row=dict(side=side,backend=backend,budget=budget,status=p.returncode,stdout=p.stdout,stderr=p.stderr);d['runs'].append(row)
   counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts
   assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],row
   print(side,backend,budget,p.returncode,p.stderr.split('error[')[-1][:100],flush=True)
  (w/'arena-extra.json').write_text(json.dumps(d,indent=2)+'\n')
for a in d['runs']:
 if a['side']!='before':continue
 b=next(x for x in d['runs'] if x['side']=='after' and all(x[k]==a[k] for k in ['backend','budget']))
 trace=lambda x:'\n'.join(z for z in x['stderr'].splitlines() if not z.startswith('MYLANG_RC_COUNTS '))
 assert (a['status'],a['stdout'],trace(a))==(b['status'],b['stdout'],trace(b)),(a,b)
