#!/usr/bin/env python3
"""Bounded libFuzzer workers; orchestration receipts belong to the caller.

Each exploration starts from an immutable copy of the supplied initial corpus.
A bundle contains raw bytes, never coverage or an alleged engine checkpoint.
Only an explicitly supplied instrumented libFuzzer executable is supported.
"""
import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import signal
import stat
import subprocess
import sys

MAX_INPUTS = 4096
MAX_INPUT_BYTES = 1 << 20
MAX_CORPUS_BYTES = 16 << 20
MAX_BUNDLE_BYTES = 24 << 20
MAX_LOG_BYTES = 16 << 20
MAX_RUNS = 1_000_000
MAX_MINIMIZATIONS = 2
SCHEMA = 'libfuzzer-inline8-log-v1'
DONE = re.compile(r'^#(\d+)\s+DONE\b', re.MULTILINE)
FINISHED = re.compile(r'^Done (\d+) runs in ', re.MULTILINE)
EXECUTED = re.compile(r'^Executed (.+) in \d+ ms\s*$', re.MULTILINE)
COUNTERS = re.compile(r'^INFO: Loaded (\d+) modules?\s+\((\d+) inline 8-bit counters\)', re.MULTILINE)
COVERAGE = re.compile(r'^#\d+\s+DONE\s+cov:\s*(\d+)\b', re.MULTILINE)
STATISTIC = re.compile(r'^stat::([a-z_]+):\s*(\d+)\s*$', re.MULTILINE)


class CoverageError(ValueError):
    """An invalid or unsupported worker input, not a certified result."""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_bounded(path, limit):
    """Refuse symlinks/devices and bound allocation before consuming bytes."""
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    fd = os.open(path, flags)
    with os.fdopen(fd, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
            raise CoverageError('non-regular or oversized input: ' + str(path))
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise CoverageError('input grew beyond its bound: ' + str(path))
        return data


def bounded_inputs(items):
    inputs = {}
    total = 0
    for data in items:
        if len(data) > MAX_INPUT_BYTES:
            raise CoverageError('input exceeds byte bound')
        key = digest(data)
        if key in inputs:
            continue
        inputs[key] = data
        total += len(data)
        if len(inputs) > MAX_INPUTS or total > MAX_CORPUS_BYTES:
            raise CoverageError('corpus exceeds input or byte bound')
    return inputs


def directory_inputs(directory):
    directory = Path(directory)
    if directory.is_symlink() or not directory.is_dir():
        raise CoverageError('corpus must be a real directory')
    entries = sorted(directory.iterdir())
    if len(entries) > MAX_INPUTS:
        raise CoverageError('corpus exceeds entry bound')
    return bounded_inputs(read_bounded(path, MAX_INPUT_BYTES) for path in entries)



def manifest_inputs(directory, names):
    """Read exactly the coordinator's watched content-addressed membership."""
    if type(names) is not list or len(names) > MAX_INPUTS:
        raise CoverageError('invalid initial corpus manifest')
    if any(type(name) is not str or re.fullmatch(r'[0-9a-f]{64}', name) is None for name in names):
        raise CoverageError('invalid initial corpus digest')
    if len(set(names)) != len(names):
        raise CoverageError('duplicate initial corpus digest')
    def checked_bytes():
        for name in names:
            data = read_bounded(Path(directory) / name, MAX_INPUT_BYTES)
            if digest(data) != name:
                raise CoverageError('initial corpus manifest digest mismatch')
            yield data
    return bounded_inputs(checked_bytes())

def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CoverageError('duplicate JSON field')
        result[key] = value
    return result


def load_bundle(path):
    try:
        bundle = json.loads(read_bounded(path, MAX_BUNDLE_BYTES), object_pairs_hook=reject_duplicates)
        if (not isinstance(bundle, dict) or set(bundle) != {'version', 'kind', 'inputs'}
                or type(bundle['version']) is not int or bundle['version'] != 1
                or bundle['kind'] != 'raw-inputs' or not isinstance(bundle['inputs'], list)
                or len(bundle['inputs']) > MAX_INPUTS):
            raise CoverageError('unsupported corpus bundle')
        inputs = {}
        total = 0
        for row in bundle['inputs']:
            if not isinstance(row, dict) or set(row) != {'sha256', 'data'}:
                raise CoverageError('invalid corpus row')
            if not isinstance(row['data'], str) or len(row['data']) > ((MAX_INPUT_BYTES + 2) // 3) * 4:
                raise CoverageError('oversized or invalid encoded input')
            data = base64.b64decode(row['data'], validate=True)
            key = digest(data)
            if row['sha256'] != key or base64.b64encode(data).decode() != row['data'] or key in inputs:
                raise CoverageError('invalid digest, noncanonical encoding or duplicate input')
            total += len(data)
            if len(data) > MAX_INPUT_BYTES or total > MAX_CORPUS_BYTES:
                raise CoverageError('corpus exceeds byte bound')
            inputs[key] = data
        return inputs
    except (TypeError, UnicodeError, json.JSONDecodeError, base64.binascii.Error) as error:
        raise CoverageError('malformed corpus bundle') from error


def save_bundle(output, inputs):
    payload = {'version': 1, 'kind': 'raw-inputs', 'inputs': [
        {'sha256': key, 'data': base64.b64encode(data).decode()} for key, data in sorted(inputs.items())]}
    atomic_json(output / 'corpus.json', payload)


def atomic_json(path, payload):
    temporary = path.with_suffix(path.suffix + '.partial')
    temporary.write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')) + '\n')
    temporary.replace(path)


def output_directory(output):
    path = Path(output).absolute()
    if path.is_symlink():
        raise CoverageError('output must not be a symlink')
    path.mkdir(parents=True, exist_ok=True)
    if any(path.iterdir()):
        raise CoverageError('output directory must be empty')
    return path


def check_engine(engine):
    path = Path(engine).resolve(strict=True)
    if not path.is_file() or not os.access(path, os.X_OK):
        raise CoverageError('explicit engine must be an executable file')
    # The executable binds its embedded engine and instrumentation implementation.
    value = hashlib.sha256()
    with path.open('rb') as stream:
        while data := stream.read(1 << 20):
            value.update(data)
    return path, value.hexdigest()


def limits(parent):
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_LOG_BYTES, MAX_LOG_BYTES))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    # The supported Linux host also kills the direct engine on worker SIGKILL.
    if sys.platform == 'linux':
        if ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'cannot bind engine parent lifetime')
        if os.getppid() != parent:
            os.kill(os.getpid(), signal.SIGKILL)


