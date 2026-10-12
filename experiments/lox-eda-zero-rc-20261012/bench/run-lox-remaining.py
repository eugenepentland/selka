#!/usr/bin/env python3
"""Run the other24 Lox cells in bounded, separately admitted timing chunks.
Initial tree/vm Fibonacci receipts are retained separately. This coordinator owns
admission; run it directly, never inside another build-slot lease.
"""
import argparse,json,pathlib,subprocess,sys
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binaries',type=pathlib.Path,required=True,help='Frozen Lox binaries.json manifest')
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--specs',type=pathlib.Path,default=pathlib.Path(__file__).with_name('frozen-specs'))
p.add_argument('--guest-timeout',type=float,default=120)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[3]
manifest=json.loads(a.binaries.read_text());arms=[]
for name,key in [('mylang-original-rc','original-rc'),('mylang-migrated-rc','migrated-rc'),('mylang-zero-rc','zero')]:
 arms+=['--arm',name+'='+manifest['binaries'][key]['path']]
cases=[]
for path in sorted(a.specs.glob('*.json')):
 cell=json.loads(path.read_text())['cell']
 if cell.startswith('lox/') and cell not in ['lox/tree/fib','lox/vm/fib','lox/vm/step']:cases.append(path.resolve())
assert len(cases)==24
# Each initial chunk has2warmups; each cell totals9measured and3separateRSSruns.
for case in cases:
 previous=None
 for start,rounds,warmups,rss in [(0,3,2,0),(3,3,0,0),(6,3,0,0),(9,0,0,3)]:
  receipt=a.output/(case.stem+f'.r{start}-{start+rounds}.w{warmups}.rss{rss}.json')
  if receipt.exists():
   # Never silently overwrite or reclassify an existing attempt.
   print('retained existing receipt',receipt,flush=True);previous=receipt;continue
  cmd=[str(root/'scripts/build-slot.sh'),'timing',sys.executable,'-B',str(pathlib.Path(__file__).with_name('run-batch.py')),
       '--output',str(a.output.resolve()),'--round-start',str(start),'--rounds',str(rounds),'--warmups',str(warmups),'--rss-rounds',str(rss),
       '--guest-timeout',str(a.guest_timeout),*(['--prior-receipt',str(previous.resolve())] if previous else []),*arms,str(case)]
  subprocess.run(cmd,cwd=root,check=True)
  previous=receipt
