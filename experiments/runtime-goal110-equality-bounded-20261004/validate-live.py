#!/usr/bin/env python3
"""Validate the immutable RF candidate and G4 comparator control artifacts."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from build_compiler import validate_receipt

BEFORE = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/manifest.json')
AFTER = ROOT / '.mylang-cache/goal110-equality-bounded-rf/runner/manifest.json'
PINS = {'before': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
        'after': '3dcbe723da4036fb7d69046e77e9f8cd16d7512f'}
MANIFESTS = {'before': '4757812159060d11f035115d40fbf94e894bc08030e961fa7c2fdd8d955f4479',
             'after': '9e0577c3798c8cd5d4d87ca00e9d39516085937e1cc3c87b37031b52d97a939b'}


def validate(path, arm):
    assert runner.digest(path) == MANIFESTS[arm]
    document = json.loads(path.read_text())
    identity = document['identity']
    receipt = identity['compiler_build_receipt']
    assert runner.digest(receipt['path']) == receipt['sha256']
    assert receipt['receipt']['source_revision'] == PINS[arm]
    assert receipt['receipt']['compiler_optimize'] == 'ReleaseFast'
    validate_receipt(receipt['receipt'], identity['tools']['mylang']['path'], artifacts=True)
    assert len(identity['binary_paths']) == 24
    for name, binary in identity['binary_paths'].items():
        assert runner.digest(binary) == document['binary_hashes'][name]
        if name.endswith(('/my-llvm', '/my-qbe')):
            manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
            assert manifest['backend'] == name.removeprefix(name.split('/')[0] + '/my-')
            if name.endswith('/my-llvm'):
                assert str(manifest['optimization']) == '3' and manifest['lto'] is True
    assert runner.digest(path.parent / 'native_clock.o') == document['binary_hashes']['native_clock.o']
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    documents = {arm: validate(path, arm) for arm, path in (('before', BEFORE), ('after', AFTER))}
    assert documents['before']['identity']['target_policy'] == documents['after']['identity']['target_policy']
    sources = {arm: document['identity']['compiler_build_receipt']['receipt']['sources_after']
               for arm, document in documents.items()}
    assert set(sources['before']) == set(sources['after'])
    differences = [name for name in sources['before'] if sources['before'][name] != sources['after'][name]]
    assert differences == ['src/native_text.c'], differences
    for group in ('legacy', 'compute', 'collections', 'text'):
        for foreign in ('rust', 'go', 'zig-safe', 'zig-fast'):
            key = group + '/' + foreign
            assert documents['before']['binary_hashes'][key] == documents['after']['binary_hashes'][key]
    output = {'status': 'passed', 'utc': datetime.now(timezone.utc).isoformat(),
              'sources': PINS, 'manifest_hashes': MANIFESTS,
              'compiler_input_differences': differences,
              'binary_hashes': {arm: document['binary_hashes'] for arm, document in documents.items()},
              'compiler_receipt_hashes': {arm: document['identity']['compiler_build_receipt']['sha256']
                                          for arm, document in documents.items()},
              'script_sha256': runner.digest(Path(__file__)),
              'checks': ['Both48 guests and clocks match immutable manifests.',
                         'Official RF compiler/source/installed assets match receipts.',
                         'Actual LLVM O3LTO and QBE backends verified.',
                         'Target policy and all16 foreign reference hashes match across arms.']}
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print('PASS source/officialRF policy/48 guests/installed assets/reference identity validation')


if __name__ == '__main__':
    main()
