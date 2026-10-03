#!/usr/bin/env python3
"""Check the complete source factorial before reporting paired Lox ratios."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


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
    arms = {f'{name}-{backend}' for name in ['baseline', 'ast', 'constant', 'combined']
            for backend in ['llvm', 'qbe']}
    if not args.screen:
        arms |= {'rust', 'go'}
    cases = {case['id']: case for case in doc['cases']}
    work = Path(doc['manifest']['candidate_sources']['baseline']['path']).parent
    scripts = work / 'reference/benchmarks/lox/bench/scripts'
    expected_cases = {f'{engine}/{script.stem}' for engine in ['vm', 'tree']
                      for script in scripts.glob('*.lox')}
    if (len(cases) != 26 or set(cases) != expected_cases or
            set(doc['binary_sha256']) != arms):
        raise ValueError('need all13 workloads and exact factorial arms')
    if not doc.get('verified_after') or doc['rounds'] < (1 if args.screen else 3):
        raise ValueError('incomplete measurement or insufficient rounds')
    expected = {(case, arm, index) for case in cases for arm in arms
                for index in range(doc['rounds'])}
    actual = {(sample['case'], sample['arm'], sample['round']) for sample in doc['samples']}
    if expected != actual or len(actual) != len(doc['samples']):
        raise ValueError('missing or duplicate cells')
    phase = 'counters' if args.metric == 'instructions' else 'time'
    if doc['phase'] != phase:
        raise ValueError('metric does not match measurement phase')
    for sample in doc['samples']:
        expected_output = Path(cases[sample['case']]['expected']).read_bytes()
        if (sample['status'] != 0 or sample['stderr'] != '' or
                sample['stdout_sha256'] != hashlib.sha256(expected_output).hexdigest()):
            raise ValueError('unexpected output, exit or diagnostic')
        if phase == 'counters':
            for counter in ['instructions', 'cycles', 'branches', 'branch-misses']:
                if sample[counter + '_running_pct'] != 100:
                    raise ValueError('PMU did not run continuously')
    repo = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('paired',
        repo / 'experiments/lox-perf-improvements-20261002/analyze.py')
    paired = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paired)
    comparisons = {}
    for name in ['ast', 'constant', 'combined']:
        for backend in ['llvm', 'qbe']:
            candidate = f'{name}-{backend}'
            controls = [f'baseline-{backend}'] + ([] if args.screen else ['rust', 'go'])
            for control in controls:
                comparisons[f'{candidate}-over-{control}'] = paired.compare(
                    doc, control, candidate, args.metric)
    result = {'receipt': str(args.receipt.resolve()),
              'receipt_sha256': hashlib.sha256(args.receipt.read_bytes()).hexdigest(),
              'coverage_verified': True, 'samples': len(actual), 'metric': args.metric,
              'screen_only': args.screen, 'comparisons': comparisons}
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, comparison in comparisons.items():
        print(name, {engine: round(value['reduction_pct'], 4)
                     for engine, value in comparison['engines'].items()})


if __name__ == '__main__':
    main()
