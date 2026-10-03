#!/usr/bin/env python3
"""Read-only independent equality/provenance and prospective composition audit."""
from pathlib import Path
from collections import Counter
import base64,difflib,gzip,hashlib,json,re,subprocess
own=Path(__file__).resolve().parents[2];work=own/'.tmp-lox-equality-numeric-review-20261003';eq=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-stack-read-20261003');exp=eq/'experiments/lox-vm-stack-read-v2-20261003';num=own/'experiments/lox-vm-numeric-20261003';root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()};digest=lambda data:hashlib.sha256(data).hexdigest()
commits={str(eq):'bb6451b5b7199adbc60a437ebb28c3f1b8b18f08',str(own):'299bd933861af1f38c3ad0ecd1ec641f3d18de5a'}
tracked={}
for lane,directory in [(eq,exp),(own,num)]:
 for path in sorted(directory.iterdir()):
  if not path.is_file():continue
  relative=str(path.relative_to(lane));data=subprocess.check_output(['git','-C',str(lane),'show',commits[str(lane)]+':'+relative]);assert digest(data)==sha(path),(path,'different from frozen commit');tracked[str(path)]=sha(path)
hashes=json.loads((exp/'source-hashes.json').read_text());qual=json.loads((exp/'qualification.json').read_text());build=json.loads((exp/'builds.json').read_text());public=json.loads((exp/'public-qualification.json').read_text());replay=json.loads((exp/'patch-replay.json').read_text());native=json.loads(gzip.decompress((exp/'native-validation.json.gz').read_bytes()));nums=json.loads((num/'sources.json').read_text())
source={name:Path(path) for name,path in hashes['source'].items()};snapshots={name:files(path) for name,path in source.items()};assert snapshots==hashes['source_sha256'];assert all(len(v)==37 for v in snapshots.values());assert files(root/'.tmp-lox-round3/ast')==snapshots['control']==nums['baseline']
assert files(Path(replay['result']['source']))==snapshots['inline-qualified']==replay['result']['source_sha256'];assert replay['status']==0 and replay['verified_files']==37;assert sha(exp/'readonly-stack-equality-inline.patch')==hashes['patch_sha256']==replay['result']['patch_sha256'];assert sha(exp/'prepare.py')==replay['prepare_sha256']
assert build['source_sha256']==public['source_sha256']==native['source_sha256']==qual['source_sha256']==snapshots['inline-qualified'];assert all(r['verified_after'] for r in [build,public,native]);assert qual['complete']
compiler=Path(build['compiler']);qbe=Path(build['qbe']);assert sha(compiler)==build['compiler_sha256']==public['compiler_sha256']=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040';assert sha(qbe)==build['qbe_sha256']==public['qbe_sha256']=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
payload={}
for name,row in qual['payload'].items():
 path=exp/name;assert sha(path)==row['packed_sha256'];data=gzip.decompress(path.read_bytes()) if name.endswith('.gz') else path.read_bytes();assert digest(data)==row['sha256'];assert sha(row['original'])==row['sha256'];payload[name]={'packed_sha256':sha(path),'raw_sha256':digest(data)}
assert len(payload)==35,len(payload)
assert sha(eq/'.tmp-lox-vm-stack-read-v2-20261003/builds.json')==native['build_receipt_sha256']
for row in build['runs']:
 assert row['status']==0;assert ('--gc-runtime' in row['argv'])==(row['runtime']=='gc');assert ('--rc-runtime' in row['argv'])==(row['runtime']=='rc');assert not any(flag in row['argv'] for flag in ['--drop-step-checks','--drop-frame-checks','--unchecked'])
 for key in ['binary','manifest','receipt','runtime_object']:assert sha(row[key])==row[key+'_sha256']
for name,path in native['binaries'].items():assert sha(path)==native['binary_sha256'][name]
expected_names=lambda p:{f.stem+'::'+name for f in p.glob('*.my') for name in re.findall(r'^public def (test_\w+)\(',f.read_text(),re.M)}
base_names=expected_names(source['control']);eq_names=expected_names(source['inline-qualified']);num_names=expected_names(Path(nums['source']));assert len(base_names)==84 and len(eq_names)==86 and len(num_names)==87;assert base_names<=eq_names and base_names<=num_names;assert not (eq_names-base_names)&(num_names-base_names)
for row in public['runs']:
 assert row['status']==0 and row['summaries']==['86 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs'];assert sha(row['log'])==row['log_sha256'];log=Path(row['log']).read_text();names=re.findall(r'^passed (\S+)',log,re.M);assert len(names)==86 and set(names)==eq_names,(len(names),row['log']);assert '--cases' not in row['argv'];assert '--max-steps' in row['argv'] and '--timeout-ms' in row['argv']
