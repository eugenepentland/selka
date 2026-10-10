#!/usr/bin/env python3
"""Verify retained diagnostic evidence and summarize every measured observation."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics


def stats(values):
    middle = statistics.median(values)
    return dict(samples=len(values), median=middle, min=min(values), max=max(values),
                spread=(max(values) - min(values)) / middle if middle else None)


def correlation(left, right):
    if len(set(left)) == 1 or len(set(right)) == 1:
        return None
    return statistics.correlation(left, right)


def analyse(root):
    method = json.loads((root / 'method.json').read_text())
    raw = json.loads((root / 'observations.json').read_text())
    assert hashlib.sha256((root / 'runner.py').read_bytes()).hexdigest() == method['runner_sha256']
    assert len(raw) == len(method['conditions']) * (method['pairs'] + 1) * 2
    for row in raw:
        for name, expected in row['evidence'].items():
            assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected
    rows = [row for row in raw if not row['warmup']]
    conditions = []
    for name, layout in sorted({(r['name'], r['layout']) for r in rows}):
        cells = {arm: sorted([r for r in rows if r['name'] == name and r['layout'] == layout and r['arm'] == arm],
                             key=lambda r: r['round']) for arm in ('base', 'candidate')}
        for cell in cells.values():
            assert [r['round'] for r in cell] == list(range(1, method['pairs'] + 1))
        result = dict(name=name, layout=layout, arms={}, paired_ratios={})
        for arm, cell in cells.items():
            metrics = {key: stats([r['metrics'][key] for r in cell]) for key in cell[0]['metrics']}
            metrics['frequency_index'] = stats([r['metrics']['cycles'] / r['metrics']['ref-cycles'] for r in cell])
            metrics['perf_elapsed_minus_task_clock_ms'] = stats([r['metrics']['duration_time'] / 1e6 - r['metrics']['task-clock'] for r in cell])
            if cell[0]['internal_ns'] is not None:
                metrics['internal_ns'] = stats([r['internal_ns'] for r in cell])
            cycles = [r['metrics']['cycles'] for r in cell]
            result['arms'][arm] = dict(metrics=metrics, cycle_correlations={key: correlation(cycles, [r['metrics'][key] for r in cell])
                                                                         for key in cell[0]['metrics']})
        for key in ('cycles', 'ref-cycles', 'duration_time', 'task-clock'):
            result['paired_ratios'][key] = stats([b['metrics'][key] / a['metrics'][key] for a, b in zip(cells['base'], cells['candidate'])])
        if cells['base'][0]['internal_ns'] is not None:
            result['paired_ratios']['internal_ns'] = stats([b['internal_ns'] / a['internal_ns'] for a, b in zip(cells['base'], cells['candidate'])])
        conditions.append(result)
    siblings = []
    for part in method['siblings'].split(','):
        limits = [int(n) for n in part.split('-')]
        siblings.extend(range(limits[0], limits[-1] + 1))
    return dict(run=root.name, profile=method.get('profile', 'memory'), conditions=conditions,
                retained_executions=len(raw), measured_executions=len(rows), evidence_verified=True,
                max_sibling_busy_percent={str(cpu): max(r['cpu_busy_percent'][f'cpu{cpu}'] for r in rows)
                                          for cpu in siblings if cpu != method['cpu']},
                total_cpu_migrations=sum(r['metrics']['cpu-migrations'] for r in rows),
                total_major_faults=sum(r['metrics']['major-faults'] for r in rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('roots', nargs='+', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    options = parser.parse_args()
    result = dict(runs=[analyse(root) for root in options.roots],
                  scope='Exploratory, instrumented diagnostics; every post-warmup sample retained; no independent accuracy qualification.')
    options.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(f'Verified {sum(run["retained_executions"] for run in result["runs"])} executions and retained raw evidence.')


if __name__ == '__main__':
    main()
