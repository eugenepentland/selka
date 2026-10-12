#!/usr/bin/env python3
"""One separately instrumented, oracle-checked run per counted arm and cell.
Invoke under shared timing admission; never mix counted results with runtime/RSS.
"""
import argparse,json,pathlib,subprocess,sys
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--arm',action='append',required=True,help='NAME=qualified counted binary')
p.add_argument('--cpu',type=int,default=8)
p.add_argument('--guest-timeout',type=float,default=120)
p.add_argument('specs',nargs='+',type=pathlib.Path)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
for path in a.specs:
 spec=json.loads(path.read_text());example=spec['arms']['zig-safe'];spec['arms']={'zig-safe':example};spec['env_by_arm']={}
 counters={}
 for arg in a.arm:
  name,binary=arg.split('=',1);assert name!='zig-safe' and name not in counters
  spec['arms'][name]=[str(pathlib.Path(binary).resolve()),*example[1:]]
  counter=(a.output/(path.stem+'.'+name+'.counters.json')).resolve();assert not counter.exists()
  spec['env_by_arm'][name]={'MYLANG_COUNTERS':str(counter)};counters[name]=counter
 generated=a.output/(path.stem+'.counted.spec.json');receipt=a.output/(path.stem+'.counted.qualification.json')
 assert not generated.exists();generated.write_text(json.dumps(spec,indent=2)+'\n')
 subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('measure.py')),str(generated),str(receipt),'--cpu',str(a.cpu),'--rounds','0','--warmups','1','--rss-rounds','0','--guest-timeout',str(a.guest_timeout)],check=True)
 qualification=json.loads(receipt.read_text())
 document={'cell':spec['cell'],'qualification_receipt':str(receipt),'separate_instrumented_runs':True,'arms':{}}
 for name,path in counters.items():
  status=qualification.get('arm_status',{}).get(name,{'status':'ok'})
  if status['status']!='ok':
   document['arms'][name]={'status':status,'metrics':None};continue
  value=json.loads(path.read_text());assert value['version']=='mylang-counters-v1'
  totals=value['totals'];kinds=value['kinds']
  metrics={k:totals[k] for k in ['allocs','reallocs','alloc_bytes','realloc_added_bytes','peak_live_bytes','live_bytes_at_exit','runtime_retains','runtime_releases']}
  metrics['cumulative_allocated_bytes']=totals['alloc_bytes']+totals['realloc_added_bytes']
  metrics['compiler_retains']=kinds['retain']['count'];metrics['compiler_releases']=kinds['release']['count']
  document['arms'][name]={'status':status,'counter_path':str(path),'metrics':metrics,'counters':value}
 result=a.output/(generated.stem+'.summary.json');assert not result.exists();result.write_text(json.dumps(document,indent=2)+'\n')
 print('counted',spec['cell'],result,flush=True)
