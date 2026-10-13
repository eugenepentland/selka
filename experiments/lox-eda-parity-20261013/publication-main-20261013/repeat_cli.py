import os,subprocess,json,time
from pathlib import Path
out=Path('.tmp/parity-publication/cli-repeats');out.mkdir(exist_ok=False)
command=[os.environ['ZIG'],'build','test-cli','-Dtest-filter=library modules and bare','-Dtest-filter=CLI an edit to one contract','-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS'],'-Dcomponent-owned-compiler-pin=/home/epentland/ai/canopy/mylang-memory-20261012-A10/experiments/memory-closeout-20261012/A10/packaging-support6-candidate/candidate-pin.json','-Dcomponent-seed-source=/home/epentland/ai/canopy/mylang-memory-20261012-A10/.tmp/memory-closeout/A10/owned-pin-support6-5167c588/source.tar']
records=[]
for i in range(20):
 start=time.monotonic()
 with (out/f'{i:02d}.log').open('x') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
 records.append(dict(round=i,exit_code=r.returncode,seconds=time.monotonic()-start))
 (out/'status.json').write_text(json.dumps(dict(command=command,rounds=records),indent=2)+'\n')
 print(json.dumps(records[-1]),flush=True)
 if r.returncode:raise SystemExit(r.returncode)
