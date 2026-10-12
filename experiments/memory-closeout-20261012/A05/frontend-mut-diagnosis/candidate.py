#!/usr/bin/env python3
# spec: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
import hashlib,json,os,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[4]
H=Path(__file__).resolve().parent
O=R/'.tmp/memory-closeout/A05/scalar-mut/candidate';O.mkdir(parents=True,exist_ok=True)
C=max((R/'.zig-cache/o').glob('*/mylang'),key=lambda p:p.stat().st_mtime).resolve()
Z=os.environ['ZIG']
env=dict(os.environ,MYLANG_COMPONENT_DIR=str(R/'zig-out/libexec/mylang/components'),MYL_CORE_LEAKCHECK='1')
results={'compiler':str(C),'compiler_sha256':hashlib.sha256(C.read_bytes()).hexdigest(),'base':'d01f772cd0cfa823a9ec6a8838aaf5c4856710b4','production_overlay':{'src/core/build.zig':hashlib.sha256((R/'src/core/build.zig').read_bytes()).hexdigest()},'cases':[]}
modes={'release':['--release'],'debug':['--unoptimized'],'verified':['--release','--verify-facts'],'optimized-debug':['--optimize-debug'],'no-facts':['--release','--no-facts']}
for mode,flags in modes.items():
 argv=[str(C),'test',str(R/'tests/lang/frontend_mut.my'),'--experimental-zero-rc',*flags,'--force','--json','--jobs','1','--zig',Z,'--cache-dir',str(O/'cache')]
 ran=subprocess.run(argv,env=env,text=True,capture_output=True)
 row={'name':mode,'argv':argv,'status':ran.returncode,'stdout':ran.stdout,'stderr':ran.stderr}
 try:row['json']=json.loads(ran.stdout)
 except ValueError:pass
 results['cases'].append(row)
 (O/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(mode,ran.returncode,{k:row.get('json',{}).get(k) for k in ['passed','failed','unsupported']},flush=True)
for name in ['dynamic','named','dynamic-values']:
 binary=O/name
 argv=[str(C),'build',str(H/(name+'.my')),'--experimental-zero-rc','--release','--counters','--zig',Z,'--cache-dir',str(O/'cache'),'--emit-llvm',str(binary)+'.ll','-o',str(binary)]
 ran=subprocess.run(argv,env=env,text=True,capture_output=True)
 row={'name':name,'argv':argv,'status':ran.returncode,'stdout':ran.stdout,'stderr':ran.stderr}
 if ran.returncode==0:
  counts=O/(name+'-counts.json');run=subprocess.run([str(binary)],env=dict(env,MYLANG_COUNTERS=str(counts)),text=True,capture_output=True)
  row['run']={'status':run.returncode,'stdout':run.stdout,'stderr':run.stderr}
  if counts.exists():row['counts']=json.loads(counts.read_text())
 results['cases'].append(row)
 (O/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(name,ran.returncode,row.get('run',{}).get('status'),flush=True)
