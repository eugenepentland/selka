import hashlib,importlib.util,json
from pathlib import Path
s=importlib.util.spec_from_file_location('replay','experiments/d9-rc-golden-replay-20260926/run.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
w=Path('.tmp-schematic/abi3-bridge/replay').resolve();(w/'tmp').mkdir(parents=True,exist_ok=True)
compiler=Path('zig-out/bin/mylang').resolve(); rows={}
for backend in ('qbe','llvm'):
 for case in m.cases()[0][:3]:
  key,row=m.execute(compiler,w,backend,case,'rc-v3-counting');rows[key]=row
  assert row['matched'] and row['balanced'] and row['runtime_matches'] and not row['missing_required_counters'],row
  print(key,row['runtime_observed'],'PASS',flush=True)
Path('.tmp-schematic/abi3-bridge/replay-smoke.json').write_text(json.dumps({'compiler_sha256':m.SHA(compiler),'runs':rows},indent=2)+'\n')
