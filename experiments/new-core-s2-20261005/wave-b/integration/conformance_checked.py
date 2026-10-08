#!/usr/bin/env python3
"""Use the existing conformance sweep with strict compiler process-status checks.

Native tests are already checked by test_runner.zig against their exit status,
stdout and trap/leak/fact reports. This wrapper also rejects an outer compiler
signal or an abnormal exit even when a JSON report was emitted before failure.
The documented empty-selection exit 3 requires an exact empty native report.
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def checked_report(original, done, what):
    if done is not None:
        if done.returncode not in (0, 1, 3):
            return f'{what}: abnormal compiler exit {done.returncode}: {(done.stderr or done.stdout)[:300]}'
        if not done.stdout.strip():
            return f'{what}: empty compiler stdout (exit {done.returncode}): {done.stderr[:300]}'
    report = original(done, what)
    if isinstance(report, dict):
        # NATIVE-TEST-3 and NEW-CORE-TEST-4: nothing selected exits 3.
        empty = (report.get('version') == 'native-tests-v1' and report.get('tests') == []
                 and all(report.get(key) == 0 for key in ('passed', 'failed', 'skipped', 'cached'))
                 and report.get('executed', 0) == 0 and report.get('unsupported', 0) == 0)
        failed = any(test.get('status') == 'failed' for test in report['tests'])
        expected = 3 if empty else int(failed)
        if done.returncode != expected:
            return f'{what}: compiler status {done.returncode} disagrees with its JSON verdicts (expected {expected})'
    return report


def main():
    spec = importlib.util.spec_from_file_location('conformance', ROOT / 'experiments/new-core-s1-20261005/conformance.py')
    sweep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sweep)
    original = sweep.parse

    sweep.parse = lambda done, what: checked_report(original, done, what)
    return sweep.main()


if __name__ == '__main__':
    raise SystemExit(main())
