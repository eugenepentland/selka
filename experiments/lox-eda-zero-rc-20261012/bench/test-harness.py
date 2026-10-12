#!/usr/bin/env python3
"""Exercise deadline/failure retention and cross-cell binary identity checks."""
import json,os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='lox-eda-harness-') as dirname:
 d=pathlib.Path(dirname);guest=d/'guest.py'
 guest.write_text('import sys,time\nif sys.argv[1]=="slow": time.sleep(5)\nif sys.argv[1]=="fail": sys.exit(2)\nprint("bad" if sys.argv[1]=="bad" else "ok")\n')
 expected=d/'expected';expected.write_text('ok\n')
 names={'zig-safe':'ok','zig-fast':'ok','rust':'ok','go':'ok','timeout':'slow','failed':'fail','wrong-output':'bad'}
 spec={'cell':'lox/tree/test','arms':{n:[sys.executable,str(guest),v] for n,v in names.items()},'expected_stdout':str(expected),'files':[str(guest)]}
 source=d/'spec.json';source.write_text(json.dumps(spec));receipt=d/'receipt.json'
 subprocess.run([sys.executable,str(root/'measure.py'),str(source),str(receipt),'--cpu',str(min(os.sched_getaffinity(0))),'--guest-timeout','0.2'],check=True,stdout=subprocess.DEVNULL)
 r=json.loads(receipt.read_text())
 assert {k:v['status'] for k,v in r['arm_status'].items()}=={k:('timeout' if k=='timeout' else 'failed' if k=='failed' else 'output_mismatch' if k=='wrong-output' else 'ok') for k in names}
 assert len(r['wall_samples'])==36 and len(r['rss_samples'])==12
 spec['prior_receipt']=str(receipt);source.write_text(json.dumps(spec));continued=d/'continued.json'
 subprocess.run([sys.executable,str(root/'measure.py'),str(source),str(continued),'--cpu',str(min(os.sched_getaffinity(0))),'--guest-timeout','0.2','--warmups','0','--rounds','0','--rss-rounds','0'],check=True,stdout=subprocess.DEVNULL)
 carry=json.loads(continued.read_text())
 assert all(carry['arm_status'][name]['inherited_from_prior_chunk'] for name in ['timeout','failed','wrong-output'])
 assert not any(json.loads(line)['kind']=='arm_failure' for line in continued.with_suffix('.json.progress.jsonl').read_text().splitlines())
 specs=d/'specs';specs.mkdir();receipts=[]
 for group,count in [('lox/tree',13),('lox/vm',13),('eda',34)]:
  for i in range(count):
   cell=f'{group}/{i}';r['spec']['cell']=cell;p=d/(cell.replace('/','-')+'.json');p.write_text(json.dumps(r));receipts.append(str(p))
   (specs/p.name).write_text(json.dumps({'cell':cell}))
 cmd=[sys.executable,str(root/'summarize.py'),'--spec-dir',str(specs),*receipts]
 summary=json.loads(subprocess.check_output(cmd,text=True))
 assert len(summary['cells'])==60
 assert summary['groups']['lox/tree/']['complete_cells_by_arm']['timeout']==0
 assert summary['groups']['lox/tree/']['wall_ratios']['timeout']['zig-safe']['full_suite_geomean'] is None
 assert summary['groups']['lox/tree/']['wall_ratios']['rust']['zig-safe']['paired_cells']==13
 p=pathlib.Path(receipts[-1]);broken=json.loads(p.read_text());broken['identities'][sys.executable]='deliberately-different';p.write_text(json.dumps(broken))
 rejected=subprocess.run(cmd,capture_output=True,text=True)
 assert rejected.returncode!=0 and 'binary changed across cells' in rejected.stderr
 print(json.dumps({'status':'passed','cases':['timeout retained','nonzero exit retained','output mismatch retained','remaining arms continue','failed arms carried without retry','60-cell denominator','incomplete aggregate withheld','changed arm identity refused']},indent=2))
