#!/usr/bin/env python3
"""Replay108 placement outcomes and pointwise paired bootstrap intervals."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('raw', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
raw = json.loads(args.raw.read_text())
assert raw['status'] == 'complete' and raw['rounds'] == 15 and raw['warmups'] == 3 and len(raw['rows']) == 2
report = {'status': 'replayed', 'outcomes': 0, 'rows': [], 'session_id': raw['session_id'],
          'raw_path': str(args.raw.resolve()), 'raw_sha256': hashlib.sha256(args.raw.read_bytes()).hexdigest(),
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'method': 'Ratio of medians, resampling the same15paired round indices;20000 deterministic draws, seed case/profile/numerator/denominator;pointwise95%percentiles with linear interpolation.',
          'limitations': ['No multiplicity or systematic host-noise coverage.',
                          'Placement counterfactual also moves later text; no unique caller-address causal claim.',
                          'Diagnostic-only, not goal acceptance or production adoption.']}
for row in raw['rows']:
    samples = row['samples']
    plan = row['plan']
    key = plan['case'] + '/' + plan['profile']
    keys = {(sample['arm'], sample['round']) for sample in samples}
    assert len(keys) == len(samples) == 54
    assert keys == {(arm, index) for arm in ('g4', 'annotation', 'fill32') for index in range(-3, 15)}
    for sample in samples:
        match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', sample['stdout'])
        assert sample['status'] == sample['exit_status'] == 0 and sample['stderr'] == '' and match
        assert int(match[1]) == sample['checksum'] == plan['expected']
        assert int(match[2]) == sample['kernel_ns'] > 0 and sample['host_before'] and sample['host_after']
        report['outcomes'] += 1
    values = {arm: [next(sample['kernel_ns'] / plan['iterations'] for sample in samples
                         if sample['arm'] == arm and sample['round'] == index) for index in range(15)]
              for arm in ('g4', 'annotation', 'fill32')}
    medians = {arm: statistics.median(numbers) for arm, numbers in values.items()}
    assert medians == row['medians_ns_per_op']
    result = {'case': plan['case'], 'profile': plan['profile'], 'medians_ns_per_op': medians, 'comparisons': {}}
    for numerator, denominator in (('annotation', 'g4'), ('fill32', 'annotation'), ('fill32', 'g4')):
        name = numerator + '/' + denominator
        seed = key + '/' + name
        rng = random.Random(seed)
        draws = [[rng.randrange(15) for _ in range(15)] for _ in range(20000)]
        ratios = sorted(statistics.median(values[numerator][index] for index in draw) /
                        statistics.median(values[denominator][index] for index in draw) for draw in draws)
        bounds = []
        for percentile in (0.025, 0.975):
            position = percentile * (len(ratios) - 1)
            lower = int(position)
            bounds.append(ratios[lower] + (position - lower) * (ratios[lower + 1] - ratios[lower]))
        ratio = medians[numerator] / medians[denominator]
        assert ratio == row['ratios'][name]
        result['comparisons'][name] = {'ratio': ratio, 'paired_bootstrap95': bounds, 'seed': seed}
    report['rows'].append(result)
assert report['outcomes'] == 108
args.output.write_text(json.dumps(report, indent=2) + '\n')
for row in report['rows']:
    print(row['case'], row['profile'], row['comparisons'])
print('PASS108 complete outcomes')
