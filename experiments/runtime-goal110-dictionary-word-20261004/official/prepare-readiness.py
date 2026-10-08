from pathlib import Path
from datetime import datetime,timezone
import ast,hashlib,json,subprocess
root=Path.cwd();work=root/'.mylang-cache/goal110-dict-word-debug';proof=root/'.mylang-cache/goal110-dict-word';logs=proof/'logs';old=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-integrated-20261004/.mylang-cache/goal110-integrated-debug')
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
bind=lambda p:{'path':str(Path(p).resolve()),'sha256':h(p)}
source='a2dfdfa994e19ac3c80373a443913c7ecdef23d7'
assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==source
assert not subprocess.check_output(['git','diff','HEAD','--','src','build.zig','build.zig.zon'],text=True).strip()
manifest=work/'runner/manifest.json';m=json.loads(manifest.read_text());r=json.loads((work/'compiler-receipt.json').read_text());assert m['identity']['source_revision']==r['source_revision']==source
q=json.loads((work/'qualification.json').read_text());o=json.loads((work/'holdouts.json').read_text());assert q['status']==o['status']=='correctness_complete';assert len(q['checks'])==720 and len(o['checks'])==516
s=json.loads((proof/'static/code-proof.json').read_text());assert s['status']=='passed';assert s['frontend']['after']['word_calls']==2 and s['frontend']['before']['word_calls']==0
language=json.loads((proof/'language/official-proof-01/report.json').read_text());assert language['status']=='passed' and language['comparison_count']==368
for name in ['gate-02','units-03','native-word-02','official-host','official-guests','qualification','holdouts','language-01','static-code-02']:assert (logs/(name+'.exit')).read_text().strip()=='0'
paths=[work/'compiler-receipt.json',manifest,work/'qualification.json',work/'holdouts.json',proof/'static/code-proof.json',proof/'static/frozen-emission.json',proof/'native-proof-02/receipt.json',proof/'focused-source-proof.json',proof/'language/official-proof-01/report.json']
paths += [logs/(name+'.'+extension) for name in ['gate-01','gate-02','units-01','units-02','units-03','native-word-01','native-word-02','official-host','official-guests','qualification','holdouts','language-01','static-code','static-code-02'] for extension in ['log','exit']]
artifacts=[]
for name,p in m['identity']['binary_paths'].items():
 assert h(p)==m['binary_hashes'][name];row={'name':name,**bind(p)}
 if name.split('/')[1].startswith('my-'):
  mp=Path(str(p)+'.qbe-manifest.json');meta=json.loads(mp.read_text());row['backend_metadata']={**bind(mp),**{k:meta[k] for k in ['backend','optimization','lto','thin_lto']}}
  assert meta['backend'] in ['llvm','qbe']
  if meta['backend']=='llvm':assert meta['optimization']=='3' and meta['lto'] is True and meta['thin_lto'] is False
 artifacts.append(row)
cases=['dict_lookup','dict_lookup_str','dict_update','dict_update_str','set_dedup','mutate_nested','string_search']
ready={'schema':'mylang-dictionary-word-debug-readiness-v1','source_revision':source,'base_revision':'1a3980631e79bc65f048acd063d7250800f01901','status':'correctness_and_static_complete','timing':False,'counts':{'edge_qualifications':720,'nearby_holdouts':516,'native_c_policies':2,'focused_tests':15,'native_language_pairs':368,'native_language_calls':736},'receipt_bindings':[bind(p) for p in paths],'guest_artifacts':artifacts,'control_manifest':bind(old/'runner/manifest.json'),'proposed_screen_cases':cases,'screen_scope':'Both sizes; six-arm5r1w then matched1a pairs5r1w; exploratory only. Both Debug hosts generate ordinary ReleaseFast guests, LLVM O3/full LTO.','static_proof':{'frontend_change':'Exactly2eligible callee substitutions; complete remaining IL equal.','ordinary_calls':[5,3],'word_calls':[0,2],'generic_read_bytes':670,'generic_read_walk_bytes':663,'word_read_bytes':426,'word_helper_has_no_calls':True,'collection_llvm_text_bytes':[295074,295506],'allocated_code_unchanged':['legacy/my-llvm','legacy/my-qbe','compute/my-llvm','compute/my-qbe','text/my-llvm'],'allocated_code_changed':['collections/my-llvm','collections/my-qbe','text/my-qbe'],'stable_controls_retained':['mutate_nested','string_search']},'finished_utc':datetime.now(timezone.utc).isoformat()}
(work/'readiness.json').write_text(json.dumps(ready,indent=2)+'\n')
commands=[['python3',str(work/'screen.py'),'--mylang',r['compiler_path'],'--zig','/home/epentland/.local/bin/zig','--candidate-id','dictionary-word-a2dfdfa9-debug','--compiler-receipt',str(work/'compiler-receipt.json'),'--reuse-reference-manifest',str(old/'runner/manifest.json'),'--expected-reference-manifest-sha256',h(old/'runner/manifest.json'),'--work',str(work/'runner'),'--output',str(work/'screen-raw.json'),'--skip-build','--rounds','5','--warmups','1','--cpu','2','--only',*cases],['python3',str(work/'time-paired.py'),'--plans',str(work/'screen-raw.json'),'--before-manifest',str(old/'runner/manifest.json'),'--after-manifest',str(manifest),'--rounds','5','--warmups','1','--cpu','2','--output',str(work/'paired-screen.json')],['python3',str(work/'finalize-screen.py'),'--raw',str(work/'screen-raw.json'),'--output',str(work/'screen.json')],['python3',str(root/'benchmarks/runtime/compare_candidate.py'),str(work/'screen.json'),'--output',str(work/'screen-comparison.json'),'--check-artifacts']]
helpers=[work/'screen.py',work/'time-paired.py',work/'finalize-screen.py',work/'execute-commands.py',root/'benchmarks/runtime/expanded/run.py',root/'benchmarks/runtime/runner.py',root/'benchmarks/runtime/compare_candidate.py',root/'benchmarks/runtime/expanded/verify.py',root/'benchmarks/runtime/diagnostics/holdouts.py',root/'benchmarks/runtime/expanded/registry.py']
for p in helpers:ast.parse(p.read_text(),filename=str(p))
d={'schema':'mylang-dictionary-word-timing-commands-v1','source_revision':source,'cwd':str(root),'commands':commands,'helper_sha256':{str(p):h(p) for p in helpers},'policy':'Internal runner lock only. No guest modification. Six-arm5r1w then matched1a pairs5r1w on same14plans. Screen summary/bootstrap deferred until all paired guest timing ends; no integration implied.','manifests':{'before':bind(old/'runner/manifest.json'),'after':bind(manifest)},'readiness':bind(work/'readiness.json')}
(work/'timing-commands.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'readiness':bind(work/'readiness.json'),'commands':bind(work/'timing-commands.json'),'static':bind(proof/'static/code-proof.json')}))
