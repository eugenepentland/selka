#!/usr/bin/env python3
"""Independently audit archived flat-retain measurements without rerunning guests.

Supply --live to also hash the original compiler, binaries and input files.
This validates this eight-row experiment; it never establishes WP-4 acceptance.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import statistics


def read(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def balance(count):
    assert count['version'] == 1 and count['runtime'] == 'rc-v3-counting'
    assert count['saturated'] is False
    assert count['owner_limit'] == count['hold_limit'] == 0
    assert count['hold_acquire'] == count['hold_release']
    assert count['heap_allocate'] == count['retire']
    assert count['owner_acquire'] + count['heap_allocate'] == count['owner_release']


def parsed_count(stderr):
    return [json.loads(line.split(' ', 1)[1]) for line in stderr.splitlines()
            if line.startswith('MYLANG_RC_COUNTS ')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--live', action='store_true')
    args = parser.parse_args()
    archive = args.archive.resolve()
    data = read(archive / 'measurements.json.gz')
    control = read(archive.parent / 'd9-rc-flat-borrow-joined-20260927/results.json.gz')
    identity = read(archive / 'source-identity.json')
    assert data['identity']['before'] == control['identity']
    assert data['identity']['after_compiler_sha256'] == identity['candidate_compiler_sha256']
    assert data['identity']['production_source_sha256'] == identity['files']['src/native_rc_values.c']
    assert data['identity']['cpu'] == 2
    keys = {program['id'] + '|' + backend for program in control['identity']['programs']
            for backend in ('qbe', 'llvm')}
    assert len(keys) == 8 and set(data['samples']) == keys and set(data['counts']) == keys
    assert len(data['builds']) == 8
    for name, build in data['builds'].items():
        backend = name.split('-')[1]
        manifest = build['manifest']
        assert manifest['backend'] == backend
        if backend == 'llvm':
            assert manifest['optimization'] == '3' and manifest['lto'] is True
        assert ('--rc-runtime=stats' if name.endswith('stats') else '--rc-runtime') in build['command']
        if args.live:
            binary = build['command'][build['command'].index('-o') + 1]
            assert sha(binary) == build['sha256']
    total = 0
    for key in sorted(keys):
        row = data['samples'][key]
        assert {(sample['arm'], sample['repetition']) for sample in row['samples']} == {
            (arm, repetition) for arm in ('before', 'after') for repetition in range(3)}
        assert len(row['samples']) == 6
        for sample in row['samples']:
            events = [line.split(',') for line in sample['stderr'].splitlines()
                      if ',cpu_core/instructions/u,' in line]
            assert len(events) == 1
            event = events[0]
            assert event[0].isdigit() and int(event[0]) > 0 and float(event[4]) >= 99.9
            assert sample['counters']['cpu_core/instructions/u'] == int(event[0])
            command = sample['command']
            assert command[:3] == ['taskset', '-c', '2']
            assert command[command.index('--') + 1:] == row['runs'][sample['arm']]['argv']
            assert sample['stdout'] == data['counts'][key]['stdout']
            total += 1
        medians = {arm: statistics.median(sample['counters']['cpu_core/instructions/u']
                   for sample in row['samples'] if sample['arm'] == arm) for arm in ('before', 'after')}
        assert medians == row['medians']
        assert medians['after'] / medians['before'] == row['after_over_before']
        count = data['counts'][key]
        assert count['counts'] == control['counts'][key]['counts']
        assert parsed_count(count['stderr']) == [count['counts']]
        balance(count['counts'])
    validation = read(archive / 'validation.json.gz')
    assert validation['compilers']['before'] == control['identity']['compiler_sha256']
    assert validation['compilers']['after'] == identity['candidate_compiler_sha256']
    runs = {(row['backend'], row['name'], row['mode'], row['arm']): row for row in validation['runs']}
    assert len(runs) == len(validation['runs']) == 16
    for backend in ('qbe', 'llvm'):
        for name in ('plain', 'broad'):
            for mode in ('gc', 'rc'):
                before, after = (runs[(backend, name, mode, arm)] for arm in ('before', 'after'))
                assert before['exit'] == after['exit'] == 0
                assert before['stdout'] == after['stdout'] and before['counts'] == after['counts']
                for count in after['counts']:
                    balance(count)
    if args.live:
        assert sha(data['identity']['after_compiler']) == identity['candidate_compiler_sha256']
        assert sha(control['identity']['compiler']) == control['identity']['compiler_sha256']
        for path, digest in control['identity']['inputs'].items():
            assert sha(path) == digest, path
        for build in control['builds'].values():
            assert sha(build['command'][build['command'].index('-o') + 1]) == build['sha256']
    print(f'PASS: {len(keys)} rows, {total} unscaled instruction samples, 8 exact balanced count records, 16 paired controls; no WP-4 acceptance claim')


if __name__ == '__main__':
    main()