assert len(native['samples'])==348;counts=Counter();cells=set();inputs={}
for row in native['samples']:
 assert row['passed'] and row['actual']==row['expected'];assert '--engine=vm' in row['argv'];assert sha(row['source'])==row['source_sha256'];assert ('--gc-stress' in row['argv'])==row['lox_gc_stress'];assert row['runtime']=='gc' or not row['native_gc_stress'];counts[(row['backend'],row['runtime'],row['native_gc_stress'],row['lox_gc_stress'])]+=1
 cell=(row['name'],row['tier'],row['backend'],row['runtime'],row['native_gc_stress'],row['lox_gc_stress']);assert cell not in cells;cells.add(cell);inputs[row['source']]=row['source_sha256']
assert len(counts)==12 and set(counts.values())=={29};assert len(inputs)==29;assert Counter(row['tier'] for row in native['samples'])=={'smoke':48,'regression':24,'error':276}
base=source['control'];candidate=source['inline-qualified'];value=(base/'value.my').read_text();body=value[value.index('    match a:',value.index('public def values_equal')):value.index('\n\n\n# The shortest')];body=body.replace('match a:','match left_value:').replace('match b:','match right_value:').replace('case Value.','case value.Value.')
vm=(candidate/'vm.my').read_text();start=vm.index('def equal_stack(');assert vm[vm.index('    match left_value:',start):vm.index('\n\n\n# Each invocation',start)]==body;assert vm[start:vm.index('    match left_value:',start)].endswith('    right_value = stack[top - 1]\n    left_value = stack[top - 2]\n')
for filename in ['driver_tests.my','driver_cases.json']:
 assert filename in hashes['changed_from_control']
base_driver=(base/'driver_tests.my').read_text();assert (candidate/'driver_tests.my').read_text().startswith(base_driver);assert (Path(nums['source'])/'driver_tests.my').read_text().startswith(base_driver)
providers={label:json.loads((path/'driver_cases.json').read_text()) for label,path in [('base',base),('equality',candidate),('numeric',Path(nums['source']))]}
for label in ['equality','numeric']:assert all(providers[label][key]==v for key,v in providers['base'].items())
added_providers={label:sorted(set(providers[label])-set(providers['base'])) for label in ['equality','numeric']};assert not set(added_providers['equality'])&set(added_providers['numeric']);assert set(added_providers['equality'])==eq_names-base_names;assert set(added_providers['numeric'])==num_names-base_names
runtime_hunks={}
for label,text in [('equality',(exp/'readonly-stack-equality-inline.patch').read_text()),('numeric',(num/'numeric-source.patch').read_text())]:
 vm_patch=text[text.index('--- a/vm.my'):];runtime_hunks[label]=re.findall(r'^@@ (.*?) @@',vm_patch,re.M)
assert runtime_hunks['equality']==['-519,6 +519,39','-586,10 +619,9'];assert runtime_hunks['numeric']==['-423,19 +423,25']
# Independently repeat the static assembly traversal without guest execution.
paths=json.loads((exp/'qbe-static-success-paths.json').read_text());staticreplay=json.loads((exp/'static-replay.json').read_text());assert paths['rows']==staticreplay['rows']
asm={name:gzip.decompress((exp/name).read_bytes()).decode() for name in ['v1-helper.asm.gz','qbe-v1-values_equal.asm.gz','qbe-equal_stack.asm.gz']}
def walk(text,choices):
 ins=[]
 for line in text.splitlines():
  m=re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)',line)
  if m:ins.append((int(m[1],16),m[2],m[3]))
 index={v[0]:i for i,v in enumerate(ins)};cursor=0;trace=[];calls=[];choice=iter(choices)
 while True:
  address,op,args=ins[cursor];trace.append(hex(address));assert op!='ud2'
  if op=='ret':break
  if op=='call':calls.append(args)
  if op.startswith('j'):
   taken=True if op=='jmp' else next(choice);cursor=index[int(args.split()[0],16)] if taken else cursor+1
  else:cursor+=1
  assert len(trace)<300
 assert list(choice)==[];return trace,calls
for row in paths['rows']:
 for key,filename in [('v1_helper','v1-helper.asm.gz'),('v1_comparison','qbe-v1-values_equal.asm.gz'),('v2_helper','qbe-equal_stack.asm.gz')]:
  saved=row[key];choices=[r['taken'] for r in saved['branches'] if r['branch']!='jmp'];visited,calls=walk(asm[filename],choices);assert visited==saved['instruction_addresses'] and calls==saved['calls'] and len(visited)==saved['count']
 assert row['v1_count']==row['v1_helper']['count']+row['v1_comparison']['count'];assert row['v2_count']==row['v2_helper']['count'];assert row['delta']==-4
