#!/usr/bin/env python3
"""Collect separately instrumented full EDA cases, one timing lease per design."""
import argparse,pathlib,subprocess,sys,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--root',type=pathlib.Path,default=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012'))
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--arm',action='append',required=True)
p.add_argument('--cpu',type=int,default=8)
a=p.parse_args();assert {x.split('=',1)[0] for x in a.arm}=={'mylang-original-rc','mylang-migrated-rc','mylang-zero-rc'}
b=a.root/'experiments/lox-eda-zero-rc-20261012/bench';specs=sorted((b/'frozen-specs').glob('eda-*.json'));assert len(specs)==34
for spec in specs:
 receipt=a.output/(spec.stem+'.counted.spec.summary.json')
 if receipt.exists():print('Existing counted receipt',receipt,flush=True);continue
 argv=[str(a.root/'scripts/build-slot.sh'),'timing',sys.executable,str(b/'run-counted.py'),'--output',str(a.output),'--cpu',str(a.cpu),'--guest-timeout','120']
 for arm in a.arm:argv+=['--arm',arm]
 argv.append(str(spec));subprocess.run(argv,cwd=a.root,check=True);time.sleep(2)
