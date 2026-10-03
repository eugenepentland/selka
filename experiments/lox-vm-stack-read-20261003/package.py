#!/usr/bin/env python3
"""Seal source overlays, completed receipts and static counts without new runs."""
from pathlib import Path
import collections,difflib,gzip,hashlib,json,re,subprocess

lane=Path(__file__).resolve().parents[2]
dest=Path(__file__).resolve().parent
work=lane/'.tmp-lox-vm-stack-read-20261003'
root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
old=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-ownership-inline-20261003/.tmp-lox-gap-static-20261003')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
maps={arm:{str(f.relative_to(work/arm)):sha(f) for f in sorted((work/arm).rglob('*')) if f.is_file()} for arm in ('control','equal','equal-qualified')}
manifest=json.loads((root/'.tmp-lox-round3/binaries.json').read_text())
assert maps['control']==manifest['candidate_sources']['ast']['all_files'] and all(len(m)==37 for m in maps.values())
changed=[name for name,h in maps['control'].items() if h!=maps['equal-qualified'][name]]
assert changed==['driver_cases.json','driver_tests.my','vm.my']
patch=''
for name in changed:
    patch+=''.join(difflib.unified_diff((work/'control'/name).read_text().splitlines(True),(work/'equal-qualified'/name).read_text().splitlines(True),fromfile='a/'+name,tofile='b/'+name))
(dest/'readonly-stack-equality.patch').write_text(patch)
(dest/'source-hashes.json').write_text(json.dumps({'base_commit':'37df3ffbfab1f2ea4f269c769eb5b013c5270be3','source':{arm:str(work/arm) for arm in maps},'source_sha256':maps,'changed':changed,'patch_sha256':sha(dest/'readonly-stack-equality.patch')},indent=2)+'\n')

build=json.loads((work/'corrected-builds.json').read_text())
tests=json.loads((work/'public-qualification.json').read_text())
native=json.loads((work/'native-corrected-validation.json').read_text())
assert build['verified_after'] and tests['verified_after'] and native['verified_after']
assert build['source_sha256']==tests['source_sha256']==native['source_sha256']==maps['equal-qualified']
assert len(native['samples'])==348 and all(x['passed'] and x['actual']==x['expected'] for x in native['samples'])
counts=collections.Counter((x['backend'],x['runtime'],x['native_gc_stress'],x['lox_gc_stress']) for x in native['samples'])
assert len(counts)==12 and set(counts.values())=={29}
names={f'driver_tests::{name}' for name in ('test_run_readonly_stack_equality_tags_and_order','test_run_readonly_stack_equality_preserves_snapshots')}
for row in tests['runs']:
    log=Path(row['log']).read_text()
    assert row['status']==0 and row['summaries']==['86 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
    assert {n for n in names if 'passed '+n in log}==names
    assert sha(row['log'])==row['log_sha256']
for row in build['runs']:
    for key in ('binary','manifest','receipt','runtime_object'):assert sha(row[key])==row[key+'_sha256']
    assert ('--gc-runtime' in row['argv'])==(row['runtime']=='gc')

static={}
payload={}
for backend in ('llvm','qbe'):
    for arm,prefix,src in (('control','',old),('equal','',work)):
        path=src/(backend+'-vm-run.asm')
        text=path.read_text()
        instructions=[line for line in text.splitlines() if re.match(r'\s*[0-9a-f]+:\s+',line)]
        static[arm+'-'+backend]={'run_instructions':len(instructions),'run_call_sites':len(re.findall(r'\bcall\s+[^\n]*<',text)),'raw_assembly':str(path),'raw_assembly_sha256':sha(path)}
    path=work/(backend+'-vm-equal_stack.asm')
    text=path.read_text()
    static['equal-'+backend].update(helper_instructions=len([line for line in text.splitlines() if re.match(r'\s*[0-9a-f]+:\s+',line)]),helper_call_sites=len(re.findall(r'\bcall\s+[^\n]*<',text)),helper_assembly_sha256=sha(path))
for arm in ('control','equal'):
    emission=json.loads((work/(arm+'-emission.json')).read_text())
    units={f['name']:f for f in emission['functions']}
    static[arm+'-il']={'run_blits':units['vm::run']['il'].count(' blit '),'run_lines':len(units['vm::run']['il'].splitlines()),'run_calls':units['vm::run']['il'].count(' call '),'emission_sha256':sha(work/(arm+'-emission.json')),'emission_status':0,'diagnostic_only':True}
    if arm=='equal':static[arm+'-il'].update(helper_blits=units['vm::equal_stack']['il'].count(' blit '))
assert static['control-llvm']['run_instructions']==5586 and static['equal-llvm']['run_instructions']==5555
assert static['control-qbe']['run_instructions']==8606 and static['equal-qbe']['run_instructions']==8373
(dest/'static-evidence.json').write_text(json.dumps({'baseline_manifest_sha256':sha(root/'.tmp-lox-round3/binaries.json'),'counts':static,'limits':['Static whole-function counts include cold failure paths; no dynamic instruction, wall or parity claim.','Diagnostic IL omits step/frame accounting; production RC/GC artifacts keep native checks.','Initial84-test and final86-test source share vm.my and production RC ELF bytes exactly.','QBE helper has126 instructions and an extra values_equal call; LLVM helper is inlined.']},indent=2)+'\n')

files=['final-builds.json','corrected-builds.json','public-qualification.json','native-validation.json','native-corrected-validation.json','native-validation.log','native-corrected-validation.log','final-build.log','corrected-build.log','public-test.log',*[Path(x['log']).name for x in tests['runs']]]
files += [Path(x[k]).name for x in build['runs'] for k in ('stdout','stderr')]
for name in files:
    data=(work/name).read_bytes()
    if name.endswith('.json') and name!='native-corrected-validation.json':
        (dest/name).write_bytes(data)
        packed=name
    else:
        packed=name+'.gz'
        with (dest/packed).open('wb') as f:
            with gzip.GzipFile(fileobj=f,mode='wb',mtime=0,filename='') as z:z.write(data)
    payload[packed]={'original':str(work/name),'sha256':sha(work/name),'packed_sha256':sha(dest/packed)}
(dest/'qualification.json').write_text(json.dumps({'complete':True,'source_sha256':maps['equal-qualified'],'compiler_sha256':build['compiler_sha256'],'qbe_sha256':build['qbe_sha256'],'public_tests':344,'native_exact_comparisons':348,'distinct_complete_checks':692,'native_matrix_counts':{str(k):v for k,v in sorted(counts.items())},'partial_initial_rows_not_added':len(json.loads((work/'native-validation.json').read_text())['samples']),'partial_initial_has_failure':any(not x['passed'] for x in json.loads((work/'native-validation.json').read_text())['samples']),'payload':payload,'performance_runs':0},indent=2)+'\n')
print('Packaged all37 source hashes,344 public tests and348 native exact comparisons.')
