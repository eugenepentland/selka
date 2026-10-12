#!/usr/bin/env python3
"""Borrowed-context source boundaries and exact A10 entry authority contracts.
Caller owns build admission. This harness never grants a replacement provider.
"""
import argparse,hashlib,json,os,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
MODES={'release':['--release'],'debug':['--unoptimized'],'verified':['--release','--verify-facts'],'optimized-debug':['--optimize-debug'],'no-facts':['--release','--no-facts']}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def command(argv,**kw):
 r=subprocess.run(list(map(str,argv)),capture_output=True,text=True,timeout=600,**kw)
 return {'argv':list(map(str,argv)),'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--zig',required=True);p.add_argument('--phase',choices=['negative','entry'],required=True);a=p.parse_args()
 a.output.mkdir(parents=True,exist_ok=True);a.compiler=a.compiler.resolve();a.output=a.output.resolve()
 report={'phase':a.phase,'compiler':str(a.compiler),'compiler_sha256':sha(a.compiler),'harness_sha256':sha(Path(__file__)),'cases':{}}
 env=dict(os.environ);env.pop('MYLANG_OPTIONS',None);env.pop('MYLANG_COUNTERS',None)
 if a.phase=='negative':
  for source in sorted(HERE.glob('negative_*.my')):
   row={'source_sha256':sha(source),'ordinary':command([a.compiler,'check',source,'--cache-dir',a.output/'cache'],env=env)}
   row['owned']=command([a.compiler,'check',source,'--experimental-zero-rc','--cache-dir',a.output/'cache'],env=env)
   row['diagnostics']=re.findall(r'error\[([^]]+)\]',row['owned']['stderr']);row['passed']=row['owned']['status']==1 and bool(row['diagnostics']);report['cases'][source.name]=row
   print(source.name,row['ordinary']['status'],row['owned']['status'],row['diagnostics'],flush=True)
 else:
  source=HERE/'entry_context.my'
  for mode,flags in MODES.items():
   target=a.output/mode;target.mkdir(exist_ok=True);binary=target/'program';llvm=target/'program.ll'
   row={'source_sha256':sha(source),'build':command([a.compiler,'build',source,'--experimental-zero-rc',*flags,'--counters','--zig',a.zig,'--cache-dir',a.output/'cache','-o',binary,'--emit-llvm',llvm],env=env),'runs':{}}
   row['passed']=row['build']['status']==0 and not row['build']['stderr']
   if row['build']['status']==0:
    row['binary_sha256']=sha(binary);row['llvm_sha256']=sha(llvm);row['marker_absent']= 'myl_core_borrowed_provider_v1_' not in llvm.read_text();row['passed'] &=row['marker_absent']
    symbols=command(['nm',binary]);row['rc_symbols_absent']=not re.search(r'\b(myl_core_retain|myl_core_release|myl_core_share|myl_core_is_unique)$',symbols['stdout'],re.M);row['passed'] &=row['rc_symbols_absent']
    for name,grant,exists,expected in [('granted',True,True,6),('missing',True,False,0),('denied',False,True,0)]:
     work=target/name;work.mkdir(exist_ok=True)
     if exists:(work/'note.txt').write_text('hello')
     counts=work/'counts.json'
     options='--restrict --allow-env=A05_ENTRY'
     if grant:options+=' --allow-read='+str(work)
     else:
      allowed=work/'allowed';allowed.mkdir(exist_ok=True);options+=' --allow-read='+str(allowed)
     run=command([binary],cwd=work,env=dict(env,A05_ENTRY='actual input',MYLANG_OPTIONS=options,MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1'))
     run['expected_status']=expected
     if counts.exists():run['counts']=json.loads(counts.read_text())
     t=run.get('counts',{}).get('totals',{});run['passed']=run['status']==expected and not run['stderr'] and t.get('live_bytes_at_exit')==0 and t.get('runtime_retains')==0 and t.get('runtime_releases')==0 and t.get('shared_retains')==0 and t.get('shared_releases')==0
     row['runs'][name]=run;row['passed'] &=run['passed']
   report['cases'][mode]=row;print(mode,row['passed'],{k:v['status'] for k,v in row['runs'].items()},flush=True)
 report['passed']=all(c['passed'] for c in report['cases'].values());(a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n');return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
