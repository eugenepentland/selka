#!/usr/bin/env python3
"""Recheck and archive fresh AST+octet qualification without running guests."""
from collections import Counter
import gzip, hashlib, json, re
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN / '.tmp-lox-ast-bytecode-20261003'
NATIVE = WORK / 'native'
OUT = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
read = lambda path: json.loads(Path(path).read_text())
files = lambda root: {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}

source = read(OUT / 'source.json')
expected = dict(source['bytecode37'])
expected['interpreter.my'] = source['baseline37']['interpreter.my']
assert expected == source['candidate37'] == files(WORK / 'candidate')
assert source['baseline37'] == files(Path(source['baseline'])) == files(WORK / 'baseline')
assert source['bytecode37'] == files(Path(source['bytecode_source']))
assert len(expected) == len(source['baseline37']) == 37
assert expected['interpreter.my'] == '6c4655266242ca4696a02f754ef5eac6646ceb8ba93b0869072c6d6161a87378'
assert expected['vm.my'] == '82c60823d7154ec3c266acd3d2d8905836e3898ad416a4ce1611d89cd9559288'
changed = sorted(k for k in expected if expected[k] != source['baseline37'][k])
assert changed == source['changed_vs_selected_ast'] == ['chunk.my', 'compiler.my', 'compiler_test.my', 'driver_cases.json', 'driver_tests.my', 'vm.my']
assert sha(OUT / 'ast-bytecode.patch') == source['patch_sha256']
replay = read(OUT / 'replay.json')
assert replay['verified'] and replay['status'] == 0
assert replay['actual37'] == replay['expected37'] == expected == files(WORK / 'replay')
names = sorted(f'{p.stem}::{name}' for p in (WORK / 'candidate').glob('*.my')
               for name in re.findall(r'^public def (test_\w+)\(', p.read_text(), re.M))
assert len(names) == 88 and names == source['public_names']
old_names = {f'{p.stem}::{name}' for p in (WORK / 'baseline').glob('*.my')
             for name in re.findall(r'^public def (test_\w+)\(', p.read_text(), re.M)}
assert len(old_names) == 84 and old_names <= set(names)
assert sorted(set(names) - old_names) == source['added_public_names']
assert (WORK / 'candidate/driver_cases.json').read_bytes() == (Path(source['bytecode_source']) / 'driver_cases.json').read_bytes()

done = read(NATIVE / 'completed.json')
before, after = done['before'], done['after']
assert done['verified_after'] and done['helper_status'] == 0
assert before['candidate37'] == after['candidate37'] == expected
assert before['control37'] == after['control37'] == source['baseline37']
assert before['artifacts_sha256'] == after['artifacts_sha256']
assert not set(before['runner_affinity']) & {2, 3, 10, 11}
for path, digest in after['artifacts_sha256'].items():
    assert sha(path) == digest, path
for name, digest in done['receipt_sha256'].items():
    assert sha(NATIVE / name) == digest, name

bounded = read(NATIVE / 'observations.json')
bins = read(NATIVE / 'binaries.json')['binaries']
assert bounded['verified_after'] and bounded['binary_sha256'] == {k: sha(v) for k, v in bins.items()}
identity = lambda x: (x['name'], x['tier'], x['engine'], x['arm'], x['lox_gc_stress'])
actual = {identity(x) for x in bounded['samples']}
unrun = {identity(x) for x in bounded['unrun']}
cases = {(x['name'], x['tier'], x['engine']) for x in bounded['samples']}
matrix = {(n, t, e, a, s) for n, t, e in cases for a in bins if not a.startswith('control-') for s in [False, True]}
assert len(bounded['samples']) == len(actual) == 1192
assert len(bounded['unrun']) == len(unrun) == 80
assert len(cases) == 106 and actual.isdisjoint(unrun) and actual | unrun == matrix
assert Counter(t for n, t, e in cases) == {'smoke': 26, 'regression': 34, 'error': 46}
modes = Counter('native_gc_stress' if x['native_gc_stress'] else 'rc' if '-rc-' in x['arm'] else 'ordinary_gc' for x in bounded['samples'])
assert modes == done['mode_counts'] == {'rc': 424, 'ordinary_gc': 424, 'native_gc_stress': 344}
for row in bounded['samples']:
    assert row['actual'] == row['expected']
    assert sha(row['command'][-1]) == row['source_sha256']
