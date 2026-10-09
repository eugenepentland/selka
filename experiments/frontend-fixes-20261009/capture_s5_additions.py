import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd(); area=root/'experiments/frontend-fixes-20261009'; compiler=Path('/home/epentland/.cache/mylang/frontend-fixes-20261009/before/bin/mylang')
assert not (area/'s5-frontend-reference.json').exists(), 'retain the captured baseline; do not refreeze it'
sha=lambda b: hashlib.sha256(b).hexdigest()
assert sha(compiler.read_bytes())==json.loads((area/'f1-before.json').read_text())['compiler_sha256']
files={}; runs=[]; sources={}
for name in ('frontend_mut','frontend_numbers','frontend_type_helpers','frontend_types'):
 path=root/'tests/lang'/(name+'.my'); original=path.read_bytes()
 assert subprocess.check_output(['git','show','b52b6edb2:tests/lang/'+name+'.my'])==original
 sources[name]=sha(original)
 for mode in ('debug','release'):
  argv=[str(compiler),'test',str(path),'--json','--cache-dir','/home/epentland/.cache/mylang/frontend-fixes-20261009/s5-additions-cache']
  if mode=='release': argv+=['--release','--verify-facts']
  run=subprocess.run(argv,capture_output=True,env=dict(os.environ,MYL_CORE_LEAKCHECK='1'))
  report=json.loads(run.stdout); rows=[[t['name'],t['status'],''] for t in report['tests']]
  assert run.returncode==(0 if rows else 3) and all(t[1]=='passed' for t in rows)
  if mode=='debug': files[name]={'tests':rows}
  else: assert files[name]['tests']==rows
  runs.append({'file':name,'mode':mode,'status':run.returncode,'tests':len(rows),'stdout_sha256':sha(run.stdout),'stderr_sha256':sha(run.stderr)})
  print(name,mode,len(rows),'PASS',flush=True)
 assert path.read_bytes()==original
renames={'dict_comprehensions::test_nested_clauses_read_left_to_right':'dict_comprehensions::test_explicit_nested_loops_read_left_to_right','dict_comprehensions::test_two_names_and_several_filters_in_a_list_comprehension':'dict_comprehensions::test_destructuring_loops_and_combined_comprehension_filter'}
sources['dict_comprehensions']=sha((root/'tests/lang/dict_comprehensions.my').read_bytes())
result={'baseline_source_commit':'d9deb9b70','baseline_compiler':str(compiler),'baseline_compiler_sha256':sha(compiler.read_bytes()),'frozen_reference_sha256':sha((root/'experiments/new-core-s5-20261007/references/conformance-v1.json').read_bytes()),'migration_commit':'a9c1109e8ab92a33a6375f38ccf8200849f5663e','name_mappings':renames,'sources_sha256':sources,'files':files,'runs':runs,'original_cases_per_mode':1518,'additional_cases_per_mode':sum(len(x['tests']) for x in files.values())}
(area/'s5-frontend-reference.json').write_text(json.dumps(result,indent=2)+'\n')
