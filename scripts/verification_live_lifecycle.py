#!/usr/bin/env python3
"""Bounded live lifecycle qualification through unmodified production dispatch.

Actions use a disposable fixture build driver. Coordinators, admission, snapshots,
shared store, serialization, publication and process supervision are production
code copied byte-for-byte. This is not native full-inventory qualification and
claims no shared in-flight subscriber model: request contenders are serialized.
"""
from __future__ import annotations
import argparse
import ast
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import traceback

REPOSITORY = Path(__file__).resolve().parents[1]
PRODUCTION_ROOT = REPOSITORY
DRIVER = '''#!{python}
import json,os,signal,subprocess,sys,time
from pathlib import Path
root=Path.cwd(); args=sys.argv[1:]; control=root/'.control'; control.mkdir(exist_ok=True)
phase='plan' if 'verification-plan' in args else 'prepare' if 'verification-prepare' in args else 'gate'
with (control/'events.jsonl').open('a') as out:
    out.write(json.dumps({{'phase':phase,'pid':os.getpid(),'argv':args}})+'\\n')
if phase=='plan':
    path=root/'zig-out/verification/inventory.json'; path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes((root/'fixture-contract.json').read_bytes())
elif phase=='prepare':
    artifacts={{}}
    for name in ['mylang','units','cli','core']:
        path=root/'zig-out/bin'/name; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(b'bounded-lifecycle-artifact-'+name.encode()); artifacts[name]=str(path)
    (root/'zig-out/verification/artifacts.json').write_text(json.dumps({{'version':1,'artifacts':artifacts}}))
    package=root/'zig-out/libexec/mylang/components'; package.mkdir(parents=True,exist_ok=True)
    for name in ['test-index','cache-plan']:
        (package/name).write_bytes(b'bounded-lifecycle-component')
        (package/(name+'.json')).write_text(json.dumps({{'artifact':name}}))
else:
    child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'],start_new_session=True)
    marker=control/('started.'+str(os.getpid())+'.json'); temporary=marker.with_suffix('.tmp')
    def birth(pid):
        stat=Path('/proc/'+str(pid)+'/stat').read_text(); return int(stat[stat.rfind(')')+2:].split()[19])
    inner=os.getppid(); launcher=int(Path('/proc/'+str(inner)+'/stat').read_text().rsplit(') ',1)[1].split()[1])
    temporary.write_text(json.dumps({{'worker':os.getpid(),'detached':child.pid,'launcher':launcher,'inner':inner,'births':{{'inner':birth(inner),'worker':birth(os.getpid()),'detached':birth(child.pid),'launcher':birth(launcher)}}}})); temporary.rename(marker)
    release=control/('release.'+str(os.getpid()))
    deadline=time.monotonic()+45
    while not release.exists() and time.monotonic()<deadline: time.sleep(.01)
    if not release.exists(): raise SystemExit(7)
    child.terminate(); child.wait(timeout=2)
    assert (root/'inputs/fixture.txt').read_text()=='checked input\\n'
    print('bounded lifecycle action completed',flush=True)
'''


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
    temporary.replace(path)


def await_condition(predicate, message, seconds=900):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError(message)


def await_lock_waiter(process):
    """Require a live production contender actually blocked on flock, not startup."""
    def waiting():
        if process.poll() is not None:
            raise AssertionError(f'contender exited {process.returncode} before serialization')
        try:
            return 'lock' in Path(f'/proc/{process.pid}/wchan').read_text()
        except FileNotFoundError:
            return False
    return await_condition(waiting, 'contender did not wait on the production coordinator lock')


def assert_dead(pid, birth):
    def dead():
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        try:
            stat = Path(f'/proc/{pid}/stat').read_text()
            # A zombie is not accepted; another process reusing the PID is safe.
            return int(stat[stat.rfind(')') + 2:].split()[19]) != birth
        except FileNotFoundError:
            return True
    await_condition(dead, f'owned action PID {pid} survived or was not reaped', 5)


