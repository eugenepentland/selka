#!/usr/bin/env python3
"""Advisory version-1 test telemetry; never grants verification authority.

The supported Python producer is a unittest result/runner, not a slow-log parser.
Native producers can emit the same document after coordinated runner changes.
"""
import argparse
import json
import os
from pathlib import Path
import resource
import sys
import tempfile
import time
import unittest

VERSION = 1
MAX_TESTS = 16384
MAX_BYTES = 2 * 1024 * 1024
MAX_LABEL = 512
MAX_REASONS = 64
STATES = frozenset(('passed', 'failed', 'skipped', 'reused'))


def member_id(action_id, index):
    """Name a registered member without depending on its display label."""
    if not isinstance(action_id, str) or not action_id or len(action_id) > MAX_LABEL:
        raise ValueError('action identity')
    if type(index) is not int or index < 0:
        raise ValueError('member index')
    return f'{action_id}/member/{index}'


def unknown_tests(reason='supported test telemetry unavailable'):
    """Keep absence distinguishable from zero selected tests."""
    return dict(version=VERSION, status='unknown', reason=reason, selected=None,
                executed=None, reused=None, skipped=None, timed=None,
                timing_coverage='unknown', execution_timing_coverage='unknown', tests=[], truncated=False,
                additive=False, aggregate_peak_rss_bytes=None)


def validate_tests(record, *, action_id=None, member=None):
    """Validate detached producer data; malformed coverage remains unknown."""
    unknown = unknown_tests('malformed or incompatible test telemetry')
    try:
        if not isinstance(record, dict) or record.get('version') != VERSION or type(record['version']) is not int:
            return unknown
        if record.get('malformed') is True:
            return unknown
        for field in ('producer', 'action_id', 'member_id'):
            if not isinstance(record[field], str) or not record[field] or len(record[field]) > MAX_LABEL:
                return unknown
        if action_id is not None and record['action_id'] != action_id:
            return unknown
        if member is not None and record['member_id'] != member:
            return unknown
        selected = record['selected']
        rows = record['tests']
        if type(selected) is not int or selected < 0 or type(record['complete']) is not bool:
            return unknown
        if not isinstance(rows, list) or len(rows) > MAX_TESTS or len(rows) > selected:
            return unknown
        identities = set()
        counts = dict(executed=0, reused=0, skipped=0, timed=0)
        detached = []
        for row in rows:
            name, state, ns = row['test_id'], row['state'], row['elapsed_ns']
            if not isinstance(name, str) or not name or len(name) > MAX_LABEL or name in identities:
                return unknown
            identities.add(name)
            if state not in STATES or (ns is not None and (type(ns) is not int or ns < 0)):
                return unknown
            if state in ('reused', 'skipped') and ns is not None:
                return unknown
            counts['reused' if state == 'reused' else 'skipped' if state == 'skipped' else 'executed'] += 1
            counts['timed'] += ns is not None
            scope = row.get('elapsed_scope', 'test-execution')
            if scope not in ('test-execution', 'runner-protocol-interval'):
                return unknown
            detached.append(dict(test_id=name, state=state, elapsed_ns=ns, elapsed_scope=scope))
        selection_scope = record.get('selection_scope', 'declared-producer-selection')
        if selection_scope not in ('declared-producer-selection', 'loaded-unittest-suite', 'actual-client-dispatch'):
            return unknown
        complete = record['complete'] and len(rows) == selected
        timing = 'complete' if complete and counts['timed'] == selected else 'partial'
        execution_timing = 'complete' if complete and counts['timed'] == counts['executed'] else 'partial'
        import verification_report
        process = verification_report.process_observations(record.get('process'))
        return dict(version=VERSION, status='observed', process=process, producer=record['producer'],
                    action_id=record['action_id'], member_id=record['member_id'],
                    selected=selected, selection_scope=selection_scope, **counts, tests=detached, complete=complete,
                    timing_coverage=timing, execution_timing_coverage=execution_timing, truncated=len(rows) < selected,
                    additive=False, aggregate_peak_rss_bytes=None)
    except (KeyError, TypeError, ValueError):
        return unknown


def read_tests(path, *, action_id=None, member=None):
    """Read strict bounded JSON and reject duplicate keys or nonfinite numbers."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate key')
            result[key] = value
        return result
    try:
        with Path(path).open('rb') as source:
            raw = source.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            return unknown_tests('test telemetry byte bound exceeded')
        record = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
                            parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite')))
        return validate_tests(record, action_id=action_id, member=member)
    except (OSError, UnicodeError, ValueError, RecursionError):
        return unknown_tests()


def stability_diagnostics(reasons=(), *, unknown=False, truncated=False):
    """Detach bounded caller observations without inspecting or clearing authority.

