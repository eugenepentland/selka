#!/usr/bin/env python3
"""Compare paired baseline/candidate samples saved by the Lox audit runner."""
import argparse
import json
import statistics
from pathlib import Path


def compare(doc, baseline, candidate, metric):
    samples = {}
    for sample in doc['samples']:
        if sample['arm'] in (baseline, candidate):
            samples.setdefault(sample['case'], {}).setdefault(sample['round'], {})[
                sample['arm']] = sample
    rows = {}
    for case, rounds in sorted(samples.items()):
        ratios = []
        for index, arms in sorted(rounds.items()):
            if set(arms) != {baseline, candidate}:
                raise ValueError(f'incomplete pair: {case}, round {index}')
            ratios.append(arms[candidate][metric] / arms[baseline][metric])
        median = statistics.median(ratios)
        rows[case] = {'candidate_over_baseline': median,
                      'reduction_pct': 100 * (1 - median),
                      'paired_ratios': ratios,
                      'spread_pct': 100 * (max(ratios) - min(ratios)) / median}
    if not rows:
        raise ValueError('no matching baseline/candidate samples')
    engines = {}
    for engine in ('vm', 'tree'):
        selected = [r['candidate_over_baseline'] for c, r in rows.items()
                    if c.startswith(engine + '/')]
        if selected:
            ratio = statistics.geometric_mean(selected)
            engines[engine] = {'cases': len(selected),
                               'candidate_over_baseline': ratio,
                               'reduction_pct': 100 * (1 - ratio)}
    return {'baseline': baseline, 'candidate': candidate, 'metric': metric,
            'engines': engines, 'rows': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--metric', choices=('wall_s', 'instructions', 'cycles',
                                           'branches', 'branch-misses', 'maxrss_kib'),
                        default='instructions')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    doc = json.loads(args.receipt.read_text())
    if not doc.get('verified_after'):
        raise ValueError('receipt did not complete post-run identity checks')
    report = compare(doc, args.baseline, args.candidate, args.metric)
    report['receipt'] = str(args.receipt.resolve())
    if args.out:
        args.out.write_text(json.dumps(report, indent=2) + '\n')
    for engine, value in report['engines'].items():
        print(f"{engine}: {value['reduction_pct']:+.2f}% {args.metric} reduction "
              f"over {value['cases']} cases")
    for case, value in report['rows'].items():
        print(f"{case}: {value['reduction_pct']:+.2f}%")


if __name__ == '__main__':
    main()
