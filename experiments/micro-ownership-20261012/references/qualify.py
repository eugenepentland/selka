#!/usr/bin/env python3
"""Run all fresh-reference correctness probes under one build-slot admission."""
import hashlib,importlib.util,json,os,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
OUT=pathlib.Path(__file__).resolve().parent
def write(name,data): (OUT/name).write_text(json.dumps(data,indent=2)+'\n')
spec=importlib.util.spec_from_file_location('registry',ROOT/'benchmarks/runtime/expanded/registry.py'); reg=importlib.util.module_from_spec(spec); spec.loader.exec_module(reg)
m=json.loads((OUT/'manifest.json').read_text()); results=m['builds']; env=dict(os.environ); env.update(m['environment'])
for key in list(env):
 if key in ('GODEBUG','RUSTFLAGS','RUSTC_BOOTSTRAP'): env.pop(key,None)
for item in results.values():
 if item['exit_status']==0:
  assert hashlib.sha256(pathlib.Path(item['path']).read_bytes()).hexdigest()==item['sha256']
qualification=[]
for case,meta in reg.inventory().items():
 for size,seed,iterations in (*reg.EDGE_PROBES,*[(n,42,7) for n in meta['sizes']]):
  expected=reg.checksum(case,size,iterations,seed)
  for arm in ('rust','go','zig-safe','zig-fast'):
   key=meta['group']+'/'+arm
   if results[key]['exit_status']!=0: continue
   cmd=[results[key]['path'],case,str(size),str(iterations),str(seed)]
   done=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=120)
   # Admission wrapper emits its receipt on stderr; guest stderr must be empty.
   stderr=re.sub(r'^build-slot:.*\n','',done.stderr,flags=re.M)
   match=re.fullmatch(r'([0-9]+) ([0-9]+)\n',done.stdout)
   ok=done.returncode==0 and not stderr and match is not None and int(match[1])==expected and int(match[2])>0
   qualification.append({'arm':key,'case':case,'size':size,'seed':seed,'iterations':iterations,'expected_checksum':expected,'command':cmd,'stdout':done.stdout,'stderr':done.stderr,'exit_status':done.returncode,'passed':ok})
write('qualification.json',{'schema':'micro-foreign-reference-qualification-v1','purpose':'correctness only; emitted kernel_ns are not performance evidence','edge_probes':reg.EDGE_PROBES,'documented_size_iterations':7,'probes':qualification,'passed':all(p['passed'] for p in qualification),'complete':len(qualification)==800})
print('qualification',len(qualification),'passed',all(p['passed'] for p in qualification),flush=True)
