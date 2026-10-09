#!/usr/bin/env python3
"""Render every alignment and the binding median ratio from R10 tax JSON."""
import gzip
import json
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
    lines += ['', '| cell | arm | K=4 | K=5 | K=6 | median |', '|---|---|---:|---:|---:|---:|']
    for key, row in data['rows'].items():
        for tag in data['tags'][1:]:
            ratios = []
            for batch in row['batches']:
                medians = batch['medians']
                metric = lambda v: v['elapsed_ns'] if isinstance(v, dict) else v
                ratios.append(metric(medians[tag]) / metric(medians['base']))
            assert len(ratios) == 3
            lines.append('| ' + key + ' | ' + tag + ' | ' + ' | '.join(f'{r:.5f}' for r in [*ratios, statistics.median(ratios)]) + ' |')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    print(render(Path(sys.argv[1])), end='')
