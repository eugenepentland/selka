#!/usr/bin/env python3
"""Validate immutable diagnostic/control artifacts without executing guests."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-search-placement'
DEBUG = ROOT / '.mylang-cache/goal110-floor-result-range-debug'
KERNEL = 'myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76'


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


spec = importlib.util.spec_from_file_location('pinned_annotation_validate', ROOT /
                                           'experiments/runtime-goal110-floor-result-range-20261004/validate-live.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def validate():
    controls = module.validate(json.loads((DEBUG / 'artifact-bindings.json').read_text()))
    capture = json.loads((WORK / 'capture/capture-build.json').read_text())
    fill = json.loads((WORK / 'fill32/fill-build.json').read_text())
    assert capture['exact_guest_reproduction'] and capture['exit_status'] == fill['exit_status'] == 0
    for report in (capture, fill):
        assert binding(Path(report['guest']['path'])) == report['guest']
        assert binding(Path(report['guest_manifest']['path'])) == report['guest_manifest']
        assert binding(Path(report['compiler']['path'])) == report['compiler']
        assert binding(Path(report['compiler_receipt']['path'])) == report['compiler_receipt']
        assert binding(Path(report['wrapper']['path'])) == report['wrapper']
        assert binding(Path(report['config']['path'])) == report['config']
        manifest = json.loads(Path(report['guest_manifest']['path']).read_text())
        assert manifest['backend'] == 'llvm' and str(manifest['optimization']) == '3'
        assert manifest['lto'] and not manifest['thin_lto']
        config = json.loads(Path(report['config']['path']).read_text())
        assert binding(Path(config['real_zig']))['sha256'] == config['real_zig_sha256']
    assert capture['guest']['sha256'] == controls['after']['binary_hashes']['text/my-llvm']
    assert capture['wrapper'] == fill['wrapper'] and capture['compiler'] == fill['compiler']
    proof_path = WORK / 'proof/placement-proof.json'
    proof = json.loads(proof_path.read_text())
    assert proof['status'] == 'passed' and all(row['normalized_equal'] for row in proof['comparisons'].values())
    for row in proof['variants'].values():
        assert binding(Path(row['binary']['path'])) == row['binary']
        for function in row['functions'].values():
            for kind in ('assembly', 'normalized'):
                assert binding(Path(function[kind]['path'])) == function[kind]
    fill_assembly = Path(proof['variants']['fill32']['functions'][KERNEL]['assembly']['path']).read_text()
    assert re.search(r'104f6da:\s+jne\s+104f550\s+<', fill_assembly)
    assert len(re.findall(r'^\s*104f5[34][0-9a-f]:\s+nop$', fill_assembly, re.MULTILINE)) == 32
    text_path = WORK / 'text-checks.json'
    text = json.loads(text_path.read_text())
    assert text['status'] == 'passed' and text['execution_count'] == len(text['records']) == 200
    for record in text['records']:
        match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', record['stdout'])
        assert record['status'] == 0 and record['stderr'] == '' and match
        assert int(match[1]) == record['oracle'] and int(match[2]) > 0
    assert text['binaries']['before']['sha256'] == capture['guest']['sha256']
    assert text['binaries']['after']['sha256'] == fill['guest']['sha256']
    binaries = {'g4': Path(controls['before']['identity']['binary_paths']['text/my-llvm']),
                'annotation': Path(capture['guest']['path']), 'fill32': Path(fill['guest']['path'])}
    result = {'status': 'passed_diagnostic_only', 'utc': datetime.now(timezone.utc).isoformat(),
              'source_revision': capture['source_revision'], 'binaries': {name: binding(path) for name, path in binaries.items()},
              'proof': binding(proof_path), 'text_checks': binding(text_path),
              'wrapper': capture['wrapper'], 'validator': binding(Path(__file__)),
              'controls_binding': binding(DEBUG / 'artifact-bindings.json'),
              'qualification': '200 ordinary text records; final backedge skips32NOPs; full caller/helpers/constants identity.'}
    return binaries, result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    _, report = validate()
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS immutable48controls+counterfactual/tools/source/200oracles/backedge')
