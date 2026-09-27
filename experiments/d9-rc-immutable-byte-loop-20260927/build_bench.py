from pathlib import Path
import os,json,subprocess,hashlib,time
r=Path.cwd();w=r/'.tmp-bytes';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();s=r/'bench/parity/micro/bytes_scan.my'
cs={'before':r.parent/'d9-rc-integration/.tmp-rc/install-loops-fixed/bin/mylang','after':w/'install-after/bin/mylang'};e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(r/'.zig-cache-bytes-guests'));result={'source_sha256':sha(s),'compilers':{k:{'path':str(v),'sha256':sha(v)} for k,v in cs.items()},'rows':[]}
def save():(w/'benchmark-builds.json').write_text(json.dumps(result,indent=2)+'\n')
for arm,c in cs.items():
 for backend in ['qbe','llvm']:
  for counted in [False,True]:
   b=w/f'bytes-scan-{arm}-{backend}'+Path('') if False else w/f'bytes-scan-{arm}-{backend}-{int(counted)}'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(s),'-o',str(b),'--cache-dir',str(w/f'guest-cache-{arm}'),f'--backend={backend}',('--rc-runtime=stats' if counted else '--rc-runtime')]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   start=time.monotonic();p=subprocess.run(cmd,env=e,capture_output=True,text=True);row=dict(arm=arm,backend=backend,counted=counted,command=cmd,exit=p.returncode,stdout=p.stdout,stderr=p.stderr,build_wall_seconds=time.monotonic()-start);result['rows'].append(row);save();assert p.returncode==0,row
   row['binary_sha256']=sha(b);row['binary']=str(b);row['manifest']=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend;save();print('BUILT',arm,backend,counted,round(row['build_wall_seconds'],2),flush=True)
print('COMPLETE',flush=True)
