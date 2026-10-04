from pathlib import Path
from datetime import datetime,timezone
import ast,hashlib,json,subprocess
root=Path.cwd();work=root/'.mylang-cache/goal110-dict-probe-debug';logs=root/'.mylang-cache/goal110-dict-probe/logs';old=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-rf-20261004/.mylang-cache/goal110-index-forward-rf')
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
bind=lambda p:{'path':str(Path(p).resolve()),'sha256':h(p)}
source='64fb7e62732db9cea46414248fd59ba362e31b56'
assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==source
assert not subprocess.check_output(['git','diff','HEAD','--','src','build.zig','build.zig.zon'],text=True).strip()
manifest=work/'runner/manifest.json';m=json.loads(manifest.read_text());r=json.loads((work/'compiler-receipt.json').read_text());assert m['identity']['source_revision']==r['source_revision']==source
q=json.loads((work/'qualification.json').read_text());o=json.loads((work/'holdouts.json').read_text());assert q['status']==o['status']=='correctness_complete';assert len(q['checks'])==720 and len(o['checks'])==516
s=json.loads((work/'static/receipt.json').read_text());assert s['frontend_identical'] and s['ordinary_found_zeroing_removed']
for name in ['guardian-02','compiler-driver','guest-build','qualification','holdouts','native-proof-02','static-02']:assert (logs/(name+'.exit')).read_text().strip()=='0'
paths=[work/'compiler-receipt.json',manifest,work/'qualification.json',work/'holdouts.json',work/'static/receipt.json',root/'.mylang-cache/goal110-dict-probe/native-proof/receipt.json',root/'.mylang-cache/goal110-dict-probe/final-native-source-binding.json']
paths += [logs/(name+'.'+extension) for name in ['guardian-01','guardian-02','compiler-driver','guest-build','qualification','holdouts','native-proof-02','static-01','static-02'] for extension in ['log','exit']]
artifacts=[]
for name,p in m['identity']['binary_paths'].items():
 assert h(p)==m['binary_hashes'][name];row={'name':name,**bind(p)}
 if name.split('/')[1].startswith('my-'):
  mp=Path(str(p)+'.qbe-manifest.json');meta=json.loads(mp.read_text());row['backend_metadata']={**bind(mp),**{k:meta[k] for k in ['backend','optimization','lto','thin_lto']}}
  assert meta['backend'] in ['llvm','qbe']
  if meta['backend']=='llvm':assert meta['optimization']=='3' and meta['lto'] and not meta['thin_lto']
 artifacts.append(row)
cases=['dict_lookup','dict_lookup_str','dict_update','dict_update_str','set_dedup','mutate_nested','string_search']
ready={'schema':'mylang-dictionary-probe-debug-readiness-v1','source_revision':source,'base_revision':'eaf4cda8f5c758cadafaadfa5e328c0fba252ac6','status':'correctness_and_static_complete','timing':False,'counts':{'edge_qualifications':720,'nearby_holdouts':516,'sanitized_native_suites':4,'new_state_transition_cases':8},'receipt_bindings':[bind(p) for p in paths],'guest_artifacts':artifacts,'control_manifest':bind(old/'runner/manifest.json'),'proposed_screen_cases':cases,'screen_scope':'Both sizes; six-arm5r1w then matched14/eaf-equivalent pairs5r1w; exploratory only. Debug candidate host generates ordinary ReleaseFast guests, LLVM O3/full LTO.','static_proof':{'frontend_collections_il_identical':True,'read_walk_bytes':[695,663],'contains_walk_bytes':[653,621],'redundant_found_stores_removed':3,'zero_vector_setup_removed':True,'stable_controls_retained':['mutate_nested','string_search']},'finished_utc':datetime.now(timezone.utc).isoformat()}
(work/'readiness.json').write_text(json.dumps(ready,indent=2)+'\n')
commands=[['python3',str(work/'screen.py'),'--mylang',r['compiler_path'],'--zig','/home/epentland/.local/bin/zig','--candidate-id','dictionary-probe-64fb7e62-debug','--compiler-receipt',str(work/'compiler-receipt.json'),'--reuse-reference-manifest',str(old/'runner/manifest.json'),'--expected-reference-manifest-sha256',h(old/'runner/manifest.json'),'--work',str(work/'runner'),'--output',str(work/'screen-raw.json'),'--skip-build','--rounds','5','--warmups','1','--cpu','2','--only',*cases],['python3',str(work/'time-paired.py'),'--plans',str(work/'screen-raw.json'),'--before-manifest',str(old/'runner/manifest.json'),'--after-manifest',str(manifest),'--rounds','5','--warmups','1','--cpu','2','--output',str(work/'paired-screen.json')],['python3',str(work/'finalize-screen.py'),'--raw',str(work/'screen-raw.json'),'--output',str(work/'screen.json')],['python3',str(root/'benchmarks/runtime/compare_candidate.py'),str(work/'screen.json'),'--output',str(work/'screen-comparison.json'),'--check-artifacts']]
helpers=[work/'screen.py',work/'time-paired.py',work/'finalize-screen.py',work/'execute-commands.py',root/'benchmarks/runtime/expanded/run.py',root/'benchmarks/runtime/runner.py',root/'benchmarks/runtime/compare_candidate.py',root/'benchmarks/runtime/expanded/verify.py',root/'benchmarks/runtime/diagnostics/holdouts.py',root/'benchmarks/runtime/expanded/registry.py']
for p in helpers:ast.parse(p.read_text(),filename=str(p))
d={'schema':'mylang-dictionary-probe-timing-commands-v1','source_revision':source,'cwd':str(root),'commands':commands,'helper_sha256':{str(p):h(p) for p in helpers},'policy':'Internal runner lock only. No guest modification. Six-arm5r1w then current14/eaf-equivalent pairs5r1w on same14plans. Screen summary/bootstrap deferred until all paired guest timing ends; no integration implied.','manifests':{'before':bind(old/'runner/manifest.json'),'after':bind(manifest)},'readiness':bind(work/'readiness.json')}
(work/'timing-commands.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'readiness':bind(work/'readiness.json'),'commands':bind(work/'timing-commands.json'),'static':bind(work/'static/receipt.json')}))