for row in bounded['unrun']:
    assert row['tier'] == 'smoke' and row['native_gc_stress'] and '-gc-' in row['arm']
    path = NATIVE / 'validation-inputs' / f"{row['name']}.{row['engine']}.{row['tier']}.lox"
    assert sha(path) == row['source_sha256']
omitted = sorted({x['name'] for x in bounded['unrun']})
assert len(omitted) == 10

extra = [('constant-255-boundary.json', 'samples', 12), ('argument-limits.json', 'pairs', 192),
         ('ast-focused-observations.json', 'samples', 96)]
for name, key, count in extra:
    rows = read(NATIVE / name)[key]
    ids = {(x.get('name', 'constant-255'), x.get('engine', 'vm'), x['arm'], x['lox_gc_stress']) for x in rows}
    assert len(rows) == len(ids) == count
    for row in rows:
        assert row['actual'] == row['expected']
        assert sha(row['argv'][-1]) == row['source_sha256']
        assert row['native_gc_stress'] == ('-gc-' in row['arm'])
for row in read(NATIVE / 'argument-limits.json')['pairs']:
    legal = row['name'] == 'argument255-last-slot'
    assert row['actual']['status'] == (0 if legal else 65)
    assert row['actual']['stdout'] == ('nil\n' if legal else '')
    assert legal or '255 arguments' in row['actual']['stderr']
refusals = read(NATIVE / 'rc-native-stress-refusals.json')['pairs']
assert len(refusals) == len({(x['backend'], x['engine'], x['lox_gc_stress']) for x in refusals}) == 8
for row in refusals:
    assert row['actual'] == row['expected'] and row['actual']['status'] == 2
    assert row['actual']['stdout'] == '' and '--gc-runtime' in row['actual']['stderr']

