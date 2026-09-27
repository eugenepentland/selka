#!/usr/bin/env python3
"""Verify archived diagnostic counts, identities and serialization-only resume."""
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent


def read(name):
    path = HERE / name
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes())


def main():
    result = read('results.json.gz')
    initial = read('partial-initial.json.gz')
    baseline = read('gc-builds.json.gz')
    summary = read('summary.json')
    assert result['diagnostic_only'] and result['complete_diagnostic']
    assert not result['failures'] and len(result['samples']) == len(result['checks']) == 60
    assert len(result['builds']) == 56 and all(b['ok'] for b in result['builds'].values())
    assert result['identity']['inputs'] == initial['identity']['inputs'] == baseline['inputs']
    old = hashlib.sha256((HERE / 'run-initial.py').read_bytes()).hexdigest()
    new = hashlib.sha256((HERE / 'run.py').read_bytes()).hexdigest()
    assert old == initial['identity']['driver_sha256']
    assert new == result['identity']['driver_sha256']
    assert result['driver_history'] == [{'sha256': old, 'completed_rows': sorted(initial['samples'])}]
    assert len(initial['samples']) == 54
    for key, row in result['samples'].items():
        assert all(check['ok'] for check in row['checks'].values())
        assert row['instruction_ratio'] == row['medians']['rc']['instructions'] / row['medians']['gc']['instructions']
        if key in initial['samples']:
            previous = dict(initial['samples'][key])
            previous['driver_sha256'] = old
            assert previous == row
        else:
            assert key.startswith('schematic/') and row['driver_sha256'] == new
        for side, observations in row['observations'].items():
            assert len(observations['perf']) == len(observations['rss']) == 3
            assert all(v['status'] == 0 and v['instructions'] > 0 for v in observations['perf'])
            assert all(v['status'] == 0 and v['peak_rss_kb'] > 0 for v in observations['rss'])
            assert row['medians'][side]['instructions'] == statistics.median(v['instructions'] for v in observations['perf'])
            assert row['medians'][side]['rss_kb'] == statistics.median(v['peak_rss_kb'] for v in observations['rss'])
            assert all(k.startswith('MYLANG_') for k in row['runs'][side]['env'])
    for backend in ('qbe', 'llvm'):
        rows = [v for k, v in result['samples'].items() if k.endswith('|' + backend)]
        assert len(rows) == 30
        actual = {'programs': 30,
                  'instruction_geomean': math.exp(statistics.mean(math.log(v['instruction_ratio']) for v in rows)),
                  'over_1_3': sum(v['instruction_ratio'] > 1.3 for v in rows),
                  'median_peak_rss_kb': {s: statistics.median(v['medians'][s]['rss_kb'] for v in rows) for s in ('gc', 'rc')}}
        assert actual == summary[backend]
    for name in ('fannkuch', 'schematic'):
        profile = read(name + '/identity.json')
        validation = read(name + '/profile-validation.json')
        assert profile['profile_is_qualitative'] and validation['text_identical']
        assert profile['compiler_sha256'] == result['identity']['compiler_sha256']
        assert len(profile['counters']) == 1
        count = profile['counters'][0]
        assert count['runtime'] == 'rc-v3-counting' and not count['saturated']
        assert count['owner_acquire'] + count['heap_allocate'] == count['owner_release']
        assert count['hold_acquire'] == count['hold_release']
        assert count['heap_allocate'] == count['retire'] and count['arena_allocate'] == 0
        assert count['owner_limit'] == count['hold_limit'] == 0
    print('PASS: 60 diagnostic rows, unchanged 54-row resume, identities, medians and balanced profiles')


if __name__ == '__main__':
    main()
