"""Trusted-machine SQLite verification coordination; no daemon is required."""
from __future__ import annotations

import contextlib
import ctypes
import json
import math
import os
from pathlib import Path
import signal
import select
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
import verification_code_identity as code_identity


_worker = threading.local()


def current_cancelled():
    """Subprocess runners poll this to honor subscriber cancellation and lease loss."""
    return getattr(_worker, 'cancelled', lambda: False)()


class Cancelled(RuntimeError):
    pass


def slot_directory():
    """Resolve the one admission domain for shell, phase and keyed clients."""
    if os.environ.get('SELKA_SLOT_DIR'):
        return Path(os.environ['SELKA_SLOT_DIR']).resolve()
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if runtime and Path(runtime).is_dir():
        return (Path(runtime) / 'selka-slots').resolve()
    return (Path.home() / '.cache/selka/slots').resolve()


def process_identity(pid=None):
    """Use boot, PID and start time to distinguish dead and reused processes."""
    pid = os.getpid() if pid is None else pid
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(') ', 1)[1].split()
        if fields[0] in ('Z', 'X'):
            return None
        return f'{Path("/proc/sys/kernel/random/boot_id").read_text().strip()}:{pid}:{fields[19]}'
    except (OSError, IndexError):
        return None


def identity_alive(identity):
    if not identity:
        return True
    try:
        return process_identity(int(identity.split(':')[1])) == identity
    except (ValueError, IndexError):
        return False


def busy_seconds():
    """How long a connection waits for SQLite's database lock before it gives up with `database is locked`: 30 seconds,
    or `SELKA_SCHEDULER_BUSY_SECONDS`. The wait ends the moment the lock is free, so a long budget costs nothing when
    holders are quick; a harness on a machine so loaded that a lock holder (a process that must be started, or paged in,
    while it holds the lock) can stall for longer than 30 seconds raises it, instead of failing on the clock."""
    try:
        return max(1.0, float(os.environ.get('SELKA_SCHEDULER_BUSY_SECONDS', '30')))
    except ValueError:
        return 30.0


def _enable_wal(path, *, timeout=None):
    """Retry competing journal-mode upgrades within one bounded busy budget."""
    deadline = time.monotonic() + (busy_seconds() if timeout is None else timeout)
    last_busy = None
    while True:
        remaining = max(0, deadline - time.monotonic())
        if last_busy is not None and not remaining:
            raise last_busy
        try:
            # SQLite can return BUSY immediately on a lock upgrade, without
            # invoking its busy handler. A fresh connection releases all state
            # before retrying; its own busy wait cannot reset our deadline.
            with contextlib.closing(sqlite3.connect(path, timeout=remaining, isolation_level=None)) as setup:
                mode = setup.execute('PRAGMA journal_mode=WAL').fetchone()[0]
            if mode != 'wal':
                raise RuntimeError(f'scheduler requires WAL journal mode, got {mode!r}')
            return
        except sqlite3.OperationalError as error:
            if getattr(error, 'sqlite_errorcode', 0) & 0xff != sqlite3.SQLITE_BUSY:
                raise
            last_busy = error
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise
            time.sleep(min(.01, remaining))


