#!/usr/bin/env python3
# spec: NEW-CORE-ZERO-RC-1
import hashlib,json,os,subprocess
from pathlib import Path
H=Path(__file__).resolve().parent
O=H.parents[3]/'.tmp/memory-closeout/A05/frontend-mut-diagnosis'
O.mkdir(parents=True,exist_ok=True)
C='/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang'
Z=os.environ['ZIG']
results={'compiler':C,'compiler_sha256':hashlib.sha256(Path(C).read_bytes()).hexdigest(),'source_revision':'bed11cf3bf3102ffec44487e431a1573fdf02ad5','cases':[]}
for name in ['dynamic','named']:
 for owned in [False,True]:
  for command in ['test','build']:
   key=name+('-owned-' if owned else '-ordinary-')+command
   argv=[C,command,str(H/(name+'.my')),'--release','--zig',Z,'--cache-dir',str(O/(key+'-cache'))]
   if owned:argv+=['--experimental-zero-rc']
   if command=='test':argv+=['--filter','test_','--force','--json','--jobs','1']
   else:argv+=['-o',str(O/key),'--emit-llvm',str(O/(key+'.ll'))]
   r=subprocess.run(argv,text=True,capture_output=True)
   row={'name':key,'argv':argv,'source_sha256':hashlib.sha256((H/(name+'.my')).read_bytes()).hexdigest(),'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
   if command=='build' and r.returncode==0:
    run=subprocess.run([str(O/key)],text=True,capture_output=True)
    row['run']={'status':run.returncode,'stdout':run.stdout,'stderr':run.stderr}
   results['cases'].append(row)
   (O/'results.json').write_text(json.dumps(results,indent=2)+'\n')
   print(key,r.returncode,row.get('run',{}).get('status',''),flush=True)
for owned in [False,True]:
 key='values'+('-owned' if owned else '-ordinary')
 argv=[C,'build',str(H/'dynamic-values.my'),'--release','--zig',Z,'--cache-dir',str(O/(key+'-cache')),'-o',str(O/key),'--emit-llvm',str(O/(key+'.ll'))]
 if owned:argv+=['--experimental-zero-rc']
 r=subprocess.run(argv,text=True,capture_output=True)
 row={'name':key,'argv':argv,'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
 if r.returncode==0:
  run=subprocess.run([str(O/key)],text=True,capture_output=True)
  row['run']={'status':run.returncode,'stdout':run.stdout,'stderr':run.stderr}
 results['cases'].append(row)
 (O/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(key,r.returncode,row.get('run',{}).get('status',''),flush=True)
