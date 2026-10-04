import hashlib,json,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path.cwd(); BASE=ROOT.parent
sys.path.insert(0,str(ROOT/'benchmarks/runtime/expanded'))
from registry import checksum
w=BASE/'goal110-collections-hot-20261004'
m=w/'.mylang-cache/goal110-append-range-debug/runner/manifest.json'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
d=read(m);i=d['identity'];rec=i['compiler_build_receipt'];r=read(rec['path'])
assert sha(rec['path'])==rec['sha256'] and r==rec['receipt']
assert r['status']=='complete' and r['exit_status']==0 and r['compiler_optimize']=='Debug'
assert sha(r['compiler_path'])==r['compiler_sha256']
assert r['source_revision']==i['source_revision']=='6910e08351a50ce8524a5e37d3f6c23feb4d3383'
assert r['sources_before']==r['sources_after']
for name,h in r['sources_after'].items():assert sha(w/name)==h,name
for name,h in i['installed_assets'].items():assert sha(name)==h,name
for name,h in d['binary_hashes'].items():assert sha(i['binary_paths'].get(name,m.parent/name))==h,name
control=read(BASE/'goal110-presize-ready-20261004/.mylang-cache/goal110-presize-ready-debug/runner/manifest.json')
refs=[name for name in d['binary_hashes'] if '/' in name and '/my-' not in name]
assert len(refs)==16
for name in refs:assert d['binary_hashes'][name]==control['binary_hashes'][name]
qpath=w/'.mylang-cache/goal110-append-range-review/qualification.json';q=read(qpath)
assert q['status']=='correctness_complete' and q['manifest_sha256']==sha(m) and q['binary_hashes']==d['binary_hashes']
seen=set()
for c in q['checks']:
 key=tuple(c[k] for k in ['case','size','seed','iterations','arm']); assert key not in seen;seen.add(key)
 assert c['expected_checksum']==checksum(c['case'],c['size'],c['iterations'],c['seed'])==c['checksum'] and c['exit_status']==0 and c['clock_protocol_validated']
p=w/'.mylang-cache/goal110-append-range-review/native-outcomes.json';n=read(p)
assert n['status']=='pass' and n['source_revision']==i['source_revision']
for c in n['checks']:
 a,b=c['ordinary'],c['fast']; assert a==b
 if not b['failed']:
  seed,count=c['seed'],c['count']; expected=0 if count<=0 else count+seed%1009+(seed+(count-1)*13)%1009
  assert b['value']==expected and b['status']==expected%256 and b['stdout']=='' and b['stderr']=='' and b['trap']['code']==''
 else:
  expected='R_MEMORY_BUDGET' if c['max_memory'] is not None else 'R_OVERFLOW'
  assert b['trap']['code']==expected and b['status']!=0
out={'reviewed_utc':datetime.now(timezone.utc).isoformat(),'status':'passed','kind':'independent saved-outcome and live-identity replay; no new executions or timing','manifest':str(m),'manifest_sha256':sha(m),'source_revision':i['source_revision'],'source_bindings':len(r['sources_after']),'asset_bindings':len(i['installed_assets']),'guest_bindings':len(i['binary_paths']),'frozen_reference_bindings':len(refs),'qualification_cells':len(q['checks']),'native_exact_pairs':len(n['checks']),'qualification_sha256':sha(qpath),'native_outcomes_sha256':sha(p),'script_sha256':sha(Path(__file__))}
p=ROOT/'.mylang-cache/goal110-review-20261004-0535/preflight-append.json';p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