class Scheduler:
    def __init__(self, path, *, cpus=4, memory=4096, workers=4, lease=30, aging=5):
        if any(not math.isfinite(value) or value <= 0 for value in (cpus, memory, workers, lease, aging)) or type(workers) is not int:
            raise ValueError('scheduler limits and lease must be positive')
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.lease, self.aging = lease, aging
        self.client_lease = max(lease * 3, 1)
        _enable_wal(self.path)
        with self._transaction() as db:
            # executescript commits an existing transaction before its script.
            # Keep both schema inspection and migration under BEGIN IMMEDIATE.
            db.execute('CREATE TABLE IF NOT EXISTS config(id INTEGER PRIMARY KEY, cpus REAL, memory REAL, workers INTEGER)')
            db.execute('''CREATE TABLE IF NOT EXISTS jobs(key TEXT PRIMARY KEY, state TEXT, created REAL,
                          priority INTEGER, cpus REAL, memory REAL, exclusive INTEGER, generation INTEGER,
                          owner TEXT, deadline REAL, result TEXT, started REAL, finished REAL)''')
            db.execute('CREATE TABLE IF NOT EXISTS subscribers(key TEXT, client TEXT, deadline REAL, PRIMARY KEY(key,client))')
            assert db.in_transaction, 'schema migration lost the write transaction'
            columns = [row[1] for row in db.execute('PRAGMA table_info(subscribers)')]
            if 'deadline' not in columns:
                db.execute('ALTER TABLE subscribers ADD COLUMN deadline REAL DEFAULT 0')
            if 'process' not in columns:
                db.execute('ALTER TABLE subscribers ADD COLUMN process TEXT')
            columns = [row[1] for row in db.execute('PRAGMA table_info(jobs)')]
            for name, declaration in [('worktree', "TEXT DEFAULT ''"), ('kind', "TEXT DEFAULT ''"),
                                      ('cpu_set', "TEXT DEFAULT '[]'"), ('process', 'TEXT')]:
                if name not in columns:
                    db.execute(f'ALTER TABLE jobs ADD COLUMN {name} {declaration}')
            db.execute('CREATE TABLE IF NOT EXISTS fair_share(worktree TEXT PRIMARY KEY, admissions INTEGER DEFAULT 0)')
            db.execute('INSERT OR IGNORE INTO config VALUES(1,?,?,?)', (cpus, memory, workers))
            actual = db.execute('SELECT cpus,memory,workers FROM config').fetchone()
            if tuple(actual) != (cpus, memory, workers):
                raise ValueError('shared scheduler resource configuration differs')

    @contextlib.contextmanager
    def _transaction(self, *, write=True):
        db = sqlite3.connect(self.path, timeout=busy_seconds(), isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE' if write else 'BEGIN')
            yield db
            if db.in_transaction:
                db.commit()
        except BaseException:
            if db.in_transaction:
                db.rollback()
            raise
        finally:
            db.close()

    def submit(self, key, client, *, cpus=1, memory=256, priority=1, exclusive=False,
               worktree='', kind='', cpu_set=(), process=None):
        if any(not math.isfinite(value) or value <= 0 for value in (cpus, memory)) or priority not in (0, 1, 2):
            raise ValueError('invalid resources or priority (0=interactive, 1=merge, 2=audit)')
        with self._transaction() as db:
            limits = db.execute('SELECT * FROM config').fetchone()
            if cpus > limits['cpus'] or memory > limits['memory']:
                raise ValueError('job exceeds scheduler capacity')
            db.execute('INSERT OR IGNORE INTO jobs(key,state,created,priority,cpus,memory,exclusive,generation,deadline,worktree,kind,cpu_set) VALUES(?,?,?,?,?,?,?,0,0,?,?,?)',
                       (key, 'queued', time.time(), priority, cpus, memory, int(exclusive),
                        str(worktree), kind, json.dumps(sorted(set(cpu_set)))))
            job = db.execute('SELECT * FROM jobs WHERE key=?', (key,)).fetchone()
            if (job['cpus'], job['memory'], job['exclusive']) != (cpus, memory, int(exclusive)):
                raise ValueError('same job key has different resource requirements')
            if job['state'] == 'cancelled':
                db.execute("UPDATE jobs SET state='queued',created=?,result=NULL WHERE key=?", (time.time(), key))
            db.execute('INSERT OR REPLACE INTO subscribers(key,client,deadline,process) VALUES(?,?,?,?)',
                       (key, client, time.time()+self.client_lease, process))

    def touch(self, key, client):
        with self._transaction() as db:
            db.execute('UPDATE subscribers SET deadline=? WHERE key=? AND client=?',
                       (time.time()+self.client_lease, key, client))

    def wait_for_change(self, timeout=.5):
        """Wake on SQLite/WAL changes; a bounded fallback also reaps dead owners."""
        library = ctypes.CDLL(None, use_errno=True)
        descriptor = library.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if descriptor < 0:
            time.sleep(timeout)
            return
        try:
            mask = 0x2 | 0x8 | 0x80 | 0x100 | 0x200  # modify, close, move, create, delete
            if library.inotify_add_watch(descriptor, os.fsencode(Path(self.path).parent), mask) < 0:
                time.sleep(timeout)
            else:
                select.select([descriptor], [], [], timeout)
        finally:
            os.close(descriptor)

    def cancel(self, key, client):
        with self._transaction() as db:
            db.execute('DELETE FROM subscribers WHERE key=? AND client=?', (key, client))
            count = db.execute('SELECT count(*) FROM subscribers WHERE key=?', (key,)).fetchone()[0]
            if not count:
                db.execute("DELETE FROM jobs WHERE key=? AND state='done'", (key,))
                db.execute("UPDATE jobs SET state='cancelled',generation=generation+1 WHERE key=? AND state IN ('queued','running')", (key,))

    def _reap(self, db, now):
        for row in db.execute('SELECT key,client,process FROM subscribers WHERE process IS NOT NULL').fetchall():
            if not identity_alive(row['process']):
                db.execute('DELETE FROM subscribers WHERE key=? AND client=?', (row['key'], row['client']))
        db.execute('DELETE FROM subscribers WHERE deadline<?', (now,))
        db.execute("UPDATE jobs SET state='cancelled',generation=generation+1 WHERE state IN ('queued','running') AND NOT EXISTS (SELECT 1 FROM subscribers s WHERE s.key=jobs.key)")
        for row in db.execute("SELECT key,process FROM jobs WHERE state='running' AND process IS NOT NULL").fetchall():
            if not identity_alive(row['process']):
                db.execute("UPDATE jobs SET state='queued',owner=NULL,process=NULL WHERE key=?", (row['key'],))
        db.execute("UPDATE jobs SET state='queued',owner=NULL,process=NULL WHERE state='running' AND deadline<?", (now,))

    def _ordered(self, db, now):
        queued = db.execute("SELECT * FROM jobs WHERE state='queued' ORDER BY created,key").fetchall()
        shares = dict(db.execute('SELECT worktree,admissions FROM fair_share'))
        active = {}
        for row in db.execute("SELECT worktree,count(*) FROM jobs WHERE state='running' GROUP BY worktree"):
            active[row[0]] = row[1]
        # Aging eventually outranks both priorities and fair share. FIFO holds
        # within a worktree and effective priority; quieter worktrees go first.
        return sorted(queued, key=lambda row: (
            row['priority'] - int((now-row['created']) / self.aging),
            active.get(row['worktree'], 0), shares.get(row['worktree'], 0), row['created']))

    def claim(self, key, owner, *, process=None, kind_limits=None):
        with self._transaction() as db:
            now = time.time()
            self._reap(db, now)
            queued = self._ordered(db, now)
            running = db.execute("SELECT * FROM jobs WHERE state='running'").fetchall()
            limits = db.execute('SELECT * FROM config').fetchone()
            if len(running) >= limits['workers'] or any(row['exclusive'] for row in running):
                return None
            job = next((row for row in queued if row['key'] == key), None)
            if job is None:
                return None
            # Independent kinds can progress around a full kind's queue, while
            # earlier work in that kind retains FIFO/fair-share precedence.
            contenders = [row for row in queued if not kind_limits or
                          sum(active['kind'] == row['kind'] for active in running) < kind_limits.get(row['kind'], limits['workers'])]
            if kind_limits:
                contenders = [row for row in contenders if row['kind'] == job['kind'] or row['exclusive']]
            if not contenders or contenders[0]['key'] != key:
                return None
            if job['exclusive'] and running:
                return None
            cpus = set(json.loads(job['cpu_set']))
            if any((job['kind'] == 'timing' or row['kind'] == 'timing') and
                   cpus.intersection(json.loads(row['cpu_set'])) for row in running):
                return None
            if sum(row['cpus'] for row in running)+job['cpus'] > limits['cpus']:
                return None
            if sum(row['memory'] for row in running)+job['memory'] > limits['memory']:
                return None
            generation = job['generation'] + 1
            db.execute("UPDATE jobs SET state='running',owner=?,generation=?,deadline=?,started=?,process=? WHERE key=?",
                       (owner, generation, now+self.lease, now, process, key))
            db.execute('INSERT INTO fair_share(worktree,admissions) VALUES(?,1) ON CONFLICT(worktree) DO UPDATE SET admissions=admissions+1', (job['worktree'],))
            return generation

    @staticmethod
    def claimable(state, now=None):
        """Whether `claim` could succeed for a job in `state` (a row of `status`): it is queued, or running under an
        owner that is gone (its lease ran out, or its process died). A job running under a live owner, or one that is
        done or cancelled, cannot be claimed, and asking still takes the write lock to find that out: a subscriber
        that polls with `claim` on every wake-up makes every other writer wait behind it."""
        if state is None or state['state'] == 'queued':
            return True
        if state['state'] != 'running':
            return False
        return state['deadline'] < (time.time() if now is None else now) or not identity_alive(state['process'])

    def renew(self, key, owner, generation):
        with self._transaction() as db:
            return db.execute("UPDATE jobs SET deadline=? WHERE key=? AND owner=? AND generation=? AND state='running' AND deadline>=?",
                              (time.time()+self.lease, key, owner, generation, time.time())).rowcount == 1

    def publish(self, key, owner, generation, result):
        with self._transaction() as db:
            return db.execute("UPDATE jobs SET state='done',result=?,finished=? WHERE key=? AND owner=? AND generation=? AND state='running' AND deadline>=?",
                              (json.dumps(result), time.time(), key, owner, generation, time.time())).rowcount == 1

    def status(self, key):
        with self._transaction(write=False) as db:
            row = db.execute('SELECT * FROM jobs WHERE key=?', (key,)).fetchone()
            if row is None:
                return None
            result = dict(row)
            result['subscribers'] = db.execute('SELECT count(*) FROM subscribers WHERE key=?', (key,)).fetchone()[0]
            waiting = self._ordered(db, time.time())
            result['queue_position'] = next((n+1 for n, item in enumerate(waiting) if item['key'] == key), None)
            result['resources_in_use'] = dict(db.execute("SELECT count(*) AS workers,coalesce(sum(cpus),0) AS cpus,coalesce(sum(memory),0) AS memory FROM jobs WHERE state='running'").fetchone())
            result['queue_wait'] = (row['started'] or time.time()) - row['created']
            result['execution_time'] = None if row['started'] is None else (row['finished'] or time.time())-row['started']
            result['wait_reason'] = 'priority or resource capacity' if row['state'] == 'queued' else None
            return result

    def execute(self, key, execute, *, client=None, cancel=None, **resources):
        client = client or uuid.uuid4().hex
        owner = uuid.uuid4().hex
        resources.setdefault('worktree', str(Path.cwd()))
        self.submit(key, client, **resources)
        next_touch = time.monotonic() + self.client_lease / 3
        try:
            while True:
                if time.monotonic() >= next_touch:
                    self.touch(key, client)
                    next_touch = time.monotonic() + self.client_lease / 3
                if cancel is not None and cancel.is_set():
                    raise Cancelled(key)
                state = self.status(key)
                if state['state'] == 'done':
                    result = json.loads(state['result'])
                    result.update(coalesced=True, executed=False)
                    if result.get('passed'):
                        result['status'] = 'cached'
                    return result
                if state['state'] == 'cancelled':
                    raise Cancelled(key)
                token = self.claim(key, owner) if state['state'] == 'queued' or state['deadline'] < time.time() else None
                if token is None:
                    self.wait_for_change()
                    continue
                stop = threading.Event()
                def heartbeat():
                    while not stop.wait(max(0.01, self.lease/3)):
                        self.touch(key, client)
                        if not self.renew(key, owner, token):
                            return
                thread = threading.Thread(target=heartbeat, daemon=True)
                thread.start()
                prior = getattr(_worker, 'cancelled', lambda: False)
                def cancelled():
                    if cancel is not None and cancel.is_set():
                        self.cancel(key, client)
                    state = self.status(key)
                    return (state is None or state['state'] != 'running' or
                            state['owner'] != owner or state['generation'] != token or
                            state['deadline'] < time.time())
                _worker.cancelled = cancelled
                try:
                    result = execute()
                    if not self.publish(key, owner, token, result):
                        raise Cancelled('lease lost before publication')
                    return result
                finally:
                    _worker.cancelled = prior
                    stop.set()
                    thread.join()
        finally:
            self.cancel(key, client)


def run_process(command, *, cwd=None, env=None, cancelled=lambda: False):
    """Process-group cleanup for workers that execute cancellable subprocesses."""
    process = subprocess.Popen(command, cwd=cwd, env=env, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        while True:
            if cancelled():
                raise Cancelled('job has no subscribers or lost its lease')
            try:
                stdout, stderr = process.communicate(timeout=0.05)
                return {'returncode': process.returncode, 'stdout': stdout.decode(errors='replace'),
                        'stderr': stderr.decode(errors='replace')}
            except subprocess.TimeoutExpired:
                continue
    finally:
        # Also clean descendants when the direct child has already exited.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdout.close()
        process.stderr.close()


def add_arguments(parser):
    """Shared scheduler options for verification and candidate certification."""
    parser.add_argument("--scheduler", type=Path, help="shared SQLite coordinator for v2 verification")
    parser.add_argument("--scheduler-cpus", type=float, default=4)
    parser.add_argument("--scheduler-memory", type=float, default=4096, help="memory admission budget in MiB")
    parser.add_argument("--scheduler-workers", type=int, default=4)
    parser.add_argument("--job-cpus", type=float, default=1)
    parser.add_argument("--job-memory", type=float, default=256)
    parser.add_argument("--priority", choices=("interactive", "merge", "audit"), default="merge")
    parser.add_argument("--exclusive", action="store_true", help="reserve quiet window for all requested jobs")


def executor_from_args(args):
    if args.scheduler is None:
        return None
    from functools import partial
    scheduler = Scheduler(args.scheduler, cpus=args.scheduler_cpus,
                          memory=args.scheduler_memory, workers=args.scheduler_workers)
    return partial(scheduler.execute, cpus=args.job_cpus, memory=args.job_memory,
                   priority=("interactive", "merge", "audit").index(args.priority),
                   exclusive=args.exclusive)


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
