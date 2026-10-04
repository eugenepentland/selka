#!/usr/bin/env python3
"""Replay the compact integrated checkpoint from immutable gzip evidence."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def source_objects(revision, sources):
    """Batch-read pinned git blobs; the surrounding checkout may be any revision."""
    requests = ''.join(revision + ':' + path + '\n' for path in sources).encode()
    result = subprocess.run(['git', 'cat-file', '--batch'], input=requests, capture_output=True,
                            cwd=ROOT, check=True)
    data = result.stdout
    view = memoryview(data)
    cursor = 0
    for path, expected in sources.items():
        end = data.index(b'\n', cursor)
        header = data[cursor:end]
        cursor = end + 1
        fields = header.split()
        assert fields[1] == b'blob', path
        size = int(fields[2])
        assert data[cursor + size:cursor + size + 1] == b'\n'
        assert digest(view[cursor:cursor + size]) == expected, path
        cursor += size + 1
    assert cursor == len(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true')
    args = parser.parse_args()
    index = json.loads((HERE / 'archive-index.json').read_text())
    raw = {}
    for entry in index['files']:
        packed = (HERE / entry['archive_path']).read_bytes()
        value = gzip.decompress(packed)
        assert digest(packed) == entry['gzip_sha256']
        assert digest(value) == entry['raw_sha256'] and len(value) == entry['raw_bytes']
        assert entry['role'] not in raw
        raw[entry['role']] = value
        if args.live:
            assert digest(Path(entry['original_path']).read_bytes()) == entry['raw_sha256']
    document = lambda role: json.loads(raw[role])
    compiler = document('compiler')
    assert compiler['source_revision'] == index['source_revision']
    assert compiler['sources_before'] == compiler['sources_after'] and compiler['exit_status'] == 0
    source_objects(index['source_revision'], compiler['sources_before'])
    for path, role in index['production_sources'].items():
        if path in compiler['sources_before']:
            assert digest(raw[role]) == compiler['sources_before'][path]
        if args.live:
            assert digest((Path(compiler['source_root']) / path).read_bytes()) == digest(raw[role])
    for name, expected in index['helper_sha256'].items():
        assert digest((ROOT / name).read_bytes()) == expected
    sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
    expanded = module('expanded_verify', ROOT / 'benchmarks/runtime/expanded/verify.py')
    assert expanded.verify(document('screen'), artifacts=args.live, focused=True) == 168
    paired = module('paired', HERE / 'time-paired.py')
    assert paired.replay(document('paired')) == 28
    qualify = module('qualify', ROOT / 'experiments/runtime-goal110-bounded-rem-llvm-20261004/qualify.py')
    assert qualify.verify(document('qualification')) == 720
    sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
    import holdouts
    assert holdouts.verify(document('holdouts')) == 516
    checkpoint = document('focused_checkpoint')
    assert checkpoint['source_revision'] == index['source_revision'] and len(checkpoint['batches']) == 4
    for batch in checkpoint['batches']:
        role = 'unit_' + batch['batch']
        assert digest(raw[role]) == batch['log_sha256'] and batch['actual_outer_exit_status'] == 0
        assert batch['guardian_result']['failed'] == 0
        assert batch['guardian_result']['passed'] == {'remainder': 58, 'index-proof': 22,
                                                     'index-native-a': 15, 'index-native-b': 17}[batch['batch']]
    pairs = [json.loads(line.split(' ', 1)[1]) for line in raw['unit_remainder'].decode().splitlines()
             if line.startswith(('BOUNDED-REMAINDER-OUTCOME ', 'APPEND-RANGE-OUTCOME '))]
    assert len(pairs) == 49 and all(pair['ordinary'] == pair['fast'] for pair in pairs)
    for phase, role in (('six_arm', 'six_arm_process'), ('paired', 'paired_process')):
        process = document(role)
        assert process['phase'] == phase and process['status'] == 'complete' and process['outer_exit_status'] == 0
        assert process['argv'] == document('commands')['commands'][phase]
        assert process['stdout_log_sha256'] == digest(raw[phase + '_log'])
        assert process['commands_sha256'] == digest(raw['commands'])
        assert process['driver_session_id'] != process['measurement_session_id']
    images = document('images')
    assert len(images['rows']) == 8
    assert sum(row['runtime_image_equal'] for row in images['rows']) == 5
    static = document('static')
    compute = [row for row in static['comparisons'] if row['group'] == 'compute']
    assert all(row['runtime_equal'] for row in compute if (row['before'], row['after']) in
               (('5e', 'df09'), ('df09', 'integrated')))
    assert all(len(row['changed_functions']) <= 1 and not row['added'] and not row['removed']
               for row in static['comparisons'])
    analysis = json.loads((HERE / 'analysis.json').read_text())
    assert len(analysis['rows']) == 28
    screen = document('screen'); timing = document('paired')
    for actual, row in zip(analysis['rows'], timing['rows']):
        plan = row['plan']
        assert (actual['case'], actual['profile']) == (plan['case'], plan['profile'])
        six = {value['arm']: value['median_ns_per_op'] for value in screen['summary']
               if (value['case'], value['profile']) == (plan['case'], plan['profile'])}
        winner = min(six, key=six.get)
        assert actual['six_arm_medians_ns'] == six and actual['current_fastest_arm'] == winner
        for backend in ('llvm', 'qbe'):
            saved = actual['paired'][backend]
            assert saved['before_ns'] == row['medians_ns_per_op']['before-' + backend]
            assert saved['after_ns'] == row['medians_ns_per_op']['after-' + backend]
            assert saved['after_before'] == row['after_before_ratios'][backend]
            assert saved['paired_95'] == row['paired_bootstrap_95'][backend]
            assert saved['six_arm_current_fastest_ratio'] == six['my-' + backend] / six[winner]
    if args.live:
        path = Path(next(entry['original_path'] for entry in index['files'] if entry['role'] == 'manifest'))
        holdouts.check_manifest(path, digest(raw['manifest']), document('manifest'))
    print(f"PASS {len(raw)} archives,{len(compiler['sources_before'])} pinned source blobs,4 batches,49 native pairs,"
          '840 six-arm samples,672 paired executions,720 qualifications,516 holdouts,5 equal/3 different runtime images')


if __name__ == '__main__':
    main()
