"""Build frozen-compiler arms and qualify all unchanged registry fixtures; no timing campaign."""
import hashlib, json, os, pathlib, re, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
HERE=pathlib.Path(__file__).resolve().parent
SCRATCH=ROOT/'.tmp/micro-ownership/expanded'
COMPILER=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/gate-4034-install/bin/mylang')
sys.path.insert(0,str(ROOT/'benchmarks/runtime/expanded'))
import registry

def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(p,obj): p.write_text(json.dumps(obj,indent=2)+'\n')

def main():
 SCRATCH.mkdir(parents=True,exist_ok=True)
 for d in ['bin','logs','tmp','cache','zig-cache','counters']: (SCRATCH/d).mkdir(exist_ok=True)
 assert sha(COMPILER)=='8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa'
 env=os.environ.copy();env.update(TMPDIR=str(SCRATCH/'tmp'),ZIG_GLOBAL_CACHE_DIR=str(SCRATCH/'zig-cache'),ZIG_LOCAL_CACHE_DIR=str(SCRATCH/'zig-cache/local'))
 entries=[]; probes=[]
 for group in registry.GROUPS:
  refusal=subprocess.run([str(COMPILER),'check',str(HERE/'original'/f'{group}.my'),'--experimental-zero-rc'],capture_output=True,text=True,env=env)
  (HERE/f'{group}-original-zero-check.txt').write_text(refusal.stdout+refusal.stderr)
  for arm,subdir,zero in [('mylang-original-rc','original',False),('mylang-migrated-rc','migrated',False),('mylang-zero-rc','migrated',True)]:
   for kind in ['runtime','counted']:
    source=HERE/subdir/f'{group}.my';binary=SCRATCH/'bin'/f'{group}-{arm}-{kind}'
    flags=['--release','--link',str(ROOT/'benchmarks/runtime/ports/native_clock.c'),'--cache-dir='+str(SCRATCH/'cache')]
    if zero: flags+=['--experimental-zero-rc']
    if kind=='counted': flags+=['--counters']
    cmd=[str(COMPILER),'build',str(source),'-o',str(binary),*flags]
    log=SCRATCH/'logs'/f'{binary.name}.txt'
    print('Building',binary.name,flush=True)
    proc=subprocess.run([str(ROOT/'scripts/build-slot.sh'),'build',*cmd],capture_output=True,text=True,env=env)
    log.write_text(proc.stdout+proc.stderr)
    entry=dict(group=group,arm=arm,kind=kind,binary=str(binary) if proc.returncode==0 else None,sha256=sha(binary) if proc.returncode==0 else None,status='ok' if proc.returncode==0 else 'refused',source=str(source),source_sha256=sha(source),flags=flags,command=cmd,diagnostic=str(log),returncode=proc.returncode)
    entries.append(entry);save(HERE/'manifest.json',dict(entries=entries,compiler=str(COMPILER),compiler_sha256=sha(COMPILER),clock_sha256=sha(ROOT/'benchmarks/runtime/ports/native_clock.c')))
    if proc.returncode: print(log.read_text()[-2500:],flush=True);continue
    for case,meta in registry.inventory().items():
     if meta['group']!=group:continue
     fixtures=list(registry.EDGE_PROBES)+[(n,42,3) for n in meta['sizes']]
     for size,seed,iters in fixtures:
      runenv=env.copy();counter=SCRATCH/'counters'/f'{binary.name}-{case}-{size}-{seed}-{iters}.json'
      if kind=='counted':runenv['MYLANG_COUNTERS']=str(counter)
      args=[str(binary),case,str(size),str(iters),str(seed)]
      run=subprocess.run(args,capture_output=True,text=True,env=runenv,timeout=60)
      match=re.fullmatch(r'(\d+) (\d+)\n',run.stdout)
      expected=registry.checksum(case,size,iters,seed)
      valid=bool(run.returncode==0 and match and int(match[1])==expected and int(match[2])>0)
      result=dict(group=group,arm=arm,kind=kind,case=case,size=size,seed=seed,iterations=iters,command=args,expected=expected,stdout=run.stdout,stderr=run.stderr,returncode=run.returncode,ok=valid,counters=str(counter) if counter.exists() else None)
      if counter.exists():
       data=json.loads(counter.read_text())
       result['counter_sha256']=sha(counter)
       result['counter_data']={key:data[key] for key in ('version','totals','kinds')}
      probes.append(result)
      if not valid:print('FAILED',result,flush=True)
    save(HERE/'qualification.json',dict(probes=probes,inventory=registry.inventory(),edge_probes=registry.EDGE_PROBES,all_ok=all(p['ok'] for p in probes),note='Native elapsed output is retained only to validate protocol; no calibration or performance measurement.'))
 print('Done',len(entries),'builds',len(probes),'probes; failures',sum(not p['ok'] for p in probes),flush=True)
if __name__=='__main__':main()
