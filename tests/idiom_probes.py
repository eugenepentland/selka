#!/usr/bin/env python3
"""Run the idiom probes that measure the simplification work.

Each probe under ``tests/fixtures/idioms`` is a small program that a Python
programmer would write, with two recorded outcomes in ``manifest.json``: the
``baseline`` it has today and the ``target`` the simplification plan requires.
A probe that meets its target is progress; a probe that matches its baseline is
unchanged; a probe that matches neither has moved and needs a human look.

The regression gate is ``must_pass``: probes that already meet their target must
keep meeting it. With ``--require-targets`` every probe must meet its target,
which is the mode to enable once the plan's workstreams have landed.
"""
import argparse
import glob
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests' / 'fixtures' / 'idioms'
MANIFEST = FIXTURES / 'manifest.json'
TIMEOUT = 60


def failed_run(result):
    """Whether stderr/status proves the guest did not complete normally."""
    stderr = result['stderr']
    return (result['status'] < 0 or 'error[' in stderr or
            'host failure:' in stderr or 'QBE runtime failure' in stderr or
            stderr.startswith('mylang:') or stderr.startswith('usage:'))


def matches(result, expected):
    """Whether one run satisfies a recorded expectation."""
    diagnostic = 'code' in expected or 'stderr_contains' in expected
    if diagnostic:
        if result['status'] != expected['status']:
            return False
    elif 'stdout' in expected:
        # A completed integer-valued main exits with that integer.  For value
        # probes, failure diagnostics distinguish completion from a compiler
        # error or trap; warnings remain compatible with successful completion.
        # The exact process status is deliberately not part of the expectation.
        if failed_run(result):
            return False
    elif result['status'] != expected['status']:
        return False
    if 'stdout' in expected and result['stdout'].strip() != expected['stdout'].strip():
        return False
    if 'code' in expected and ('error[' + expected['code'] + ']') not in result['stderr']:
        return False
    if 'stderr_contains' in expected and expected['stderr_contains'] not in result['stderr']:
        return False
    return True


