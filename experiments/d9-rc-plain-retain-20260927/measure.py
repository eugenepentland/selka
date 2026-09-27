"""Full one-million-list allocation churn, actual backends and median three."""
import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/retain-run';work.mkdir(exist_ok=True)
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang','after':root/'.tmp-mut-argument/retain-candidate/bin/mylang'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=root/'bench/parity/micro/alloc_churn.my'
result={'base':'e926d1e13bf61ae3125102b46309225ca963a38d','cpu':2,'source_sha256':sha(source),'compilers':{a:{'path':str(p),'sha256':sha(p)} for a,p in compilers.items()},'builds':[],'backends':{}}
def save():(work/'measurement.json').write_text(json.dumps(result,indent=2)+'\n')
def run(cmd):return subprocess.run(cmd,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
for backend in ('qbe','llvm'):
 binaries={};counts={};outputs=[]
 for arm,compiler in compilers.items():
  for mode in ('rc','stats'):
   binary=work/f'alloc-churn-{backend}-{arm}-{mode}'
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(work/'cache'),'--keep-symbols','--rc-runtime=stats' if mode=='stats' else '--rc-runtime']
   if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
   built=run(command);row=dict(command=command,exit=built.returncode,stdout=built.stdout,stderr=built.stderr);result['builds'].append(row);save();assert built.returncode==0,row
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
   row.update(sha256=sha(binary),manifest=manifest);save();print('built',binary.name,flush=True)
   if mode=='rc':binaries[arm]=binary
   else:
    done=run(['taskset','-c','2',str(binary)]);assert done.returncode==0,done
    counts[arm]=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '));outputs.append(done.stdout)
 assert len(set(outputs))==1 and counts['before']==counts['after'],(outputs,counts)
 samples=[]
 for repetition in range(3):
  for arm in (('before','after') if repetition%2==0 else ('after','before')):
   command=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
   done=run(command);assert done.returncode==0 and done.stdout==outputs[0],done
   counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   samples.append(dict(arm=arm,command=command,counters=counters,stderr=done.stderr))
 medians={a:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==a) for a in binaries}
 result['backends'][backend]=dict(samples=samples,medians=medians,after_over_before=medians['after']/medians['before'],counts=counts,stdout=outputs[0]);save();print(backend,medians,result['backends'][backend]['after_over_before'],counts,flush=True)
