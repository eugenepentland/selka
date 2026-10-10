#!/usr/bin/env python3
"""Retain compact checked qualification evidence; append additional build runs."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def keys(row):
    return {test['name']: test.get('cache', {}).get('key') for test in row['report']['tests']}


def outcomes(row):
    return {test['name']: ('passed' if test['status'] == 'cached' else test['status'],
                           test.get('reason', ''), test.get('at', ''))
            for test in row['report']['tests']}


def pair(actual, forced, raw):
    a = (raw / (actual['label'] + '.stderr.txt')).read_bytes()
    b = (raw / (forced['label'] + '.stderr.txt')).read_bytes()
    result = {'keys_equal': keys(actual) == keys(forced),
              'outcomes_equal': outcomes(actual) == outcomes(forced),
              'warnings_bytes_equal': a == b}
    assert all(result.values()), (actual['label'], result)
    return result


def paired_group(rows, raw):
    indexed = {row['label']: row for row in rows}
    checks = []
    for row in rows:
        if row['label'].endswith('-forced'):
            actual = indexed[row['label'][:-len('-forced')]]
            checks.append(pair(actual, row, raw))
    return {'pairs': len(checks), 'keys_equal': all(x['keys_equal'] for x in checks),
            'outcomes_equal': all(x['outcomes_equal'] for x in checks),
            'warnings_bytes_equal': all(x['warnings_bytes_equal'] for x in checks)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--qualification', type=Path, required=True)
    parser.add_argument('--admission', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).with_name('qualification-summary.json'))
    args = parser.parse_args()
    directory = args.qualification.resolve()
    report_path = directory / 'results.json'
    report = read(report_path)
    admission_path = args.admission.resolve() / 'results.json'
    admission = read(admission_path)
    assert 'completed_utc' in report and admission['wrapper_exit'] == 0
    private = {row['label']: row for row in report['private_selected']}
    private_checks = pair(private['private'], private['private-forced'], directory / 'private-selected/raw')
    cold_keys, edited_keys = keys(private['cold']), keys(private['private'])
    unchanged = sorted(name for name, key in cold_keys.items() if key == edited_keys[name])
    warning_bytes = [(directory / 'warnings/raw' / (row['label'] + '.stderr.txt')).read_bytes()
                     for row in report['warnings']]
    assert warning_bytes and all(b == warning_bytes[0] for b in warning_bytes)
    assert warning_bytes[0].count(b'warning[W_NOALLOC_ALLOCATES]') == 1
    concurrent = {}
    for name, run in report['concurrent_edit'].items():
        checks = pair(run['current'], run['forced'], directory / ('concurrent-' + name) / 'raw')
        assert run['exit'] == 1 and 'SourceChanged' in run['diagnostic'] and not run['success_publication']
        concurrent[name] = {'interrupted_exit': run['exit'], 'diagnostic': run['diagnostic'].strip(),
                            'success_publication': run['success_publication'],
                            'current_counts': run['current']['counts'], 'forced_counts': run['forced']['counts'],
                            'agreement': checks}
    all_rows = report['records'] + report['private_selected'] + report['warnings']
    for run in report['concurrent_edit'].values():
        all_rows += [run['current'], run['forced']]
    counts = Counter()
    for row in all_rows:
        counts.update(row['counts'])
    selected = private['private']
    item = {'evidence': str(report_path), 'evidence_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
            'compiler': report['compiler'], 'started_utc': report['started_utc'],
            'completed_utc': report['completed_utc'], 'planner_mode': report['planner_mode'],
            'compression': report['compression'], 'baseline': report['baseline'], 'oracle_env': report['oracle_env'],
            'invocations': {'main': len(report['records']), 'private_selected': len(report['private_selected']),
                            'warnings': len(report['warnings']), 'concurrent': 3 * len(concurrent),
                            'total': len(all_rows) + len(concurrent)},
            'test_verdict_counts_across_reported_invocations': dict(counts),
            'main_agreement': paired_group(report['records'], directory / 'raw'),
            'private_selected': {'counts': selected['counts'], 'unchanged_key_tests': unchanged,
                                 'agreement': private_checks, 'work': selected['work'],
                                 'noop_counts': private['noop']['counts'], 'noop_work': private['noop']['work']},
            'corruption': dict(report['corruption'],
                               cases={row['label']: row['counts'] for row in report['records']
                                      if row['label'] in ['corrupt-metadata', 'evicted-metadata']}),
            'warnings': {'agreement': paired_group(report['warnings'], directory / 'warnings/raw'),
                         'all_replays_bytes_equal': True, 'bytes_per_invocation': len(warning_bytes[0]),
                         'sha256': hashlib.sha256(warning_bytes[0]).hexdigest(), 'allocation_warning_count': 1},
            'concurrent_edit': concurrent,
            'admission': {'evidence': str(admission_path),
                          **{k: admission[k] for k in ['kind', 'queue_s', 'held_s', 'command_wall_s', 'wrapper_exit']},
                          'command_metrics': admission['completion']['metrics'], 'method': admission['method']}}
    output = read(args.output) if args.output.exists() else {'runs': {}}
    output['runs'][args.label] = item
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({'label': args.label, 'invocations': item['invocations'], 'output': str(args.output)}))


if __name__ == '__main__':
    main()
