"""Shared admission clients, staged scheduler rollout, and keyed subscriptions."""
from contextlib import contextmanager
import ctypes
import fcntl
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import sys
import threading
import time
import uuid
import verification_code_identity as code_identity
from verification import scheduler as scheduler_backend
from verification.scheduler import Cancelled, Scheduler, identity_alive, process_identity, slot_directory


SLOT = Path(__file__).with_name("build-slot.sh")
MARKERS = ("SELKA_ADMISSION_DIR", "SELKA_ADMISSION_KIND")


class AdmissionLost(RuntimeError):
    """The real slot holder failed to acquire or preserve admission."""


@contextmanager
def admission(kind):
    """Acquire outside measured intervals, then release on completion or failure.

    A pipe keeps the admitted helper alive. Parent death closes it and releases
    the locks too. Reusing an outer admission is allowed, but upgrading a build
    to timing is rejected: that would wait for the caller's own build to finish.
    """
    if kind not in ("build", "gate", "timing"):
        raise ValueError("unknown admission kind: " + kind)
    if os.environ.get("SELKA_ADMISSION_DIR") == str(slot_directory()):
        outer = os.environ.get("SELKA_ADMISSION_KIND")
        if outer == "timing" or outer == kind or (outer == "gate" and kind == "build"):
            yield
            return
        raise RuntimeError(f"cannot request {kind} inside {outer}; run this harness directly")
    # A parent killed while still queued must not leave a live timing request
    # blocking ordinary work. Once admitted, closing the pipe releases the lease.
    parent_start = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()[19]
    environment = dict(os.environ, SELKA_ADMISSION_PARENT_PID=str(os.getpid()),
                       SELKA_ADMISSION_PARENT_START=parent_start)
    process = subprocess.Popen(
        [str(SLOT), kind, sys.executable, "-B", str(Path(__file__).resolve()), "--hold"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, start_new_session=True,
        env=environment)
    original = os.sched_getaffinity(0)
    markers = {key: os.environ.get(key) for key in MARKERS}
    ready = False
    try:
        line = process.stdout.readline()
        if not line:
            raise AdmissionLost(f"{kind} admission failed (exit {process.wait()})")
        identity = json.loads(line)
        os.sched_setaffinity(0, identity["cpus"])
        os.environ.update(identity["markers"])
        ready = True
        yield process
    finally:
        os.sched_setaffinity(0, original)
        for key, value in markers.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        process.stdin.close()
        try:
            if not ready and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            status = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            status = process.wait()
        finally:
            process.stdout.close()
        if ready and status != 0 and sys.exc_info()[0] is None:
            raise AdmissionLost(f"{kind} admission holder failed (exit {status})")


def keyed_scheduler():
    """Return the shared coalescing pool; waiting subscribers hold no gate slot."""
    return Scheduler(slot_directory() / 'keyed.sqlite3', cpus=1024, memory=1048576,
                     workers=1024, lease=30, aging=5)


def subscribe(key, command, *, cwd, env=None, kind='gate', cancel=None, client=None):
    """Join one detached command keyed by the caller's complete semantic identity.

    Placement (cwd and argv paths) may differ between subscribers. The first
    claimant supplies the worker command. A successful result is not a cache
    receipt: callers must still validate their own input snapshot and evidence.
    Use kind=None for a coordinator which already owns admission itself.
    """
    if kind not in ('build', 'gate', 'timing', None):
        raise ValueError('unknown admission kind: ' + str(kind))
    queue = keyed_scheduler()
    client = client or uuid.uuid4().hex
    identity = process_identity()
    queue.submit(key, client, worktree=str(Path(cwd).resolve()), process=identity)
    launched = False
    next_touch = time.monotonic() + queue.client_lease / 3
    try:
        while True:
            if cancel is not None and cancel.is_set():
                raise Cancelled(key)
            if time.monotonic() >= next_touch:
                queue.touch(key, client)
                next_touch = time.monotonic() + queue.client_lease / 3
            state = queue.status(key)
            if state is not None and state['state'] == 'done':
                result = json.loads(state['result'])
                return dict(result, executed=launched, coalesced=not launched)
            owner = uuid.uuid4().hex
            # Only a job nobody holds can be claimed; the others would take the write lock to be refused.
            token = queue.claim(key, owner) if queue.claimable(state) else None
            if token is not None:
                payload = {'key': key, 'owner': owner, 'generation': token,
                           'command': list(command), 'cwd': str(cwd), 'kind': kind,
                           'env': dict(os.environ if env is None else env)}
                worker = subprocess.Popen(
                    [sys.executable, '-B', str(Path(__file__).resolve()), '--keyed-worker'],
                    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True, env=dict(os.environ))
                worker.stdin.write(json.dumps(payload).encode())
                worker.stdin.close()
                threading.Thread(target=worker.wait, daemon=True).start()
                launched = True
            queue.wait_for_change()
    finally:
        queue.cancel(key, client)


def keyed_worker(payload):
    """Run independently of the first subscriber, fencing publication by lease."""
    from verification.scheduler import run_process
    queue = keyed_scheduler()
    key, owner, token = (payload[name] for name in ('key', 'owner', 'generation'))
    with queue._transaction() as db:
        attached = db.execute("UPDATE jobs SET process=? WHERE key=? AND owner=? AND generation=? AND state='running' AND deadline>=?",
                              (process_identity(), key, owner, token, time.time())).rowcount
    if not attached:
        return
    stop = threading.Event()
    lost = threading.Event()
    def heartbeat():
        while not stop.wait(.2):
            with queue._transaction() as db:
                queue._reap(db, time.time())
            if not queue.renew(key, owner, token):
                lost.set()
                return
    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    command = payload['command']
    if payload['kind'] is not None:
        command = [str(SLOT), payload['kind'], *command]
    command = [sys.executable, '-B', str(Path(__file__).resolve()), '--parent-guard',
               process_identity(), *command]
    try:
        result = run_process(command, cwd=payload['cwd'], env=payload['env'], cancelled=lost.is_set)
        result['passed'] = result['returncode'] == 0
        queue.publish(key, owner, token, result)
    except BaseException as error:
        queue.publish(key, owner, token, {'returncode': 2, 'stdout': '',
                                        'stderr': str(error), 'passed': False})
    finally:
        stop.set()
        thread.join()


def _pool(name):
    # Resource configuration is shared and immutable once the database exists;
    # Scheduler rejects callers attempting to open it with different limits.
    # One token admits one wrapper (compile, link or test), while the existing
    # per-kind slot limits and the aggregate memory reservation also apply.
    tokens = int(os.environ.get('SELKA_ADMISSION_TOKENS', str(os.cpu_count() or 1)))
    physical = next(int(line.split()[1])*1024 for line in Path('/proc/meminfo').read_text().splitlines()
                    if line.startswith('MemTotal:'))
    memory = _bytes(os.environ.get('SELKA_ADMISSION_MEMORY', str(physical))) / (1 << 20)
    return Scheduler(slot_directory() / (name + '-v2.sqlite3'), cpus=tokens,
                     memory=memory, workers=tokens, lease=30, aging=5)


def _requirements(kind):
    limits = {name: int(os.environ.get('SELKA_' + name.upper() + '_SLOTS', default))
              for name, default in [('build', '3'), ('gate', '1'), ('timing', '1')]}
    if any(value <= 0 for value in limits.values()):
        raise ValueError('slot count must be a positive integer')
    need = _bytes(os.environ.get('SELKA_' + kind.upper() + '_MEM', '6G' if kind == 'gate' else '4G'))
    return limits, need


def _reservation(queue, need):
    with queue._transaction(write=False) as db:
        capacity = db.execute('SELECT memory FROM config').fetchone()[0]
    # Impossible requests remain queued like the legacy wrapper. The live
    # MemAvailable check prevents admission even though SQL clamps the request.
    return max(min(need / (1 << 20), capacity), min(1, capacity))


def _log(event, *, lock_timeout=None, **values):
    directory = slot_directory()
    directory.mkdir(parents=True, exist_ok=True)
    row = dict(version=1, event=event, timestamp=time.time(),
               monotonic_ns=time.monotonic_ns(), observer_identity=process_identity(),
               admission_sha256=LOADED_CODE_SHA256,
               scheduler_sha256=scheduler_backend.LOADED_CODE_SHA256, **values)
    with (directory / 'scheduler-shadow.jsonl').open('a') as stream:
        if lock_timeout is None:
            fcntl.flock(stream, fcntl.LOCK_EX)
        else:
            deadline = time.monotonic() + lock_timeout
            while True:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError('shadow log lock unavailable') from None
                    time.sleep(min(.05, remaining))
        stream.write(json.dumps(row, sort_keys=True) + '\n')


def _detached(mode, payload, *, ready=False):
    """Do not let a short legacy command outrun its shadow registration."""
    read_fd, write_fd = os.pipe() if ready else (None, None)
    try:
        if ready:
            payload = dict(payload, ready_fd=write_fd)
        process = subprocess.Popen([sys.executable, '-B', str(Path(__file__).resolve()), mode],
                                   stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, start_new_session=True,
                                   pass_fds=(write_fd,) if ready else ())
        if ready:
            os.close(write_fd)
            write_fd = None
        process.stdin.write(json.dumps(payload).encode())
        process.stdin.close()
        threading.Thread(target=process.wait, daemon=True).start()
        if ready and (not select.select([read_fd], [], [], 30)[0] or os.read(read_fd, 1) != b'R'):
            raise OSError('shadow observer did not register its first decision within 30 seconds')
    finally:
        for descriptor in (read_fd, write_fd):
            if descriptor is not None:
                os.close(descriptor)


def _shadow_ready(payload):
    descriptor = payload.pop('ready_fd', None)
    if descriptor is not None:
        try:
            os.write(descriptor, b'R')
        except BrokenPipeError:
            pass  # The observation is still useful after a readiness timeout.
        finally:
            os.close(descriptor)


def _watch(payload, shadow):
    if not identity_alive(payload['identity']):
        if shadow:
            _log('observation_missed', key=payload['key'], kind=payload['kind'],
                 reason='request exited before observer registration')
        return
    queue = _pool('shadow' if shadow else 'admission')
    identity, key = payload['identity'], payload['key']
    kind = payload['kind']
    token = payload.get('token')
    owner = payload.get('owner', key)
    if shadow:
        limits, need = _requirements(kind)
        cpus, reservation = _cpu_policy(queue, kind, shadow=True)
        queue.submit(key, key, worktree=payload['worktree'], kind=kind,
                     memory=_reservation(queue, need), cpu_set=cpus,
                     exclusive=kind == 'timing' and not reservation, process=identity,
                     priority=0 if kind == 'timing' else 1)
        _log('queued', key=key, kind=kind, worktree=payload['worktree'],
             kind_limits=limits, memory_bytes=need, cpu_set=sorted(cpus),
             timing_cpu_set=sorted(reservation), policy='candidate', scope='observed-clients')
    actual = False
    candidate_admitted_at = None
    candidate_admitted_ns = None
    marker = slot_directory() / 'shadow-events' / (key + '.admitted')
    def observe_actual():
        nonlocal actual
        if not shadow or actual or not marker.exists():
            return
        # The legacy wrapper writes this immediately before exec, so even a
        # command shorter than the polling interval has a retained transition.
        event = json.loads(marker.read_text())
        admitted_at = event['timestamp']
        admitted_ns = event['monotonic_ns']
        actual = True
        _log('legacy_admitted', key=key, kind=kind, admitted_at=admitted_at,
             admitted_monotonic_ns=admitted_ns, marker_admission_sha256=event['admission_sha256'],
             scheduler_admitted=candidate_admitted_ns is not None and candidate_admitted_ns <= admitted_ns,
             divergence=candidate_admitted_ns is None or candidate_admitted_ns > admitted_ns,
             queue_age_seconds=queue.status(key)['queue_wait'])
    next_wait_log = 0
    try:
        while identity_alive(identity):
            queue.touch(key, key)
            if token is None:
                free = _available()
                token = queue.claim(key, owner, process=identity, kind_limits=limits) if free >= need else None
                if token is not None and shadow:
                    candidate_admitted_at = time.time()
                    candidate_admitted_ns = time.monotonic_ns()
                    _log('would_admit', key=key, kind=kind,
                         admitted_at=candidate_admitted_at, admitted_monotonic_ns=candidate_admitted_ns,
                         wait_seconds=queue.status(key)['queue_wait'],
                         legacy_admitted=actual, divergence=not actual)
                elif shadow and time.monotonic() >= next_wait_log:
                    state = queue.status(key)
                    _log('waiting', key=key, kind=kind, queue_age_seconds=state['queue_wait'],
                         queue_position=state['queue_position'], resources_in_use=state['resources_in_use'],
                         reason='available memory' if free < need else state['wait_reason'],
                         available_memory_bytes=free, divergence=actual)
                    next_wait_log = time.monotonic() + 60
            elif not queue.renew(key, owner, token):
                if not shadow and identity_alive(identity):
                    os.kill(int(identity.split(':')[1]), signal.SIGTERM)
                return
            observe_actual()
            _shadow_ready(payload)
            time.sleep(.2)
    finally:
        observe_actual()
        queue.cancel(key, key)
        if shadow:
            _log('released', key=key, kind=kind, legacy_admitted=actual,
                 scheduler_admitted=token is not None)
            marker.unlink(missing_ok=True)


def _bytes(value):
    suffix = value[-1:].upper()
    number = value[:-1] if suffix in ('K', 'M', 'G') else value
    if not number.isdigit():
        raise ValueError(f"not a size: '{value}' (use bytes or a K/M/G suffix)")
    return int(number) * {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}.get(suffix, 1)


def _cpus(value):
    result = set()
    for piece in value.split(','):
        if not piece:
            continue
        bounds = piece.split('-')
        if len(bounds) > 2 or not all(part.isdigit() for part in bounds):
            raise ValueError('not a CPU list: ' + value)
        low, high = int(bounds[0]), int(bounds[-1])
        if low > high:
            raise ValueError('not a CPU list: ' + value)
        result.update(range(low, high + 1))
    return result


def _lock(path):
    stream = path.open('a+')
    try:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        stream.close()
        return None
    return stream


def _available():
    return next(int(line.split()[1])*1024 for line in Path('/proc/meminfo').read_text().splitlines()
                if line.startswith('MemAvailable:'))


def _holder_cpus(path):
    """Read the actual flock owner's affinity; unknown ownership is not proof."""
    stat = path.stat()
    for line in Path('/proc/locks').read_text().splitlines():
        fields = line.split()
        if len(fields) < 6 or fields[1] != 'FLOCK':
            continue
        device = fields[5].split(':')
        if len(device) != 3:
            continue
        if (int(device[0], 16), int(device[1], 16), int(device[2])) != (
                os.major(stat.st_dev), os.minor(stat.st_dev), stat.st_ino):
            continue
        try:
            return set(os.sched_getaffinity(int(fields[4])))
        except (OSError, ValueError):
            return None
    return None


def _cpu_policy(queue, kind, *, shadow=False):
    directory = slot_directory()
    allowed = set(os.sched_getaffinity(0))
    prefix = 'shadow-' if shadow else ''
    reserve_file = directory / (prefix + 'timing-cpus.json')
    reservation = _cpus(os.environ.get('SELKA_TIMING_CPUS', ''))
    policy = _lock(directory / (prefix + 'policy.lock'))
    while policy is None:
        time.sleep(.02)
        policy = _lock(directory / (prefix + 'policy.lock'))
    try:
        stored = set(json.loads(reserve_file.read_text())) if reserve_file.exists() else set()
        if reservation and reservation != stored:
            if not reservation < allowed:
                raise ValueError('SELKA_TIMING_CPUS must leave allowed CPUs for ordinary work')
            with queue._transaction() as db:
                queue._reap(db, time.time())
                if db.execute("SELECT count(*) FROM jobs WHERE state IN ('queued','running')").fetchone()[0]:
                    raise ValueError('timing CPU reservation may change only while admission is idle')
            reserve_file.write_text(json.dumps(sorted(reservation)))
            stored = reservation
        reservation = stored
    finally:
        policy.close()
    cpus = allowed.intersection(reservation) if kind == 'timing' and reservation else allowed - reservation
    if not cpus:
        raise ValueError('SELKA_TIMING_CPUS leaves no CPU for ' + kind)
    return cpus, reservation


def _settle(stream, seconds, slot_lock):
    """Hold the admission lock STREAM for at most SECONDS after an admission, in a detached timer.

    The timer waits for SLOT_LOCK, the lock the admitted job holds, so the delay ends the moment the job has exited:
    it exists so the next memory check sees the job's footprint, and a job that is gone has none (the legacy
    wrapper's rule, `scripts/build_slot_legacy.sh`).
    """
    if seconds == 0:
        return
    process = subprocess.Popen(['setsid', 'flock', '-w', str(seconds), str(slot_lock), 'true'],
                               pass_fds=(stream.fileno(),),
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 5
    while process.poll() is None:
        fields = Path(f'/proc/{process.pid}/stat').read_text().rsplit(') ', 1)[1].split()
        if fields[3] == str(process.pid):
            return
        if time.monotonic() >= deadline:
            process.kill()
            process.wait()
            raise ValueError('admission timer did not detach')
        time.sleep(.001)
    raise ValueError('admission timer failed before detaching')


def _reap_tickets(directory):
    """Reap legacy-compatible ticket metadata while the caller holds queue.lock."""
    for ticket in directory.glob('[0-9]*.wait'):
        try:
            pid, birth, boot, created = ticket.read_text().split()
            valid = (pid.isdigit() and birth.isdigit() and created.isdigit() and
                     identity_alive(f'{boot}:{pid}:{birth}'))
        except (OSError, ValueError):
            valid = False
        if not valid:
            ticket.unlink(missing_ok=True)


def _request_age(fallback_started):
    """Seconds since the request began: build-slot.sh's own start (before this interpreter started) when it says so."""
    started_us = os.environ.pop('SELKA_ADMISSION_STARTED_US', '')
    if started_us.isdigit() and len(started_us) == 16:
        return max(0.0, time.time() - int(started_us) / 1e6)
    return time.monotonic() - fallback_started


def _native(kind, command):
    directory = slot_directory()
    directory.mkdir(parents=True, exist_ok=True)
    if os.environ.get('SELKA_ADMISSION_DIR') == str(directory):
        raise ValueError('nested admission would deadlock; run the coordinator directly')
    limits, need = _requirements(kind)
    poll = float(os.environ.get('SELKA_SLOT_POLL', '0.25'))
    settle = int(os.environ.get('SELKA_SLOT_SETTLE', '5'))
    if poll <= 0 or settle < 0:
        raise ValueError('poll must be positive and settle non-negative')
    # The domain reservation is persistent so clients without a local setting
    # still exclude the same CPUs. Changing it requires an idle domain.
    queue = _pool('admission')
    cpus, reservation = _cpu_policy(queue, kind)
    key = uuid.uuid4().hex
    identity = process_identity()
    queue.submit(key, key, worktree=str(Path.cwd()), kind=kind, cpu_set=cpus,
                 exclusive=kind == 'timing' and not reservation, process=identity,
                 memory=_reservation(queue, need),
                 priority=0 if kind == 'timing' else 1)
    ticket_dir = directory / ('queue-' + kind)
    ticket_dir.mkdir(exist_ok=True)
    with (ticket_dir / 'queue.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        _reap_tickets(ticket_dir)
        sequence = ticket_dir / 'sequence'
        number = int(sequence.read_text()) + 1 if sequence.exists() else 1
        sequence.write_text(str(number) + '\n')
        ticket = ticket_dir / ('%020d.wait' % number)
        boot, pid, birth = identity.split(':')
        ticket.write_text(f'{pid} {birth} {boot} {int(time.time())}\n')
    started = time.monotonic()
    next_touch = started + queue.client_lease / 3
    next_report = 0
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda number, _frame: sys.exit(128 + number))
    try:
        while True:
            parent = os.environ.get('SELKA_ADMISSION_PARENT_PID')
            if parent and (process_identity(int(parent)) or '').split(':')[-1] != os.environ.get('SELKA_ADMISSION_PARENT_START'):
                raise SystemExit(143)
            if time.monotonic() >= next_touch:
                queue.touch(key, key)
                next_touch = time.monotonic() + queue.client_lease / 3
            admitted = _lock(directory / 'admit.lock')
            # A reserved window holds the compatibility lock to exclude older
            # wrappers. New clients may enter only when their CPUs are disjoint.
            if admitted is None and kind != 'timing' and reservation:
                with queue._transaction(write=False) as db:
                    windows = db.execute("SELECT cpu_set FROM jobs WHERE state='running' AND kind='timing'").fetchall()
                if windows and all(not cpus.intersection(json.loads(row[0])) for row in windows):
                    admitted = _lock(directory / 'parallel-admit.lock')
            if admitted is not None:
                try:
                    free = _available()
                    slot = next(((n, held) for n in range(1, limits[kind] + 1)
                                 if (held := _lock(directory / f'{kind}{n}.lock')) is not None), None)
                    if slot is not None:
                        n, held = slot
                        try:
                            # Unknown legacy holders have no affinity proof: drain
                            # them before timing, including slots above our count.
                            drained = True
                            if kind == 'timing':
                                for path in [*directory.glob('build[0-9]*.lock'), *directory.glob('gate[0-9]*.lock')]:
                                    check = _lock(path)
                                    if check is None:
                                        holder_cpus = _holder_cpus(path)
                                        if holder_cpus is None or cpus.intersection(holder_cpus):
                                            drained = False
                                    else:
                                        check.close()
                            token = queue.claim(key, key, process=identity, kind_limits=limits) if free >= need and drained else None
                            if token is not None:
                                if kind != 'timing':
                                    _settle(admitted, settle, directory / f'{kind}{n}.lock')
                                _detached('--lease-watch', dict(identity=identity, key=key, kind=kind, owner=key, token=token))
                                ticket.unlink(missing_ok=True)
                                os.set_inheritable(held.fileno(), True)
                                if kind == 'timing':
                                    os.set_inheritable(admitted.fileno(), True)
                                else:
                                    admitted.close()
                                waited = _request_age(started)
                                os.environ.update(SELKA_ADMISSION_DIR=str(directory), SELKA_ADMISSION_KIND=kind,
                                                  SELKA_ADMISSION_WAIT_S=f'{waited:.3f}')
                                os.sched_setaffinity(0, cpus)
                                print(f'build-slot: {kind} slot {n}, FIFO ticket {number} after {waited:.3f}s', file=sys.stderr)
                                for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                                    signal.signal(signum, signal.SIG_DFL)
                                os.execvp(command[0], command)
                        finally:
                            held.close()
                finally:
                    admitted.close()
            if time.monotonic() >= next_report:
                state = queue.status(key)
                print(f'build-slot: FIFO ticket {number}, position {state["queue_position"]}; waiting ({time.monotonic()-started:.3f}s so far)', file=sys.stderr)
                next_report = time.monotonic() + 60
            queue.wait_for_change(min(poll, .5))
    finally:
        ticket.unlink(missing_ok=True)
        queue.cancel(key, key)


def main(argv):
    if argv[:1] == ['--shadow-admitted']:
        if len(argv) != 2:
            raise ValueError('shadow admission marker requires one path')
        marker = Path(argv[1])
        temporary = marker.with_name(marker.name + '.' + str(os.getpid()) + '.tmp')
        with temporary.open('x') as stream:
            json.dump(dict(timestamp=time.time(), monotonic_ns=time.monotonic_ns(),
                           admission_sha256=LOADED_CODE_SHA256), stream)
        os.replace(temporary, marker)
        return 0
    if argv[:1] == ['--parent-guard']:
        # Configure parent-death signaling in a fresh, single-threaded process,
        # avoiding Python preexec_fn locks in the worker's heartbeat thread.
        if len(argv) < 3:
            raise ValueError('parent guard requires an identity and command')
        library = ctypes.CDLL(None, use_errno=True)
        if library.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'cannot set parent-death signal')
        if process_identity(os.getppid()) != argv[1]:
            return 143
        os.execvp(argv[2], argv[2:])
    if argv == ['--hold']:
        print(json.dumps({'cpus': sorted(os.sched_getaffinity(0)),
                          'markers': {key: os.environ[key] for key in MARKERS}}), flush=True)
        sys.stdin.buffer.read()
        return 0
    if argv == ['--keyed-worker']:
        keyed_worker(json.load(sys.stdin))
        return 0
    if argv in (['--shadow-watch'], ['--lease-watch']):
        payload = json.load(sys.stdin)
        try:
            _watch(payload, argv == ['--shadow-watch'])
        except Exception as error:
            if argv == ['--shadow-watch']:
                _log('shadow_error', key=payload['key'], kind=payload['kind'], reason=str(error))
            else:
                raise
        finally:
            descriptor = payload.pop('ready_fd', None)
            if descriptor is not None:
                os.close(descriptor)
        return 0
    if not argv or argv[0] not in ('build', 'gate', 'timing', 'watch', 'status'):
        raise ValueError('usage: build-slot.sh build|gate|timing|watch [--] CMD... | status')
    kind, *command = argv
    if command[:1] == ['--']:
        command.pop(0)
    os.environ['SELKA_SLOT_DIR'] = str(slot_directory())
    if kind == 'watch':
        # A watcher holds a watch slot and no build slot, under every backend: its rebuilds are the build admissions its
        # daemon requests, which the backends see as builds. The scheduler and its shadow have no watch kind to observe.
        if not command:
            raise ValueError('no command given')
        os.execv(str(SLOT.with_name('build_slot_legacy.sh')), [str(SLOT), kind, *command])
    backend = os.environ.get('SELKA_ADMISSION_BACKEND', 'shadow')
    if backend not in ('legacy', 'shadow', 'scheduler'):
        raise ValueError('SELKA_ADMISSION_BACKEND must be legacy, shadow or scheduler')
    if kind != 'status' and not command:
        raise ValueError('no command given')
    if backend == 'scheduler' and kind == 'status':
        policy = slot_directory() / 'timing-cpus.json'
        if policy.exists():
            os.environ['SELKA_TIMING_CPUS'] = ','.join(map(str, json.loads(policy.read_text())))
        print('admission backend: scheduler (qualification opt-in)', flush=True)
    if backend == 'scheduler' and kind != 'status':
        _native(kind, command)
    if backend == 'shadow' and kind != 'status':
        key = uuid.uuid4().hex
        try:
            marker = slot_directory() / 'shadow-events' / (key + '.admitted')
            marker.parent.mkdir(parents=True, exist_ok=True)
            os.environ['SELKA_SHADOW_ADMITTED_MARKER'] = str(marker)
            # Shadow diagnostics must not indefinitely delay real admission.
            _log('request', lock_timeout=2, key=key, kind=kind,
                 identity=process_identity(), worktree=str(Path.cwd()))
            _detached('--shadow-watch', dict(identity=process_identity(), key=key,
                                           kind=kind, worktree=str(Path.cwd())), ready=True)
        except OSError as error:
            try:
                _log('shadow_error', lock_timeout=2, key=key, kind=kind, reason=str(error))
            except OSError:
                pass
            print('build-slot: shadow observation unavailable: ' + str(error), file=sys.stderr)
    os.execv(str(SLOT.with_name('build_slot_legacy.sh')), [str(SLOT), kind, *command])


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (ValueError, OSError) as error:
        print('build-slot: ' + str(error), file=sys.stderr)
        raise SystemExit(2)
