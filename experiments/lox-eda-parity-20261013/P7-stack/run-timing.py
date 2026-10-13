#!/usr/bin/env python3
"""Authorized diagnostic; one non-nested shared timing admission per chunk."""
import pathlib,json,subprocess,time
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack/timing-001';plan=json.loads((base/'comparison.json').read_text());rows=[]
for item in plan['commands']:
 case=item['case'];original=json.loads((base/(case+'.json')).read_text());prior=None
 for n in range(10):
  spec=base/(case+f'.run-spec{n:02}.json');output=base/(case+f'.chunk{n:02}.json');value=dict(original)
  if prior:value['prior_receipt']=str(prior.resolve())
  spec.write_text(json.dumps(value,indent=2)+'\n')
  argv=['python3',str(root/'experiments/lox-eda-parity-20261013/measure.py'),str(spec),str(output),'--cpu','8','--guest-timeout','120','--calibration-rounds','5','--calibration-warmups','0','--warmups',str(2 if n==0 else 0),'--round-start',str(n if n<9 else 9),'--rounds',str(1 if n<9 else 0),'--rss-rounds',str(3 if n==9 else 0)]
  admitted=['bash','-c','source /home/epentland/.config/mylang/dev-env.sh; exec scripts/build-slot.sh timing "$@"','runtime-timing',*argv]
  with (base/(case+f'.chunk{n:02}.log')).open('wb') as log:r=subprocess.run(admitted,stdout=log,stderr=subprocess.STDOUT)
  rows.append({'case':case,'chunk':n,'argv':admitted,'returncode':r.returncode});(base/'execution.json').write_text(json.dumps(rows,indent=2)+'\n')
  if r.returncode:raise SystemExit(r.returncode)
  prior=output
print('diagnostic timing chunks complete')
