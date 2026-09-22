"""Trusted-machine SQLite verification coordination; no daemon is required."""
from __future__ import annotations

import contextlib
import json
import math
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import threading
import time
import uuid


_worker = threading.local()


def current_cancelled():
    """Subprocess runners poll this to honor subscriber cancellation and lease loss."""
    return getattr(_worker, 'cancelled', lambda: False)()


class Cancelled(RuntimeError):
    pass


class Scheduler:
    def __init__(self, path, *, cpus=4, memory=4096, workers=4, lease=30, aging=5):
        if any(not math.isfinite(value) or value <= 0 for value in (cpus, memory, workers, lease, aging)) or type(workers) is not int:
            raise ValueError('scheduler limits and lease must be positive')
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.lease, self.aging = lease, aging
        self.client_lease = max(lease * 3, 1)
        with sqlite3.connect(self.path, timeout=30, isolation_level=None) as setup:
            setup.execute('PRAGMA journal_mode=WAL')
        with self._transaction() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS config(id INTEGER PRIMARY KEY, cpus REAL, memory REAL, workers INTEGER);
                CREATE TABLE IF NOT EXISTS jobs(key TEXT PRIMARY KEY, state TEXT, created REAL,
                    priority INTEGER, cpus REAL, memory REAL, exclusive INTEGER, generation INTEGER,
                    owner TEXT, deadline REAL, result TEXT, started REAL, finished REAL);
                CREATE TABLE IF NOT EXISTS subscribers(key TEXT, client TEXT, deadline REAL, PRIMARY KEY(key,client));
            ''')
            columns = [row[1] for row in db.execute('PRAGMA table_info(subscribers)')]
            if 'deadline' not in columns:
                db.execute('ALTER TABLE subscribers ADD COLUMN deadline REAL DEFAULT 0')
            db.execute('INSERT OR IGNORE INTO config VALUES(1,?,?,?)', (cpus, memory, workers))
            actual = db.execute('SELECT cpus,memory,workers FROM config').fetchone()
            if tuple(actual) != (cpus, memory, workers):
                raise ValueError('shared scheduler resource configuration differs')

    @contextlib.contextmanager
    def _transaction(self, *, write=True):
        db = sqlite3.connect(self.path, timeout=30, isolation_level=None)
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

    def submit(self, key, client, *, cpus=1, memory=256, priority=1, exclusive=False):
        if any(not math.isfinite(value) or value <= 0 for value in (cpus, memory)) or priority not in (0, 1, 2):
            raise ValueError('invalid resources or priority (0=interactive, 1=merge, 2=audit)')
        with self._transaction() as db:
            limits = db.execute('SELECT * FROM config').fetchone()
            if cpus > limits['cpus'] or memory > limits['memory']:
                raise ValueError('job exceeds scheduler capacity')
            db.execute('INSERT OR IGNORE INTO jobs VALUES(?,?,?,?,?,?,?,0,NULL,0,NULL,NULL,NULL)',
                       (key, 'queued', time.time(), priority, cpus, memory, int(exclusive)))
            job = db.execute('SELECT * FROM jobs WHERE key=?', (key,)).fetchone()
            if (job['cpus'], job['memory'], job['exclusive']) != (cpus, memory, int(exclusive)):
                raise ValueError('same job key has different resource requirements')
            if job['state'] == 'cancelled':
                db.execute("UPDATE jobs SET state='queued',created=?,result=NULL WHERE key=?", (time.time(), key))
            db.execute('INSERT OR REPLACE INTO subscribers VALUES(?,?,?)', (key, client, time.time()+self.client_lease))

    def touch(self, key, client):
        with self._transaction() as db:
            db.execute('UPDATE subscribers SET deadline=? WHERE key=? AND client=?',
                       (time.time()+self.client_lease, key, client))

    def cancel(self, key, client):
        with self._transaction() as db:
            db.execute('DELETE FROM subscribers WHERE key=? AND client=?', (key, client))
            count = db.execute('SELECT count(*) FROM subscribers WHERE key=?', (key,)).fetchone()[0]
            if not count:
                db.execute("DELETE FROM jobs WHERE key=? AND state='done'", (key,))
                db.execute("UPDATE jobs SET state='cancelled',generation=generation+1 WHERE key=? AND state IN ('queued','running')", (key,))

    def claim(self, key, owner):
        with self._transaction() as db:
            now = time.time()
            db.execute('DELETE FROM subscribers WHERE deadline<?', (now,))
            db.execute("UPDATE jobs SET state='cancelled',generation=generation+1 WHERE state IN ('queued','running') AND NOT EXISTS (SELECT 1 FROM subscribers s WHERE s.key=jobs.key)")
            db.execute("UPDATE jobs SET state='queued',owner=NULL WHERE state='running' AND deadline<?", (now,))
            queued = db.execute("SELECT * FROM jobs WHERE state='queued' ORDER BY created").fetchall()
            # Waiting jobs gain unbounded priority, so a stream of interactive jobs cannot starve audits.
            queued = sorted(queued, key=lambda row: (row['priority'] - (now-row['created'])/self.aging, row['created']))
            if not queued or queued[0]['key'] != key:
                return None
            job = queued[0]
            running = db.execute("SELECT * FROM jobs WHERE state='running'").fetchall()
            limits = db.execute('SELECT * FROM config').fetchone()
            if len(running) >= limits['workers'] or any(row['exclusive'] for row in running):
                return None
            if job['exclusive'] and running:
                return None
            if sum(row['cpus'] for row in running)+job['cpus'] > limits['cpus']:
                return None
            if sum(row['memory'] for row in running)+job['memory'] > limits['memory']:
                return None
            generation = job['generation'] + 1
            db.execute("UPDATE jobs SET state='running',owner=?,generation=?,deadline=?,started=? WHERE key=?",
                       (owner, generation, now+self.lease, now, key))
            return generation

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
            waiting = db.execute("SELECT key,created,priority FROM jobs WHERE state='queued'").fetchall()
            waiting = sorted(waiting, key=lambda row: row['created'] + row['priority']*self.aging)
            result['queue_position'] = next((n+1 for n, item in enumerate(waiting) if item['key'] == key), None)
            result['resources_in_use'] = dict(db.execute("SELECT count(*) AS workers,coalesce(sum(cpus),0) AS cpus,coalesce(sum(memory),0) AS memory FROM jobs WHERE state='running'").fetchone())
            result['queue_wait'] = (row['started'] or time.time()) - row['created']
            result['execution_time'] = None if row['started'] is None else (row['finished'] or time.time())-row['started']
            result['wait_reason'] = 'priority or resource capacity' if row['state'] == 'queued' else None
            return result

    def execute(self, key, execute, *, client=None, cancel=None, **resources):
        client = client or uuid.uuid4().hex
        owner = uuid.uuid4().hex
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
                    time.sleep(0.02)
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
