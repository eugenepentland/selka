#!/usr/bin/env python3
"""Render every alignment and the binding median ratio from R10 tax JSON."""
import gzip
import json
import math
from pathlib import Path
import statistics
import sys


def render(path):
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt') as handle:
        data = json.load(handle)
    assert data['valid']
    lines = [f"Source: `{data['source']}`. CPU 10 under `cpu10.lock`; K=4,5,6 in order.", '',
             '| corpus / arm | cells | geomean | cells >1.03 | verdict |',
             '|---|---:|---:|---:|---|']
    for tag in data['tags'][1:]:
        summary = data['summary'][tag]
        lines.append(f"| {data.get('corpus', 'rows')} / {tag} | {len(data['rows'])} | {summary['geomean']:.6f} | {len(summary['rows_over_1_03'])} | {'PASS' if summary['pass'] else 'MISS'} |")
        if data.get('corpus') == 'lox':
            for engine in ('tree', 'vm'):
                ratios = {key: ratio for key, ratio in summary['ratios'].items() if key.endswith('/' + engine)}
                gm = math.exp(statistics.mean(math.log(r) for r in ratios.values()))
                misses = sum(r > 1.03 for r in ratios.values())
                verdict = 'PASS' if gm <= 1.010 and not misses else 'MISS'
                lines.append(f"| Lox {engine} / {tag} | {len(ratios)} | {gm:.10f} | {misses} | {verdict} |")
    lines += ['', f"[Raw samples, wall times, load and hashes]({path.name}). Times below are milliseconds; ratios use each batch's paired medians.", '',
              '| cell | arm | K4 base → arm | K4 ratio | K5 base → arm | K5 ratio | K6 base → arm | K6 ratio | median ratio |',
              '|---|---|---:|---:|---:|---:|---:|---:|---:|']
    for key, row in data['rows'].items():
        for tag in data['tags'][1:]:
            ratios, columns = [], []
            for batch in row['batches']:
                medians = batch['medians']
                metric = lambda v: v['elapsed_ns'] if isinstance(v, dict) else v
                ratios.append(metric(medians[tag]) / metric(medians['base']))
                scale = 1e-6 if isinstance(medians[tag], dict) else 1000
                columns.extend([f"{metric(medians['base']) * scale:.4f} → {metric(medians[tag]) * scale:.4f}", f"{ratios[-1]:.5f}"])
            assert len(ratios) == 3
            lines.append('| ' + key + ' | ' + tag + ' | ' + ' | '.join([*columns, f'{statistics.median(ratios):.5f}']) + ' |')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    print(render(Path(sys.argv[1])), end='')
