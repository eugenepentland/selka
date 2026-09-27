#!/usr/bin/env python3
"""Recompute full-corpus evidence from raw observations without executing guests."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent


def read(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def events(stderr):
    result = []
    for line in stderr.splitlines():
        fields = line.split(',')
        if len(fields) < 5 or 'cpu_atom' in fields[2]:
            continue
        metric = 'instructions' if 'instructions' in fields[2] else 'cycles' if 'cycles' in fields[2] else None
        if metric is None or not fields[0].strip().isdigit():
            continue
        result.append({'metric': metric, 'event': fields[2], 'count': int(fields[0]),
                       'enabled_percent': float(fields[4]), 'run_time': fields[3]})
    return result


def perf(sample):
    assert sample['status'] == 0 and sample['ok']
    actual = events(sample['stderr'])
    assert actual == sample['events']
    instructions = [event for event in actual if event['metric'] == 'instructions']
    assert len(instructions) == 1
    assert instructions[0]['enabled_percent'] >= 99.9
    assert sample['instructions'] == instructions[0]['count'] > 0


def manifests(result, baseline):
    archived = read(HERE / 'build-manifests.json.gz')
    expected = {side + '/' + key for side, data in [('rc', result), ('gc', baseline)] for key in data['builds']}
    assert set(archived) == expected
    for name, entry in archived.items():
        side, key = name.split('/', 1)
        build = (result if side == 'rc' else baseline)['builds'][key]
        assert entry['binary_sha256'] == build['sha256']
        assert hashlib.sha256(entry['manifest_text'].encode()).hexdigest() == entry['manifest_sha256']
        manifest = json.loads(entry['manifest_text'])
        backend = 'llvm' if '.llvm' in key else 'qbe'
        assert manifest['backend'] == backend
        if backend == 'llvm':
            assert manifest['optimization'] == '3' and manifest['lto'] and not manifest['thin_lto']
        if side == 'rc':
            assert '--rc-runtime' in build['cmd'] and result['identity']['compiler'] in build['cmd']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, default=HERE / 'results.json.gz')
    parser.add_argument('--baseline', type=Path, default=HERE / 'gc-builds.json.gz')
    parser.add_argument('--calibration', type=Path, default=HERE / 'parser-calibration.json')
    parser.add_argument('--partial', action='store_true', help='audit existing rows; never claim corpus completion')
    args = parser.parse_args()
    result, baseline, calibration = (read(path) for path in (args.results, args.baseline, args.calibration))
    identity = result['identity']
    driver_hash = hashlib.sha256((HERE / 'run.py').read_bytes()).hexdigest()
    assert identity['driver_sha256'] == calibration['driver_sha256'] == driver_hash
    baseline_bytes = args.baseline.read_bytes()
    if args.baseline.suffix == '.gz':
        baseline_bytes = gzip.decompress(baseline_bytes)
    assert hashlib.sha256(baseline_bytes).hexdigest() == identity['baseline_manifest_sha256']
    assert identity['inputs'] == baseline['inputs']
    assert identity['programs'] == baseline['programs']
    programs = identity['programs']
    expected = {program['id'] + '|' + backend for program in programs for backend in ('qbe', 'llvm')}
    assert len(programs) == 43 and len(expected) == 86
    assert len([program for program in programs if program['id'].startswith('parity/')]) == 27
    assert len([program for program in programs if program['id'].startswith('schematic/')]) == 3
    build_keys = {program['build_key'] + '.' + backend for program in programs for backend in ('qbe', 'llvm')}
    assert len(build_keys) == 58 and set(result['builds']) == set(baseline['builds']) == build_keys
    assert all(build['ok'] for build in result['builds'].values())
    assert all(build['ok'] for build in baseline['builds'].values())
    assert not result['failures']
    manifests(result, baseline)
    assert set(result['samples']) <= set(result['checks']) <= expected
    perf(calibration['sample'])
    for key, row in result['samples'].items():
        assert row['checks'] == result['checks'][key]
        assert set(row['checks']) == set(row['observations']) == set(row['runs']) == {'gc', 'rc'}
        assert all(check['ok'] and check['status'] == 0 for check in row['checks'].values())
        assert row['instruction_ratio'] == row['medians']['rc']['instructions'] / row['medians']['gc']['instructions']
        for side, observed in row['observations'].items():
            run = row['runs'][side]
            assert all(name.startswith('MYLANG_') for name in run['env'])
            assert len(observed['perf']) == len(observed['rss']) == 3
            for sample in observed['perf']:
                perf(sample)
                assert sample['command'][-len(run['argv']):] == run['argv']
            for sample in observed['rss']:
                assert sample['ok'] and sample['status'] == 0
                values = [line.split('=', 1)[1] for line in sample['stderr'].splitlines() if line.startswith('D9_RSS_KB=')]
                assert len(values) == 1 and sample['peak_rss_kb'] == int(values[0]) > 0
                assert sample['command'][-len(run['argv']):] == run['argv']
            assert row['medians'][side]['instructions'] == statistics.median(sample['instructions'] for sample in observed['perf'])
            assert row['medians'][side]['rss_kb'] == statistics.median(sample['peak_rss_kb'] for sample in observed['rss'])
    if args.partial:
        print(f'PARTIAL AUDIT: {len(result["samples"])} / 86 rows internally consistent; no acceptance claim')
        return
    assert result['complete'] and set(result['samples']) == set(result['checks']) == expected
    summary = {}
    for backend in ('qbe', 'llvm'):
        rows = [row for key, row in result['samples'].items() if key.endswith('|' + backend)]
        geometric = math.exp(statistics.mean(math.log(row['instruction_ratio']) for row in rows))
        maximum = max(row['instruction_ratio'] for row in rows)
        memory = {side: statistics.median(row['medians'][side]['rss_kb'] for row in rows) for side in ('gc', 'rc')}
        summary[backend] = {'complete': True, 'programs': 43, 'instruction_geomean': geometric,
                            'maximum_instruction_ratio': maximum, 'median_peak_rss_kb': memory,
                            'performance_pass': geometric <= 1.0 and maximum <= 1.3 and memory['rc'] < memory['gc']}
    assert summary == result['summary']
    assert result['performance_pass'] == all(row['performance_pass'] for row in summary.values())
    print(f'PASS: complete 86-row evidence; performance acceptance = {result["performance_pass"]}')


if __name__ == '__main__':
    main()
