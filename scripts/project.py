#!/usr/bin/env python3
"""Check a project, inspect bounded context, and run explicitly declared tests."""
import argparse
from contextlib import redirect_stderr
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import sys
import subprocess
import time

import navigate
import verify
from verification.core import run_manifest, tree


def identity(compiler, entry, manifest):
    return {'compiler_sha256': hashlib.sha256(navigate.bounded_read(compiler, 256 * 1024 * 1024)).hexdigest(),
            'sources': navigate.sources(entry.parent),
            'project_files': tree(entry.parent),
            'manifest_sha256': hashlib.sha256(navigate.bounded_read(manifest, 4 * 1024 * 1024)).hexdigest()}


def diagnostics(compiler, entry):
    row = verify.command([str(compiler), 'check-project', str(entry), '--diagnostics=json'], entry.parent,
                         {'timeout': 60, 'max_output_bytes': 65536})
    return row


def run(compiler, entry, manifest, *, query='', symbol=None, cache_dir=None, patterns=()):
    compiler, entry, manifest = (Path(p).resolve(strict=True) for p in (compiler, entry, manifest))
    if manifest.parent != entry.parent:
        raise ValueError('verification manifest must be beside the entry; commands run from that project root')
    cache_dir = Path(cache_dir) if cache_dir else Path.home() / ".cache" / "mylang-project"
    started = time.monotonic()
    before = identity(compiler, entry, manifest)
    report = {'version': 'project-workflow-v1', 'captured_utc': datetime.now(timezone.utc).isoformat(),
              'identity': before, 'status': 'failed', 'navigation': None, 'verification': None,
              'coverage': 'declared tests only; static impact does not select or prove test coverage'}
    try:
        index, cached = navigate.load(compiler, entry, cache_dir / 'navigation' if cache_dir else None)
        report['navigation'] = navigate.query(index, text=query, symbol=symbol, relation='context')
        report['navigation_cache_hit'] = cached
        report['check_passed'] = index['checked']
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        report['navigation_error'] = str(error)
        report['check_passed'] = False
    if not report['check_passed']:
        report['diagnostics'] = diagnostics(compiler, entry)
    else:
        verification_log = io.StringIO()
        try:
            with redirect_stderr(verification_log):
                verification = run_manifest(manifest, cache_dir=cache_dir / 'verification', patterns=patterns, mode='full')
            report['verification'] = verification
            selected = set(verification['selected'])
            rows = [row for row in verification['steps'] if row['id'] in selected]
            tests = [row for row in rows if row.get('kind', row.get('definition', {}).get('kind')) in ('test', 'parity', 'mutation')]
            report['declared_test_steps'] = len(tests)
            report['status'] = 'passed' if verification['selected_passed'] and tests else 'failed'
            if not tests:
                report['error'] = 'no selected test, parity, or mutation step; compilation alone is not test acceptance'
        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
            report.update(status='infrastructure-failure', error=str(error))
        finally:
            report['verification_log'] = verification_log.getvalue()
    try:
        report['identity_unchanged'] = identity(compiler, entry, manifest) == before
    except (OSError, ValueError) as error:
        report.update(identity_unchanged=False, identity_error=str(error))
    if not report['identity_unchanged']:
        report['status'] = 'stale'
    report['elapsed_seconds'] = time.monotonic() - started
    return report


def excerpt(value, limit=512):
    value = str(value)
    return value if len(value) <= limit else value[:limit] + '… [see full report]'


def failure_summary(row):
    result = {key: row[key] for key in ('exit', 'timed_out', 'cancelled', 'output_truncated') if key in row}
    for key in ('id', 'status', 'reason', 'note', 'error', 'stdout', 'stderr'):
        if row.get(key):
            result[key] = excerpt(row[key])
    definition = row.get('definition', {})
    expected = {key: excerpt(definition[key]) for key in ('expect_stdout', 'expect_stderr_contains', 'expect_exit') if key in definition}
    if expected:
        result['expected'] = expected
    commands = row.get('commands', [])
    failed_commands = [command for command in commands if not command.get('passed', False)]
    # Parity can fail even when all individual commands succeed.
    shown = failed_commands or commands
    if shown:
        result['commands'] = [failure_summary(command) for command in shown[:2]]
        result['commands_omitted'] = max(0, len(shown) - 2)
    return result


