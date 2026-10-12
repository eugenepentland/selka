#!/usr/bin/env python3
"""Run specified cells within an outer shared timing lease; never admits slots.
Supply exact qualified candidate/control binaries with --arm NAME=BINARY.
Use bounded lists of cases and measurement round chunks; finished receipts persist.
"""
import argparse,json,pathlib,subprocess,sys
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--arm',action='append',default=[])
p.add_argument('--cpu',type=int,default=8)
p.add_argument('--rounds',type=int,default=9)
p.add_argument('--round-start',type=int,default=0)
p.add_argument('--warmups',type=int,default=2)
p.add_argument('--rss-rounds',type=int,default=3)
p.add_argument('--guest-timeout',type=float,default=120)
p.add_argument('--prior-receipt',type=pathlib.Path,help='Carry failed arms from an earlier chunk of this cell')
p.add_argument('specs',nargs='+',type=pathlib.Path)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
for source in a.specs:
 spec=json.loads(source.read_text());example=spec['arms']['zig-safe']
 for item in a.arm:
  name,binary=item.split('=',1);assert pathlib.Path(binary).is_file()
  assert name not in spec['arms'],name
  spec['arms'][name]=[str(pathlib.Path(binary).resolve()),*example[1:]]
 if a.prior_receipt:spec['prior_receipt']=str(a.prior_receipt.resolve())
 prefix=source.stem+f'.r{a.round_start}-{a.round_start+a.rounds}.w{a.warmups}.rss{a.rss_rounds}'
 generated=a.output/(prefix+'.spec.json');result=a.output/(prefix+'.json')
 assert not generated.exists() and not result.exists()
 generated.write_text(json.dumps(spec,indent=2)+'\n')
 subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('measure.py')),str(generated),str(result),
                 '--cpu',str(a.cpu),'--rounds',str(a.rounds),'--round-start',str(a.round_start),
                 '--warmups',str(a.warmups),'--rss-rounds',str(a.rss_rounds),'--guest-timeout',str(a.guest_timeout)],check=True)
 print('completed',spec['cell'],result,flush=True)