def run_engine(command, log_path, wall_timeout):
    """Bound logs and wall time, including child processes on timeout/cancel."""
    child = None
    handlers = {}
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    try:
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            handlers[signum] = signal.signal(signum, interrupted)
        with log_path.open('wb') as log:
            parent = os.getpid()
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                     start_new_session=True, preexec_fn=lambda: limits(parent))
            try:
                status = child.wait(timeout=wall_timeout)
                return status, False
            except subprocess.TimeoutExpired:
                stop_engine(child)
                return child.returncode, True
    except BaseException:
        if child is not None:
            stop_engine(child)
        raise
    finally:
        if child is not None:
            stop_engine(child)
        for signum, handler in handlers.items():
            signal.signal(signum, handler)


def stop_engine(child):
    # Descendants can outlive an exited group leader (e.g. crash minimization).
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()


def engine_flags(timeout, max_len):
    if type(timeout) is not int or not 1 <= timeout <= 60:
        raise CoverageError('timeout must be in 1..60 seconds')
    if type(max_len) is not int or not 1 <= max_len <= MAX_INPUT_BYTES:
        raise CoverageError('max-len is outside its supported bound')
    return [f'-timeout={timeout}', f'-max_len={max_len}', '-rss_limit_mb=1024',
            '-malloc_limit_mb=256', '-reload=0', '-print_final_stats=1']


def result_for(mode, engine_hash):
    return {'version': 1, 'kind': 'libfuzzer', 'mode': mode, 'complete': False, 'success': False,
            'explored': 0, 'replayed': 0, 'bundle': 'corpus.json',
            'engine': {'sha256': engine_hash, 'coverage_schema': SCHEMA, 'stats': {}},
            'artifacts': {'logs': [], 'crashes': [], 'minimized': []}, 'failure': None}


