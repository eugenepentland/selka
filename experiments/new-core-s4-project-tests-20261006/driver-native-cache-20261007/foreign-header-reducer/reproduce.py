#!/usr/bin/env python3
"""Immutable Core --link header-generation reducer; no production edits."""
import hashlib
import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
EVIDENCE = ROOT / 'experiments/new-core-s4-frontend-20261006/c-prep-core-foreign-header-01'
WORK = ROOT / '.mylang-cache/s4-frontend/c-prep-core-foreign-header-01'
EXPECTED = '591886dc7d20409c878ee0a5b15c9faa0394b5b836eeaaa8c75e43a31350f120'


def fingerprint(path):
    data = path.read_bytes()
    stat = path.stat()
    return {'path': str(path), 'resolved': str(path.resolve()),
            'device': stat.st_dev, 'inode': stat.st_ino, 'size': stat.st_size,
            'mode': stat.st_mode, 'mtime_ns': stat.st_mtime_ns,
            'ctime_ns': stat.st_ctime_ns,
            'sha256': hashlib.sha256(data).hexdigest()}


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def execute(name, argv, environment, timeout=300):
    start = time.monotonic()
    with (EVIDENCE / (name + '.stdout')).open('wb') as out:
        with (EVIDENCE / (name + '.stderr')).open('wb') as err:
            process = subprocess.Popen(argv, cwd=WORK, env=environment,
                                       stdout=out, stderr=err,
                                       start_new_session=True)
            timed_out = False
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGKILL)
                status = process.wait()
    receipt = {'command': argv, 'cwd': str(WORK), 'status': status,
               'timed_out': timed_out, 'seconds': time.monotonic() - start}
    save(EVIDENCE / (name + '.json'), receipt)
    return receipt


def phase(name, expected_native, environment, argv):
    compiler = fingerprint(WORK / 'mylang-core')
    assert compiler['sha256'] == EXPECTED
    before = {file: fingerprint(WORK / file)
              for file in ('app.my', 'value.c', 'value.h')}
    build = execute(name + '-build',
                    ['strace', '-f', '-qq', '-s', '8192', '-e', 'trace=execve',
                     '-o', str(EVIDENCE / (name + '-execve.trace'))] + argv,
                    environment)
    result = {'phase': name, 'compiler': compiler, 'inputs': before,
              'zig': fingerprint(Path(environment['ZIG'])), 'build': build,
              'expected_native': expected_native}
    if build['status'] == 0:
        for file in ('guest', 'program.ll'):
            result[file] = fingerprint(WORK / file)
            shutil.copy2(WORK / file, WORK / (name + '-' + file))
        shutil.copy2(WORK / 'program.ll', EVIDENCE / (name + '-program.ll'))
        result['native'] = execute(name + '-native', [str(WORK / 'guest')],
                                   environment, timeout=30)
        result['correct'] = result['native']['status'] == expected_native
    else:
        result['correct'] = False
    save(EVIDENCE / (name + '.json'), result)
    print(name, 'build', build['status'], 'native',
          result.get('native', {}).get('status'), 'expected', expected_native,
          flush=True)
    return result


environment = os.environ.copy()
environment['ZIG'] = str(Path('/home/epentland/.local/bin/zig').resolve())
environment['ZIG_GLOBAL_CACHE_DIR'] = str(WORK / 'zig-global')
argv = [str(WORK / 'mylang-core'), 'build', str(WORK / 'app.my'),
        '-o', str(WORK / 'guest'), '--link', str(WORK / 'value.c'),
        '--emit-llvm', str(WORK / 'program.ll'), '--zig', environment['ZIG'],
        '--cache-dir', str(WORK / 'core-cache')]
save(EVIDENCE / 'invocation.json', {
    'argv': argv, 'environment_overrides': {
        key: environment[key] for key in ('ZIG', 'ZIG_GLOBAL_CACHE_DIR')},
    'affinity': sorted(os.sched_getaffinity(0)),
    'rule': 'Every native build/run is under the enclosing build-slot wrapper.'})
original = (WORK / 'value.h').stat()
first = phase('original', 7, environment, argv)
if first['build']['status'] == 0:
    (WORK / 'value.h').write_text('#define VALUE 8\n')
    os.utime(WORK / 'value.h', ns=(original.st_atime_ns, original.st_mtime_ns))
    assert (WORK / 'value.h').stat().st_mtime_ns == original.st_mtime_ns
    assert (WORK / 'value.h').stat().st_size == original.st_size
    second = phase('edited-restored-mtime', 8, environment, argv)
else:
    second = {'skipped': 'Initial build failed; no edit comparison admitted.'}
save(EVIDENCE / 'summary.json', {'original': first, 'edited': second,
     'same_command': True, 'same_cache': True,
     'status': 'GREEN' if first['correct'] and second.get('correct') else 'RED'})
raise SystemExit(0)
