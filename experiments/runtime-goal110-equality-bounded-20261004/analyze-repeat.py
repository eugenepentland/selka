#!/usr/bin/env python3
"""Replay the independent two-row guest repeat; no goal acceptance analysis."""
import argparse
import importlib.util
import json
from pathlib import Path
import statistics

spec = importlib.util.spec_from_file_location('batch_analysis', Path(__file__).with_name('analyze-batch.py'))
batch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(batch)
digest, interval = batch.digest, batch.interval


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    report = json.loads(args.raw.read_text())
    assert report['status'] == 'complete'
    assert report['rounds'] == 15 and report['warmups'] == 3
    assert len(report['rows']) == 2
    rows, outcomes = [], 0
    for row in report['rows']:
        plan, samples = row['plan'], row['samples']
        assert (plan['case'], plan['profile']) in (
            ('string_equal', 'small'), ('string_search', 'large'))
        keys = {(sample['round'], sample['arm']) for sample in samples}
        assert keys == {(index, arm) for index in range(-3, 15)
                        for arm in ('before-llvm', 'after-llvm', 'before-qbe', 'after-qbe')}
        assert len(samples) == len(keys)
        for sample in samples:
            assert sample['exit_status'] == 0 and sample['checksum'] == plan['expected']
            assert sample['kernel_ns'] > 0
            assert sample['host_before'] and sample['host_after']
            outcomes += 1
        for backend in ('llvm', 'qbe'):
            before, after = ([next(sample['kernel_ns'] / plan['iterations'] for sample in samples
                                  if sample['round'] == index and sample['arm'] == arm + '-' + backend)
                              for index in range(15)] for arm in ('before', 'after'))
            ratio = statistics.median(after) / statistics.median(before)
            assert ratio == row['after_before_ratios'][backend]
            key = f"{plan['case']}/{plan['profile']}/{backend}"
            rows.append({'case': plan['case'], 'profile': plan['profile'], 'backend': backend,
                         'before_ns_per_op': statistics.median(before),
                         'after_ns_per_op': statistics.median(after), 'after_before_ratio': ratio,
                         'paired_bootstrap95': interval(before, after, key)})
    output = {'status': 'replayed', 'raw': {'path': str(args.raw.resolve()),
                                         'sha256': digest(args.raw)},
              'session_id': report['session_id'], 'outcomes': outcomes, 'rows': rows,
              'interval_method': 'Paired ratio of arm medians;20000 deterministic draws;95%pointwise percentiles.',
              'limitations': ['Pointwise15round repeat excludes systematic/between-session noise and multiplicity.',
                              'Initial5round search+5.64% remains retained; repeat supports a smaller positive cost.',
                              'Guest success/checksum/clock retained; complete process streams unknown.',
                              'No goal confirmation or production adoption claimed.'],
              'analysis_script': {'path': str(Path(__file__).resolve()),
                                  'sha256': digest(Path(__file__))}}
    assert outcomes == 144
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print('PASS144 guest outcomes; independent paired intervals retained')
    for row in rows:
        print(row['case'], row['profile'], row['backend'], row['after_before_ratio'],
              row['paired_bootstrap95'])


if __name__ == '__main__':
    main()