def materialize(directory, inputs):
    directory.mkdir()
    paths = []
    for key, data in sorted(inputs.items()):
        path = directory / key
        path.write_bytes(data)
        paths.append(path)
    return paths


def log_text(path):
    return read_bounded(path, MAX_LOG_BYTES).decode('utf-8', errors='replace')


def stats(text):
    values = {}
    for name, value in STATISTIC.findall(text):
        if name in values:
            raise CoverageError('duplicate final engine statistic')
        values[name] = int(value)
    return values


def minimize_crashes(engine, output, paths, timeout, flags, result):
    """Best-effort bounded minimization preserves originals even if it fails."""
    for index, original in enumerate(paths[:MAX_MINIMIZATIONS]):
        minimized = output / 'artifacts' / f'minimized-{index}'
        log = output / f'minimize-{index}.log'
        command = [str(engine), *flags, '-minimize_crash=1', '-runs=256',
                   '-max_total_time=5', f'-exact_artifact_path={minimized}', str(original)]
        status, timed_out = run_engine(command, log, min(15, timeout + 6))
        result['artifacts']['logs'].append(log.name)
        if status == 0 and not timed_out and minimized.exists():
            read_bounded(minimized, MAX_INPUT_BYTES)
            proof = output / f'minimize-proof-{index}.log'
            proof_status, proof_timeout = run_engine([str(engine), *flags, '-runs=0', str(minimized)],
                                                     proof, timeout + 10)
            result['artifacts']['logs'].append(proof.name)
            if proof_status != 0 and not proof_timeout:
                result['artifacts']['minimized'].append(str(minimized.relative_to(output)))


def retain(output, working, result):
    retained = directory_inputs(working)
    artifact_dir = output / 'artifacts'
    crashes = []
    entries = sorted(artifact_dir.iterdir())
    if len(entries) > MAX_INPUTS:
        raise CoverageError('too many crash artifacts')
    for path in entries:
        data = read_bounded(path, MAX_INPUT_BYTES)
        retained[digest(data)] = data
        result['artifacts']['crashes'].append(str(path.relative_to(output)))
        crashes.append(path)
    return bounded_inputs(retained.values()), crashes


def explore(engine, corpus, output, seed, runs, max_len=4096, timeout=10, initial_digests=None):
    if type(seed) is not int or not 1 <= seed <= 0xffffffff:
        raise CoverageError('seed must be a nonzero uint32')
    if type(runs) is not int or not 1 <= runs <= MAX_RUNS:
        raise CoverageError('runs must be in 1..1000000')
    flags = engine_flags(timeout, max_len)
    engine, engine_hash = check_engine(engine)
    initial = directory_inputs(corpus) if initial_digests is None else manifest_inputs(corpus, initial_digests)
    if any(len(data) > max_len for data in initial.values()):
        raise CoverageError('initial corpus would be truncated by max-len')
    output = output_directory(output)
    working = output / 'working-corpus'
    materialize(working, initial)
    (output / 'artifacts').mkdir()
    result = result_for('explore', engine_hash)
    log = output / 'explore.log'
    result['artifacts']['logs'].append(log.name)
    command = [str(engine), *flags, f'-seed={seed}', f'-runs={runs}',
               f'-artifact_prefix={output / "artifacts"}/', str(working)]
    status, timed_out = run_engine(command, log, min(600, max(30, runs * timeout + 10)))
    text = log_text(log)
    final_stats = stats(text)
    modules = COUNTERS.findall(text)
    coverage = COVERAGE.findall(text)
    if len(modules) == 1:
        final_stats['modules'] = int(modules[0][0])
        final_stats['inline_8bit_counters'] = int(modules[0][1])
    if len(coverage) == 1:
        final_stats['observed_pcs'] = int(coverage[0])
    result['engine']['stats'] = final_stats
    result['explored'] = final_stats.get('number_of_executed_units', 0)
    retained, crashes = retain(output, working, result)
    done = DONE.findall(text)
    finished = FINISHED.findall(text)
    complete = (not timed_out and status == 0 and not crashes
                and 'WARNING: unrecognized flag' not in text
                and all(len(data) <= max_len for data in retained.values())
                and done == [str(runs)] and finished == [str(runs)]
                and result['explored'] == runs
                and final_stats.get('modules', 0) > 0
                and final_stats.get('inline_8bit_counters', 0) > 0
                and final_stats.get('observed_pcs', 0) > 0)
    result['complete'] = complete
    result['success'] = complete
    if not complete:
        result['failure'] = 'timeout' if timed_out else f'uncertified engine completion (status {status})'
        minimize_crashes(engine, output, crashes, timeout, flags, result)
        for relative in result['artifacts']['minimized']:
            data = read_bounded(output / relative, MAX_INPUT_BYTES)
            retained[digest(data)] = data
    save_bundle(output, bounded_inputs(retained.values()))
    atomic_json(output / 'result.json', result)
    return result


