#!/usr/bin/env python3
"""Validate matched hot-path measurements before reporting paired reductions."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    parser.add_argument('--metric', choices=['wall_s', 'instructions'], required=True)
    parser.add_argument('--screen', action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise ValueError('refusing to overwrite analysis')
    doc = json.loads(args.receipt.read_text())
    work = Path(doc['manifest']['candidate_sources']['baseline']['path']).parent
    arms = {f'{name}-{backend}' for name in ('baseline', 'candidate') for backend in ('llvm', 'qbe')}
    if not args.screen:
        arms |= {'rust', 'go'}
    expected_cases = {f'{engine}/{p.stem}' for engine in ('vm', 'tree')
                      for p in (work / 'reference/benchmarks/lox/bench/scripts').glob('*.lox')}
    cases = {case['id']: case for case in doc['cases']}
    assert len(doc['cases']) == 26 and len(cases) == 26 and set(cases) == expected_cases
    assert set(doc['binary_sha256']) == arms
    assert all(doc['binary_sha256'][arm] == doc['manifest']['binary_sha256'][arm] for arm in arms)
    assert doc.get('verified_after') and doc['rounds'] == (1 if args.screen else 3)
    expected = {(case, arm, index) for case in cases for arm in arms for index in range(doc['rounds'])}
    actual = {(sample['case'], sample['arm'], sample['round']) for sample in doc['samples']}
    assert expected == actual and len(actual) == len(doc['samples'])
    assert doc['phase'] == ('counters' if args.metric == 'instructions' else 'time')
    for sample in doc['samples']:
        assert sample['status'] == 0 and sample['stderr'] == ''
        assert sample['stdout_sha256'] == sha(Path(cases[sample['case']]['expected']))
        if doc['phase'] == 'counters':
            for name in ('instructions', 'cycles', 'branches', 'branch-misses'):
                assert sample[name + '_running_pct'] == 100
    guards = json.loads((work / 'guards.json').read_text())
    for path, digest in guards.items():
        assert sha(Path(path)) == digest, path
    repo = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('paired',
        repo / 'experiments/lox-perf-improvements-20261002/analyze.py')
    paired = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paired)
    comparisons = {}
    for backend in ('llvm', 'qbe'):
        candidate = 'candidate-' + backend
        for control in ['baseline-' + backend] + ([] if args.screen else ['rust', 'go']):
            comparisons[candidate + '-over-' + control] = paired.compare(doc, control, candidate, args.metric)
    result = {'receipt': str(args.receipt.resolve()), 'receipt_sha256': sha(args.receipt),
              'coverage_verified': True, 'stable_guards_after': len(guards),
              'samples': len(actual), 'metric': args.metric, 'screen_only': args.screen,
              'comparisons': comparisons}
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, comparison in comparisons.items():
        print(name, {engine: round(value['reduction_pct'], 4)
                     for engine, value in comparison['engines'].items()})


if __name__ == '__main__':
    main()
