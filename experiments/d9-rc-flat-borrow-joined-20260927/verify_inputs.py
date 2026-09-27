"""Check private copied inputs against accepted GC identities without execution."""
from pathlib import Path
import hashlib,json
root=Path.cwd();base=root.parent/'d9-rc-performance';work=root/'.tmp-mut-argument/joined-flat-measure'
accepted=json.loads((base/'.tmp-rc-performance/gc-builds.json').read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
rows=[]
for p in (work/'lox-guest').rglob('*.my'):
 old=base/'.tmp-rc-performance/lox/benchmarks/lox/ports/mylang'/p.relative_to(work/'lox-guest')
 assert sha(p)==accepted['inputs'][str(old)]
 rows.append({'path':str(p),'accepted_path':str(old),'sha256':sha(p)})
for p in list((root/'src/schematic/guest').rglob('*.my'))+[root/'src/schematic/native_schematic.c']:
 old=base/p.relative_to(root);assert sha(p)==accepted['inputs'][str(old)]
 rows.append({'path':str(p),'accepted_path':str(old),'sha256':sha(p)})
result={'verified_files':len(rows),'rows':rows,'driver_sha256':sha(root/'experiments/d9-rc-flat-borrow-joined-20260927/measure.py')}
(work/'accepted-source-identity.json').write_text(json.dumps(result,indent=2)+'\n');print('accepted source identities',len(rows),'match')
