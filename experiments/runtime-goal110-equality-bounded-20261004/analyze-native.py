#!/usr/bin/env python3
"""Verify retained streams and summarize the exploratory paired native screen."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import statistics


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def percentile(values, fraction):
    position = fraction * (len(values) - 1)
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (position - lower) * (values[upper] - values[lower])


def paired_interval(samples):
    pairs = [(sample['results']['before']['ns_per_call'],
              sample['results']['after']['ns_per_call']) for sample in samples]
    ratios = [statistics.median(pairs[i][1] for i in draw)
              / statistics.median(pairs[i][0] for i in draw)
              for draw in itertools.product(range(len(pairs)), repeat=len(pairs))]
    ratios.sort()
    return [percentile(ratios, 0.025), percentile(ratios, 0.975)]


def verify_result(result, row, count, binaries):
    assert result['exit_status'] == 0 and result['stderr'] == ''
    expected = count if row['distribution'] == 'equal' else 0
    assert result['checksum'] == result['expected_checksum'] == expected
    assert result['stdout'] == f"{expected} {result['elapsed_ns']}\n"
    assert result['elapsed_ns'] > 0
    assert result['ns_per_call'] == result['elapsed_ns'] / count
    arm = next(arm for arm, path in binaries.items() if path == result['command'][3])
    mode = ('equal', 'first', 'middle', 'last').index(row['distribution'])
    assert result['command'] == ['taskset', '-c', '2', binaries[arm], str(row['length']),
                                 str(mode), str(int(row['views'])), str(int(row['unicode'])), str(count)]


def verify(report):
    assert report['status'] == 'complete' and report['rounds'] == 5 and report['warmups'] == 1
    assert report['binary_hashes_before'] == report['binary_hashes_after']
    for arm, path in report['binaries'].items():
        assert digest(path) == report['binary_hashes_before'][arm]
    expected = {(length, mode, view, wide) for length in (17, 32, 33, 64)
                for mode in ('equal', 'first', 'middle', 'last')
                for view, wide in ((False, False), (True, False), (False, True), (True, True))}
    expected |= {(length, mode, view, wide) for length in (65, 128, 256, 4096)
                 for mode in ('equal', 'middle') for view, wide in ((False, False), (True, True))}
    actual = {(row['length'], row['distribution'], row['views'], row['unicode']) for row in report['rows']}
    assert expected == actual and len(report['rows']) == 80
    counts = {'pilots': 0, 'warmups': 0, 'measured': 0}
    for row in report['rows']:
        assert [sample['round'] for sample in row['samples']] == list(range(-1, 5))
        for pilot in row['pilots']:
            assert set(pilot['results']) == {'before', 'after'}
            for result in pilot['results'].values():
                verify_result(result, row, pilot['iterations'], report['binaries'])
                counts['pilots'] += 1
        for sample in row['samples']:
            assert set(sample['results']) == set(sample['arm_order']) == {'before', 'after'}
            for result in sample['results'].values():
                verify_result(result, row, row['iterations'], report['binaries'])
                counts['warmups' if sample['round'] < 0 else 'measured'] += 1
        measured = [sample for sample in row['samples'] if sample['round'] >= 0]
        medians = {arm: statistics.median(sample['results'][arm]['ns_per_call'] for sample in measured)
                   for arm in ('before', 'after')}
        assert row['medians_ns_per_call'] == medians
        assert row['after_before_ratio'] == medians['after'] / medians['before']
    return counts


def summary(rows):
    ratios = [row['after_before_ratio'] for row in rows]
    return {'rows': len(rows), 'ratio_min': min(ratios), 'ratio_max': max(ratios),
            'geometric_mean_ratio': math.exp(statistics.mean(map(math.log, ratios))),
            'point_estimate_improved': sum(ratio < 1 for ratio in ratios),
            'pointwise_interval_below_one': sum(row['paired_bootstrap95'][1] < 1 for row in rows),
            'pointwise_interval_above_one': sum(row['paired_bootstrap95'][0] > 1 for row in rows)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    counts = verify(report)
    elapsed = [result['elapsed_ns'] for row in report['rows'] for sample in row['samples']
               if sample['round'] >= 0 for result in sample['results'].values()]
    rows = []
    for row in report['rows']:
        measured = [sample for sample in row['samples'] if sample['round'] >= 0]
        rows.append({key: row[key] for key in ('length', 'distribution', 'views', 'unicode',
                                               'medians_ns_per_call', 'after_before_ratio')}
                    | {'paired_bootstrap95': paired_interval(measured),
                       'round_ratios': [sample['results']['after']['ns_per_call']
                                        / sample['results']['before']['ns_per_call'] for sample in measured]})
    out = {'kind': 'exploratory native screen analysis; no guest acceptance',
           'raw_report': {'path': str(args.report.resolve()), 'sha256': digest(args.report)},
           'session_id': report['session_id'], 'source_revision': report['source_revision'],
           'checks': counts, 'rows': rows,
           'calibration': {'nominal_target_ns': 30000000, 'iteration_cap': 10000000,
                           'minimum_measured_ns': min(elapsed),
                           'samples_below_nominal_target': sum(value < 30000000 for value in elapsed)},
           'interval_method': 'Exact 5^5 paired empirical bootstrap draws; ratio of arm medians; pointwise 95% percentile interval.',
           'limitations': ['Five rounds do not establish guest or goal confirmation.',
                          'Intervals do not cover between-session/systematic noise or multiple-comparison selection.',
                          'Native LLVM/defaultnative LTO differs from earlier portable GCC/noLTO scalar diagnostics.',
                          'The 10M-iteration cap stops some approximately2ns rows near20ms, below the nominal30ms calibration target.'],
           'by_length': {str(length): summary([row for row in rows if row['length'] == length])
                         for length in (17, 32, 33, 64, 65, 128, 256, 4096)},
           'affected_by_representation': {f"{'view' if view else 'owned'}_{'UTF8' if wide else 'ASCII'}":
                                           summary([row for row in rows if row['length'] <= 64
                                                    and row['views'] == view and row['unicode'] == wide])
                                         for view, wide in ((False, False), (True, False), (False, True), (True, True))},
           'affected_by_distribution': {mode: summary([row for row in rows if row['length'] <= 64
                                                      and row['distribution'] == mode])
                                        for mode in ('equal', 'first', 'middle', 'last')}}
    args.output.write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps({key: out[key] for key in ('checks', 'by_length', 'affected_by_representation',
                                               'affected_by_distribution')}, indent=2))


if __name__ == '__main__':
    main()
