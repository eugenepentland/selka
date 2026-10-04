#!/usr/bin/env python3
"""Replay append6910 screens, paired arithmetic, and immutable artifact scope."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import verify as expanded_verify


def digest(value):
    return hashlib.sha256(value).hexdigest()


def document(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.name.endswith('.gz') else raw)


def helper(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-artifacts', action='store_true')
    args = parser.parse_args()
    receipt = document(HERE / 'timing-evidence.json')
    assert receipt['status'] == 'provisional_adoption_pending_coordinator_replay'
    assert digest((HERE / 'validation-receipt.json').read_bytes()) == receipt['validation_receipt_sha256']
    validation = document(HERE / 'validation-receipt.json')
    for name, binding in receipt['evidence'].items():
        stored = (HERE / name).read_bytes()
        raw = gzip.decompress(stored) if name.endswith('.gz') else stored
        assert digest(stored) == binding['archive_sha256'] and digest(raw) == binding['raw_sha256']
        assert len(raw) == binding['raw_bytes']
    for name, expected in receipt['helper_sha256'].items():
        assert digest((HERE / name).read_bytes()) == expected
    screen = document(HERE / 'six-arm-screen.json.gz')
    expanded_verify.verify(screen, artifacts=args.check_artifacts, focused=True)
    candidate = document(HERE / 'runner-manifest.json.gz')
    assert screen['identity'] == candidate['identity'] and screen['binary_hashes'] == candidate['binary_hashes']
    assert screen['measurement_session_id'] == receipt['six_arm_session_id']
    manifests = {'before': document(HERE / 'baseline-runner-manifest.json.gz'), 'after': candidate}
    plans = {(plan['case'], plan['profile']): plan for plan in screen['plans']}
    total = 0
    for name, script in (('paired-screen', 'time-paired'), ('paired-repeat', 'time-paired-repeat')):
        paired = document(HERE / (name + '.json.gz'))
        helper(script).replay(paired)
        assert paired['six_arm_screen_sha256'] == receipt['evidence']['six-arm-screen.json.gz']['raw_sha256']
        for row in paired['rows']:
            assert row['plan'] == plans[row['plan']['case'], row['plan']['profile']]
            total += len(row['samples'])
        for label, manifest in manifests.items():
            archive = 'baseline-runner-manifest.json.gz' if label == 'before' else 'runner-manifest.json.gz'
            assert paired['manifests'][label]['sha256'] == validation['evidence'][archive]['raw_sha256']
            assert paired['manifests'][label]['identity'] == manifest['identity']
            for backend in ('llvm', 'qbe'):
                assert paired['binary_hashes_before_after'][label + '-' + backend] == manifest['binary_hashes']['collections/my-' + backend]
        if name == 'paired-repeat':
            assert paired['measurement_session_id'] == receipt['repeat_session_id'] != screen['measurement_session_id']
            assert paired['measurement_session_id'] != receipt['initial_paired_session_id']
    assert total == 408
    print('PASS append arithmetic timing replay:240 six-arm samples;408 paired outcomes;unchanged plans/artifacts;no goal acceptance claimed')


if __name__ == '__main__':
    main()
