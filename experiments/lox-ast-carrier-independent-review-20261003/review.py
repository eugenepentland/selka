#!/usr/bin/env python3
"""Read frozen AST source and qualification evidence; never execute guests."""
import argparse
from collections import Counter
import datetime
import gzip
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
READS = {}
COMMIT = '941b030cfa2ec49b0c6c4bdb88501d9785462a46'
D14 = 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
C4 = '4cbaeafad871b4527e6e550b4412629341335340590f8a0b8b3ec97a7f8c91d0'


def read(path):
    path = Path(path).resolve()
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert str(path) not in READS or READS[str(path)] == digest
    READS[str(path)] = digest
    return data


def sha(path):
    read(path)
    return READS[str(Path(path).resolve())]


def load(path):
    data = read(path)
    return json.loads(gzip.decompress(data) if str(path).endswith('.gz') else data)


def body(source, name):
    match = re.search(r'^def ' + name + r'\(.*?(?=^def |^public def |\Z)', source, re.M | re.S)
    assert match
    return match[0].split('\n', 1)[1].rstrip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lane', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    assert not a.out.exists(), 'choose a fresh receipt path'
    lane = a.lane.resolve()
    exp = lane / 'experiments/lox-tree-ast-carrier-20261003'
    scratch = lane / '.tmp-lox-ast-carrier-20261003'
    identities = {}
    for path in sorted(exp.iterdir()):
        if not path.is_file():
            continue
        relative = str(path.relative_to(lane))
        committed = subprocess.run(['git', 'show', COMMIT + ':' + relative], cwd=lane,
                                   capture_output=True, check=True).stdout
        assert read(path) == committed
        identities[relative] = sha(path)
    s = load(exp / 'source.json')
    assert s['changed'] == ['interpreter.my'] and s['root_source_verified_after']
    original, current = {}, {}
    for key, target in [('baseline', original), ('candidate', current)]:
        directory = Path(s[key])
        assert len(s[key + '_hashes']) == 37
        assert {str(p.relative_to(directory)) for p in directory.rglob('*') if p.is_file()} == set(s[key + '_hashes'])
        for name, digest in s[key + '_hashes'].items():
            target[name] = read(directory / name)
            assert sha(directory / name) == digest
    assert [k for k in original if original[k] != current[k]] == ['interpreter.my']
    # Reuse the earlier strict in-memory unified-diff reader, never patch disk sources.
    helper = Path(__file__).parent.parent / 'lox-callee-table-checkpoint-independent-review-20261003/audit.py'
    spec = importlib.util.spec_from_file_location('checkpoint_replay', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    replay, changed = module.patch_replay(read(exp / 'ast-carrier.patch'), original)
    assert changed == ['interpreter.my'] and replay == current
    assert sha(exp / 'ast-carrier.patch') == s['patch_sha256']
    for name, digest in s['candidate_hashes'].items():
        assert sha(scratch / 'overlay-replay' / name) == digest
    old, new = original['interpreter.my'].decode(), current['interpreter.my'].decode()
    # Expected-arm operations must retain the complete original order, including ? exits.
    for handler, getter, tag in [('call_expr', 'call_node', 'ast.Expr.call'),
                                 ('class_declaration', 'class_node', 'ast.Stmt.class_decl')]:
        before = body(old, handler)
        assert before.splitlines()[0] == '    node = ' + getter + '(program, id)'
        after = body(new, handler).splitlines()
        begin = after.index('        case ' + tag + '(node):') + 1
        end = after.index('        case _:')
        assert [line[8:] for line in after[begin:end]] == before.splitlines()[1:]
        assert body(old, getter) == body(new, getter)
    builds = load(exp / 'selectedd14-builds.json')
    historical = load(exp / 'historical4cbae-builds.json')
    build_report = {}
    for flavor, d in builds.items():
        backend, runtime = flavor.split('-')
        argv = d['argv']
        assert d['status'] == 0 and d['source_verified_after'] and d['compiler_verified_after']
        assert d['source_files'] == s['candidate_hashes'] and d['compiler_sha256'] == D14
        assert sha(argv[2]) == D14 and sha(Path(argv[2]).parent / 'qbe') == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
        assert '--' + runtime + '-runtime' in argv and '--keep-symbols' in argv
        assert argv[0].endswith('/scripts/build-slot.sh') and argv[1] == 'build'
        assert sha(d['binary']) == d['binary_sha256']
        assert sha(d['binary'] + '.qbe-manifest.json') == d['manifest_sha256']
        manifest = load(d['binary'] + '.qbe-manifest.json')
        assert manifest['backend'] == backend and manifest['runtime_object'] == d['runtime_object']
        assert sha(d['runtime_object']) == d['runtime_object_sha256']
        assert manifest['optimization'] == ('3' if backend == 'llvm' else 'default')
        assert manifest['lto'] == (backend == 'llvm') and not manifest['thin_lto']
        sha(d['binary'] + '.qbe-receipt')
        h = historical[flavor]
        assert h['compiler_sha256'] == C4 and sha(h['binary']) == h['binary_sha256']
        same = d['binary_sha256'] == h['binary_sha256']
        assert same == (runtime == 'gc')
        build_report[flavor] = {'binary_sha256': d['binary_sha256'], 'manifest_sha256': d['manifest_sha256'],
                                'runtime_object_sha256': d['runtime_object_sha256'], 'historical_byte_identical': same}
    v = load(exp / 'validation.json')
    assert v['verified_after'] and v['before']['candidate37'] == v['after']['candidate37'] == s['candidate_hashes']
    assert v['before']['root_baseline37'] == v['after']['root_baseline37'] == s['baseline_hashes']
    assert v['before']['artifacts_sha256'] == v['after']['artifacts_sha256']
    for path, digest in v['before']['artifacts_sha256'].items():
        assert sha(path) == digest
    work = Path(v['raw_final_runner']).parent
    assert sha(v['raw_final_runner']) == v['raw_final_runner_sha256']
    for name, digest in v['receipt_sha256'].items():
        assert sha(work / name) == digest
    bins = load(work / 'binaries.json')['binaries']
    bounded = load(exp / 'bounded-observations.json.gz')
    focused = load(exp / 'focused-observations.json.gz')
    assert read(work / 'observations.json') == gzip.decompress(read(exp / 'bounded-observations.json.gz'))
    assert read(work / 'focused-observations.json') == gzip.decompress(read(exp / 'focused-observations.json.gz'))
    assert bounded['verified_after'] and bounded['manifest_sha256'] == sha(work / 'binaries.json')
    assert bounded['binary_sha256'] == {arm: sha(path) for arm, path in bins.items()}
    prior = load(bounded['resume_provenance']['path'])
    assert sha(bounded['resume_provenance']['path']) == bounded['resume_provenance']['sha256']
    assert prior['samples'] == bounded['samples'] and prior['unrun'] == bounded['unrun']
    assert prior['binary_sha256'] == bounded['binary_sha256']
    observations = bounded['samples']
    keys = lambda row: tuple(row[k] for k in ['name', 'tier', 'engine', 'arm', 'lox_gc_stress'])
    done, unrun = {keys(r) for r in observations}, {keys(r) for r in bounded['unrun']}
    cases = {(r['name'], r['tier'], r['engine']) for r in observations}
    # Build expected case identities from inputs independently of observed rows.
    bench = lane.parent / 'codex-lox-parity-20261003/.tmp-lox-parity/reference/benchmarks/lox/bench'
    regressions = load(lane / 'experiments/lox-vm-callee-20261003/regressions.json')
    fixture_cases = {(p.stem, 'smoke', e) for p in (bench / 'scripts').glob('*.lox') for e in ['tree', 'vm']}
    fixture_cases |= {(r['name'], 'regression', e) for r in regressions for e in ['tree', 'vm']}
    root = lane.parent / 'codex-lox-parity-20261003'
    error_fixtures = {}
    for engine, name in [('tree', 'd9-lox-env-reads-runs.json.gz'), ('vm', 'd9-lox-class-method-runs.json.gz')]:
        traces = load(root / 'docs/audits/evidence' / name)['traces']
        by_name = {r['name']: r for r in traces}
        assert len(by_name) == 23
        error_fixtures[engine] = by_name
        fixture_cases |= {(n, 'error', engine) for n in by_name}
    assert cases == fixture_cases
    targets = {(n, t, e, arm, stress) for n, t, e in cases
               for arm in bins if not arm.startswith('control-') for stress in [False, True]}
    assert len(observations) == len(done) == 1168 and len(bounded['unrun']) == len(unrun) == 80
    assert not done & unrun and done | unrun == targets and len(cases) == 104
    assert Counter(r['tier'] for r in observations) == {'smoke': 232, 'regression': 384, 'error': 552}
    modes = Counter('native_gc_stress' if r['native_gc_stress'] else 'rc' if '-rc-' in r['arm'] else 'ordinary_gc' for r in observations)
    assert modes == v['mode_counts'] == {'rc': 416, 'ordinary_gc': 416, 'native_gc_stress': 336}
    for row in observations + focused['samples']:
        assert row['actual'] == row['expected']
        cmd = row.get('command', row.get('argv'))
        assert cmd[0] == bins[row['arm']] and '--engine=' + row['engine'] in cmd
        assert ('--gc-stress' in cmd) == row['lox_gc_stress']
        assert row['native_gc_stress'] == ('-gc-' in row['arm'])
        assert sha(cmd[-1]) == row['source_sha256']
        assert row['actual']['status'] in [0, 65, 70]
        assert re.search(r'\[stats\] engine=' + row['engine'] + r' allocations=\d+ collections=\d+ freed=\d+ live=\d+\n$', row['actual']['stderr'])
    for row in observations:
        if row['tier'] == 'smoke':
            assert row['actual']['stdout'] == read(bench / 'expected' / (row['name'] + '.smoke.out')).decode()
        elif row['tier'] == 'regression':
            assert row['actual']['stdout'] == next(r['stdout'] for r in regressions if r['name'] == row['name'])
        else:
            historical_error = error_fixtures[row['engine']][row['name']]['expected']
            assert row['actual']['status'] == historical_error['status']
            assert row['actual']['stdout'] == historical_error['stdout']
            assert row['actual']['stderr'].startswith(historical_error['stderr'])
    fc = load(exp / 'regressions.json')
    expected_focused = set(itertools.product([c['name'] for c in fc], ['tree', 'vm'],
                         ['ast-' + m + '-' + b for m in ['rc', 'ordinary', 'gc'] for b in ['llvm', 'qbe']], [False, True]))
    actual_focused = [(r['name'], r['engine'], r['arm'], r['lox_gc_stress']) for r in focused['samples']]
    assert len(actual_focused) == 96 and set(actual_focused) == expected_focused
    for row in focused['samples']:
        fixture = next(c for c in fc if c['name'] == row['name'])
        assert read(row['argv'][-1]) == fixture['source'].encode()
        assert row['actual']['status'] == fixture['status'] and row['actual']['stdout'] == fixture['stdout']
        if 'stderr_prefix_by_engine' in fixture:
            assert row['actual']['stderr'].startswith(fixture['stderr_prefix_by_engine'][row['engine']])
    refuses = v['rc_native_stress_refusals']['comparisons']
    assert len(refuses) == 8 and {(r['backend'], r['engine'], r['lox_gc_stress']) for r in refuses} == set(itertools.product(['llvm', 'qbe'], ['tree', 'vm'], [False, True]))
    assert all(r['actual'] == r['expected'] and r['actual']['status'] == 2 for r in refuses)
    failed = v['failed_prefix_fixture_receipt']
    prior_work = Path(bounded['resume_provenance']['path']).parent
    assert failed['runner_status'] == 1 and failed['main_matrix_passed'] == 1168 and failed['partial_focused_passed'] == 60
    for name, digest in failed['receipts_sha256'].items():
        assert sha(prior_work / name) == digest
    partial = load(prior_work / 'focused-observations.json')['samples']
    assert len(partial) == 60 and all(r['actual'] == r['expected'] for r in partial)
    assert not any(r['name'] == 'ast_call_argument_error_after_two_side_effects' and r['engine'] == 'vm' for r in partial)
    assert sha(scratch / 'focused-regressions.json') == failed['original_fixture_sha256']
    failure_log = read(prior_work / 'runner.log').decode()
    assert 'AssertionError' in failure_log and 'expected' in failure_log and 'in script' in failure_log
    assert v['public_accounted_compiler'] == C4 and v['selected_native_compiler'] == D14
    accounted = load(exp / 'accounted-public-observations.json.gz')
    qualification = load(exp / 'accounted-public-qualification.json')
    assert qualification['start']['compiler_sha256'] == C4 and sha(qualification['start']['compiler']) == C4
    assert qualification['start']['source_hashes'] == s['candidate_hashes']
    totals = []
    for flavor in ['qbe-normal', 'qbe-stress', 'llvm-normal', 'llvm-stress']:
        commands = accounted[flavor + '/commands.json']
        names = []
        for command in commands:
            module = Path(command['module']).stem
            doc = accounted[flavor + '/' + module + '.json']
            names.extend(t['name'] for t in doc['tests'])
            assert command['status'] == 0 and '--force' in command['argv'] and '--max-steps' in command['argv']
            assert ('--gc-stress' in command['argv']) == flavor.endswith('stress')
            assert all(doc[x] == 0 for x in ['failed', 'skipped', 'cached'])
            assert doc['passed'] == doc['executed'] == len(doc['tests'])
            assert all(t['status'] == 'passed' for t in doc['tests'])
        assert len(names) == len(set(names)) == 84
        expected = {Path(n).stem + '::' + f for n, data in current.items() if n.endswith('.my')
                    for f in re.findall(r'^public def (test_\w+)\(', data.decode(), re.M)}
        assert set(names) == expected
        totals.append({'flavor': flavor, 'fresh_tests': 84, 'mode': 'Debug' if flavor.startswith('qbe') else 'release'})
    emission = load(exp / 'selected-emission.json')
    assert emission['compiler_sha256'] == D14
    bounds = {}
    for arm, data in emission['arms'].items():
        assert sha(data['manifest']) == data['manifest_sha256']
        for name, fn in data['functions'].items():
            il = read(fn['ssa_source']).decode()
            assert sha(fn['ssa_source']) == fn['ssa_sha256']
            assert fn['normalized_index_bounds'] == il.count('$myl_qbe_fail_normalized_index_bounds')
            assert fn['managed_ops'] == {op: len(re.findall('_rcg_' + op + r'\b', il)) for op in ['take', 'drop', 'loan', 'unloan', 'copy']}
            for backend, asm in fn['assembly'].items():
                assert sha(asm['binary']) == asm['binary_sha256']
                path = scratch / 'selected-emission' / (arm + '-' + name + '.' + backend + '.asm')
                assert sha(path) == asm['sha256']
            bounds[arm + '/' + name] = fn['normalized_index_bounds']
    assert bounds['baseline/call_expr'] + bounds['baseline/call_node'] == bounds['candidate/call_expr'] == 2
    assert bounds['baseline/class_declaration'] + bounds['baseline/class_node'] == bounds['candidate/class_declaration'] == 3
    getter_sites = {}
    for arm, data in emission['arms'].items():
        for handler, getter in [('call_expr', 'call_node'), ('class_declaration', 'class_node')]:
            fn = data['functions'][handler]
            symbol = data['functions'][getter]['symbol']
            il_sites = read(fn['ssa_source']).decode().count('$' + symbol)
            asm_path = scratch / 'selected-emission' / (arm + '-' + handler + '.qbe.asm')
            calls = Counter(re.findall(r'call\s+[0-9a-f]+\s+<([^>]+)>', read(asm_path).decode()))
            assert dict(sorted(calls.items())) == fn['assembly']['qbe']['calls']
            assert il_sites == calls[symbol] == (1 if arm == 'baseline' else 0)
            getter_sites[arm + '/' + handler] = {'ssa_getter_calls': il_sites, 'saved_qbe_assembly_getter_calls': calls[symbol]}
    for path, digest in list(READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    result = {'outcome': 'pass with stated coverage and native-diagnostic limits; no actionable source defect found',
              'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'candidate_commit': COMMIT,
              'patch_sha256': s['patch_sha256'], 'candidate_interpreter_sha256': s['candidate_hashes']['interpreter.my'],
              'source37_and_overlay_replay_verified': True, 'expected_arm_operation_order_textually_preserved': True,
              'selected_native_compiler': D14, 'selected_native_builds': build_report,
              'bounded_exact_comparisons': 1168, 'bounded_mode_counts': dict(modes), 'native_smoke_cells_explicitly_unrun': 80,
              'bounded_resume_prior_sha256': bounded['resume_provenance']['sha256'], 'bounded_rows_reused_without_double_counting': True,
              'new_focused_exact_comparisons': 96, 'rc_native_stress_refusal_pairs': 8, 'accounted_historical_compiler': C4,
              'fresh_accounted_public_tests': 336, 'accounted_modes': totals, 'static_bounds_and_ssa_assembly_hashes_verified': True,
              'owning_getter_calls_removed': getter_sites,
              'historical_fixture_failure_preserved': {'status': 1, 'bounded_passes': 1168, 'partial_focused_passes': 60,
                                                       'failed_vm_fixture_candidate_rows': 0, 'corrected_focused_passes': 96},
              'author_experiment_file_hashes': identities, 'stable_read_input_count': len(READS),
              'stable_read_identity_sha256': hashlib.sha256(json.dumps(READS, sort_keys=True).encode()).hexdigest(),
              'guest_or_perf_executions': 0, 'source_or_root_mutations': 0,
              'limits': ['Internal wrong-node assertions retain their messages but now originate in handlers; exact native source PCs, frames and step cutoffs are not unchanged.',
                         'All 80 unrun native-GC smoke cells remain unrun, never passed; selected closures/instantiation/properties, focused programs and errors supply bounded native-stress coverage.',
                         'The accounted suite uses historical4cbae; native d14 builds are independently checked and tested, without claiming d14 accounted336 execution.',
                         'Resumed1168 and corrected96 counts exclude duplicated historical1168/partial60 observations.',
                         'Saved static SSA and assembly identities are checked without new disassembly or timing; absent standalone LLVM symbols do not prove absent work.',
                         'Read-only evidence review does not rerun tests or prove performance, parity, or whole-program correctness.']}
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(a.out), 'sha256': hashlib.sha256(a.out.read_bytes()).hexdigest(), 'outcome': result['outcome']}))


if __name__ == '__main__':
    main()
