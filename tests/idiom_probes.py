#!/usr/bin/env python3
"""Run the idiom probes that measure the simplification work.

Each probe under ``tests/fixtures/idioms`` is a small program that a Python
programmer would write, with two recorded outcomes in ``manifest.json``: the
``baseline`` it has today and the ``target`` the simplification plan requires.
A probe that meets its target is progress; a probe that matches its baseline is
unchanged; a probe that matches neither has moved and needs a human look.

The regression gate is ``must_pass``: probes that already meet their target must
keep meeting it. An explicit ``retired`` expectation checks an exact removal
diagnostic while preserving the historical baseline and target. Such probes
must reject rather than resume accepting the retired syntax. With
``--require-targets`` every probe must meet its target or retirement contract,
which is the mode to enable once the plan's workstreams have landed.

``cpython_oracle`` runs one probe under CPython with ``runpy`` and reports the
exit status ``main()``'s value implies. It is shared with ``velocity/score.py``,
the lane C scorer, so the two instruments cannot disagree about what CPython
does (backlog item V0).
"""
import argparse
import concurrent.futures
import glob
import json
import os
import re
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests' / 'fixtures' / 'idioms'
MANIFEST = FIXTURES / 'manifest.json'

# "The probe must finish" and "the probe must finish soon" are different
# promises, and only the first one belongs in a test. A `selka run` is a whole
# build (check, lower, emit, `zig cc`, link) and then the program: about 5 CPU
# seconds for the first probe after a compiler edit, which has to build the
# runtime, and 12 for the whole corpus; a machine at load 60 gives it a few
# percent of a core, so any wall-clock budget that is not enormous fails there
# and passes alone in a second (the 60 s limit this replaces did, twice).
# What a probe needs is a CPU bound: a hang burns CPU and a loaded machine does
# not add any, so `CPU_LIMIT` stops a runaway at the same point under any load.
# `STUCK_LIMIT` only ends a probe that makes no use of the CPU at all (a
# deadlock); it is a ceiling under the build step's 30 minute deadline that
# still lets the whole corpus finish at about 1% of a core, never a budget.
CPU_LIMIT = 120
STUCK_LIMIT = 1200
# The oracle runs CPython on a few lines: milliseconds of CPU, so a minute of
# wall time is generous even at 1% of a core.
ORACLE_TIMEOUT = 60
CPU_MARKER = 'idiom-probe: stopped at the CPU limit of '
STUCK_MARKER = 'idiom-probe: no result after the wall-clock ceiling of '

# Starts the probe with a CPU limit on every process it creates and says so
# when the limit is what ended it. `RLIMIT_CPU` counts each process's own time,
# so the limit is inherited by the compiler, `zig cc` and the program, and the
# kernel sends SIGXCPU to whichever one spins. `selka run` reports a program
# killed by a signal as exit status 128 + the signal, so the status alone cannot
# tell the limit from a program that returns 152; the CPU actually consumed can
# (the kernel counts in ticks, so half the limit is the test, not all of it).
CPU_LAUNCHER = '''
import os
import resource
import signal
import subprocess
import sys

cap = int(sys.argv[1])
resource.setrlimit(resource.RLIMIT_CPU, (cap, cap + 10))
status = subprocess.call(sys.argv[3:])
used = resource.getrusage(resource.RUSAGE_CHILDREN)
if used.ru_utime + used.ru_stime >= cap / 2 and status in (-signal.SIGXCPU, 128 + signal.SIGXCPU):
    sys.stderr.write(sys.argv[2] + str(cap) + " CPU seconds\\n")
if status < 0:
    signal.signal(-status, signal.SIG_DFL)
    os.kill(os.getpid(), -status)
sys.exit(status)
'''

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

# A host failure is the toolchain's problem, not the guest's: the native backend
# drives zig as its assembler and linker, and a global cache the process cannot
# write fails the link with `manifest_create ReadOnlyFileSystem` and
# `selka: host failure: NativeToolFailed`. A caller must never count that as a
# guest rejection, or a broken environment reads as a language defect.
HOST_FAILURE_MARKERS = ('host failure:', 'NativeToolFailed', 'ReadOnlyFileSystem')


def failed_run(result):
    """Whether stderr/status proves the guest did not complete normally."""
    stderr = result['stderr']
    return (result['status'] < 0 or 'error[' in stderr or
            'host failure:' in stderr or 'QBE runtime failure' in stderr or
            stderr.startswith('selka:') or stderr.startswith('usage:'))


