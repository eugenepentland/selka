from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd(); w=r/'.tmp-rc/dict-loop'; src=w/'controls'; src.mkdir(exist_ok=True)
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}; e['TMPDIR']=str(r/'.tmp-rc/tmp')
cs={'before':r/'.tmp-rc/install-dict-key-prototype/bin/mylang','after':r/'.tmp-rc/install-dict-loop/bin/mylang'}
base='''def work() -> int:
    keys = ["a" + "-key", "b-key"]
    counts: dict[str, int] = {}
    for i in range(10):
        key = keys[i % 2]
        counts[key] = counts.get(key, 0) + 1
    assert len(keys) == 2
    return counts.get("a-key", 0)
'''
main='''
def main(out: Stream) -> int:
    out.print("before")
    out.print(work())
    return 0
'''
sources={'steps':base+main,'bounds':base.replace('range(10)','range(3)').replace('keys[i % 2]','keys[i]')+main,'zero':base.replace('range(10)','range(0)')+main,'overflow':base.replace('counts.get(key, 0) + 1','counts.get(key, 9223372036854775807) + 1')+main}
growth='''def work() -> int:
    keys: list[str] = []
    for i in range(1000):
        keys.append("key" + str(i))
    counts: dict[str, int] = {}
    for i in range(1000):
        key = keys[i]
        counts[key] = counts.get(key, 0) + 1
    assert len(keys) == 1000
    return len(counts)
'''
sources['growth']=growth+main
sources['arena']=growth+main.replace('    out.print(work())','    with arena():\n        out.print(work())')
for name,s in sources.items():(src/f'{name}.my').write_text(s)
d={'compilers':{k:{'path':str(c),'sha256':hashlib.sha256(c.read_bytes()).hexdigest()} for k,c in cs.items()},'emission':[],'builds':[],'runs':[]}
def save():(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n')
for name in sources:
 cmd=[str(cs['after']),'emit-qbe',str(src/f'{name}.my'),'--rc-runtime']
 p=subprocess.run(cmd,env=e,text=True,capture_output=True);assert p.returncode==0,p.stderr
 il=next(x['il'] for x in json.loads(p.stdout)['functions'] if x['name']=='work');(src/f'{name}.ssa').write_text(il)
 row={'case':name,'command':cmd,'sha256':hashlib.sha256((src/f'{name}.my').read_bytes()).hexdigest(),'entry': '\n@ce' in il,'fast':'\n@fi' in il};d['emission'].append(row);save();assert row['entry'],row
for backend in ['qbe','llvm']:
 for side,c in cs.items():
  for case in sources:
   b=w/f'control-{side}-{backend}-{case}'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(src/f'{case}.my'),'-o',str(b),'--cache-dir='+str(w/f'control-cache-{side}'),'--backend='+backend,'--mode=Debug','--rc-runtime=stats']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=subprocess.run(cmd,env=e,text=True,capture_output=True);row=dict(side=side,backend=backend,case=case,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);d['builds'].append(row);save();assert p.returncode==0,row
   m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert m['backend']==backend;row.update(manifest=m,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest());save()
   variants=[('128M','')]
   if case=='steps':variants=[('128M',f'--max-steps={n}') for n in [30,40,50,60]]
   if case in ['growth','arena']:variants=[(n,'') for n in ['384K','512K','1M']]
   if case=='zero':variants=[('192K',''),('128M','')]
   for budget,opt in variants:
    env=dict(e);env.update(MYLANG_MEMORY_LIMIT=budget,MYLANG_OPTIONS=opt)
    p=subprocess.run([str(b)],env=env,text=True,capture_output=True,timeout=60)
    row=dict(side=side,backend=backend,case=case,budget=budget,options=opt,status=p.returncode,stdout=p.stdout,stderr=p.stderr);d['runs'].append(row);save()
    lines=[x for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(lines)==1,row
    counts=json.loads(lines[0].removeprefix('MYLANG_RC_COUNTS '));row['counts']=counts
    assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],row
    assert p.returncode in [0,1],row
    if case in ['bounds','overflow','steps']:assert p.returncode==1 and {'bounds':'R_LIST_BOUNDS','overflow':'R_OVERFLOW','steps':'R_STEP_LIMIT'}[case] in p.stderr,row
    save()
   print(backend,side,case,'pass',flush=True)
for a in d['runs']:
 if a['side']!='before':continue
 b=next(x for x in d['runs'] if x['side']=='after' and all(x[k]==a[k] for k in ['backend','case','budget','options']))
 trace=lambda x:'\n'.join(y for y in x['stderr'].splitlines() if not y.startswith('MYLANG_RC_COUNTS '))
 assert (a['status'],a['stdout'],trace(a))==(b['status'],b['stdout'],trace(b)),(a,b)
print('exact paired outputs/status/traces pass',flush=True)
