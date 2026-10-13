#!/usr/bin/env python3
"""Validate the complete partial receipt before correcting one diagnostic expectation."""
import pathlib,json,hashlib,os,subprocess,shutil
P=pathlib.Path;root=P.cwd();base=root/'experiments/lox-eda-parity-20261013/P7';old=base/'verification-008';out=base/'recovery-008';work=root/'.tmp/lox-eda-parity/P7/recovery-008';prior_work=root/'.tmp/lox-eda-parity/P7/verification-008'
assert os.environ['MYLANG_ADMISSION_KIND']=='build'
out.mkdir();work.mkdir()
def digest(p):return hashlib.sha256(P(p).read_bytes()).hexdigest()
before=json.loads((old/'inputs-before.json').read_text());installation=before['installation'];compiler=P(next(p for p in installation if p.endswith('/bin/mylang')))
def unchanged():
 assert all(digest(p)==h for p,h in installation.items())
 assert {str(p) for p in compiler.parents[1].rglob('*') if p.is_file()}==set(installation)
 assert all(digest(p)==h for p,h in before['compiler_source_files'].items())
 assert {str(p) for p in (root/'src').rglob('*') if p.is_file()}==set(before['compiler_source_files'])
 assert digest(before['fixture'])==before['fixture_sha256']
unchanged();assert digest(base/'verify-008-original.py')==before['verifier_sha256']
rows=json.loads((old/'commands.json').read_text());assert len(rows)==142 and rows[-1]['name']=='refusal-type'
refusals={'mut-pending-overwrite':b'E_RESULT_OVERWRITE','generic-pending-overwrite':b'E_RESULT_OVERWRITE','index-relocation':b'E_MUTATION_OVERLAP','replacement-relocation':b'E_MUTATION_OVERLAP','borrow':b'E_SINGLE_OWNER_BORROW','moved':b'E_SINGLE_OWNER_MOVED','pending':b'E_EXPLICIT_DISCARD_REQUIRED','arity':b'E_ARITY','type':b'E_TYPE'}
for row in rows:
 name=row['name'];stdout=(old/(name+'.stdout')).read_bytes();stderr=(old/(name+'.stderr')).read_bytes()
 if name.startswith('refusal-'):
  assert row['returncode']==1 and refusals[name.removeprefix('refusal-')] in stderr
 elif name.endswith(('-negative','-positive','-empty','-unsigned-max')):
  assert row['returncode']==1 and b'error[R_LIST_BOUNDS]' in stderr and not stdout
 else:
  assert row['returncode']==0 and not stderr
  if name.endswith('-build'):assert not stdout
  elif name.startswith('rc-snapshot-'):assert stdout==b'RC exchange passed\n'
  elif name.startswith('list_exchange_sibling_zero_fixture'):assert stdout==b'sibling zero overwrite passed\n'
  elif name.startswith('list_exchange_sibling_fixture'):assert stdout==b'sibling overwrite passed\n'
  elif name.startswith('list_exchange_wide_discard_fixture'):assert stdout==b'wide discard passed\n'
  elif name in ['10-run','10000-run']:assert stdout==b'1 3\n'
  else:assert stdout==b'exchange passed\n'
# Revalidate every recorded counting run, not only an aggregate live count.
counts={}
for path in sorted(prior_work.glob('*.counts.json')):
 value=json.loads(path.read_text());totals=value['totals'];assert totals['live_bytes_at_exit']==0
 if 'zero-rc' in path.name or path.name in [m+'.counts.json' for m in ['release','debug','verified','optimized-debug','no-facts']] or path.name in ['10.counts.json','10000.counts.json']:
  assert all(totals[k]==0 for k in ['runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'])
  assert all(value['kinds'][k]['count']==0 for k in ['retain','release','unique_test'])
 shutil.copyfile(path,out/path.name);counts[path.name]=digest(path)
assert len(counts)==72
for mode in ['release','debug','verified','optimized-debug','no-facts']:
 llvm=(prior_work/(mode+'.ll')).read_text();assert all(s not in llvm for s in ['@myl_core_retain(', '@myl_core_release(', '@myl_core_share('])
slope=json.loads((old/'allocation-slope.json').read_text());assert slope['iterations']==[10,10000]
for key in ['allocs','reallocs','alloc_bytes','realloc_added_bytes','peak_live_bytes','live_bytes_at_exit']:assert slope['totals'][0][key]==slope['totals'][1][key]
recovered=[]
for name in ['type','remaining-result-refusal','generic-remaining-result-refusal','local-old-result-refusal']:
 unchanged()
 original=prior_work/'refusal-type.my' if name=='type' else base/'fixtures'/(name+'.my')
 private=work/(name+'.my');shutil.copyfile(original,private)
 argv=[str(compiler),'build',str(private),'--experimental-zero-rc','--release','--cache-dir',str(work/('cache-'+name)),'-o',str(work/name)]
 env={**os.environ,'MYLANG_JOBS':'4'};env.pop('MYLANG_COUNTERS',None);env.pop('MYL_CORE_LEAKCHECK',None)
 result=subprocess.run(argv,capture_output=True,env=env,timeout=120)
 (out/(name+'.stdout')).write_bytes(result.stdout);(out/(name+'.stderr')).write_bytes(result.stderr)
 code=b'E_TYPE' if name=='type' else b'E_RESULT_UNHANDLED'
 recovered.append({'name':name,'argv':argv,'returncode':result.returncode,'required_code':code.decode(),'source_sha256':digest(private)})
 (out/'commands.json').write_text(json.dumps(recovered,indent=2)+'\n')
 assert result.returncode==1 and code in result.stderr,(name,result.stderr)
unchanged()
inputs={str(p):digest(p) for p in sorted(prior_work.glob('*.my'))};inputs.update({str(p):digest(p) for p in work.glob('*.my')});inputs.update({str(p):digest(p) for p in (root/'src/core').glob('list_exchange_*fixture.my')})
evidence={str(p.relative_to(base)):digest(p) for directory in [old,out,base/'docs-008'] for p in sorted(directory.rglob('*')) if p.is_file()}
(out/'qualification.json').write_text(json.dumps({'status':'qualified_with_explicit_diagnostic_expectation_recovery','original_stop':'E_CALL_ARGUMENT expectation corrected to actual E_TYPE; original142 commands/log/harness retained','original_commands':len(rows),'recovery_commands':len(recovered),'counts':counts,'installation':installation,'compiler_source_files':before['compiler_source_files'],'all_native_sources':inputs,'evidence_sha256':evidence,'original_verifier_sha256':before['verifier_sha256'],'recovery_verifier_sha256':digest(__file__),'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n')
print('qualified:142 validated original commands +4 recovery refusals;72 counting runs; all5 modes')
