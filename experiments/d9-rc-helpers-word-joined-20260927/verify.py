#!/usr/bin/env python3
"""Independently audit the four-workload joined diagnostic without running guests."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent


def raw(path):
    value = path.read_bytes()
    return gzip.decompress(value) if path.suffix == '.gz' else value


def sha(value):
    return hashlib.sha256(value).hexdigest()


def load(name):
    return json.loads(raw(HERE / name))


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


def output(check, expected):
    assert check['ok'] and check['status'] == 0
    assert check['stdout_sha256'] == expected['stdout_sha256']
    if 'svg_sha256' in expected:
        assert check['svg_sha256'] == expected['svg_sha256'] and check['svg_bytes'] == expected['svg_bytes']


def native(receipt, backend, live):
    assert sha(receipt['raw'].encode()) == receipt['sha256']
    value = json.loads(receipt['raw'])
    assert value == receipt['value'] and value['backend'] == backend
    if backend == 'llvm':
        assert value['optimization'] == '3' and value['lto'] and not value['thin_lto']
    if live:
        assert sha(Path(receipt['path']).read_bytes()) == receipt['sha256']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true', help='also check immutable local compiler and guest identities')
    args = parser.parse_args()
    archive = load('identity.json')
    for name, digest in archive['artifacts'].items():
        assert sha((HERE / name).read_bytes()) == digest, name
    data, baseline, prior = load('results.json.gz'), load('gc-builds.json.gz'), load('prior-results.json.gz')
    identity = data['identity']
    assert data['complete'] and data['diagnostic_only'] and identity['cpu'] == 2
    assert identity['source_commit'] == 'c07016f308422b76cfe55607b26243efe0b4257e'
    assert identity['before_source_commit'] == '49c6ca07bbba8b35cda4436b831327ac40c8fc87'
    assert identity['driver_sha256'] == sha((HERE / 'run.py').read_bytes())
    assert identity['measurement_driver_sha256'] == sha((HERE.parent / 'd9-rc-loops-joined-parity-20260927/run.py').read_bytes())
    assert identity['baseline_manifest_sha256'] == sha(raw(HERE / 'gc-builds.json.gz'))
    assert identity['prior_receipt_sha256'] == sha(raw(HERE / 'prior-results.json.gz'))
    assert identity['accepted_gc_compiler_sha256'] == baseline['compiler_sha256'] == '8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478'
    assert identity['inputs'] == baseline['inputs'] == prior['identity']['inputs']
    programs = [p for p in baseline['programs'] if p['kind'] == 'schematic' or p['id'] == 'parity/micro/dict_count']
    assert identity['programs'] == programs and len(programs) == 4
    expected = {p['id'] + '|' + b for p in programs for b in ('qbe', 'llvm')}
    assert set(data['samples']) == expected and len(expected) == 8
    assert set(data['counted']) == {key + '|' + side for key in expected for side in ('before', 'after')}
    assert len(data['builds']) == 12 and all(build['ok'] for build in data['builds'].values())
    for name, build in data['builds'].items():
        native(build['manifest'], name.split('.')[2], args.live)
        command = build['cmd']
        assert command[1] == 'build' and command[2] == identity['compilers'][name.split('.')[0]]['path']
        assert ('--rc-runtime=stats' if name.endswith('.stats') else '--rc-runtime') in command
        if args.live:
            assert sha(Path(command[command.index('-o') + 1]).read_bytes()) == build['sha256']
    for key, row in data['samples'].items():
        backend = key.split('|')[1]
        program = next(p for p in programs if p['id'] == key.split('|')[0])
        build_key = program['build_key'] + '.' + backend
        assert set(row['checks']) == set(row['runs']) == set(row['observations']) == {'gc', 'before', 'after'}
        expected_output = baseline['checks'][key]
        assert row['binaries']['gc']['sha256'] == baseline['builds'][build_key]['sha256']
        assert row['binaries']['before']['sha256'] == prior['builds'][build_key]['sha256']
        assert row['binaries']['after']['sha256'] == data['builds']['after.' + build_key]['sha256']
        for side, observed in row['observations'].items():
            output(row['checks'][side], expected_output)
            native(row['binaries'][side]['manifest'], backend, args.live)
            if args.live:
                assert sha(Path(row['binaries'][side]['path']).read_bytes()) == row['binaries'][side]['sha256']
            run = row['runs'][side]
            assert all(name.startswith('MYLANG_') for name in run['env'])
            assert len(observed['perf']) == len(observed['rss']) == 3
            for sample in observed['perf']:
                assert sample['status'] == 0 and sample['ok']
                actual = events(sample['stderr'])
                assert actual == sample['events']
                instructions = [event for event in actual if event['metric'] == 'instructions']
                assert len(instructions) == 1 and instructions[0]['enabled_percent'] == 100
                assert sample['instructions'] == instructions[0]['count'] > 0
            for sample in observed['rss']:
                assert sample['status'] == 0 and sample['ok']
                values = [line.split('=', 1)[1] for line in sample['stderr'].splitlines() if line.startswith('D9_RSS_KB=')]
                assert len(values) == 1 and int(values[0]) == sample['peak_rss_kb'] > 0
            for sample in observed['perf'] + observed['rss']:
                assert sample['command'][:3] == ['taskset', '-c', '2']
                assert sample['command'][-len(run['argv']):] == run['argv']
            assert row['medians'][side]['instructions'] == statistics.median(v['instructions'] for v in observed['perf'])
            assert row['medians'][side]['rss_kb'] == statistics.median(v['peak_rss_kb'] for v in observed['rss'])
        assert row['after_before'] == row['medians']['after']['instructions'] / row['medians']['before']['instructions']
        assert row['after_gc'] == row['medians']['after']['instructions'] / row['medians']['gc']['instructions']
        for side in ('before', 'after'):
            counted = data['counted'][key + '|' + side]
            output(counted['check'], expected_output)
            n = counted['counts']
            emitted = [json.loads(line.split(' ', 1)[1]) for line in counted['check']['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
            assert emitted == [n] and not n['saturated']
            assert n['hold_acquire'] == n['hold_release'] and n['heap_allocate'] == n['retire']
            assert n['owner_release'] == n['owner_acquire'] + n['heap_allocate']
            assert counted['binary_sha256'] == data['builds'][side + '.' + build_key + '.stats']['sha256']
            other = key.rsplit('|', 1)[0] + '|' + ('llvm' if backend == 'qbe' else 'qbe') + '|' + side
            assert n == data['counted'][other]['counts']
    if args.live:
        for compiler in identity['compilers'].values():
            assert sha(Path(compiler['path']).read_bytes()) == compiler['sha256']
    print('Verified 8 focused rows, 72 unscaled instruction samples, 72 RSS samples, 16 balanced counted runs and actual backend manifests. Full-corpus acceptance remains open.')


if __name__ == '__main__':
    main()
