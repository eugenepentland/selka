#!/usr/bin/env python3
"""Use the existing conformance sweep with strict compiler process-status checks.

Native tests are already checked by test_runner.zig against their exit status,
stdout and trap/leak/fact reports. This wrapper also rejects an outer compiler
signal or an abnormal exit even when a JSON report was emitted before failure.
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def main():
    spec = importlib.util.spec_from_file_location('conformance', ROOT / 'experiments/new-core-s1-20261005/conformance.py')
    sweep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sweep)
    original = sweep.parse

    def checked(done, what):
        if done is not None:
            if done.returncode not in (0, 1):
                return f'{what}: abnormal compiler exit {done.returncode}: {(done.stderr or done.stdout)[:300]}'
            if not done.stdout.strip():
                return f'{what}: empty compiler stdout (exit {done.returncode}): {done.stderr[:300]}'
        report = original(done, what)
        if isinstance(report, dict):
            failed = any(test.get('status') == 'failed' for test in report['tests'])
            if done.returncode != int(failed):
                return f'{what}: compiler status {done.returncode} disagrees with its JSON verdicts'
        return report

    sweep.parse = checked
    return sweep.main()


if __name__ == '__main__':
    raise SystemExit(main())
