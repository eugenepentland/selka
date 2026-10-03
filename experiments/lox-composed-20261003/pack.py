#!/usr/bin/env python3
"""Recheck and preserve completed composed85 receipts; never runs guests."""
from collections import Counter
import gzip, hashlib, json, shutil
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-composed-20261003'
OUT = Path(__file__).resolve().parent
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
ROUND = ROOT/'.tmp-lox-round3'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
read = lambda n: json.loads((WORK/n).read_text())
files = lambda p: {str(x.relative_to(p)):sha(x) for x in sorted(p.rglob('*')) if x.is_file()}

done = read('completed.json')
before, after = done['before'], done['after']
assert done['verified_after'] and done['helper_status'] == 0
assert before['candidate37'] == after['candidate37'] == files(ROUND/'combined')
assert before['control37'] == after['control37'] == files(ROUND/'baseline')
assert len(before['candidate37']) == len(before['control37']) == 37
assert before['artifacts_sha256'] == after['artifacts_sha256']
for path, digest in after['artifacts_sha256'].items():
    assert sha(path) == digest, path
for name, digest in done['receipt_sha256'].items():
    assert sha(WORK/name) == digest, name

r = read('observations.json')
assert r['verified_after'] and len(r['samples']) == 1168 and len(r['unrun']) == 80
bins = read('binaries.json')['binaries']
assert r['binary_sha256'] == {k:sha(v) for k,v in bins.items()}
identity = lambda x:(x['name'],x['tier'],x['engine'],x['arm'],x['lox_gc_stress'])
actual, unrun = {identity(x) for x in r['samples']}, {identity(x) for x in r['unrun']}
cases = {(x['name'],x['tier'],x['engine']) for x in r['samples']}
expected = {(n,t,e,a,s) for n,t,e in cases for a in bins if not a.startswith('control-') for s in [False,True]}
assert len(cases) == 104 and len(actual) == 1168 and len(unrun) == 80
assert not actual & unrun and actual | unrun == expected
assert Counter(t for n,t,e in cases) == {'smoke':26,'regression':32,'error':46}
modes = Counter('native_gc_stress' if x['native_gc_stress'] else 'rc' if '-rc-' in x['arm'] else 'ordinary_gc' for x in r['samples'])
assert modes == {'rc':416,'ordinary_gc':416,'native_gc_stress':336}
for row in r['samples']:
    assert row['actual'] == row['expected']
    assert sha(row['command'][-1]) == row['source_sha256']
for row in r['unrun']:
    assert row['tier'] == 'smoke' and row['native_gc_stress'] and '-gc-' in row['arm']
    path = WORK/'validation-inputs'/f"{row['name']}.{row['engine']}.{row['tier']}.lox"
    assert sha(path) == row['source_sha256']
omitted = sorted({x['name'] for x in r['unrun']})
assert len(omitted) == 10
for name, count in [('constant-255-boundary.json',12),('ast-focused-observations.json',96)]:
    rows = read(name)['samples']
    assert len(rows) == count
    ids = {(x.get('name','constant-255'),x.get('engine','vm'),x['arm'],x['lox_gc_stress']) for x in rows}
    assert len(ids) == count
    for row in rows:
        assert row['actual'] == row['expected']
        assert sha(row['argv'][-1]) == row['source_sha256']
refusals = read('rc-native-stress-refusals.json')['pairs']
assert len(refusals) == len({(x['backend'],x['engine'],x['lox_gc_stress']) for x in refusals}) == 8
for x in refusals:
    assert x['actual'] == x['expected']
    assert x['actual']['status'] == 2 and x['actual']['stdout'] == '' and '--gc-runtime' in x['actual']['stderr']

