#!/usr/bin/env python3
"""Collect common-artifact A04 evidence without treating instrumented time as timing."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
A04 = HERE.parent
SHA = '540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
SOURCE = 'bed11cf3bf3102ffec44487e431a1573fdf02ad5'
PHASE = 'support7-01'
paths = {'public_exports': A04 / PHASE / 'results.json'}
paths.update({name: A04 / name / PHASE / 'results.json' for name in ('selections', 'formatting', 'repetition', 'rendering', 'slices', 'extrema', 'tuples', 'additional-migrations')})
paths['migrations'] = A04 / 'migrations/execution-support7.json'
report = {'compiler_sha256': SHA, 'source_commit': SOURCE, 'suites': {}, 'normal_return_instrumented_metrics': [], 'fatal_trap_metrics': [],
          'limits': ['Overlapping suites retain their own denominators; counts are not unique workload counts.',
                     'Managed allocation traffic, peak live bytes and exit-live bytes are separate metrics; none estimates RSS.',
                     'Instrumented build/run durations in raw records are operational observations, not paired timings.',
                     'Ordinary controls remain distinct; checked RC/LLVM/symbol checks apply to selected checked lanes.',
                     'Guest-test command suites verify assertions and leak stderr but do not supply whole-program allocation/RC counters.',
                     'Support7 qualifies one integrated opt-in artifact with owned installed components; default and legacy retirement require later qualification.']}


def walk(value, keys=()):
    if not isinstance(value, dict):
        return
    if 'binary_sha256' in value:
        for run_name, run in value.get('runs', {}).items():
            audit = run.get('audit', {})
            report['normal_return_instrumented_metrics'].append({'case': '/'.join(keys), 'run': run_name,
                'binary_sha256': value['binary_sha256'], 'source_sha256': value.get('source_sha256'),
                'ordinary_control': 'ordinary' in '/'.join(keys), 'memory': run.get('memory', {}),
                'observed_rc_free': audit.get('observed_rc_free'), 'managed_leak_free': audit.get('managed_leak_free')})
        if 'audit' in value and 'run' in value:
            if value['run']['status'] == 0:
                report['normal_return_instrumented_metrics'].append({'case': '/'.join(keys), 'run': '1',
                    'binary_sha256': value['binary_sha256'], 'source_sha256': value.get('source_sha256'),
                    'ordinary_control': 'ordinary' in '/'.join(keys), 'memory': value['memory'],
                    'observed_rc_free': value['audit']['observed_rc_free'],
                    'managed_leak_free': value['audit']['managed_leak_free']})
            else:
                assert keys[0] == 'extrema' and value['run']['status'] == 1
                report['fatal_trap_metrics'].append({'case': '/'.join(keys), 'binary_sha256': value['binary_sha256'],
                    'audit': value['audit'], 'exit_status': value['run']['status'],
                    'classification': 'Intentional fatal _exit trap without local owner unwinding; not a normal-return leak assertion.'})
        return
    for key, item in value.items():
        walk(item, (*keys, key))

for name, path in paths.items():
    data = json.loads(path.read_text())
    actual = data.get('compiler_sha256', data.get('compiler', {}).get('sha256') if isinstance(data.get('compiler'), dict) else None)
    actual = actual or data.get('identity', {}).get('compiler_sha256')
    assert actual == SHA, (name, actual)
    summary = data.get('summary')
    if name == 'tuples':
        summary = {'native_lanes': len(data['native']), 'source_checks': len(data['source_checks']), 'failed': data['failed']}
    assert summary is not None, (name, 'incomplete')
    report['suites'][name] = {'report': str(path.relative_to(A04)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'summary': summary}
    walk(data, (name,))
base = json.loads((A04 / 'c0/results.json').read_text())
final = json.loads(paths['public_exports'].read_text())
assert [(r['module'], r['name'], r['source_sha256']) for r in base['inventory']['declarations']] == [(r['module'], r['name'], r['source_sha256']) for r in final['inventory']['declarations']], 'public library source changed; classify source migration separately'
comparisons = []
for case, modes in base['cases'].items():
    for mode, before in modes.items():
        after = final['cases'][case][mode]
        assert before['source_sha256'] == after['source_sha256']
        for run_id, baseline_run in before['runs'].items():
            candidate_run = after['runs'][run_id]
            old, new = baseline_run['memory'], candidate_run['memory']
            comparisons.append({'case': case, 'mode': mode, 'source_sha256': before['source_sha256'],
                'baseline_compiler_sha256': before['compiler_sha256'], 'candidate_compiler_sha256': SHA,
                'metrics': {key: {'C0': old[key], 'Support7': new[key]} for key in ('allocs','reallocs','alloc_bytes','peak_live_bytes','live_bytes_at_exit')},
                'all_memory_counters_equal': old == new,
                'selected_metrics_equal': all(old[key] == new[key] for key in ('allocs','reallocs','alloc_bytes','peak_live_bytes','live_bytes_at_exit'))})
report['source_matched_C0_counter_comparison'] = comparisons
report['public_functions'] = final['inventory']['public_functions']
report['public_types'] = final['inventory']['public_types']
report['uncovered_functions'] = final['inventory']['uncovered_functions']
(HERE / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({name: row['summary'] for name, row in report['suites'].items()}, indent=2))
