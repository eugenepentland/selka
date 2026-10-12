#!/usr/bin/env python3
"""Combine explicit candidate receipts without borrowing mixed-revision evidence."""
# spec: NEW-CORE-ZERO-RC-LIBRARY-1
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODES = ('release', 'debug', 'verified', 'optimized-debug', 'no-facts')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports', nargs='+', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--stage', choices=('C1', 'C2', 'C3'), required=True)
    args = parser.parse_args()
    rows = []
    failures = []
    identities = set()
    report_files = []
    for path in args.reports:
        path = path.resolve()
        data = json.loads(path.read_text())
        identity = (data.get('compiler_source_revision'), data.get('compiler_sha256'))
        identities.add(identity)
        report_files.append({'path': str(path), 'sha256': digest(path)})
        if not all(identity):
            failures.append({'report': str(path), 'reason': 'missing compiler identity'})
        if data.get('overlay') or data.get('check_only'):
            failures.append({'report': str(path), 'reason': 'overlay or source-only positive report'})
        expected_selection = 'experimental-zero-rc' if args.stage == 'C1' else 'ordinary-command'
        if data.get('ownership_selection') != expected_selection:
            failures.append({'report': str(path), 'reason': 'wrong command ownership selection'})
        for name, modes in data.get('cases', {}).items():
            for mode, row in modes.items():
                if not row.get('passed'):
                    failures.append({'report': str(path), 'case': name, 'mode': mode,
                                     'reason': 'fixture failure'})
                if row.get('expected_refusal'):
                    continue
                source = row['original_source']
                current = ROOT / source
                if not current.is_file() or digest(current) != row['original_sha256']:
                    failures.append({'report': str(path), 'case': name, 'mode': mode,
                                     'reason': 'source differs from candidate checkout'})
                    continue
                if row.get('passed') and row.get('binary_sha256'):
                    rows.append({'source': source, 'case': name, 'mode': mode,
                                 'report': str(path), 'source_sha256': row['original_sha256'],
                                 'binary_sha256': row['binary_sha256']})
    if len(identities) != 1:
        failures.append({'reason': 'receipts do not use one compiler revision and binary'})
    exports = []
    for item in json.loads((HERE / 'exports.json').read_text())['exports']:
        evidence = [row for row in rows if row['source'] in item['source_coverage']]
        missing = [mode for mode in MODES if not any(row['mode'] == mode for row in evidence)]
        exports.append({'module': item['module'], 'name': item['name'], 'kind': item['kind'],
                        'contract': item['ownership_contract'], 'evidence': evidence,
                        'missing_modes': missing, 'qualified': not missing and not failures})
    result = {'stage': args.stage, 'compiler_identities': sorted(identities, key=str),
              'receipt_files': report_files, 'required_modes': MODES,
              'public_declarations': len(exports),
              'qualified_declarations': sum(row['qualified'] for row in exports),
              'receipt_failures': failures, 'exports': exports,
              'scope': 'Public export fixture contracts only; does not certify complete release gate, package ABI, performance or retirement.'}
    result['passed'] = not failures and all(row['qualified'] for row in exports)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(result['qualified_declarations'], 'of', len(exports), 'qualified;', len(failures), 'receipt failures')
    return not result['passed']


if __name__ == '__main__':
    raise SystemExit(main())
