from pathlib import Path
import os,subprocess,json,hashlib,statistics
r=Path.cwd();w=r/'.tmp-rc/dict-loop';f=w/'full';f.mkdir(exist_ok=True)
cs={'before':r/'.tmp-rc/install-dict-key-prototype/bin/mylang','after':r/'.tmp-rc/install-dict-loop/bin/mylang'}
s=r/'bench/parity/micro/dict_count.my';expected=s.with_suffix('.expected').read_text()
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
d={'source':{'path':str(s),'sha256':sha(s)},'compilers':{k:{'path':str(c),'sha256':sha(c)} for k,c in cs.items()},'builds':[],'runs':[],'medians':{}}
def save():(w/'measurements.json').write_text(json.dumps(d,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for side,c in cs.items():
  for stats in (False,True):
   b=f/f'{side}-{backend}-{"stats" if stats else "rc"}'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(s),'-o',str(b),'--cache-dir='+str(w/f'final-cache-{side}'),'--keep-symbols','--rc-runtime'+('=stats' if stats else '')]
   cmd+=['--release'] if backend=='llvm' else ['--mode=ReleaseFast']
   
   p=subprocess.run(cmd,env=e,text=True,capture_output=True)
   row=dict(side=side,backend=backend,stats=stats,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);d['builds'].append(row);save();assert p.returncode==0,row
   manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend,manifest
   row.update(binary_sha256=sha(b),manifest=manifest);save()
 for side in ('gc','before','after'):
  b=r.parent/'d9-rc-performance/.tmp-rc-performance/bin/gc'/f'parity-micro-dict_count.{backend}' if side=='gc' else f/f'{side}-{backend}-rc'
  counts=[]
  for repeat in range(3):
   stat=f/f'{side}-{backend}-{repeat}.stat';cmd=['taskset','-c','11','perf','stat','-x,','-e','instructions:u','-o',str(stat),str(b)]
   p=subprocess.run(cmd,env=e,text=True,capture_output=True,timeout=600);raw=stat.read_text();line=next(x for x in raw.splitlines() if 'instructions' in x and x.split(',')[0].isdigit());n=int(line.split(',')[0]);assert float(line.split(',')[4])==100.0,line
   row=dict(side=side,backend=backend,repeat=repeat,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr,perf=raw,instructions=n,binary_sha256=sha(b));d['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row;counts.append(n)
  d['medians'][side+'-'+backend]=statistics.median(counts);save()
 for side in cs:
  b=f/f'{side}-{backend}-stats';cmd=['taskset','-c','11',str(b)];p=subprocess.run(cmd,env=e,text=True,capture_output=True,timeout=600)
  row=dict(side=side,backend=backend,stats=True,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=sha(b));d['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row
  counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts
  assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],counts;save()
 print(backend,'after/before',d['medians']['after-'+backend]/d['medians']['before-'+backend],'after/GC',d['medians']['after-'+backend]/d['medians']['gc-'+backend],flush=True)
