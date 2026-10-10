#!/usr/bin/env python3
"""Retain compact paired measurements and work counts from completed matrices."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import statistics

import qualify


def flatten(value, prefix=''):
    result = {}
    for key, item in value.items():
        name = prefix + key
        if isinstance(item, dict):
            result.update(flatten(item, name + '.'))
        elif isinstance(item, (int, float)):
            result[name] = item
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('matrices', type=Path, nargs='+')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'method': 'Arrays preserve sample order; sample zero includes first discovery-scope transitions. '
                        'CPU is process-tree user+system; RSS is maximum individual process, not simultaneous tree sum. '
                        'Per-group work counters are summed once per scope; wall intervals may overlap.',
              'inputs': {}, 'fixtures': {}, 'groups': {}, 'invocations': 0}
    groups = defaultdict(list)
    for matrix in args.matrices:
        path = matrix / 'results.json'
        data = json.loads(path.read_text())
        assert data.get('completed_utc'), str(path)
        report['inputs'][matrix.name] = {key: data[key] for key in
                                       ['started_utc', 'completed_utc', 'execution_context']}
        report['inputs'][matrix.name].update(sha256=qualify.digest(path), invocations=len(data['records']))
        report['inputs'][matrix.name]['compilers'] = data.get('compilers', data.get('inputs'))
        report['fixtures'].update(data.get('fixtures', {}))
        report['invocations'] += len(data['records'])
        for row in data['records']:
            groups[f"{row['fixture']}/{row['variant']}/{row['phase']}"].append(row)
    for name, rows in sorted(groups.items()):
        rows.sort(key=lambda row: row['sample'])
        metrics = {key: [row[key] for row in rows] for key in
                   ['wall_s', 'peak_rss_kb', 'new_native_objects', 'new_guest_unit_objects', 'new_runtime_objects']}
        metrics['cpu_s'] = [row['user_s'] + row['system_s'] for row in rows]
        metrics['retained_logical_bytes'] = [row['retained_cache']['logical_bytes'] for row in rows]
        metrics['retained_allocated_bytes'] = [row['retained_cache']['allocated_bytes'] for row in rows]
        metrics['retained_files'] = [row['retained_cache']['files'] for row in rows]
        work = []
        for row in rows:
            total = defaultdict(int)
            for scope in row['work'].values():
                for key, value in flatten(scope).items():
                    total[key] += value
            work.append(dict(total))
        report['groups'][name] = {'samples': len(rows), 'metrics': metrics,
                                 'median': {key: statistics.median(values) for key, values in metrics.items()},
                                 'counts': [row['counts'] for row in rows],
                                 'work_scopes': [len(row['work']) for row in rows],
                                 'work': {key: [row.get(key, 0) for row in work]
                                          for key in sorted({key for row in work for key in row})}}
    encoded = json.dumps(report, indent=2)
    # Keep short numeric sample arrays on one line for review.
    encoded = re.sub(r'\[\n(?:[ \t]+-?[0-9][0-9.eE+-]*,?\n)+[ \t]*\]',
                     lambda match: json.dumps(json.loads(match.group())), encoded)
    args.output.write_text(encoded + '\n')


if __name__ == '__main__':
    main()
