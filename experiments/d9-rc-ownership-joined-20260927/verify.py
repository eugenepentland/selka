#!/usr/bin/env python3
"""Independently check combined diagnostic receipts; no builds or timed reruns."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
SELECTED = {'parity/micro/dict_count', 'lox/vm/binary_trees',
            'schematic/fixture', 'schematic/changed-net', 'schematic/changed-value'}


def data(path):
    raw = path.read_bytes()
    return gzip.decompress(raw) if path.suffix == '.gz' else raw


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def manifests(result, baseline):
    archived = json.loads(data(HERE / 'build-manifests.json.gz'))
    expected = {'rc/' + key for key in result['builds']}
    expected.update('gc/' + key for key in result['builds'] if not key.endswith('.stats'))
    assert set(archived) == expected
    for name, entry in archived.items():
        side, key = name.split('/', 1)
        build = (result if side == 'rc' else baseline)['builds'][key]
        assert entry['binary_sha256'] == build['sha256']
        assert digest(entry['manifest_text'].encode()) == entry['manifest_sha256']
        manifest = json.loads(entry['manifest_text'])
        backend = 'llvm' if '.llvm' in key else 'qbe'
        assert manifest['backend'] == backend
        if backend == 'llvm':
            assert manifest['optimization'] == '3' and manifest['lto'] and not manifest['thin_lto']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, default=HERE / 'results.json.gz')
    parser.add_argument('--baseline', type=Path, default=HERE / 'gc-builds.json.gz')
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    result = json.loads(data(args.results))
    baseline_raw = data(args.baseline)
    baseline = json.loads(baseline_raw)
    identity = result['identity']
    assert identity['driver_sha256'] == digest((HERE / 'run.py').read_bytes())
    assert identity['measurement_core_sha256'] == digest((HERE / 'measurement_core.py').read_bytes())
    assert identity['baseline_manifest_sha256'] == digest(baseline_raw)
    assert identity['inputs'] == baseline['inputs']
    assert identity['programs'] == [p for p in baseline['programs'] if p['id'] in SELECTED]
    assert len(identity['programs']) == 5 and identity['cpu'] == 2
    assert result['diagnostic_only'] and not result['rss_measured'] and not result['full_corpus_acceptance']
    manifests(result, baseline)
    expected = {p + '|' + b for p in SELECTED for b in ('qbe', 'llvm')}
    production = {p['build_key'] + '.' + b for p in identity['programs'] for b in ('qbe', 'llvm')}
    counting = {p['build_key'] + '.' + b + '.stats' for p in identity['programs']
                if p['kind'] != 'schematic' for b in ('qbe', 'llvm')}
    assert set(result['builds']) <= production | counting
    for key, build in result['builds'].items():
        assert build['ok'] and build['sha256']
        command = build['cmd']
        flag = '--rc-runtime=stats' if key.endswith('.stats') else '--rc-runtime'
        assert flag in command and identity['compiler'] in command
        if '.llvm' in key:
            assert command[command.index('--backend') + 1] == 'llvm'
            assert command[command.index('--llvm-opt') + 1] == '3' and '--lto' in command
    assert set(result['samples']) <= set(result['checks']) <= expected
    for key, row in result['samples'].items():
        assert row['checks'] == result['checks'][key]
        assert all(check['ok'] and check['status'] == 0 for check in row['checks'].values())
        for side, observations in row['observations'].items():
            assert side in ('gc', 'rc') and len(observations) == 3
            run = row['runs'][side]
            assert all(name.startswith('MYLANG_') for name in run['env'])
            for receipt in observations:
                assert receipt['status'] == 0 and receipt['ok'] and receipt['wrapper_wall_seconds'] > 0
                assert receipt['command'][-len(run['argv']):] == run['argv']
                assert receipt['command'][:3] == ['taskset', '-c', '2']
                fields = [line.split(',') for line in receipt['stderr'].splitlines()]
                events = [f for f in fields if len(f) >= 5 and 'instructions' in f[2]
                          and 'cpu_atom' not in f[2] and f[0].strip().isdigit()]
                assert len(events) == 1 and float(events[0][4]) >= 99.9
                assert receipt['instructions'] == int(events[0][0]) > 0
            assert row['medians'][side]['instructions'] == statistics.median(r['instructions'] for r in observations)
            assert row['medians'][side]['wrapper_wall_seconds'] == statistics.median(r['wrapper_wall_seconds'] for r in observations)
        assert row['instruction_ratio'] == row['medians']['rc']['instructions'] / row['medians']['gc']['instructions']
    expected_counted = {p + '|' + b for p in SELECTED if not p.startswith('schematic/') for b in ('qbe', 'llvm')}
    assert set(result['counted']) <= expected_counted
    for row in result['counted'].values():
        assert row['ok'] and row['balanced'] and row['check']['ok'] and row['check']['status'] == 0
        raw = [line.removeprefix('MYLANG_RC_COUNTS ') for line in row['check']['stderr'].splitlines()
               if line.startswith('MYLANG_RC_COUNTS ')]
        assert len(raw) == 1 and json.loads(raw[0]) == row['counts']
        counts = row['counts']
        assert not counts['saturated'] and counts['runtime'] == 'rc-v3-counting'
        assert counts['hold_acquire'] == counts['hold_release']
        assert counts['owner_release'] == counts['owner_acquire'] + counts['heap_allocate']
        assert counts['retire'] == counts['heap_allocate'] and counts['arena_allocate'] == 0
        assert counts['owner_limit'] == counts['hold_limit'] == 0
    if not args.partial:
        assert result['complete_diagnostic'] and set(result['samples']) == expected
        assert set(result['counted']) == expected_counted and set(result['builds']) == production | counting
    print(f'Verified {len(result["samples"])}/10 diagnostic rows and {len(result["counted"])}/4 counted runs; no RSS/full-corpus acceptance claim.')


if __name__ == '__main__':
    main()