def compact(report, report_path=None):
    """A bounded receipt; all inventories, context, and streams stay in the report."""
    result = {key: report[key] for key in ('status', 'captured_utc', 'check_passed',
                                          'identity_unchanged', 'elapsed_seconds', 'declared_test_steps') if key in report}
    result.update(version='project-feedback-v1', report_version=report.get('version'))
    if report_path is not None:
        result['report_path'] = str(Path(report_path).resolve())
    for key in ('error', 'identity_error', 'navigation_error'):
        if key in report:
            result[key] = excerpt(report[key])
    if 'identity' in report:
        original = report['identity']
        result['identity'] = {key: original[key] for key in ('compiler_sha256', 'manifest_sha256') if key in original}
        for key in ('sources', 'project_files'):
            if key in original:
                encoded = json.dumps(original[key], sort_keys=True, separators=(',', ':')).encode()
                result['identity'][key + '_sha256'] = hashlib.sha256(encoded).hexdigest()
    if 'diagnostics' in report:
        result['diagnostics'] = failure_summary(report['diagnostics'])
    verification = report.get('verification')
    if verification is not None:
        selected = set(verification['selected'])
        rows = [row for row in verification['steps'] if row['id'] in selected]
        passed = lambda row: row.get('passed', row.get('status') == 'passed')
        result['verification'] = {'selected_passed': verification['selected_passed'],
                                  'full_manifest_passed': verification['full_manifest_passed'],
                                  'step_counts': {
                                      'total': len(verification['steps']), 'selected': len(rows),
                                      'passed': sum(bool(passed(row)) for row in rows),
                                      'failed': sum(not passed(row) and row.get('status') != 'blocked' for row in rows),
                                      'blocked': sum(row.get('status') == 'blocked' for row in rows),
                                      'executed': sum(bool(row.get('executed')) for row in rows),
                                      'cached': sum(row.get('status') == 'cached' or bool(row.get('cache_hit')) for row in rows)},
                                  'test_case_count': None,
                                  'coverage': 'declared verification steps; individual test cases are not counted'}
        failures = [row for row in rows if not passed(row)]
        if failures:
            result['verification']['failures'] = [failure_summary(row) for row in failures[:3]]
            result['verification']['failures_omitted'] = max(0, len(failures) - 3)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--entry', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--query', default='')
    parser.add_argument('--symbol')
    parser.add_argument('--only', action='append', default=[])
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--report', type=Path, required=True, help='new full evidence file; existing files are never replaced')
    parser.add_argument('--details', action='store_true', help='also print the full report instead of a compact receipt')
    args = parser.parse_args()
    if args.report.exists():
        print(json.dumps({'version': 'project-feedback-v1', 'status': 'infrastructure-failure',
                          'error': 'report already exists; choose a new attempt path'}))
        return 2
    try:
        report = run(args.compiler, args.entry, args.manifest, query=args.query, symbol=args.symbol,
                     cache_dir=args.cache_dir, patterns=args.only)
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        report = {'version': 'project-workflow-v1', 'status': 'infrastructure-failure',
                  'captured_utc': datetime.now(timezone.utc).isoformat(), 'error': str(error)}
    try:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open('x') as stream:
            json.dump(report, stream, indent=2)
            stream.write('\n')
    except OSError as error:
        print(json.dumps({'version': 'project-feedback-v1', 'status': 'infrastructure-failure',
                          'error': excerpt('could not preserve attempt: ' + str(error)), 'attempt': compact(report)}))
        return 2
    print(json.dumps(dict(report, report_path=str(args.report.resolve())) if args.details else compact(report, args.report)))
    return 0 if report['status'] == 'passed' else 2 if report['status'] == 'infrastructure-failure' else 1


if __name__ == '__main__':
    sys.exit(main())