public = read('public-qualification.json')
assert public['verified_after'] and public['source_sha256'] == before['candidate37']
assert len(public['runs']) == 4
for row in public['runs']:
    assert row['status'] == 0 and '--cases' not in row['argv']
    assert sha(row['log']) == row['log_sha256']
    assert row['summaries'] == ['85 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
provider = read('provider-qualification.json')
assert provider['verified_after'] and provider['source37'] == before['candidate37']
assert len(provider['runs']) == 4
provider_ids = []
for row in provider['runs']:
    assert row['status'] == 0 and '--cases' in row['argv']
    assert sha(row['stdout']) == row['stdout_sha256'] and sha(row['stderr']) == row['stderr_sha256']
    report = json.loads(Path(row['stdout']).read_text())
    assert {k:report[k] for k in ['passed','failed','skipped','cached','executed']} == {'passed':1,'failed':0,'skipped':0,'cached':0,'executed':1}
    assert len(report['tests']) == 1
    test = report['tests'][0]
    assert test['name'] == 'driver_tests::test_run_constant_operand_last_byte'
    assert test['status'] == 'passed' and test['actual'] is True and test['provider']
    provider_ids.append(test['provider'])
assert len(set(provider_ids)) == 1

# Exact source scope and mechanical preservation of the two AST arm bodies.
changed = sorted(k for k in before['candidate37'] if before['candidate37'][k] != before['control37'][k])
assert changed == ['driver_cases.json','driver_tests.my','interpreter.my','vm.my']
def body(path,name):
    text = path.read_text()
    start = text.index('def '+name+'(')
    end = text.index('\n\ndef ',start)
    return text[start:end].strip().splitlines()[1:]
ast_proofs = {}
for name, getter, arm in [('call_expr','call_node','ast.Expr.call'),('class_declaration','class_node','ast.Stmt.class_decl')]:
    old = body(ROUND/'baseline/interpreter.my',name)
    new = body(ROUND/'combined/interpreter.my',name)
    assert old[0].strip() == f'node = {getter}(program, id)'
    assert new[1].strip() == f'case {arm}(node):'
    stop = new.index('        case _:')
    assert [line[8:] if line else line for line in new[2:stop]] == old[1:]
    ast_proofs[name] = 'Original body identical after removing the additional match-arm indentation; original node getter retained.'
interpreter = (ROUND/'combined/interpreter.my').read_text()
assert 'def call_node(' in interpreter and 'def class_node(' in interpreter
for name in ['call_expr','class_declaration']:
    assert f'def {name}(program: ast.Program,' in interpreter
assert before['candidate37']['vm.my'] == '6197b4edbcf69ec39aaf1411e6f676f7d5f88057e7410b6e46368165a5e40d88'
assert before['candidate37']['interpreter.my'] == '6c4655266242ca4696a02f754ef5eac6646ceb8ba93b0869072c6d6161a87378'

copies = ['binaries.json','command.json','gc-builds.json','public-qualification.json','provider-qualification.json','observations.log','runner.log']
copies += [Path(x['log']).name for x in public['runs']]
copies += [Path(x['stderr']).name for x in provider['runs']]
for name in copies:
    shutil.copyfile(WORK/name, OUT/name)
raw = ['completed.json','observations.json','constant-255-boundary.json','ast-focused-observations.json','rc-native-stress-refusals.json']
raw += [Path(x['stdout']).name for x in provider['runs']]
archived = {}
for name in raw:
    data = (WORK/name).read_bytes()
    target = OUT/(name+'.gz')
    target.write_bytes(gzip.compress(data,mtime=0))
    assert gzip.decompress(target.read_bytes()) == data
    archived[name] = {'raw_sha256':sha(WORK/name),'gzip_sha256':sha(target),'raw_bytes':len(data),'gzip_bytes':target.stat().st_size}
summary = {
    'source':str(ROUND/'combined'),'control':str(ROUND/'baseline'),
    'source37':before['candidate37'],'control37':before['control37'],
    'changed_files':changed,'ast_body_checks':ast_proofs,
    'vm_source_check':'Matches frozen reviewed constant-readonly candidate; original read_constant and all other consumers remain unchanged.',
    'composition_sha256':sha(ROUND/'combined.json'),'patch_sha256':sha(ROUND/'combined.patch'),
    'binary_sha256':r['binary_sha256'],'compiler_sha256':public['compiler_sha256'],'qbe_sha256':public['qbe_sha256'],
    'fresh_public_directory_passes':340,'public_directory_provider':'No --cases; these runs are provider-free.',
    'fresh_explicit_provider_passes':4,'provider_identity':provider_ids[0],
    'bounded_comparisons':1168,'bounded_mode_counts':dict(modes),
    'constant_operand_boundary_comparisons':12,'ast_root_error_comparisons':96,
    'total_unaccounted_program_comparisons':1276,'rc_native_stress_checked_refusal_pairs':8,
    'explicit_unrun_native_smoke_cells':80,'unrun_smoke_names':omitted,
    'full_status_stdout_stderr_statistics_equal':True,'all_generated_input_hashes_verified_after':True,
    'frozen_sources_artifacts_inputs_unchanged':True,'verified_after':True,
    'started_utc':before['started_utc'],'finished_utc':done['finished_utc'],
    'runner_affinity':before['runner_affinity'],'receipts':archived,
    'copied_receipt_sha256':{n:sha(OUT/n) for n in copies},
    'limitations':['80 bounded native-GC-stress smoke omissions are not passes.',
                  '8 native-stress RC checked refusals are not program passes.',
                  'Accounted public tests and actual unaccounted ELF comparisons are separate qualifications.',
                  'Malformed internal AST/bytecode native helper-frame attribution may differ; valid Lox traces were compared exactly.',
                  'No performance workloads or parity claims in this stage.']}
(OUT/'qualification.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Verified fresh 340 public +4 explicit provider passes, 1276 actual ELF program pairs and8 checked refusal pairs; 80 omissions recorded.')