def host_failure(result):
    """Whether a failed run failed for a host reason rather than a guest one.

    The distinction matters to the scorer: a host failure is a broken
    measurement, and counting it as a rejection would put a toolchain problem in
    the C3 denominator and hide a probe that never ran.
    """
    stderr = result['stderr']
    return any(marker in stderr for marker in HOST_FAILURE_MARKERS)


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
    host_cases = [
        ('read-only zig cache is a host failure',
         {'status': 2, 'stdout': '', 'stderr': 'error: sub-compilation of compiler_rt failed\n'
                                              '    note: failed to check cache: '
                                              'manifest_create ReadOnlyFileSystem\n'},
         True),
        ('a missing tool is a host failure',
         {'status': 2, 'stdout': '', 'stderr': 'selka: host failure: NativeToolFailed\n'}, True),
        ('a guest diagnostic is not a host failure',
         {'status': 1, 'stdout': '', 'stderr': 'p.selka:1:1: error[E_TYPE]: mismatch\n'}, False),
        ('a clean trap is not a host failure',
         {'status': 1, 'stdout': '', 'stderr': 'error[R_ASSERT]: trap\n'}, False),
    ]
    failures += [name for name, observed, wanted in host_cases
                 if host_failure(observed) != wanted]
    if failures:
        print('idiom classifier self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'idiom classifier self-test: {len(cases) + len(host_cases)} passed')
    if retirement_self_test():
        return 1
    if bounds_self_test():
        return 1
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
        path = Path(directory) / 'probe.selka'
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


def stop_group(process):
    """Kill everything the probe started: the compiler, `zig cc`, the program."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_bounded(command, cpu_limit=CPU_LIMIT, stuck_limit=STUCK_LIMIT):
    """Run ``command`` and capture what it said, with the bounds described above.

    The result is ``status``, ``stdout`` and ``stderr`` as for any run, plus
    ``limit``: ``'cpu'`` when a process hit ``cpu_limit`` CPU seconds,
    ``'stuck'`` when ``stuck_limit`` wall seconds passed and the whole process
    group was killed, else ``None``. Either way stderr says so, so a probe that
    was stopped reads as one that did not complete and names the reason.
    """
    launcher = [sys.executable, '-I', '-S', '-c', CPU_LAUNCHER, str(cpu_limit), CPU_MARKER, *map(str, command)]
    process = subprocess.Popen(launcher, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True)
    limit = None
    try:
        stdout, stderr = process.communicate(timeout=stuck_limit)
    except subprocess.TimeoutExpired:
        stop_group(process)
        stdout, stderr = process.communicate()
        limit = 'stuck'
        stderr = f'{STUCK_MARKER}{stuck_limit} seconds\n{stderr}'
    if limit is None and CPU_MARKER in stderr:
        limit = 'cpu'
    return {'status': process.returncode, 'stdout': stdout, 'stderr': stderr, 'limit': limit}


def run_probe(compiler, path, cache_dir=None):
    """Run one probe and capture what the compiler said.

    `cache_dir` names the compiler's work directory. A caller that runs the whole corpus passes a private, empty one:
    a probe is a distinct program that is built once, so the replay and stage records of the repository's shared
    `.selka-cache/core` serve it nothing, while every `selka run` that opens a store pays to index every record in
    it (about 0.8 CPU-s a probe against the 9 GB that directory reaches). Unit objects and the runtime stay content-keyed
    in the per-user store, so a private directory does not rebuild them.
    """
    command = [compiler, 'run', path, '--print-result']
    if cache_dir is not None:
        command += ['--cache-dir', str(cache_dir)]
    return run_bounded(command)


def cpython_oracle(path, timeout=ORACLE_TIMEOUT):
    """Run one probe under CPython and report the outcome ``main()`` implies.

    The probe executes with ``runpy`` under a non-``__main__`` name, so a
    ``if __name__ == "__main__"`` guard does not run it twice, and ``main()`` is
    called once. Its return value is truncated to the low byte exactly as the
    language truncates a ``func main() -> int`` value, and ``None`` means success.

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


def matches_retirement(observed, expected):
    """Require the reviewed removal diagnostic, without accepting host failures."""
    if host_failure(observed) or not matches(observed, expected):
        return False
    codes = re.findall(r'error\[([^]]+)\]', observed['stderr'])
    return bool(codes) and set(codes) == {expected['code']}


def retirement_self_test():
    """Retirement cannot hide unexpected errors or restored old syntax."""
    expected = {'status': 1, 'code': 'E_GENERATOR_REMOVED'}
    record = {'target': {'status': 0, 'stdout': '42'},
              'baseline': {'status': 1, 'code': 'E_SYNTAX'}, 'retired': expected}
    cases = [
        ('reviewed removal', {'status': 1, 'stdout': '', 'stderr': 'error[E_GENERATOR_REMOVED]: removed'}, 'retired'),
        ('wrong removal', {'status': 1, 'stdout': '', 'stderr': 'error[E_TUPLE_REMOVED]: removed'}, 'changed'),
        ('wrong status', {'status': 2, 'stdout': '', 'stderr': 'error[E_GENERATOR_REMOVED]: removed'}, 'changed'),
        ('unexpected extra error', {'status': 1, 'stdout': '', 'stderr': 'error[E_GENERATOR_REMOVED]: removed\nerror[E_TYPE]: bad'}, 'changed'),
        ('host failure', {'status': 1, 'stdout': '', 'stderr': 'error[E_GENERATOR_REMOVED]: removed\nhost failure: NativeToolFailed'}, 'changed'),
        ('old target restored', {'status': 42, 'stdout': '42', 'stderr': ''}, 'changed'),
        ('old baseline restored', {'status': 1, 'stdout': '', 'stderr': 'error[E_SYNTAX]: old'}, 'changed'),
    ]
    failures = [name for name, observed, wanted in cases if classify(record, observed) != wanted]
    if failures:
        print('idiom retirement self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'idiom retirement self-test: {len(cases)} passed')
    return 0


SPIN = 'while True: pass'
# What `selka run` does when its program dies of a signal: exit 128 + signal.
SPIN_UNDER_PARENT = (
    'import subprocess, sys\n'
    f'status = subprocess.call([sys.executable, "-c", "{SPIN}"])\n'
    'sys.exit(128 - status if status < 0 else status)')
# A parent with a child of its own, as `selka run` has `zig cc` and the program.
PARENT_AND_CHILD = (
    'import subprocess, sys\n'
    'child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])\n'
    'print(child.pid, flush=True)\n'
    'child.wait()')


def process_finished(pid):
    """Whether ``pid`` is gone or a zombie: a killed process stays one until its subreaper reaps it."""
    try:
        stat = Path('/proc', str(pid), 'stat').read_text()
    except OSError:
        return True
    return stat.split(') ', 1)[1].split()[0] == 'Z'


def wait_finished(pid, tries=600):
    """Poll ``process_finished`` for up to a minute; the kill has already been sent."""
    for _ in range(tries):
        if process_finished(pid):
            return True
        time.sleep(0.1)
    return False


def bounds_self_test():
    """The bounds stop a runaway and an idle process, and nothing that finishes."""
    cases = [
        ('a finished run keeps its status and output', 'import sys; print("ok"); sys.exit(3)', {},
         lambda run: (run['status'], run['stdout'], run['limit']) == (3, 'ok\n', None)),
        ('a spinning process reaches the CPU limit', SPIN, {'cpu_limit': 1},
         lambda run: (run['status'], run['limit']) == (-signal.SIGXCPU, 'cpu') and CPU_MARKER in run['stderr']),
        ('a spinning child reported as 128 + signal reaches it too', SPIN_UNDER_PARENT, {'cpu_limit': 1},
         lambda run: (run['status'], run['limit']) == (128 + signal.SIGXCPU, 'cpu')),
        ('exiting 152 without the CPU is not the limit', 'import sys; sys.exit(152)', {'cpu_limit': 1},
         lambda run: (run['status'], run['limit']) == (152, None)),
        ('an idle process meets the wall ceiling', 'import time; time.sleep(600)', {'stuck_limit': 1},
         lambda run: (run['status'], run['limit']) == (-signal.SIGKILL, 'stuck') and STUCK_MARKER in run['stderr']),
    ]
    failures = [name for name, code, limits, holds in cases
                if not holds(run_bounded([sys.executable, '-c', code], **limits))]
    # The ceiling must take the processes under the probe with it, or a stuck
    # `selka run` leaves its `zig cc` and its program behind.
    tree = subprocess.Popen([sys.executable, '-c', PARENT_AND_CHILD], stdout=subprocess.PIPE,
                            text=True, start_new_session=True)
    child = int(tree.stdout.readline())
    stop_group(tree)
    tree.wait()
    tree.stdout.close()
    if not wait_finished(child):
        failures.append('the whole process group is killed')
    if failures:
        print('idiom bounds self-test failed: ' + ', '.join(failures), file=sys.stderr)
        return 1
    print(f'idiom bounds self-test: {len(cases) + 1} passed')
    return 0


def classify(record, observed):
    """Name where a probe stands relative to its current reviewed contract."""
    if 'retired' in record:
        return 'retired' if matches_retirement(observed, record['retired']) else 'changed'
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
    for probe in manifest['probes']:
        if 'retired' in probe:
            expected = probe['retired']
            if (set(expected) != {'status', 'code'} or expected['status'] != 1 or
                    not re.fullmatch(r'E_[A-Z_]+_REMOVED', expected['code'])):
                raise SystemExit(f"invalid retirement expectation for {probe['name']}")
    names = {probe['name'] for probe in manifest['probes']}
    files = {Path(path).stem for path in glob.glob(str(FIXTURES / '*.selka'))}
    missing = sorted(name for name in names if name not in files)
    orphan = sorted(name for name in files if name not in names)
    if missing or orphan:
        raise SystemExit(f'manifest and fixtures disagree: missing {missing}, unlisted {orphan}')
    return manifest['probes']


def default_jobs():
    """Concurrent probes: `SELKA_JOBS` when set, else the cores up to 8."""
    try:
        return max(1, int(os.environ['SELKA_JOBS']))
    except (KeyError, ValueError):
        return max(1, min(8, os.cpu_count() or 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--self-test', action='store_true',
                        help='test expectation classification without running probes')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--filter', default='*', help='glob matched against probe names')
    parser.add_argument('--require-targets', action='store_true',
                        help='fail unless every selected probe meets its target or retirement contract')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--jobs', type=int, default=default_jobs(),
                        help='probes compiled and run at once (default: SELKA_JOBS, else up to 8)')
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.compiler is None:
        parser.error('--compiler is required unless --self-test is used')

    compiler = args.compiler.resolve()
    probes = [probe for probe in load_manifest()
              if glob.fnmatch.fnmatch(probe['name'], args.filter)]
    rows, groups = [], {}
    # Every probe is an independent `selka run`; running them concurrently keeps
    # the report in manifest order while the build waits on the slowest few.
    with tempfile.TemporaryDirectory(prefix='idiom-probes-work-') as work, \
            concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        outcomes = list(pool.map(lambda probe: run_probe(compiler, FIXTURES / (probe['name'] + '.selka'), work), probes))
    for probe, observed in zip(probes, outcomes):
        state = classify(probe, observed)
        groups.setdefault(probe['group'], []).append(state)
        rows.append({'name': probe['name'], 'group': probe['group'], 'audit': probe['audit'],
                     'state': state, 'must_pass': probe['must_pass'],
                     'note': probe['note'], 'observed': observed})
        if args.verbose:
            detail = observed['stdout'].strip() or first_line(observed['stderr'])
            print(f"{state:9s} {probe['name']:26s} {detail[:90]}")

    regressions = [row for row in rows if row['must_pass'] and row['state'] not in ('target', 'retired')]
    targets = [row for row in rows if row['state'] == 'target']
    retired = [row for row in rows if row['state'] == 'retired']
    changed = [row for row in rows if row['state'] == 'changed']

    print(f"idiom probes: {len(rows)} selected, {len(targets)} at target, "
          f"{len(retired)} retired, {len(rows) - len(targets) - len(retired)} not yet")
    for group in sorted(groups):
        states = groups[group]
        print(f"  {group:14s} {states.count('target'):3d}/{len(states):3d} at target, {states.count('retired')} retired")
    if regressions:
        print('\nregressions (must_pass probes that no longer meet their current contract):')
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
            'retired': [row['name'] for row in retired],
            'regressions': [row['name'] for row in regressions],
            'changed': [row['name'] for row in changed],
            'probes': [{'name': row['name'], 'group': row['group'], 'state': row['state']}
                       for row in rows]}, indent=1) + '\n')

    if regressions:
        return 1
    if args.require_targets and len(targets) + len(retired) != len(rows):
        print('\n--require-targets: not every selected probe meets its target or retirement contract')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
