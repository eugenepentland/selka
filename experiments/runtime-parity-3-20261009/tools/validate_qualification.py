#!/usr/bin/env python3
"""Validate raw and additive lane conformance against M0's exact known results."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re

AREA = Path(__file__).resolve().parents[1]
ROOT = AREA.parents[1]


def text(path):
    if path.exists():
        return path.read_text()
    return gzip.open(path.with_suffix(path.suffix + '.gz'), 'rt').read()


def validate(directory, expected, baseline):
    summary = json.loads(text(directory / 'summary.json'))
    assert summary['references_sha256'] == baseline['frozen_reference_sha256']
    assert summary['core_shards'] == 64
    steps = summary['results']
    assert len(steps) == 3 and all(step['status'] == 0 for step in steps[:2])
    assert steps[-1]['status'] == expected['status']
    assert summary['qualified'] == (expected['status'] == 0)
    assert steps[1]['tests']['failed'] == steps[1]['tests']['skipped'] == 0
    assert steps[1]['tests']['passed'] >= baseline['additive']['core_tests_passed']
    assert not steps[1]['build_inspection']['errors']
    assert '--leakcheck' in steps[-1]['command'] and '--verify' in steps[-1]['command']
    log = text(directory / 'full-conformance.log')
    modes = {mode: [int(a), int(b), int(c)] for mode, a, b, c in
             re.findall(r'^\s+(debug|release)\s+matching (\d+), mismatching (\d+), unsupported (\d+)', log, re.M)}
    assert modes == {mode: expected[mode] for mode in ('debug', 'release')}, modes
    problems = sorted(line for line in log.splitlines() if line.startswith('PROBLEM '))
    assert problems == sorted(expected.get('problem_lines', [])), problems
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--raw', type=Path, required=True)
    parser.add_argument('--additive', type=Path, required=True)
    args = parser.parse_args()
    baseline = json.loads((AREA / 'M0/conformance-baseline.json').read_text())
    frontend = ROOT / 'experiments/frontend-fixes-20261009/s5-frontend-reference.json'
    assert hashlib.sha256(frontend.read_bytes()).hexdigest() == baseline['frontend_reference_sha256']
    raw = validate(args.raw, baseline['unadapted'], baseline)
    additive = validate(args.additive, baseline['additive'], baseline)
    assert raw['core_sha256'] == additive['core_sha256'], 'different compilers in raw/additive qualification'
    print('qualified: exact M0 raw differences and complete additive conformance; 64 core shards, leak/fact checks')


if __name__ == '__main__':
    main()
