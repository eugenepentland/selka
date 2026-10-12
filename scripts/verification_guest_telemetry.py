#!/usr/bin/env python3
"""Supported guest JSON verdict inventory; existing runner supplies no test clocks.

This adapter does not execute tests, infer selection from slow/text output, or
claim complete verification. Native-tests-v1 cached verdicts are historical reuse;
property counts and preparation work are not individual test durations.
"""
from pathlib import Path

import verification_report as report
import verification_telemetry as telemetry

STATES = {'passed': 'passed', 'failed': 'failed', 'cached': 'reused',
          'skipped': 'skipped', 'unsupported': 'unsupported'}


def guest_tests(value, *, action_id, member):
    """Validate the actual runner inventory, retaining explicitly unknown clocks."""
    unknown = telemetry.unknown_tests('supported guest report unavailable or malformed')
    try:
        if not isinstance(value, dict) or value.get('version') != 'native-tests-v1':
            return unknown
        tests = value['tests']
        if not isinstance(tests, list) or len(tests) > telemetry.MAX_TESTS:
            return unknown
        counts = {state: 0 for state in STATES}
        rows, names = [], set()
        for test in tests:
            name, state = test['name'], test['status']
            if not isinstance(name, str) or not name or len(name) > telemetry.MAX_LABEL or '::' not in name or name in names:
                return unknown
            if state not in STATES:
                return unknown
            names.add(name)
            counts[state] += 1
            rows.append(dict(test_id=name, state=STATES[state], elapsed_ns=None,
                             elapsed_scope='unknown'))
        for state, count in counts.items():
            if type(value.get(state)) is not int or value[state] != count:
                return unknown
        telemetry.member_id(action_id, member)
        return dict(version=1, status='observed', producer='guest-native-tests-v1',
                    action_id=action_id, member_id=telemetry.member_id(action_id, member),
                    selected=len(rows), executed=counts['passed'] + counts['failed'],
                    reused=counts['cached'], skipped=counts['skipped'], unsupported=counts['unsupported'],
                    timed=0, complete=True, inventory_coverage='complete',
                    timing_coverage='unknown', execution_timing_coverage='unknown',
                    reason='supported guest verdict report has no per-test timing contract',
                    tests=rows, truncated=False, additive=False,
                    aggregate_peak_rss_bytes=None, process=report.process_observations())
    except (KeyError, TypeError, ValueError):
        return unknown


def read_guest_tests(path, *, action_id, member):
    """Read only bounded strict JSON; missing, mixed or partial logs stay unknown."""
    try:
        with Path(path).open('rb') as source:
            raw = source.read(telemetry.MAX_BYTES + 1)
        if len(raw) > telemetry.MAX_BYTES:
            return telemetry.unknown_tests('guest report byte bound exceeded')
        return guest_tests(report._decode(raw.decode('utf-8')), action_id=action_id, member=member)
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError):
        return telemetry.unknown_tests('supported guest JSON log unavailable')
