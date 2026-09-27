import pathlib,subprocess,json,hashlib,statistics
r=pathlib.Path.cwd();w=r/'.tmp-rc/empty-frame/full';w.mkdir(exist_ok=True)
compilers={'before':r.parent/'d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang','after':r/'.tmp-rc/install-empty-frame/bin/mylang'}
data={'source_sha256':hashlib.sha256((r/'bench/parity/suite/nbody.my').read_bytes()).hexdigest(),'compilers':{k:{'path':str(v),'sha256':hashlib.sha256(v.read_bytes()).hexdigest()} for k,v in compilers.items()},'builds':[],'runs':[],'medians':{}}
def save():(w/'results.json').write_text(json.dumps(data,indent=2)+'\n')
expected=None
for backend in ['qbe','llvm']:
 for side,c in compilers.items():
  for stats in [False,True]:
   b=w/f'{side}-{backend}-{"stats" if stats else "rc"}'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(r/'bench/parity/suite/nbody.my'),'-o',str(b),'--cache-dir='+str(w/f'cache-{side}'),'--keep-symbols','--rc-runtime'+('=stats' if stats else '')]
   cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
   p=subprocess.run(cmd,text=True,capture_output=True);row=dict(command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);data['builds'].append(row);save();assert p.returncode==0,row
   row['binary_sha256']=hashlib.sha256(b.read_bytes()).hexdigest();save()
 for side in compilers:
  counts=[];binary=w/f'{side}-{backend}-rc'
  for repeat in range(3):
   stat=w/f'{side}-{backend}-{repeat}.stat';cmd=['taskset','-c','10','perf','stat','-x,','-e','instructions:u','-o',str(stat),str(binary)]
   p=subprocess.run(cmd,text=True,capture_output=True);raw=stat.read_text();count=next(int(line.split(',')[0]) for line in raw.splitlines() if 'instructions' in line and line.split(',')[0].isdigit())
   row=dict(command=cmd,backend=backend,side=side,repeat=repeat,status=p.returncode,stdout=p.stdout,stderr=p.stderr,perf=raw,instructions=count,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());data['runs'].append(row);save();assert p.returncode==0,row
   if expected is None:expected=p.stdout
   assert p.stdout==expected,row
   counts.append(count)
  data['medians'][side+'-'+backend]=statistics.median(counts);save()
  binary=w/f'{side}-{backend}-stats';p=subprocess.run(['taskset','-c','10',str(binary)],text=True,capture_output=True)
  row=dict(backend=backend,side=side,stats=True,status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());data['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row
  row['counts']=json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in p.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')));save()
 pair=[a['counts'] for a in data['runs'] if a.get('stats') and a['backend']==backend];assert pair[0]==pair[1],pair
 print(backend,data['medians']['after-'+backend]/data['medians']['before-'+backend],flush=True)
