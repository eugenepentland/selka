#!/usr/bin/env python3
"""Retain real guard/native/fallback outputs; run inside one build admission."""
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import time

M = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
F = M.parent / 'codex-new-core-s4-frontend'
LLVM = F / 'experiments/new-core-s4-frontend-20261006/c-prep-e-debug-cwd-01/actual-unit.ll'
ZIG = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
WORK = M / '.mylang-cache/s4-m/tool-discovery-native-replay-28'
PROBE = M / '.mylang-cache/s4-m/tool-discovery-guard-probe-25'
CORE = M / '.mylang-cache/s4-m/tool-discovery-core-26/bin/mylang-core'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    (HERE / (name + '.json')).write_text(json.dumps(value, indent=2) + '\n')


def run(name, argv, env, cwd, expected=0):
    with (HERE / (name + '.stdout')).open('wb') as out, (HERE / (name + '.stderr')).open('wb') as err:
        child = subprocess.Popen(argv, cwd=cwd, env=env, stdout=out, stderr=err, start_new_session=True)
        expired = False
        try:
            status = child.wait(timeout=180)
        except subprocess.TimeoutExpired:
            expired = True
            os.killpg(child.pid, signal.SIGKILL)
            status = child.wait()
    record = {'command': argv, 'cwd': str(cwd), 'status': status, 'timeout': expired,
              'affinity': sorted(os.sched_getaffinity(0))}
    save(name, record)
    assert status == expected and not expired, record
    return record


def native(case, phase, executable, env):
    private = WORK / (case + '-' + phase)
    private.mkdir()
    input_path = private / ('canonical-' + sha(LLVM) + '.ll')
    shutil.copy2(LLVM, input_path)
    output = private / 'fresh.o'
    native_env = env.copy()
    native_env['ZIG_LOCAL_CACHE_DIR'] = str(private / 'local')
    native_env['ZIG_GLOBAL_CACHE_DIR'] = str(private / 'global')
    cc = [str(executable), 'cc', '-c', '-O0', '-target', 'x86_64-linux-gnu.2.31', '-march=native',
          '-mllvm', '-x86-experimental-pref-innermost-loop-alignment=6', '-Wno-override-module',
          '-o', str(output), str(input_path)]
    trace = HERE / ('native-28-' + case + '-' + phase + '.strace')
    argv = ['strace', '-f', '-yy', '-s', '4096', '-e',
            'trace=%file,read,pread64,mmap,getdents64,getcwd,close', '-o', str(trace)] + cc
    record = run('native-28-' + case + '-' + phase, argv, native_env, private)
    record.update({'object_sha256': sha(output), 'object_bytes': output.stat().st_size,
                   'llvm_sha256': sha(input_path), 'native_cache_dirs':
                   [native_env['ZIG_LOCAL_CACHE_DIR'], native_env['ZIG_GLOBAL_CACHE_DIR']]})
    save('native-28-' + case + '-' + phase, record)
    return record


def replay(case, executable, resource, env):
    argv = [str(PROBE), str(executable), str(resource), str(WORK / 'helper-cache')]
    if case == 'regular-file-parent':
        argv.append('file-parent')
    child = subprocess.Popen(argv, cwd=WORK, env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(child.stderr, selectors.EVENT_READ)
    prefix = b''
    deadline = time.monotonic() + 45
    try:
        while b'ready=true\n' not in prefix:
            if time.monotonic() > deadline:
                raise TimeoutError('capture readiness')
            if selector.select(1):
                data = os.read(child.stderr.fileno(), 65536)
                if not data:
                    raise RuntimeError(prefix.decode())
                prefix += data
        before = native(case, 'before', executable, env)
        stdout, suffix = child.communicate(b'x', timeout=45)
        stderr = prefix + suffix
    except BaseException:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
        raise
    finally:
        selector.close()
    (HERE / ('guard-28-' + case + '.stdout')).write_bytes(stdout)
    (HERE / ('guard-28-' + case + '.stderr')).write_bytes(stderr)
    values = dict(line.split('=', 1) for line in stderr.decode().splitlines())
    row = {'command': argv, 'status': child.returncode, 'values': values, 'native_before': before}
    save('guard-28-' + case, row)
    assert child.returncode == 0 and values['cacheable_after'] == 'false', row
    if case == 'initially-absent':
        assert values['cacheable_before'] == 'true' and values['unchanged'] == 'false', row
        assert values['provisional_present'] == 'true' and values['provisional_unchanged'] == 'false', row
        assert values['before_digest'] != values['after_digest'], row
    else:
        assert values['cacheable_before'] == 'false' and values['provisional_present'] == 'false', row
    if case == 'regular-file-parent':
        assert values['unchanged'] == 'false' and values['before_digest'] != values['after_digest'], row
    row['native_after'] = native(case, 'after', executable, env)
    return row


assert not set(os.sched_getaffinity(0)).intersection({2, 3, 10, 11})
assert sha(LLVM) == '1c40b584bc71793ebd6e8a1d597b03c65677dd33857bed2370293efed1363e48'
expected = json.loads((HERE / 'source-notdir-23.json').read_text())
assert all(sha(M / path) == digest for path, digest in expected.items())
WORK.mkdir()
distribution = WORK / 'tool/distribution'
distribution.mkdir(parents=True)
executable = distribution / 'zig'
shutil.copy2(ZIG, executable)
shutil.copytree(ZIG.parent / 'lib', distribution / 'lib', symlinks=True)
assert sha(executable) == sha(ZIG)
env = os.environ.copy()
env['XDG_CACHE_HOME'] = str(WORK / 'xdg')
sibling = WORK / 'tool/lib'
resource = sibling / 'clang/22/share/ubsan_ignorelist.txt'
rows = []
for case in ['initially-absent', 'preexisting-lib-root', 'regular-file-parent']:
    if sibling.exists():
        shutil.rmtree(sibling)
    if case == 'preexisting-lib-root':
        sibling.mkdir()
    if case == 'regular-file-parent':
        sibling.write_text('first')
    assert not resource.exists()
    rows.append(replay(case, executable, sibling if case == 'regular-file-parent' else resource, env))
    if case != 'initially-absent':
        source = WORK / (case + '-source') / 'app.my'
        source.parent.mkdir()
        source.write_text('module app\ndef main() -> int:\n    return 7\n')
        cache = WORK / (case + '-core-cache')
        output = WORK / (case + '-guest')
        build = [str(CORE), 'build', str(source), '-o', str(output), '--zig', str(executable),
                 '--cache-dir', str(cache)]
        rows[-1]['core_fallback'] = run('fallback-28-' + case, build, env, WORK)
        rows[-1]['native_guest'] = run('guest-28-' + case, [str(output)], env, WORK, expected=7)
        rows[-1]['guest_sha256'] = sha(output)
        leftovers = [str(p) for p in cache.rglob('*')
                     if p.name.startswith(('native-link-', 'unproved-tool-'))]
        assert not leftovers, leftovers
        rows[-1]['owned_private_cache_leftovers'] = leftovers
    print(case + ' GREEN', flush=True)
assert all(sha(M / path) == digest for path, digest in expected.items())
save('native-replay-28-summary', {'classification': 'GREEN', 'source_snapshot': 'source-notdir-23.json',
     'tool_sha256': sha(executable), 'probe_sha256': sha(PROBE), 'core_sha256': sha(CORE),
     'llvm_sha256': sha(LLVM), 'cases': rows,
     'scope': 'Correctness only. Unknown-state reuse bypass retained; identical objects do not prove action closure.'})