def self_test():
    """Exercise value and diagnostic expectation classification."""
    cases = [
        ('value uses printed result, not exit status',
         {'status': 6, 'stdout': '6\n', 'stderr': ''},
         {'status': 0, 'stdout': '6'}, True),
        ('wrong printed result fails',
         {'status': 6, 'stdout': '7\n', 'stderr': ''},
         {'status': 0, 'stdout': '6'}, False),
        ('runtime trap is not completion',
         {'status': 1, 'stdout': '6\n', 'stderr': 'error[R_ASSERT]: trap\n'},
         {'status': 0, 'stdout': '6'}, False),
        ('compiler error is not completion',
         {'status': 1, 'stdout': '', 'stderr': 'error[E_TYPE]: mismatch\n'},
         {'status': 0, 'stdout': ''}, False),
        ('warning does not hide completion',
         {'status': 6, 'stdout': '6\n', 'stderr': 'warning[W_UNUSED]: note\n'},
         {'status': 0, 'stdout': '6'}, True),
        ('diagnostic checks exact status and code',
         {'status': 1, 'stdout': '', 'stderr': 'error[E_TYPE]: mismatch\n'},
         {'status': 1, 'code': 'E_TYPE'}, True),
        ('diagnostic rejects a different status',
         {'status': 2, 'stdout': '', 'stderr': 'error[E_TYPE]: mismatch\n'},
         {'status': 1, 'code': 'E_TYPE'}, False),
        ('diagnostic substring matches',
         {'status': 1, 'stdout': '', 'stderr': 'error: canonical replacement is len(x)\n'},
         {'status': 1, 'stderr_contains': 'len(x)'}, True),
    ]
    failures = [name for name, observed, expected, wanted in cases
                if matches(observed, expected) != wanted]
    if failures:
        print('idiom classifier self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'idiom classifier self-test: {len(cases)} passed')
    return 0


def run_probe(compiler, path):
    """Run one probe and capture what the compiler said."""
    completed = subprocess.run(
        [str(compiler), 'run', str(path), '--print-result'],
        capture_output=True, text=True, timeout=TIMEOUT)
    return {'status': completed.returncode, 'stdout': completed.stdout, 'stderr': completed.stderr}


def first_line(text):
    """The diagnostic line of captured output, for one-line reporting."""
    for line in text.splitlines():
        if 'error[' in line or 'warning[' in line:
            return line.strip()
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ''


def classify(record, observed):
    """Name where a probe stands relative to its baseline and target."""
    if matches(observed, record['target']):
        return 'target'
    if matches(observed, record['baseline']):
        return 'baseline'
    return 'changed'


def observed_detail(row):
    """One line describing what a probe actually did."""
    return row['observed']['stdout'].strip() or first_line(row['observed']['stderr'])


def load_manifest():
    """Read the probe manifest and check it agrees with the fixture directory."""
    manifest = json.loads(MANIFEST.read_text())
    names = {probe['name'] for probe in manifest['probes']}
    files = {Path(path).stem for path in glob.glob(str(FIXTURES / '*.my'))}
    missing = sorted(name for name in names if name not in files)
    orphan = sorted(name for name in files if name not in names)
    if missing or orphan:
        raise SystemExit(f'manifest and fixtures disagree: missing {missing}, unlisted {orphan}')
    return manifest['probes']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--self-test', action='store_true',
                        help='test expectation classification without running probes')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--filter', default='*', help='glob matched against probe names')
    parser.add_argument('--require-targets', action='store_true',
                        help='fail unless every selected probe meets its target')
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.compiler is None:
        parser.error('--compiler is required unless --self-test is used')

    compiler = args.compiler.resolve()
    probes = [probe for probe in load_manifest()
              if glob.fnmatch.fnmatch(probe['name'], args.filter)]
    rows, groups = [], {}
    for probe in probes:
        observed = run_probe(compiler, FIXTURES / (probe['name'] + '.my'))
        state = classify(probe, observed)
        groups.setdefault(probe['group'], []).append(state)
        rows.append({'name': probe['name'], 'group': probe['group'], 'audit': probe['audit'],
                     'state': state, 'must_pass': probe['must_pass'],
                     'note': probe['note'], 'observed': observed})
        if args.verbose:
            detail = observed['stdout'].strip() or first_line(observed['stderr'])
            print(f"{state:9s} {probe['name']:26s} {detail[:90]}")

    regressions = [row for row in rows if row['must_pass'] and row['state'] != 'target']
    targets = [row for row in rows if row['state'] == 'target']
    changed = [row for row in rows if row['state'] == 'changed']

    print(f"idiom probes: {len(rows)} selected, {len(targets)} at target, "
          f"{len(rows) - len(targets)} not yet")
    for group in sorted(groups):
        states = groups[group]
        print(f"  {group:14s} {states.count('target'):3d}/{len(states):3d} at target")
    if regressions:
        print('\nregressions (must_pass probes that no longer meet their target):')
        for row in regressions:
            print(f"  {row['name']}: {observed_detail(row)}")
    if changed:
        print('\nchanged (neither baseline nor target — review these):')
        for row in changed:
            print(f"  {row['name']}: {observed_detail(row)}")

    if args.output:
        args.output.write_text(json.dumps({
            'version': 'idiom-probes-report-v1',
            'compiler': str(compiler),
            'selected': len(rows),
            'at_target': len(targets),
            'regressions': [row['name'] for row in regressions],
            'changed': [row['name'] for row in changed],
            'probes': [{'name': row['name'], 'group': row['group'], 'state': row['state']}
                       for row in rows]}, indent=1) + '\n')

    if regressions:
        return 1
    if args.require_targets and len(targets) != len(rows):
        print('\n--require-targets: not every selected probe meets its target')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