class Fixture:
    def __init__(self, scratch, name, output):
        self.name = name
        self.root = Path(scratch)/'fixture'
        existing = self.root.exists()
        self.root.mkdir(exist_ok=True)
        self.output = Path(output)
        self.processes = []
        self.handles = []
        if not existing:
            shutil.copytree(PRODUCTION_ROOT/'scripts', self.root/'scripts', ignore=shutil.ignore_patterns('__pycache__'))
            manifest = {str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (self.root/'scripts').rglob('*') if path.is_file()}
            atomic_json(self.output/'frozen-script-manifest.json', manifest)
            for directory in ('src', 'test', 'tests', 'selfhost', 'docs', 'inputs', 'tools/lib', '.control'):
                (self.root/directory).mkdir(parents=True, exist_ok=True)
            for name in ('build.zig.zon', 'guardian.toml', 'src/user_docs.zig', 'README.md', 'SPEC.md', 'benchmarks/runtime/ports/native_clock.c'):
                path = self.root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('bounded fixture placeholder\n')
            guardian = Path(scratch)/'guardian-zig'
            (guardian/'src').mkdir(parents=True, exist_ok=True)
            for name in ('build.zig', 'build.zig.zon'):
                (guardian/name).write_text('bounded guardian dependency placeholder\n')
            (self.root/'inputs/fixture.txt').write_text('checked input\n')
            (self.root/'build.zig').write_text('// bounded fixture driver supplies the graph\n')
            (self.root/'build_test_inputs.zig').write_text('pub const lifecycle = [_][]const u8{"inputs/fixture.txt"};\n')
            shutil.copy2(PRODUCTION_ROOT/'.zigversion', self.root/'.zigversion')
            self.zig = self.root/'tools/fixture-zig'
            self.zig.write_text(DRIVER.format(python=sys.executable))
            self.zig.chmod(0o755)
            contract = {
                'version': 2, 'required_targets': ['test', 'fmt-check'],
                'configuration': {'filtered': False, 'rerun': False, 'optimize': 'Debug'},
                'groups': [{'id': 'lifecycle', 'target': 'verification-lifecycle', 'label': 'bounded lifecycle',
                            'inputs': ['inputs/fixture.txt'], 'cacheable': True, 'reason': 'bounded lifecycle fixture'}],
                'input_lists': [{'name': 'lifecycle', 'inputs': ['inputs/fixture.txt']}],
                'coverage': {'required_actions': 1, 'registered_actions': 1, 'unknown_actions': []},
                'action_metadata': [{'id': 'lifecycle', 'identity_scope': 'group-local-v1', 'steps': [
                    {'label': 'verification action lifecycle member 0', 'original_label': 'bounded lifecycle', 'kind': 'run'}]}],
            }
            (self.root/'fixture-contract.json').write_text(json.dumps(contract))
        self.zig = self.root/'tools/fixture-zig'
        self.shared = self.root/'.shared'
        module = ast.parse((self.root/'scripts/verify_cache.py').read_text())
        version = next(node.value.value for node in module.body if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == 'VERSION' for target in node.targets)
                       and isinstance(node.value, ast.Constant) and type(node.value.value) is int)
        self.cache = self.root/('.mylang-cache/verification-v'+str(version))
        self.control = self.root/'.control'
        if existing:
            # Prior case close() has joined every coordinator: no active borrower.
            for path in (self.shared, self.cache/'actions', self.control):
                if path.exists():
                    shutil.rmtree(path)
            (self.cache/'last-run.json').unlink(missing_ok=True)
        self.control.mkdir(exist_ok=True)
        self.env = dict(os.environ, TMPDIR=str(self.root/'.tmp'),
                        ZIG_LOCAL_CACHE_DIR=str(self.root/'.zig-cache'), PYTHONDONTWRITEBYTECODE='1')
        (self.root/'.tmp').mkdir(exist_ok=True)

    def start(self, label, *options, retained=False):
        logfile = self.output/(self.name+'-'+label+'.log')
        handle = logfile.open('wb')
        self.handles.append(handle)
        args = ['--zig', str(self.zig), '--shared-cache-dir', str(self.shared), *options]
        entry = 'cache_session.py' if retained else 'verify_cache.py'
        process = subprocess.Popen([sys.executable, str(self.root/'scripts'/entry), *([] if retained else args)],
            cwd=self.root, env=self.env, stdin=subprocess.PIPE if retained else subprocess.DEVNULL,
            stdout=handle, stderr=handle, start_new_session=True)
        self.processes.append(process)
        if retained:
            process.stdin.write((json.dumps({'id': label, 'command': 'verify', 'args': args})+'\n').encode())
            process.stdin.flush()
        return process

    def gates(self):
        path = self.control/'events.jsonl'
        rows = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [row for row in rows if row['phase'] == 'gate']

    def started(self, count=1):
        def ready():
            paths = sorted(self.control.glob('started.*.json'))
            if len(paths) >= count:
                return [json.loads(path.read_text()) for path in paths]
            if self.processes and self.processes[-1].poll() is not None:
                raise AssertionError(f'{self.name}: coordinator exited {self.processes[-1].returncode} before gate {count}')
            return None
        return await_condition(ready, f'{self.name}: {count} admitted gates did not start')

    def release(self, marker):
        (self.control/('release.'+str(marker['worker']))).touch()

    def finish(self, process, expected=0, retained=False):
        if retained and process.poll() is None:
            process.stdin.write(b'{"id":"stop","command":"stop"}\n')
            process.stdin.close()
        status = process.wait(timeout=900)
        if status != expected:
            raise AssertionError(f'{self.name}: coordinator status {status}, expected {expected}')
        return status

    def report(self):
        return json.loads((self.cache/'last-run.json').read_text())

    def receipts(self):
        return list((self.cache/'actions').glob('*.json'))

    def no_success(self):
        path = self.cache/'last-run.json'
        report = self.report() if path.exists() else {'observation': 'no report after hard crash'}
        atomic_json(self.output/(self.name+'-failed-report.json'), report)
        if self.receipts():
            raise AssertionError(f'{self.name}: incomplete request left local success')
        if report.get('success') is True:
            raise AssertionError(f'{self.name}: incomplete request last report claims success')


    def close(self):
        for process in self.processes:
            if process.poll() is None:
                os.kill(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            if process.stdin is not None and not process.stdin.closed:
                process.stdin.close()
        # Only fixture-marked processes are considered, never unrelated jobs.
        for path in self.control.glob('started.*.json'):
            row = json.loads(path.read_text())
            for name in ('launcher', 'inner', 'worker', 'detached'):
                pid = row[name]
                try:
                    descriptor = os.pidfd_open(pid)
                except ProcessLookupError:
                    continue
                try:
                    stat = Path(f'/proc/{pid}/stat').read_text()
                    birth = int(stat[stat.rfind(')') + 2:].split()[19])
                    if birth == row['births'][name]:
                        if name == 'launcher':
                            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
                            time.sleep(.5)
                        else:
                            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                except (FileNotFoundError, ProcessLookupError):
                    pass
                finally:
                    os.close(descriptor)
        report = self.cache/'last-run.json'
        if report.exists():
            atomic_json(self.output/(self.name+'-last-report.json'), json.loads(report.read_text()))
        for handle in self.handles:
            handle.close()


def matching_complete(scratch, output):
    fixture = Fixture(scratch, 'matching-complete', output)
    try:
        owner = fixture.start('owner', retained=True)
        marker = fixture.started()[0]
        waiter = fixture.start('waiter', retained=True)
        await_lock_waiter(waiter)
        fixture.release(marker)
        fixture.finish(owner, retained=True)
        fixture.finish(waiter, retained=True)
        report = fixture.report()
        if len(fixture.gates()) != 1 or report['actions'][0]['state'] != 'reused' or report['success'] is not True:
            raise AssertionError('matching concurrent complete requests did not serialize and reuse')
        return {'owner_status': 0, 'waiter_status': 0, 'gates': 1, 'reused': 1,
                'dispatch': 'two real retained-session verify requests'}
    finally:
        fixture.close()


def matching_waiter_cancel(scratch, output):
    fixture = Fixture(scratch, 'waiter-cancel', output)
    try:
        owner = fixture.start('owner', retained=True)
        marker = fixture.started()[0]
        waiter = fixture.start('waiter', retained=True)
        await_lock_waiter(waiter)
        os.kill(waiter.pid, signal.SIGTERM)
        fixture.finish(waiter, 143)
        if owner.poll() is not None or len(fixture.gates()) != 1:
            raise AssertionError('waiter cancellation stopped or duplicated owner work')
        descriptor = os.pidfd_open(marker['detached'])
        os.close(descriptor)
        fixture.release(marker)
        fixture.finish(owner, retained=True)
        fixture.finish(fixture.start('shared-reuse', retained=True), retained=True)
        if len(fixture.gates()) != 1 or fixture.report()['actions'][0]['state'] != 'reused':
            raise AssertionError('matching complete request did not reuse serialized owner result')
        return {'owner_status': 0, 'waiter_status': 143, 'gates': 1, 'reused': 1}
    finally:
        fixture.close()


def owner_cancel_retry(scratch, output):
    fixture = Fixture(scratch, 'owner-cancel', output)
    try:
        owner = fixture.start('owner')
        first = fixture.started()[0]
        waiter = fixture.start('waiter')
        await_lock_waiter(waiter)
        os.kill(owner.pid, signal.SIGTERM)
        fixture.finish(owner, 143)
        assert_dead(first['worker'], first['births']['worker']); assert_dead(first['detached'], first['births']['detached'])
        fixture.no_success()
        second = next(row for row in fixture.started(2) if row != first)
        fixture.release(second)
        fixture.finish(waiter)
        if len(fixture.gates()) != 2 or fixture.report()['success'] is not True:
            raise AssertionError('surviving contender did not recover claim and execute')
        return {'owner_status': 143, 'waiter_status': 0, 'gates': 2, 'cancelled_successes': 0}
    finally:
        fixture.close()


def timeout_retry(scratch, output):
    fixture = Fixture(scratch, 'timeout-retry', output)
    try:
        owner = fixture.start('timeout', '--gate-timeout-seconds', '.25')
        first = fixture.started()[0]
        fixture.finish(owner, 124)
        fixture.no_success()
        assert_dead(first['worker'], first['births']['worker']); assert_dead(first['detached'], first['births']['detached'])
        timed = next(row for row in fixture.report()['admissions'] if row['kind'] == 'gate')
        if timed['timed_out'] is not True or timed['incomplete'] is not False:
            raise AssertionError('timeout outcome was not distinctly recorded')
        retry = fixture.start('retry', '--gate-timeout-seconds', '.25')
        second = next(row for row in fixture.started(2) if row != first)
        fixture.release(second)
        fixture.finish(retry)
        return {'timeout_status': 124, 'retry_status': 0, 'gates': 2, 'reaped': True,
                'queue_seconds': timed['admission_wait_seconds'], 'worker_seconds': timed['worker_seconds']}
    finally:
        fixture.close()


def shared_only_reuse(scratch, output):
    fixture = Fixture(scratch, 'shared-only', output)
    try:
        owner = fixture.start('owner')
        fixture.release(fixture.started()[0]); fixture.finish(owner)
        for path in fixture.receipts():
            path.unlink()
        fixture.finish(fixture.start('shared-only'))
        report = fixture.report()
        if len(fixture.gates()) != 1 or report['actions'][0]['state'] != 'reused' or report['evidence_store']['shared'] is not True:
            raise AssertionError('shared authoritative store did not supply the missing private receipt')
        return {'gates': 1, 'private_receipts_removed': 1, 'shared_reused': 1}
    finally:
        fixture.close()


def publication_interrupt(scratch, output):
    fixture = Fixture(scratch, 'publication', output)
    descriptor = None
    try:
        initial = fixture.start('initial')
        fixture.release(fixture.started()[0]); fixture.finish(initial)
        receipt = fixture.receipts()[0]
        action_key = receipt.stem
        owner = fixture.start('interrupted', '--force')
        markers = fixture.started(2)
        second = next(row for row in markers if not (fixture.control/('release.'+str(row['worker']))).exists())
        # Existing authoritative store lock blocks shared publication after local save.
        lock = fixture.shared/'locks/success'/(action_key+'.lock')
        descriptor = os.open(lock, os.O_RDWR)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        fixture.release(second)
        await_condition(lambda: receipt.exists(), 'local publication did not reach shared-store lock')
        os.kill(owner.pid, signal.SIGTERM)
        await_condition(lambda: not receipt.exists(), 'publication interruption did not roll back local receipt')
        os.close(descriptor); descriptor = None
        fixture.finish(owner, 143)
        fixture.no_success()
        # Validate through the same production store, not by counting JSON files.
        sys.path.insert(0, str(REPOSITORY/'scripts'))
        from fuzz_campaign_store import Store
        if Store(fixture.shared).load_success(action_key) is not None:
            raise AssertionError('interrupted refresh forged a shared success')
        retry = fixture.start('retry')
        third = next(row for row in fixture.started(3) if row not in markers)
        fixture.release(third); fixture.finish(retry)
        return {'interrupted_status': 143, 'retry_status': 0, 'rollback': True, 'gates': 3}
    finally:
        if descriptor is not None:
            os.close(descriptor)
        fixture.close()

def crash_after_admission(scratch, output):
    fixture = Fixture(scratch, 'crash-admitted', output)
    try:
        owner = fixture.start('owner')
        first = fixture.started()[0]
        waiter = fixture.start('waiter')
        await_lock_waiter(waiter)
        os.kill(owner.pid, signal.SIGKILL)
        fixture.finish(owner, -signal.SIGKILL)
        for name in ('worker', 'detached', 'inner', 'launcher'):
            assert_dead(first[name], first['births'][name])
        fixture.no_success()
        second = next(row for row in fixture.started(2) if row != first)
        fixture.release(second); fixture.finish(waiter)
        return {'owner_status': -9, 'waiter_status': 0, 'gates': 2,
                'owned_lineage_reaped': True, 'incomplete_successes': 0}
    finally:
        fixture.close()


def crash_before_admission(scratch, output):
    fixture = Fixture(scratch, 'crash-before-admission', output)
    wrapper = None
    birth = None
    try:
        owner = fixture.start('owner')
        def find_wrapper():
            if owner.poll() is not None:
                raise AssertionError('owner exited before creating admission wrapper')
            children = Path(f'/proc/{owner.pid}/task/{owner.pid}/children').read_text().split()
            for child in children:
                try:
                    command = Path(f'/proc/{child}/cmdline').read_bytes().split(b'\0')
                    if any(item.endswith(b'build-slot.sh') for item in command) and b'gate' in command:
                        return int(child)
                except FileNotFoundError:
                    pass
            return None
        wrapper = await_condition(find_wrapper, 'could not observe pre-handshake admission wrapper')
        stat = Path(f'/proc/{wrapper}/stat').read_text()
        birth = int(stat[stat.rfind(')') + 2:].split()[19])
        descriptor = os.pidfd_open(wrapper)
        try:
            current = Path(f'/proc/{wrapper}/stat').read_text()
            if int(current[current.rfind(')') + 2:].split()[19]) != birth:
                raise AssertionError('owned wrapper identity changed before crash injection')
            signal.pidfd_send_signal(descriptor, signal.SIGSTOP)
            if fixture.gates():
                raise AssertionError('wrapper had already dispatched action before startup crash injection')
            os.kill(owner.pid, signal.SIGKILL); fixture.finish(owner, -signal.SIGKILL)
            signal.pidfd_send_signal(descriptor, signal.SIGCONT)
        finally:
            os.close(descriptor)
        assert_dead(wrapper, birth)
        fixture.no_success()
        retry = fixture.start('retry')
        first = fixture.started()[0]
        fixture.release(first); fixture.finish(retry)
        return {'owner_status': -9, 'retry_status': 0, 'gates': 1,
                'wrapper_reaped': True, 'pre_handshake': True}
    finally:
        if wrapper is not None and birth is not None:
            try:
                descriptor = os.pidfd_open(wrapper)
                signal.pidfd_send_signal(descriptor, signal.SIGCONT)
                os.close(descriptor)
            except ProcessLookupError:
                pass
        fixture.close()



CASES = {
    'matching_complete': matching_complete,
    'waiter_cancel': matching_waiter_cancel,
    'owner_cancel_retry': owner_cancel_retry,
    'timeout_retry': timeout_retry,
    'shared_only_reuse': shared_only_reuse,
    'publication_interrupt': publication_interrupt,
    'crash_after_admission': crash_after_admission,
    'crash_before_admission': crash_before_admission,
}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=CASES, action='append')
    parser.add_argument('--production-root', type=Path, default=REPOSITORY)
    args = parser.parse_args(argv)
    global PRODUCTION_ROOT
    PRODUCTION_ROOT = args.production_root.resolve()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'cannot subreap owned crash fixtures')
    args.output.mkdir(parents=True, exist_ok=True)
    (REPOSITORY/'.tmp').mkdir(exist_ok=True)
    result = {'version': 1, 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=PRODUCTION_ROOT, text=True).strip(),
              'source_dirty_status': subprocess.check_output(['git', 'status', '--short', '--', 'scripts'], cwd=PRODUCTION_ROOT, text=True),
              'harness_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'python_executable_sha256': hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest(),
              'production_sources': {name: hashlib.sha256((PRODUCTION_ROOT/'scripts'/name).read_bytes()).hexdigest()
                                     for name in ('verify_cache.py','cache_session.py','verification_process.py','fuzz_campaign_store.py','build-slot.sh')},
              'model': 'serialized contenders; no shared in-flight subscriber ownership',
              'native_full_inventory': 'not qualified', 'cache_conditions': 'one disposable fixture; retain prepared artifacts/inventory; reset only its action receipts/shared store with no active borrowers', 'cases': {}, 'success': True}
    with tempfile.TemporaryDirectory(prefix='verification-live-', dir=REPOSITORY/'.tmp') as scratch:
        for name in args.case or CASES:
            print('live lifecycle: '+name, flush=True)
            try:
                result['cases'][name] = dict(status='passed', **CASES[name](scratch, args.output))
            except Exception as error:
                result['success'] = False
                result['cases'][name] = {'status': 'failed', 'error': str(error), 'traceback': traceback.format_exc()}
            atomic_json(args.output/'results.json', result)
            print('live lifecycle: '+name+' '+result['cases'][name]['status'], flush=True)
    return 0 if result['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
