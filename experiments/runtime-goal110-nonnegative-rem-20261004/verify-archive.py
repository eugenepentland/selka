#!/usr/bin/env python3
"""Replay saved correctness/timing arithmetic without building or measuring."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(ROOT / 'benchmarks/runtime/expanded'), str(ROOT / 'benchmarks/runtime/diagnostics'),
                str(ROOT / 'benchmarks/runtime')]
import verify as expanded_verify
import holdouts


def helper(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def saved(name):
    return json.loads(gzip.decompress((HERE / 'raw' / (name + '.gz')).read_bytes()))


def main():
    index = json.loads((HERE / 'archive-index.json').read_text())
    assert index['source_revision'] == '27de73d302d23a9efaf811d541f1cb723323c434'
    assert index['status'] == 'unintegrated_negative_input_cost_blocker'
    for name, binding in index['archives'].items():
        archive = (HERE / name).read_bytes(); raw = gzip.decompress(archive)
        assert hashlib.sha256(archive).hexdigest() == binding['archive_sha256']
        assert hashlib.sha256(raw).hexdigest() == binding['uncompressed_sha256']
        assert len(raw) == binding['uncompressed_bytes']
    assert expanded_verify.verify(saved('screen.json'), False, True) == 48
    assert helper('qualify').verify(saved('qualification.json')) == 720
    assert holdouts.verify(saved('holdouts.json')) == 516
    assert helper('time-paired').replay(saved('paired.json')) == 8
    assert helper('time-supplement').replay(saved('supplement-timing.json')) == 96
    semantic = saved('actual-llvm-semantics.json')
    oracle = helper('actual-llvm-semantics')
    assert semantic['source_revision'] == index['source_revision'] and semantic['status'] == 'complete'
    assert [row['input'] for row in semantic['outcomes']] == list(oracle.CASES)
    for row in semantic['outcomes']:
        result = row['unaccounted']['run']
        assert result == row['accounted']['run']
        assert result['stdout'] == '17\n' and result['trap']['code'] == row['input'].get('trap', '')
        if 'trap' in row['input']:
            assert result['failed'] and result['status'] == 1 and result['trap']['frames']
        else:
            assert not result['failed'] and result['value'] == oracle.expected(row['input'])
            assert result['status'] == result['value'] % 256
    native = json.loads((HERE / 'native-outcomes.json').read_text())
    assert native == saved('llvm-final-native-outcomes.json')
    assert native['source_revision'] == index['source_revision'] and len(native['outcomes']) == 41
    for row in native['outcomes']:
        assert row['ordinary'] == row['fast']
    print('PASS archive byte identities,48groups/240samples/720qualifications,720untimedchecks,516holdouts,192frozenpairsamples,96signedsamples,18actualLLVMexecutions,41nativepairs')


if __name__ == '__main__':
    main()