def replay(engine, bundle, output, timeout=10):
    flags = engine_flags(timeout, MAX_INPUT_BYTES)
    engine, engine_hash = check_engine(engine)
    inputs = load_bundle(bundle)
    output = output_directory(output)
    paths = materialize(output / 'replay-inputs', inputs)
    (output / 'artifacts').mkdir()
    result = result_for('replay', engine_hash)
    result['complete'] = True
    result['success'] = True
    for index, path in enumerate(paths):
        log = output / f'replay-{index}.log'
        result['artifacts']['logs'].append(log.name)
        command = [str(engine), *flags, '-runs=0',
                   f'-artifact_prefix={output / "artifacts"}/', str(path)]
        status, timed_out = run_engine(command, log, timeout + 10)
        text = log_text(log)
        # A filename argument selects fixed-input execution, not exploration.
        expected = str(path)
        complete = (not timed_out and status == 0
                    and 'WARNING: unrecognized flag' not in text
                    and f'Running: {expected}\n' in text and EXECUTED.findall(text) == [expected]
                    and 'fuzzing was not performed' in text
                    and len(COUNTERS.findall(text)) == 1
                    and all(int(value) > 0 for value in COUNTERS.findall(text)[0]))
        if not complete:
            result['complete'] = False
            result['success'] = False
            result['failure'] = 'timeout' if timed_out else f'uncertified replay (status {status})'
            # Fixed-file libFuzzer execution disables artifact saving. Retain
            # the exact original input ourselves, including for timeout/signal.
            (output / 'artifacts' / ('crash-replay-' + path.name)).write_bytes(inputs[path.name])
            break
        result['replayed'] += 1
    retained, crashes = retain(output, output / 'replay-inputs', result)
    if crashes:
        result['complete'] = False
        result['success'] = False
        result['failure'] = result['failure'] or 'replay emitted a crash artifact'
        minimize_crashes(engine, output, crashes, timeout, flags, result)
        for relative in result['artifacts']['minimized']:
            data = read_bounded(output / relative, MAX_INPUT_BYTES)
            retained[digest(data)] = data
    save_bundle(output, bounded_inputs(retained.values()))
    atomic_json(output / 'result.json', result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    for mode in ('explore', 'replay'):
        child = commands.add_parser(mode)
        child.add_argument('--engine', type=Path, required=True)
        child.add_argument('--output', type=Path, required=True)
        child.add_argument('--timeout', type=int, default=10)
        if mode == 'explore':
            child.add_argument('--corpus', type=Path, required=True)
            child.add_argument('--seed', type=int, required=True)
            child.add_argument('--runs', type=int, required=True)
            child.add_argument('--max-len', type=int, default=4096)
        else:
            child.add_argument('--bundle', type=Path, required=True)
    options = vars(parser.parse_args(argv))
    mode = options.pop('mode')
    try:
        result = (explore if mode == 'explore' else replay)(**options)
    except (CoverageError, OSError) as error:
        print('coverage worker: ' + str(error), file=sys.stderr)
        return 2
    print(str(Path(options['output']).absolute() / 'result.json'))
    return 0 if result['complete'] and result['success'] else 1


if __name__ == '__main__':
    sys.exit(main())