static=json.loads((exp/'static-evidence.json').read_text());elf_assembly={}
for backend in ['qbe','llvm']:
 row=next(r for r in build['runs'] if r['runtime']=='rc' and r['codegen']['backend']==backend);qbe_row=next(r for r in build['runs'] if r['runtime']=='rc' and r['codegen']['backend']=='qbe');cache=Path(qbe_row['argv'][qbe_row['argv'].index('--cache-dir')+1]);manifest=json.loads(next(cache.glob('modules/*/out/vm.manifest.json')).read_text())
 for name in ['run','equal_stack']:
  symbol=next(f['symbol'] for f in manifest['functions'] if f['name']=='vm::'+name);data=subprocess.check_output(['objdump','-d','--no-show-raw-insn','--disassemble='+symbol,row['binary']]);stored=gzip.decompress((exp/(backend+'-'+name+'.asm.gz')).read_bytes());assert data==stored
  count=len(re.findall(rb'^\s*[0-9a-f]+:\s+',data,re.M));assert count==static[backend][name]['instructions'];elf_assembly[backend+'-'+name]={'sha256':digest(data),'instructions':count}
# Only provenance/composability checks below concern the author's numeric arm.
numqual=json.loads((num/'qualification.json').read_text());assert files(Path(nums['source']))==nums['candidate']==numqual['source37'];assert numqual['public_tests']['fresh_total']==348 and numqual['native']['total_program_pairs']==1096 and numqual['native']['rc_native_stress_refusal_pairs']==8 and numqual['native']['unrun_native_smoke_cells']==80
archive=num/'receipts.json.gz';assert sha(archive)==numqual['archive']['sha256'];raw=json.loads(gzip.decompress(archive.read_bytes()))['files'];assert len(raw)==292
for name,row in raw.items():assert digest(base64.b64decode(row['base64']))==row['sha256']
result={'kind':'Independent read-only equality V2 review and prospective equality/numeric patch composability; numeric authorship not independently certified','frozen_commits':commits,'tracked_artifact_sha256':tracked,'source_hashes_verified':snapshots,'replayed_source37_verified':True,'compiler_sha256':sha(compiler),'qbe_sha256':sha(qbe),'equality_payload_files_verified':len(payload),'equality_payload_sha256':payload,'equality_public':{'fresh_passes':344,'per_flavor':86,'exact_discovered_names':sorted(eq_names),'zero_cached_failed_skipped_dropped':True,'directory_provider_backed_execution_not_claimed':True},'equality_native':{'exact_vm_pairs':348,'case_inputs':inputs,'tier_counts':{'smoke':48,'regression':24,'error':276},'mode_counts':{str(k):v for k,v in sorted(counts.items())},'tree_unaccounted_matrix_and_rc_native_stress_refusals_not_run':True},'static_verified':{'elf_assembly':elf_assembly,'v1_to_v2_same_tag_path_counts':[{k:row[k] for k in ['same_tag','v1_count','v2_count','delta']} for row in paths['rows']],'comparison_baseline':'qualified V1, not selected AST','no_dynamic_speed_claim':True},'prospective_composition':{'runtime_hunks_from_selected_baseline':runtime_hunks,'runtime_regions_disjoint':True,'shared_append_files':['driver_tests.my','driver_cases.json'],'added_provider_keys':added_providers,'expected_union_test_names_count_if_composed':89,'base84_names_preserved_in_each_arm':True,'same_baseline37_hashes':True,'source_composed':False,'composition_qualified':False},'numeric_receipt_scope_only':{'author':'this reviewer','archive_sha256':sha(archive),'raw_files_verified':292,'public_fresh':348,'native_pairs':1096,'rc_refusals':8,'native_smoke_unrun':80,'independent_authorship_review_claimed':False},'findings':[],'limits':['Checked Values/Lox source semantics reviewed; no forged invalid tag mutation-order equivalence claim.','Native frame/step quota PCs, source-expanded helper traces and exhausted-budget thresholds change with source layout and are not claimed identical.','Host snapshot fixture executes in accounted public suite; standalone unaccounted native regression covers its Lox program, not host snapshot lifetime.','Diagnostic IL drops frame/step flags only for inspection; actual RC/GC builds retain checks.','Static same-tag walks assume nonnegative in-range indices and valid matching tags; no timing/PMU inference.','Independent current hash verification supplements authors before/after receipt assertions; no new tests/perf/source composition or root writes.'],'verified_after':files(candidate)==snapshots['inline-qualified'] and files(root/'.tmp-lox-round3/ast')==snapshots['control']}
(work/'review.json').write_text(json.dumps(result,indent=2)+'\n');print('Equality V2:37 source/replay hashes,35 packed records,344 exact public names/pass rows,348 native VM pairs and actual ELF static paths verified; prospective union89 only; no composition/perf')
