#!/usr/bin/env python3
"""Run the qualified 34-design EDA matrix with one exclusive lease per cell.
Use the root frozen specs and current root harness; preserve failed/censored arms.
"""
import argparse,json,pathlib,subprocess,sys,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--root',type=pathlib.Path,default=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012'))
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--arm',action='append',required=True)
p.add_argument('--cpu',type=int,default=8)
p.add_argument('--pause-file',type=pathlib.Path)
a=p.parse_args();names={item.split('=',1)[0] for item in a.arm};assert names=={'mylang-original-rc','mylang-migrated-rc','mylang-zero-rc'}
bench=a.root/'experiments/lox-eda-zero-rc-20261012/bench';specs=sorted((bench/'frozen-specs').glob('eda-*.json'));assert len(specs)==34
for source in specs:
 if a.pause_file and a.pause_file.exists():
  print('Paused before',source.stem,flush=True);break
 receipt=a.output/(source.stem+'.r0-9.w2.rss3.json')
 if receipt.exists():
  d=json.loads(receipt.read_text());assert d['spec']['cell']=='eda/'+source.stem[4:]
  print('Existing completed receipt',receipt,flush=True);continue
 argv=[str(a.root/'scripts/build-slot.sh'),'timing',sys.executable,str(bench/'run-batch.py'),'--output',str(a.output),'--cpu',str(a.cpu),'--rounds','9','--warmups','2','--rss-rounds','3','--guest-timeout','120']
 for arm in a.arm:argv+=['--arm',arm]
 argv.append(str(source));subprocess.run(argv,cwd=a.root,check=True)
 time.sleep(2)
