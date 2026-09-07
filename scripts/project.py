#!/usr/bin/env python3
"""Check a project, inspect bounded context, and run explicitly declared tests."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time

import navigate
import verify
from verification.core import run_manifest


def identity(compiler, entry, manifest):
    return {'compiler_sha256': hashlib.sha256(navigate.bounded_read(compiler, 256 * 1024 * 1024)).hexdigest(),
            'sources': navigate.sources(entry.parent),
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
    except (OSError, ValueError, TypeError, KeyError) as error:
        report['navigation_error'] = str(error)
        report['check_passed'] = False
    if not report['check_passed']:
        report['diagnostics'] = diagnostics(compiler, entry)
    else:
        verification = run_manifest(manifest, cache_dir=cache_dir / 'verification' if cache_dir else None,
                                    patterns=patterns, mode='full')
        report['verification'] = verification
        selected = set(verification['selected'])
        rows = [row for row in verification['steps'] if row['id'] in selected]
        declared_tests = [row for row in rows if row.get('kind', row.get('definition', {}).get('kind')) in ('test', 'parity', 'mutation')]
        report['declared_test_steps'] = len(declared_tests)
        report['status'] = 'passed' if verification['selected_passed'] and declared_tests else 'failed'
        if not declared_tests:
            report['error'] = 'no selected test, parity, or mutation step; compilation alone is not test acceptance'
    report['identity_unchanged'] = identity(compiler, entry, manifest) == before
    if not report['identity_unchanged']:
        report['status'] = 'stale'
    report['elapsed_seconds'] = time.monotonic() - started
    return report


def compact(report):
    result = {key: value for key, value in report.items() if key != 'verification'}
    verification = report.get('verification')
    if verification is not None:
        result['verification'] = {'selected_passed': verification['selected_passed'],
                                  'full_manifest_passed': verification['full_manifest_passed'],
                                  'steps': [{key: row[key] for key in ('id', 'status', 'selected', 'executed', 'cache_hit') if key in row}
                                            for row in verification['steps']]}
        failures = [row for row in verification['steps'] if row['id'] in verification['selected'] and not row.get('passed', row.get('status') == 'passed')]
        if failures:
            result['verification']['failures'] = failures
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
    args = parser.parse_args()
    try:
        if args.report.exists():
            raise ValueError('report already exists; choose a new attempt path')
        report = run(args.compiler, args.entry, args.manifest, query=args.query, symbol=args.symbol,
                     cache_dir=args.cache_dir, patterns=args.only)
        # Exclusive create retains attempts and prevents accidental concurrent overwrite.
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open('x') as stream:
            json.dump(report, stream, indent=2)
            stream.write('\n')
        print(json.dumps(compact(report)))
        return 0 if report['status'] == 'passed' else 1
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({'version': 'project-workflow-v1', 'status': 'infrastructure-failure', 'error': str(error)}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