Each reason names role, facet (path/host/authority/watch), name and reason.
Providers retain responsibility for dirty state, including byte-restored ABA.
"""
    rows = []
    try:
        for index, item in enumerate(reasons):
            if index >= MAX_REASONS:
                truncated = True
                break
            if not isinstance(item, dict):
                unknown = True
                continue
            row = {}
            for field in ('role', 'facet', 'name', 'reason'):
                value = item.get(field)
                if value is None and field == 'name':
                    row[field] = None
                elif isinstance(value, str) and value:
                    row[field] = value[:MAX_LABEL]
                    truncated = truncated or len(value) > MAX_LABEL
                else:
                    unknown = True
                    break
            else:
                if row['facet'] in ('path', 'host', 'authority', 'watch'):
                    rows.append(row)
                else:
                    unknown = True
    except (TypeError, ValueError):
        unknown = True
    return dict(version=VERSION, status='observed' if rows else 'unknown', reasons=rows,
                unknown=bool(unknown or not rows), truncated=bool(truncated))


class TelemetryResult(unittest.TextTestResult):
    """Capture every selected unittest result, including failure and skip."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.telemetry = []
        self._started = {}
        self._states = {}
        self.telemetry_truncated = False

    def startTest(self, test):
        self._started[test] = time.monotonic_ns()
        self._states[test] = 'passed'
        super().startTest(test)

    def addFailure(self, test, err):
        self._states[test] = 'failed'
        super().addFailure(test, err)

    def addError(self, test, err):
        self._states[test] = 'failed'
        super().addError(test, err)

    def addUnexpectedSuccess(self, test):
        self._states[test] = 'failed'
        super().addUnexpectedSuccess(test)

    def addSkip(self, test, reason):
        self._states[test] = 'skipped'
        super().addSkip(test, reason)

    def addSubTest(self, test, subtest, err):
        if err is not None:
            self._states[test] = 'failed'
        super().addSubTest(test, subtest, err)

    def stopTest(self, test):
        ended = time.monotonic_ns()
        state = self._states.pop(test)
        started = self._started.pop(test)
        if len(self.telemetry) < MAX_TESTS:
            self.telemetry.append(dict(test_id=test.id(), state=state,
                                       elapsed_ns=None if state == 'skipped' else ended - started))
        else:
            self.telemetry_truncated = True
        super().stopTest(test)


class TelemetryRunner(unittest.TextTestRunner):
    """Run ordinary unittest semantics with an optional advisory document."""
    resultclass = TelemetryResult

    def run(self, test):
        selected = test.countTestCases()
        before = resource.getrusage(resource.RUSAGE_SELF)
        result = super().run(test)
        after = resource.getrusage(resource.RUSAGE_SELF)
        result.telemetry_process = dict(scope="runner-process", user_cpu_seconds=after.ru_utime - before.ru_utime,
                                        system_cpu_seconds=after.ru_stime - before.ru_stime,
                                        peak_rss_bytes=after.ru_maxrss * 1024 if sys.platform.startswith("linux") else None,
                                        rss_scope="process-lifetime-high-water", aggregate_peak_rss_bytes=None)
        result.telemetry_selected = selected
        result.telemetry_complete = (not result.telemetry_truncated and len(result.telemetry) == selected)
        return result


def document(result, action_id, index):
    """Build producer output after the suite terminates, preserving partial runs."""
    return dict(version=VERSION, producer='python-unittest-v1', action_id=action_id,
                member_id=member_id(action_id, index), selected=result.telemetry_selected,
                complete=result.telemetry_complete, selection_scope='loaded-unittest-suite',
                tests=result.telemetry, process=result.telemetry_process)


def write_document(path, record):
    """Publish advisory data atomically; failure cannot change a test verdict."""
    temporary = None
    try:
        encoded = json.dumps(record, allow_nan=False, sort_keys=True).encode('utf-8')
        if len(encoded) > MAX_BYTES:
            return False
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = output.name
            output.write(encoded)
        os.replace(temporary, path)
        temporary = None
        return True
    except (OSError, ValueError, TypeError, UnicodeError):
        return False
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def main(argv=None):
    """Supported unittest module entry point; status comes only from the suite."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action-id', required=True)
    parser.add_argument('--member', type=int, default=0)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument('--output')
    destination.add_argument('--output-directory-env', help='optional per-request sidecar directory from inherited environment')
    parser.add_argument('tests', nargs='+', help='unittest module or qualified test names')
    args = parser.parse_args(argv)
    member_id(args.action_id, args.member)
    suite = unittest.defaultTestLoader.loadTestsFromNames(args.tests)
    result = TelemetryRunner(verbosity=2).run(suite)
    output = args.output
    if args.output_directory_env:
        directory = os.environ.get(args.output_directory_env)
        # Canonical action IDs are path components in this directory mode.
        safe_id = args.action_id.replace('/', '_').replace('\\', '_')
        output = str(Path(directory) / f'{safe_id}.member.{args.member}.json') if directory else None
    if output is not None:
        write_document(output, document(result, args.action_id, args.member))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
