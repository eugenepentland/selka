#!/usr/bin/env python3
"""Verify complete Lox checkpoint coverage and report paired source/reference ratios."""
import argparse
import importlib.util
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    parser.add_argument('--candidate', default='final-sweep')
    parser.add_argument('--baseline', default='baseline')
    parser.add_argument('--metric', choices=['wall_s', 'instructions'], required=True)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('paired',
        repo / 'experiments/lox-perf-improvements-20261002/analyze.py')
    paired = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paired)
    doc = json.loads(args.receipt.read_text())
    if not doc.get('verified_after'):
        raise ValueError('measurement is incomplete')
    cases = {c['id'] for c in doc['cases']}
    if len(cases) != 26:
        raise ValueError('checkpoint needs all13 scripts on both engines')
    arms = set(doc['binary_sha256'])
    required = {f'{p}-{b}' for p in (args.baseline, args.candidate)
                for b in ('llvm', 'qbe')} | {'rust', 'go'}
    if arms != required or doc['rounds'] < 3:
        raise ValueError('checkpoint needs matched controls and three rounds')
    expected = {(c, a, r) for c in cases for a in arms for r in range(doc['rounds'])}
    actual = {(s['case'], s['arm'], s['round']) for s in doc['samples']}
    if actual != expected or len(actual) != len(doc['samples']):
        raise ValueError('missing or duplicate samples')
    for sample in doc['samples']:
        if sample['status'] != 0 or sample['stderr'] != '':
            raise ValueError('unexpected exit or diagnostic')
        if args.metric == 'instructions' and sample['instructions_running_pct'] != 100:
            raise ValueError('instruction PMU did not run continuously')
    comparisons = {}
    for backend in ('llvm', 'qbe'):
        candidate = f'{args.candidate}-{backend}'
        for control in (f'{args.baseline}-{backend}', 'rust', 'go'):
            key = f'{candidate}-over-{control}'
            comparisons[key] = paired.compare(doc, control, candidate, args.metric)
    result = {'receipt': str(args.receipt.resolve()), 'coverage_verified': True,
              'samples': len(actual), 'metric': args.metric, 'comparisons': comparisons}
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    for name, comparison in comparisons.items():
        print(name, {e: round(v['candidate_over_baseline'], 6)
                     for e, v in comparison['engines'].items()})


if __name__ == '__main__':
    main()
