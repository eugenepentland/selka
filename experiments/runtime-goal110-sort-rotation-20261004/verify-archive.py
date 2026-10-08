#!/usr/bin/env python3
"""Verify archived byte bindings and replay every saved correctness/timing cell."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import goal110
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def raw(name):
    value = (HERE / name).read_bytes()
    return gzip.decompress(value) if name.endswith('.gz') else value


def document(name):
    return json.loads(raw(name))


def digest(value):
    return hashlib.sha256(value).hexdigest()


def helper(name):
    specification = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main():
    validation, timing = document('validation-receipt.json'), document('timing-evidence.json')
    assert validation['source_revision'] == timing['candidate_revision'] == '8043c4d9e0ad907c8a1b9e8416a1e58815eef0df'
    assert timing['validation_receipt_sha256'] == digest(raw('validation-receipt.json'))
    evidence = {**validation['evidence'], **timing['evidence']}
    assert not set(validation['evidence']).intersection(timing['evidence'])
    for name, row in evidence.items():
        saved = (HERE / name).read_bytes()
        assert digest(saved) == row['archive_sha256'] and len(saved) == row['archive_bytes'], name
        value = raw(name)
        assert digest(value) == row['raw_sha256'] and len(value) == row['raw_bytes'], name
    for name, expected in validation['helper_and_static_sha256'].items():
        assert digest(raw(name)) == expected, name
    manifests = {label: document(prefix + 'runner-manifest.json.gz')
                 for label, prefix in (('before', 'baseline-'), ('after', ''))}
    receipt = document('compiler-receipt.json.gz')
    assert receipt['compiler_optimize'] == validation['compiler']['optimize'] == 'Debug'
    assert receipt['compiler_sha256'] == validation['compiler']['sha256']
    assert goal110.content_hash(goal110.production_sources(receipt)) == validation['production_sources_fingerprint']
    baseline = document('baseline-compiler-receipt.json.gz')
    assert baseline['compiler_optimize'] == 'Debug'
    assert baseline['source_revision'] == '5a60ef1039aca32657ef5877a464eb8a81d6c115'
    assert goal110.content_hash(goal110.production_sources(baseline)) == validation['matched_baseline']['production_sources_fingerprint']
    qualification, holdout = document('qualification.json.gz'), document('holdouts.json.gz')
    assert qualification['identity'] == holdout['identity'] == manifests['after']['identity']
    assert qualification['binary_hashes'] == holdout['binary_hashes'] == manifests['after']['binary_hashes']
    assert helper('qualify').verify(qualification) == 720 and holdouts.verify(holdout) == 516
    screen = document('six-arm-screen.json.gz')
    assert screen['identity'] == manifests['after']['identity'] and screen['binary_hashes'] == manifests['after']['binary_hashes']
    assert screen['status'] == 'subset' and len(screen['samples']) == 240
    for name, count in (('paired-screen', 8), ('paired-repeat', 6)):
        report = document(name + '.json.gz')
        module = helper('time-paired' if name == 'paired-screen' else 'time-paired-repeat')
        assert module.replay(report) == count
        assert report['six_arm_screen_sha256'] == evidence['six-arm-screen.json.gz']['raw_sha256']
        for label, manifest in manifests.items():
            prefix = 'baseline-' if label == 'before' else ''
            assert report['manifests'][label]['sha256'] == evidence[prefix + 'runner-manifest.json.gz']['raw_sha256']
            assert report['manifests'][label]['identity'] == manifest['identity']
            for backend in ('llvm', 'qbe'):
                assert report['binary_hashes_before_after'][label + '-' + backend] == manifest['binary_hashes']['collections/my-' + backend]
    assert digest(raw('time-paired.py')) == timing['preserved_original_helper_sha256']
    binary = document('static-binary.json')
    assert binary['qbe_comparison']['changed_instruction_functions'] == list(helper('static-binary').SORTS)
    assert binary['qbe_comparison']['named_functions_compared'] == 402
    assert not binary['qbe_comparison']['closure_intersects_changed_sort_routines']
    for label in ('baseline', 'candidate'):
        assert digest(raw('assembly/qbe-' + label + '-full.asm.gz')) == binary['qbe_comparison']['assembly_sha256'][label]
    assert '88 check(s) passed' in raw('logs/commit-guardian.log').decode()
    assert 'whole-tree run' in raw('logs/commit-guardian.log').decode()
    assert '78 stable run cases, 7 unchanged scratch refusals passed' in raw('logs/native-focused-asan-ubsan.log').decode()
    print('PASS archive: ' + str(len(evidence)) + ' byte bindings; 720 qualifications, 516 holdouts, 624 paired outcomes; exact matched Debug artifacts and whole-QBE static scope')


if __name__ == '__main__':
    main()
