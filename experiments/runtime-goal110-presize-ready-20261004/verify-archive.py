#!/usr/bin/env python3
"""Replay the immutable readiness validation archive, without guest timing."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re
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
    spec = importlib.util.spec_from_file_location('ready_qualification', HERE / 'qualify.py')
    qualification = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qualification)
    assert qualification.verify(json.loads(saved['qualification.json.gz'])) == 720
    assert holdouts.verify(json.loads(saved['holdouts.json.gz'])) == 516
    assert '"passed":20,"failed":0,"skipped":0' in saved['logs/unit-final.log'].decode()
    assert 'native RC collections: 53 passed' in saved['logs/native-ready-check.log'].decode()
    assert 'run-all: 88 check(s) passed' in saved['logs/production-commit.log'].decode()
    assert 'whole-tree run' in saved['logs/production-commit.log'].decode()
    for name in ('static-source.json', 'static-binary.json'):
        assert json.loads(saved[name])['status'] == 'pass'
    if args.check_artifacts:
        for name in ('runner-manifest.json.gz', 'baseline-runner-manifest.json.gz'):
            document = json.loads(saved[name])
            binding = receipt['evidence'][name]
            holdouts.check_manifest(Path(binding['original_path']), binding['raw_sha256'], document)
    print(f"PASS readiness archive: {len(saved)} byte bindings;720 qualifications;516 holdouts;20 focused units;53 native checks")


if __name__ == '__main__':
    main()
