from pathlib import Path
import os,subprocess,json,hashlib,statistics,time
r=Path.cwd();w=r/'.tmp-rc/owned-hoist/full';w.mkdir(exist_ok=True)
compilers={'before':r.parent/'d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang','after':r/'.tmp-rc/install-owned-hoist/bin/mylang'}
sources={'fannkuch':r/'bench/parity/suite/fannkuch_redux.my','sieve':r/'bench/parity/suite/sieve.my','append':r/'bench/parity/micro/list_append_sum.my'}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env['TMPDIR']=str(r/'.tmp-rc/tmp')
data={'sources':{k:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in sources.items()},'compilers':{k:{'path':str(v),'sha256':hashlib.sha256(v.read_bytes()).hexdigest()} for k,v in compilers.items()},'builds':[],'runs':[],'medians':{}}
def save():(w/'results.json').write_text(json.dumps(data,indent=2)+'\n')
for name,source in sources.items():
 expected=source.with_suffix('.expected').read_text()
 for backend in ['qbe','llvm']:
  for side,c in compilers.items():
   for stats in [False,True]:
    b=w/f'{name}-{side}-{backend}-{"stats" if stats else "rc"}'
    cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(source),'-o',str(b),'--cache-dir='+str(w/f'cache-{side}'),'--keep-symbols','--rc-runtime'+('=stats' if stats else '')]
    cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
    p=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(case=name,backend=backend,side=side,stats=stats,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr);data['builds'].append(row);save();assert p.returncode==0,row
    row['binary_sha256']=hashlib.sha256(b.read_bytes()).hexdigest();save()
  for side in compilers:
   counts=[];binary=w/f'{name}-{side}-{backend}-rc'
   for repeat in range(3):
    stat=w/f'{name}-{side}-{backend}-{repeat}.stat';cmd=['taskset','-c','10','perf','stat','-x,','-e','instructions:u','-o',str(stat),str(binary)]
    p=subprocess.run(cmd,env=env,text=True,capture_output=True,timeout=600);raw=stat.read_text();count=next(int(line.split(',')[0]) for line in raw.splitlines() if 'instructions' in line and line.split(',')[0].isdigit())
    row=dict(case=name,command=cmd,backend=backend,side=side,repeat=repeat,status=p.returncode,stdout=p.stdout,stderr=p.stderr,perf=raw,instructions=count,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());data['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row
    counts.append(count)
   data['medians'][name+'-'+side+'-'+backend]=statistics.median(counts);save()
   binary=w/f'{name}-{side}-{backend}-stats';p=subprocess.run(['taskset','-c','10',str(binary)],env=env,text=True,capture_output=True,timeout=600)
   row=dict(case=name,backend=backend,side=side,stats=True,status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());data['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row
   row['counts']=json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in p.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')));save()
  pair=[a['counts'] for a in data['runs'] if a.get('stats') and a['case']==name and a['backend']==backend]
  for key in pair[0]:
   if key!='unique_check':assert pair[0][key]==pair[1][key],(name,key,pair)
  print(name,backend,data['medians'][name+'-after-'+backend]/data['medians'][name+'-before-'+backend],pair,flush=True)
