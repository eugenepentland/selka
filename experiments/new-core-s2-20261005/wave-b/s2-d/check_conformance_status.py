#!/usr/bin/env python3
"""Check crash rejection and the documented empty-selection exception without native runs."""
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def main():
    wrapper = module('strict_conformance', HERE / 'conformance_checked.py')
    original = module('s1_conformance', ROOT / 'experiments/new-core-s1-20261005/conformance.py')
    empty = dict(version='native-tests-v1', tests=[], passed=0, failed=0, cached=0, skipped=0, executed=0)
    passed = dict(empty, tests=[dict(name='sample', status='passed')], passed=1, executed=1)
    failed = dict(empty, tests=[dict(name='sample', status='failed')], failed=1, executed=1)
    unsupported = dict(empty, tests=[dict(name='sample', status='unsupported')], unsupported=1)
    cases = [(3, empty, True), (0, passed, True), (1, failed, True), (0, unsupported, True),
             (-11, passed, False), (2, passed, False), (3, passed, False), (0, failed, False),
             (1, passed, False), (3, dict(empty, executed=1), False), (0, empty, False)]
    for status, report, accepted in cases:
        done = subprocess.CompletedProcess(['synthetic'], status, json.dumps(report), '')
        result = wrapper.checked_report(original.parse, done, 'synthetic compiler')
        assert isinstance(result, dict) == accepted, (status, report, result)
    for status in (0, 1, 3, -11):
        done = subprocess.CompletedProcess(['synthetic'], status, '', '')
        assert isinstance(wrapper.checked_report(original.parse, done, 'synthetic compiler'), str)
    assert isinstance(wrapper.checked_report(original.parse, None, 'synthetic compiler'), str)
    print('PASS: 16 process/report cases; empty status3 admitted, signals/blank stdout/status disagreement rejected; no native runs')


if __name__ == '__main__':
    main()
