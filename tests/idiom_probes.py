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

``cpython_oracle`` runs one probe under CPython with ``runpy`` and reports the
exit status ``main()``'s value implies. It is shared with ``velocity/score.py``,
the lane C scorer, so the two instruments cannot disagree about what CPython
does (backlog item V0).
"""
import argparse
import glob
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests' / 'fixtures' / 'idioms'
MANIFEST = FIXTURES / 'manifest.json'
TIMEOUT = 60

# Run the probe with runpy, call main(), and exit with that value's low byte.
# The status travels as the driver's own exit status, so the probe's stdout is
# exactly what CPython produced and nothing else is mixed into it.
CPYTHON_DRIVER = '''
import runpy
import sys

namespace = runpy.run_path(sys.argv[1], run_name="idiom_probe")
main = namespace.get("main")
if main is None:
    sys.stderr.write("idiom-oracle-error: probe defines no main()\\n")
    sys.exit(1)
value = main()
sys.exit(0 if value is None else int(value) & 0xFF)
'''
ORACLE_ERROR_PREFIX = 'idiom-oracle-error: '
TRACEBACK_HEADER = 'Traceback (most recent call last)'


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
    return oracle_self_test()


def oracle_self_test():
    """Exercise the CPython oracle against known statuses and stdout."""
    cases = [
        ('value becomes the exit status',
         'def main() -> int:\n    print("hi")\n    return 6\n', 6, 'hi\n'),
        ('none exits zero', 'def main():\n    print("none")\n', 0, 'none\n'),
        ('high values truncate', 'def main() -> int:\n    return 300\n', 300 & 0xFF, ''),
        ('a missing main is an oracle error', 'x = 1\n', None, None),
        ('a raising probe is an oracle error',
         'def main() -> int:\n    raise ValueError("boom")\n', None, None),
    ]
    failures = []
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'probe.my'
        for name, source, status, stdout in cases:
            path.write_text(source)
            observed = cpython_oracle(path)
            if status is None:
                if observed['ok']:
                    failures.append(name)
            elif (not observed['ok'] or observed['status'] != status or
                  observed['stdout'] != stdout):
                failures.append(name)
    if failures:
        print('cpython oracle self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'cpython oracle self-test: {len(cases)} passed')
    return 0


def run_probe(compiler, path):
    """Run one probe and capture what the compiler said."""
    completed = subprocess.run(
        [str(compiler), 'run', str(path), '--print-result'],
        capture_output=True, text=True, timeout=TIMEOUT)
    return {'status': completed.returncode, 'stdout': completed.stdout, 'stderr': completed.stderr}


def cpython_oracle(path, timeout=TIMEOUT):
    """Run one probe under CPython and report the outcome ``main()`` implies.

    The probe executes with ``runpy`` under a non-``__main__`` name, so a
    ``if __name__ == "__main__"`` guard does not run it twice, and ``main()`` is
    called once. Its return value is truncated to the low byte exactly as the
    language truncates a ``def main() -> int`` value, and ``None`` means success.

    A returned mapping always carries ``status`` (``None`` when the oracle
    failed), ``stdout``, ``stderr``, ``error`` and ``ok``. ``ok`` is false for a
    probe that raises, defines no ``main``, or times out; a caller must not
    compare a probe's output against an oracle that did not answer.
    """
    try:
        completed = subprocess.run(
            [sys.executable, '-c', CPYTHON_DRIVER, str(path)],
            capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as expired:
        stdout = expired.stdout or ''
        stderr = expired.stderr or ''
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors='replace')
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors='replace')
        return {'status': None, 'stdout': stdout, 'stderr': stderr, 'ok': False,
                'error': f'timeout after {timeout}s'}
    except OSError as error:
        return {'status': None, 'stdout': '', 'stderr': '', 'ok': False,
                'error': f'cannot start {sys.executable}: {error}'}
    error = None
    if ORACLE_ERROR_PREFIX in completed.stderr:
        error = completed.stderr.split(ORACLE_ERROR_PREFIX, 1)[1].strip()
    elif TRACEBACK_HEADER in completed.stderr:
        error = 'probe raised under CPython'
    elif completed.returncode < 0:
        error = f'oracle killed by signal {-completed.returncode}'
    return {'status': completed.returncode, 'stdout': completed.stdout,
            'stderr': completed.stderr, 'ok': error is None, 'error': error}


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
