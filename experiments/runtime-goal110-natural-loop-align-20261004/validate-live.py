#!/usr/bin/env python3
"""Validate pinned natural-loop candidate, integrated Debug control, and original foreign references."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from build_compiler import validate_receipt


def validate(bindings):
    documents = {}
    for label, binding in bindings['arms'].items():
        path = Path(binding['manifest'])
        assert runner.digest(path) == binding['manifest_sha256']
        document = json.loads(path.read_text())
        identity = document['identity']
        receipt = identity['compiler_build_receipt']
        assert runner.digest(receipt['path']) == receipt['sha256']
        assert receipt['receipt']['source_revision'] == binding['source_revision']
        assert receipt['receipt']['compiler_optimize'] == binding['compiler_optimize']
        validate_receipt(receipt['receipt'], identity['tools']['mylang']['path'], artifacts=True)
        assert len(identity['binary_paths']) == 24
        for name, binary in identity['binary_paths'].items():
            assert runner.digest(binary) == document['binary_hashes'][name]
            if name.endswith(('/my-llvm', '/my-qbe')):
                manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
                assert manifest['backend'] == name.split('/my-')[1]
                if name.endswith('/my-llvm'):
                    assert str(manifest['optimization']) == '3' and manifest['lto'] and not manifest['thin_lto']
        assert runner.digest(path.parent / 'native_clock.o') == document['binary_hashes']['native_clock.o']
        documents[label] = document
    before, after = documents['before'], documents['after']
    assert before['identity']['target_policy'] == after['identity']['target_policy']
    sources = {label: document['identity']['compiler_build_receipt']['receipt']['sources_after']
               for label, document in documents.items()}
    differences = sorted(name for name in set(sources['before']) | set(sources['after'])
                         if sources['before'].get(name) != sources['after'].get(name))
    assert differences == bindings['expected_source_changes'], differences
    for group in ('legacy', 'compute', 'collections', 'text'):
        for foreign in ('rust', 'go', 'zig-safe', 'zig-fast'):
            name = group + '/' + foreign
            assert before['binary_hashes'][name] == after['binary_hashes'][name]
    qualified = bindings['qualified_text']
    assert runner.digest(qualified['path']) == qualified['sha256']
    assert after['binary_hashes']['text/my-llvm'] == qualified['sha256']
    return documents


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bindings', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    bindings = json.loads(args.bindings.read_text())
    documents = validate(bindings)
    args.output.write_text(json.dumps({'status': 'passed', 'utc': datetime.now(timezone.utc).isoformat(),
                                      'bindings_sha256': runner.digest(args.bindings),
                                      'binary_hashes': {label: document['binary_hashes'] for label, document in documents.items()},
                                      'qualified_text_hash_identical': True,
                                      'script_sha256': runner.digest(Path(__file__))}, indent=2) + '\n')
    print('PASS source/receipt/assets/48 guests/backends/references; final text equals qualified oracle ELF')