builds = read(WORK / 'builds.json')
assert builds['verified_after'] and builds['source37'] == expected and len(builds['runs']) == 4
assert builds['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert builds['qbe_sha256'] == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
for row in builds['runs']:
    assert row['status'] == 0 and sha(row['binary']) == row['binary_sha256']
    assert sha(row['manifest']) == row['manifest_sha256']
    assert sha(row['binary'] + '.qbe-receipt') == row['receipt_sha256']
    assert sha(row['runtime_object']) == row['runtime_object_sha256']
    assert '--project' in row['argv'] and '--keep-symbols' in row['argv']
    assert ('--rc-runtime' in row['argv']) == row['key'].startswith('rc-')
    assert ('--gc-runtime' in row['argv']) == row['key'].startswith('gc-')
    if row['key'].endswith('-llvm'):
        assert '--lto' in row['argv'] and row['argv'][row['argv'].index('--llvm-opt') + 1] == '3'

public = read(WORK / 'public-qualification.json')
assert public['verified_after'] and public['source_sha256'] == expected and len(public['runs']) == 4
assert public['compiler_sha256'] == builds['compiler_sha256'] and public['qbe_sha256'] == builds['qbe_sha256']
counts = {'passed': 88, 'failed': 0, 'skipped': 0, 'cached': 0, 'executed': 88, 'dropped': 0, 'unloaded': 0, 'programs': 10}
for row in public['runs']:
    assert row['status'] == 0 and '--cases' not in row['argv'] and row['provider_identity'] == ''
    assert sha(row['log']) == row['log_sha256'] and sha(row['stderr']) == row['stderr_sha256']
    report = read(row['log'])
    assert row['counts'] == {k: report[k] for k in counts} == counts
    assert sorted(x['name'] for x in report['tests']) == names
    assert all(x['status'] == 'passed' and x['actual'] is True and x['provider'] == '' for x in report['tests'])

# The archive stores exact raw text, including full JSON test dependencies and every guest stream.
paths = {NATIVE / name for name in ['preflight.json', 'completed.json', 'binaries.json', 'command.json',
    'observations.json', 'observations.log', 'constant-255-boundary.json', 'argument-limits.json',
    'ast-focused-observations.json', 'rc-native-stress-refusals.json', 'runner.log']}
paths.update(WORK / name for name in ['builds.json', 'public-qualification.json', 'builds.log', 'public.log'])
for row in builds['runs']:
    paths.update([Path(row['log']), Path(row['manifest']), Path(row['binary'] + '.qbe-receipt')])
for row in public['runs']:
    paths.update([Path(row['log']), Path(row['stderr'])])
paths.update(NATIVE / 'validation-inputs' / p.name for p in (NATIVE / 'validation-inputs').iterdir() if p.is_file())
raw = {str(p.relative_to(WORK)): p.read_text() for p in sorted(paths)}
archive = json.dumps(raw, sort_keys=True, separators=(',', ':')).encode()
target = OUT / 'receipts.json.gz'
target.write_bytes(gzip.compress(archive, mtime=0))
assert gzip.decompress(target.read_bytes()) == archive
summary = {
    'source': str(WORK / 'candidate'), 'control': source['baseline'], 'base_commit': source['base_commit'],
    'bytecode_author_commit': 'beaaf97c7397beafb0988f5ed73dde0bf4813ebb',
    'source37': expected, 'control37': source['baseline37'], 'bytecode37': source['bytecode37'],
    'changed_files_vs_selected_ast': changed, 'composition_rule': 'Bytecode v3 source37 with only interpreter.my copied from selected AST84.',
    'patch_sha256': source['patch_sha256'], 'replay_verified_all37': True,
    'binary_sha256': bounded['binary_sha256'], 'compiler_sha256': builds['compiler_sha256'], 'qbe_sha256': builds['qbe_sha256'],
    'fresh_public_passes': 352, 'fresh_public_names': names,
    'public_provider_scope': 'No --cases; empty provider identities; driver_cases.json is preserved structurally, without provider-backed execution claim.',
    'bounded_comparisons': 1192, 'bounded_mode_counts': dict(modes), 'constant_operand_boundary_comparisons': 12,
    'argument_limit_recovery_comparisons': 192, 'ast_root_error_comparisons': 96,
    'total_unaccounted_program_comparisons': 1492, 'rc_native_stress_checked_refusal_pairs': 8,
    'explicit_unrun_native_smoke_cells': 80, 'unrun_smoke_names': omitted,
    'full_status_stdout_stderr_statistics_equal': True, 'all_generated_input_hashes_verified_after': True,
    'frozen_sources_artifacts_inputs_unchanged': True, 'verified_after': True,
    'started_utc': before['started_utc'], 'finished_utc': done['finished_utc'], 'runner_affinity': before['runner_affinity'],
    'archive': {'path': str(target), 'sha256': sha(target), 'raw_bytes': len(archive), 'gzip_bytes': target.stat().st_size,
                'files': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in raw.items()}},
    'limitations': ['80 native-GC-stress smoke omissions are not passes.', '8 RC native-stress refusals are not program passes.',
        'Accounted public checks and actual unaccounted ELF comparisons are separate qualifications.',
        'Malformed internal AST/bytecode helper frames may differ; valid Lox error traces and statistics are compared exactly.',
        'No performance workloads or parity claims in this qualification.']}
(OUT / 'qualification.json').write_text(json.dumps(summary, indent=2) + '\n')
print('Verified fresh352 public checks +1492 exact native program pairs +8 checked refusals;80 omissions preserved.')
