#!/usr/bin/env python3
"""Untimed checksums for every MyLang runtime cell against independent oracles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
from registry import EDGE_PROBES, checksum, inventory
from build_compiler import validate_receipt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text())
identity = manifest['identity']
receipt = identity['compiler_build_receipt']['receipt']
validate_receipt(receipt, receipt['compiler_path'], artifacts=True)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


for key, filename in identity['binary_paths'].items():
    assert digest(filename) == manifest['binary_hashes'][key], key
assert digest(args.manifest.parent / 'native_clock.o') == manifest['binary_hashes']['native_clock.o']
report = {'schema': 'mylang-unique-capture-untimed-qualification-v1', 'source_revision': identity['source_revision'],
          'manifest': {'path': str(args.manifest.resolve()), 'sha256': digest(args.manifest)},
          'binary_hashes': manifest['binary_hashes'], 'samples': [],
          'limits': 'Untimed oracle checks only. Kernel times printed by guests are retained as raw output and never used to infer performance.'}
environment = {key: value for key, value in os.environ.items() if not key.startswith('MYLANG_')}
try:
    for case, meta in inventory().items():
        for size, seed, count in EDGE_PROBES:
            expected = checksum(case, size, count, seed)
            for arm in ('my-llvm', 'my-qbe'):
                key = meta['group'] + '/' + arm
                command = [identity['binary_paths'][key], case, str(size), str(count), str(seed)]
                done = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=120)
                match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', done.stdout)
                row = {'case': case, 'size': size, 'seed': seed, 'iterations': count, 'arm': arm,
                       'expected': expected, 'command': command, 'status': done.returncode,
                       'stdout': done.stdout, 'stderr': done.stderr}
                report['samples'].append(row)
                assert done.returncode == 0 and done.stderr == '' and match, row
                assert int(match.group(1)) == expected and int(match.group(2)) > 0, row
    for key, filename in identity['binary_paths'].items():
        assert digest(filename) == manifest['binary_hashes'][key], key
    report['status'] = 'passed'
finally:
    report['execution_count'] = len(report['samples'])
    args.output.write_text(json.dumps(report, indent=2) + '\n')
print(f"{report['execution_count']} untimed MyLang/oracle checks passed")
