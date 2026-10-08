#!/usr/bin/env python3
"""Replay the immutable append6910 validation archive without executing guests."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-artifacts', action='store_true')
    args = parser.parse_args()
    receipt = json.loads((HERE / 'validation-receipt.json').read_text())
    assert receipt['status'] == 'correctness_and_static_complete'
    saved = {}
    for name, binding in receipt['evidence'].items():
        stored = (HERE / name).read_bytes()
        raw = gzip.decompress(stored) if name.endswith('.gz') else stored
        assert digest(stored) == binding['archive_sha256']
        assert digest(raw) == binding['raw_sha256'] and len(raw) == binding['raw_bytes']
        saved[name] = raw
    for name, expected in receipt['helper_sha256'].items():
        assert digest((HERE / name).read_bytes()) == expected
    spec = importlib.util.spec_from_file_location('append_qualification', HERE / 'qualify.py')
    qualification = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qualification)
    assert qualification.verify(json.loads(saved['qualification.json.gz'])) == 720
    assert holdouts.verify(json.loads(saved['holdouts.json.gz'])) == 516
    assert '"passed":27,"failed":0,"skipped":0' in saved['logs/unit-final.log'].decode()
    assert 'run-all: 88 check(s) passed' in saved['logs/production-commit-final.log'].decode()
    assert 'whole-tree run' in saved['logs/production-commit-final.log'].decode()
    assert json.loads(saved['static-binary.json'])['status'] == 'pass'
    native = json.loads(saved['native-outcomes.json'])
    assert native['status'] == 'pass' and native['source_revision'] == receipt['source_revision']
    assert len(native['checks']) == 11
    logged = [json.loads(line.split('APPEND-RANGE-OUTCOME ', 1)[1])
              for line in saved['logs/unit-final.log'].decode().splitlines() if 'APPEND-RANGE-OUTCOME ' in line]
    assert logged == native['checks']
    for row in native['checks']:
        result = row['fast']
        assert result == row['ordinary']
        if row['max_memory'] is not None:
            assert result['failed'] and result['trap']['code'] == 'R_MEMORY_BUDGET' and result['status'] == 1
        elif row['seed'] == 2**63 - 1 and row['count'] > 0:
            assert result['failed'] and result['trap']['code'] == 'R_OVERFLOW' and result['status'] == 1
        else:
            n, seed = row['count'], row['seed']
            expected = 0 if n <= 0 else n + seed % 1009 + (seed + (n - 1) * 13) % 1009
            assert not result['failed'] and result['trap']['code'] == ''
            assert result['value'] == expected and result['status'] == expected % 256
            assert result['stdout'] == result['stderr'] == ''
    if args.check_artifacts:
        for name in ('runner-manifest.json.gz', 'baseline-runner-manifest.json.gz'):
            document = json.loads(saved[name])
            binding = receipt['evidence'][name]
            holdouts.check_manifest(Path(binding['original_path']), binding['raw_sha256'], document)
    print(f'PASS append archive: {len(saved)} byte bindings;720 qualifications;516 holdouts;27 focused units;11 exact native pairs/oracles')


if __name__ == '__main__':
    main()
