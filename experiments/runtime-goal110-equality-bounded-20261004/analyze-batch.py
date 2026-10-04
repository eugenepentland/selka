#!/usr/bin/env python3
"""Replay paired guest outcomes and the native control repeat; no goal analysis."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import random
import statistics


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def quantile(values, fraction):
    position = fraction * (len(values) - 1)
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (position - lower) * (values[upper] - values[lower])


def interval(before, after, seed):
    size = len(before)
    assert size == len(after) and size in (5, 15)
    rng = random.Random(seed)
    draws = (itertools.product(range(size), repeat=size) if size == 5 else
             ([rng.randrange(size) for _ in range(size)] for _ in range(20000)))
    ratios = sorted(statistics.median(after[i] for i in draw)
                    / statistics.median(before[i] for i in draw) for draw in draws)
    return [quantile(ratios, 0.025), quantile(ratios, 0.975)]


def native_rows(report):
    assert report['status'] == 'complete' and report['rounds'] == 15 and report['warmups'] == 3
    assert report['binary_hashes_before'] == report['binary_hashes_after']
    assert len(report['rows']) == 8
    rows, outcomes = [], 0
    for row in report['rows']:
        assert [sample['round'] for sample in row['samples']] == list(range(-3, 15))
        for sample, count in [(pilot, pilot['iterations']) for pilot in row['pilots']] + [
                (sample, row['iterations']) for sample in row['samples']]:
            assert set(sample['results']) == {'before', 'after'}
            for result in sample['results'].values():
                expected = count if row['distribution'] == 'equal' else 0
                assert result['exit_status'] == 0 and result['stderr'] == ''
                assert result['checksum'] == result['expected_checksum'] == expected
                assert result['stdout'] == f"{expected} {result['elapsed_ns']}\n"
                assert result['ns_per_call'] == result['elapsed_ns'] / count
                outcomes += 1
        measured = [sample for sample in row['samples'] if sample['round'] >= 0]
        before, after = ([sample['results'][arm]['ns_per_call'] for sample in measured]
                         for arm in ('before', 'after'))
        assert statistics.median(after) / statistics.median(before) == row['after_before_ratio']
        key = f"{row['length']}/{row['distribution']}/{row['views']}/{row['unicode']}"
        rows.append({key: row[key] for key in ('length', 'distribution', 'views', 'unicode',
                                               'medians_ns_per_call', 'after_before_ratio')}
                    | {'paired_bootstrap95': interval(before, after, key)})
    return rows, outcomes


def guest_rows(report):
    assert report['status'] == 'complete' and report['rounds'] == 5 and report['warmups'] == 1
    rows, outcomes = [], 0
    for row in report['rows']:
        plan = row['plan']
        samples = row['samples']
        keys = {(sample['round'], sample['arm']) for sample in samples}
        assert keys == {(index, arm) for index in range(-1, 5)
                        for arm in ('before-llvm', 'after-llvm', 'before-qbe', 'after-qbe')}
        assert len(samples) == len(keys)
        for sample in samples:
            assert sample['exit_status'] == 0 and sample['checksum'] == plan['expected']
            assert sample['kernel_ns'] > 0
            outcomes += 1
        for backend in ('llvm', 'qbe'):
            before, after = ([next(sample['kernel_ns'] / plan['iterations'] for sample in samples
                                  if sample['round'] == index and sample['arm'] == arm + '-' + backend)
                              for index in range(5)] for arm in ('before', 'after'))
            ratio = statistics.median(after) / statistics.median(before)
            assert ratio == row['after_before_ratios'][backend]
            key = f"{plan['case']}/{plan['profile']}/{backend}"
            rows.append({'case': plan['case'], 'profile': plan['profile'], 'backend': backend,
                         'before_ns_per_op': statistics.median(before),
                         'after_ns_per_op': statistics.median(after), 'after_before_ratio': ratio,
                         'paired_bootstrap95': interval(before, after, key)})
    return rows, outcomes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('native', type=Path)
    parser.add_argument('guest', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    native, guest = (json.loads(path.read_text()) for path in (args.native, args.guest))
    native_result, native_count = native_rows(native)
    guest_result, guest_count = guest_rows(guest)
    output = {'status': 'replayed', 'kind': 'exploratory paired intervals; no acceptance analysis',
              'raw': {kind: {'path': str(path.resolve()), 'sha256': digest(path)}
                      for kind, path in (('native', args.native), ('guest', args.guest))},
              'native_session_id': native['session_id'], 'guest_session_id': guest['session_id'],
              'native_checked_calls': native_count, 'guest_checked_outcomes': guest_count,
              'native_rows': native_result, 'guest_rows': guest_result,
              'interval_method': 'Paired ratio of arm medians; exact5^5 draws for5rounds,20000 seeded draws for15rounds;95%pointwise percentiles.',
              'limitations': ['Pointwise intervals exclude between-session/systematic noise and multiple-comparison selection.',
                             'Standalone native helper timing does not establish generated guest or goal confirmation.',
                             'Guest helper validates success/clock/checksum but does not retain complete process streams.']}
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print('PASS', native_count, 'native calls;', guest_count, 'guest outcomes; paired intervals retained')
    for row in native_result:
        if row['length'] == 128:
            print('native', row['length'], row['distribution'], 'viewUTF8' if row['views'] else 'ownedASCII',
                  row['after_before_ratio'], row['paired_bootstrap95'])
    for row in guest_result:
        if row['case'] in ('string_equal', 'string_search'):
            print('guest', row['case'], row['profile'], row['backend'], row['after_before_ratio'], row['paired_bootstrap95'])


if __name__ == '__main__':
    main()
