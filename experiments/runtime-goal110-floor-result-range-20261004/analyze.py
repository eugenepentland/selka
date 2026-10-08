#!/usr/bin/env python3
"""Replay all paired streams and deterministic pointwise paired intervals."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import random
import re
import statistics


def quantile(values, fraction):
    position = fraction * (len(values) - 1)
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (position - lower) * (values[upper] - values[lower])


def interval(before, after, seed):
    size = len(before)
    rng = random.Random(seed)
    draws = (itertools.product(range(size), repeat=size) if size == 5 else
             ([rng.randrange(size) for _ in range(size)] for _ in range(20000)))
    ratios = sorted(statistics.median(after[index] for index in draw) /
                    statistics.median(before[index] for index in draw) for draw in draws)
    return [quantile(ratios, 0.025), quantile(ratios, 0.975)]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('initial', type=Path)
parser.add_argument('repeat', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
report = {'status': 'replayed', 'outcomes': 0, 'batches': [], 'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'method': 'Paired ratio of arm medians; exhaustive3125 draws for5rounds and deterministic20000 draws for15rounds;95%pointwise percentile intervals.',
          'limitations': ['Intervals exclude systematic host noise and multiplicity; Debug compiler host is exploratory.',
                          'Both initial and repeat raw streams and host snapshots retained; no production adoption or goal confirmation.']}
for path, rounds, warmups, expected_rows in ((args.initial, 5, 1, 12), (args.repeat, 15, 3, 2)):
    raw = json.loads(path.read_text())
    assert raw['status'] == 'complete' and raw['rounds'] == rounds and raw['warmups'] == warmups
    assert len(raw['rows']) == expected_rows
    batch = {'raw': {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
             'session_id': raw['session_id'], 'rows': []}
    for row in raw['rows']:
        plan, samples = row['plan'], row['samples']
        keys = {(sample['round'], sample['arm']) for sample in samples}
        assert len(keys) == len(samples)
        assert keys == {(index, label + '-' + backend) for index in range(-warmups, rounds)
                        for label in ('before', 'after') for backend in ('llvm', 'qbe')}
        for sample in samples:
            assert sample['status'] == sample['exit_status'] == 0 and sample['stderr'] == ''
            match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', sample['stdout'])
            assert match and int(match[1]) == sample['checksum'] == plan['expected']
            assert int(match[2]) == sample['kernel_ns'] > 0
            assert sample['host_before'] and sample['host_after']
            report['outcomes'] += 1
        for backend in ('llvm', 'qbe'):
            before, after = ([next(sample['kernel_ns'] / plan['iterations'] for sample in samples
                                  if sample['round'] == index and sample['arm'] == label + '-' + backend)
                              for index in range(rounds)] for label in ('before', 'after'))
            ratio = statistics.median(after) / statistics.median(before)
            assert ratio == row['after_before_ratios'][backend]
            key = plan['case'] + '/' + plan['profile'] + '/' + backend
            batch['rows'].append({'case': plan['case'], 'profile': plan['profile'], 'backend': backend,
                                  'before_ns_per_op': statistics.median(before), 'after_ns_per_op': statistics.median(after),
                                  'after_before_ratio': ratio, 'paired_bootstrap95': interval(before, after, key)})
    report['batches'].append(batch)
assert report['outcomes'] == 432
args.output.write_text(json.dumps(report, indent=2) + '\n')
for row in report['batches'][-1]['rows']:
    print(row['case'], row['profile'], row['backend'], row['after_before_ratio'], row['paired_bootstrap95'])
print('PASS432 complete paired outcomes')
