import concurrent.futures
from contextlib import closing, contextmanager
import json
import os
import select
import subprocess
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from verification.scheduler import Cancelled, Scheduler, current_cancelled, run_process
from verification import scheduler as scheduler_backend
import build_admission

# The detached-worker tests wait on conditions (a worker started, a subscriber counted, a result published), each of
# which ends the wait the moment it holds, so a long ceiling costs nothing when the machine is healthy. Starting a
# worker is an interpreter start, which a machine short of memory stretches to minutes.
CONDITION_SECONDS = 600


@contextmanager
def fixture_pool(workers, *, release=lambda: None, cancellations=()):
    """Release fixture work before draining threads, even after an assertion."""
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=workers)
    futures = []
    original = None
    def submit(*args, **kwargs):
        future = pool.submit(*args, **kwargs)
        futures.append(future)
        return future
    try:
        yield submit
    except BaseException as error:
        original = error
        raise
    finally:
        try:
            try:
                release()
            finally:
                for event in cancellations:
                    event.set()
                # __exit__ would wait forever before the fixture can release a
                # worker. Stop accepting work, then explicitly bound the drain.
                pool.shutdown(wait=False, cancel_futures=True)
            _, pending = concurrent.futures.wait(futures, timeout=CONDITION_SECONDS)
            if pending:
                raise AssertionError(f'{len(pending)} fixture subscribers did not stop during cleanup')
            pool.shutdown(wait=True)
        except BaseException as error:
            if original is None:
                raise
            original.add_note('Fixture cleanup also failed: ' + repr(error))


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.scheduler = Scheduler(Path(self.temporary.name)/'queue.db', cpus=2, memory=512, workers=2, lease=30, aging=.05)

    def test_wal_initialization_retries_after_real_lock_contention(self):
        path = Path(self.temporary.name) / 'rollback-reader.db'
        original_connect = sqlite3.connect
        errors = []
        with closing(original_connect(path, isolation_level=None)) as reader:
            reader.execute('CREATE TABLE fixture(value INTEGER)')
            reader.execute('BEGIN')
            reader.execute('SELECT * FROM fixture').fetchall()

            class Connection(sqlite3.Connection):
                def execute(connection, sql, *args, **kwargs):
                    try:
                        return super().execute(sql, *args, **kwargs)
                    except sqlite3.OperationalError as error:
                        if sql == 'PRAGMA journal_mode=WAL':
                            errors.append(error.sqlite_errorcode)
                            # Release the real rollback-journal reader only once
                            # the competing connection has failed its upgrade.
                            reader.rollback()
                        raise

            def connect(*args, **kwargs):
                # Lock upgrades may bypass SQLite's busy handler. Force that
                # immediate-BUSY outcome deterministically with a real lock.
                kwargs.update(timeout=0, factory=Connection)
                return original_connect(*args, **kwargs)

            with patch.object(scheduler_backend.sqlite3, 'connect', side_effect=connect):
                queue = Scheduler(path, cpus=2, memory=512, workers=2)
            self.assertEqual(errors, [sqlite3.SQLITE_BUSY])
            with closing(original_connect(path)) as observer:
                self.assertEqual(observer.execute('PRAGMA journal_mode').fetchone()[0], 'wal')
            queue.submit('after-contention', 'client')
            self.assertEqual(queue.status('after-contention')['subscribers'], 1)

    def test_wal_initialization_stops_at_contention_deadline(self):
        path = Path(self.temporary.name) / 'blocked-rollback-reader.db'
        original_connect = sqlite3.connect
        with closing(original_connect(path, isolation_level=None)) as reader:
            reader.execute('CREATE TABLE fixture(value INTEGER)')
            reader.execute('BEGIN')
            reader.execute('SELECT * FROM fixture').fetchall()
            def connect(*args, **kwargs):
                kwargs['timeout'] = 0
                return original_connect(*args, **kwargs)
            clock = [0.0]
            def advance(seconds):
                clock[0] += seconds
            # Exercise the total retry budget without asserting machine speed.
            with patch.object(scheduler_backend, 'time', SimpleNamespace(
                    monotonic=lambda: clock[0], sleep=advance)), \
                    patch.object(scheduler_backend.sqlite3, 'connect', side_effect=connect) as attempts:
                with self.assertRaises(sqlite3.OperationalError) as raised:
                    scheduler_backend._enable_wal(path, timeout=.1)
            self.assertEqual(raised.exception.sqlite_errorcode, sqlite3.SQLITE_BUSY)
            self.assertGreater(attempts.call_count, 1)
            self.assertEqual(clock[0], .1)
            reader.rollback()
            Scheduler(path, cpus=2, memory=512, workers=2)

    def test_wal_initialization_preserves_non_busy_database_error(self):
        path = Path(self.temporary.name) / 'invalid.db'
        path.write_text('not a SQLite database')
        with patch.object(scheduler_backend.sqlite3, 'connect', wraps=sqlite3.connect) as attempts:
            with self.assertRaises(sqlite3.DatabaseError) as raised:
                Scheduler(path, cpus=2, memory=512, workers=2)
        self.assertEqual(raised.exception.sqlite_errorcode, sqlite3.SQLITE_NOTADB)
        self.assertEqual(attempts.call_count, 1)

    def test_wal_initialization_rejects_database_without_wal_support(self):
        with self.assertRaisesRegex(RuntimeError, "requires WAL journal mode, got 'memory'"):
            Scheduler(':memory:')

    def test_concurrent_processes_initialize_fresh_and_legacy_schemas(self):
        code = ("from pathlib import Path; import sys,time\n"
                "from verification.scheduler import Scheduler\n"
                "while not Path(sys.argv[1]).exists(): time.sleep(.01)\n"
                "queue=Scheduler(sys.argv[2],cpus=2,memory=512,workers=2)\n"
                "queue.submit(sys.argv[3],sys.argv[3])\n")
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                base = Path(self.temporary.name) / str(legacy)
                base.mkdir()
                path, ready = base / 'queue.db', base / 'ready'
                if legacy:
                    with closing(sqlite3.connect(path)) as db:
                        db.executescript('''
                            CREATE TABLE jobs(key TEXT PRIMARY KEY, state TEXT, created REAL,
                                priority INTEGER, cpus REAL, memory REAL, exclusive INTEGER,
                                generation INTEGER, owner TEXT, deadline REAL, result TEXT,
                                started REAL, finished REAL);
                            CREATE TABLE subscribers(key TEXT, client TEXT, PRIMARY KEY(key,client));
                        ''')
                processes = []
                try:
                    for index in range(8):
                        processes.append(subprocess.Popen(
                            [sys.executable, '-B', '-c', code, str(ready), str(path), str(index)],
                            cwd=Path(__file__).resolve().parents[2] / 'scripts',
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE))
                    ready.touch()
                    for process in processes:
                        output, error = process.communicate(timeout=120)
                        self.assertEqual(process.returncode, 0, (output, error))
                finally:
                    for process in processes:
                        if process.poll() is None:
                            process.kill()
                    for process in processes:
                        process.communicate(timeout=10)
                with closing(sqlite3.connect(path)) as db:
                    self.assertEqual(db.execute('SELECT count(*) FROM jobs').fetchone()[0], 8)
                    self.assertEqual(db.execute('SELECT count(*) FROM subscribers').fetchone()[0], 8)
                    for table, required in [('jobs', {'worktree', 'kind', 'cpu_set', 'process'}),
                                            ('subscribers', {'deadline', 'process'})]:
                        columns = [row[1] for row in db.execute('PRAGMA table_info(' + table + ')')]
                        self.assertTrue(required <= set(columns))
                        self.assertEqual(len(columns), len(set(columns)))
                with self.assertRaisesRegex(ValueError, 'shared scheduler resource configuration differs'):
                    Scheduler(path, cpus=3, memory=512, workers=2)

    def test_claim_lease_starts_after_database_lock_wait(self):
        self.scheduler.submit('delayed', 'client')
        locked = threading.Event()
        def holder():
            with closing(sqlite3.connect(self.scheduler.path, isolation_level=None)) as db:
                db.execute('BEGIN IMMEDIATE')
                locked.set()
                time.sleep(.25)
                db.commit()
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            holding = pool.submit(holder)
            self.assertTrue(locked.wait(2))
            token = self.scheduler.claim('delayed', 'owner')
            holding.result()
        self.assertIsNotNone(token)
        self.assertTrue(self.scheduler.publish('delayed', 'owner', token, {'passed': True}))

    def test_ten_clients_coalesce(self):
        barrier = threading.Barrier(10)
        cancel = threading.Event()
        calls = []
        def execute():
            calls.append(1)
            deadline = time.monotonic() + 120
            while self.scheduler.status('same')['subscribers'] < 10:
                if cancel.is_set():
                    raise Cancelled('another fixture subscriber failed')
                if time.monotonic() > deadline:
                    raise AssertionError('clients did not subscribe')
                time.sleep(.01)
            return {'passed': True}
        def client(index):
            try:
                barrier.wait(timeout=120)
                return self.scheduler.execute('same', execute, client=str(index), cancel=cancel)
            except BaseException:
                cancel.set()
                barrier.abort()
                raise
        with fixture_pool(10, cancellations=[cancel]) as submit:
            futures = [submit(client, index) for index in range(10)]
            results = [future.result(timeout=120) for future in futures]
        self.assertEqual(len(calls), 1)
        self.assertTrue(all(row['passed'] for row in results))

    def test_ten_worktrees_share_core_execution(self):
        from verification.core import run_manifest
        base = Path(self.temporary.name)
        data = {'version': 2, 'policy': 'concurrent', 'steps': [
            {'id': 'check', 'kind': 'test', 'complete': True, 'inputs': ['input'],
             'commands': [[sys.executable, '-c', "import time; from pathlib import Path; time.sleep(.15); assert Path('input').read_text() == 'ok'"]]}]}
        manifests = []
        for n in range(10):
            root = base / str(n)
            root.mkdir()
            (root/'input').write_text('ok')
            (root/'verify.json').write_text(json.dumps(data))
            manifests.append(root/'verify.json')
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
            reports = list(pool.map(lambda path: run_manifest(path, cache_dir=base/'cache', executor=self.scheduler.execute), manifests))
        self.assertTrue(all(row['full_manifest_passed'] for row in reports))
        self.assertEqual(sum(row['steps'][0]['executed'] for row in reports), 1)

    def test_worker_process_crash_reclaims_lease(self):
        queue = self.scheduler
        queue.submit('crash', 'client')
        code = "from verification.scheduler import Scheduler; import os; q=Scheduler(__import__('sys').argv[1],cpus=2,memory=512,workers=2,lease=.15,aging=.05); print(q.claim('crash','dead'),flush=True); os._exit(7)"
        result = subprocess.run([sys.executable, '-c', code, queue.path],
                                cwd=Path(__file__).resolve().parents[2]/'scripts', capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        old = int(result.stdout)
        with queue._transaction() as db:
            db.execute("UPDATE jobs SET deadline=0 WHERE key='crash'")
        token = queue.claim('crash', 'replacement')
        self.assertGreater(token, old)
        self.assertTrue(queue.publish('crash', 'replacement', token, {'passed': True}))

    def test_dead_only_client_does_not_block_unrelated_job(self):
        code = "from verification.scheduler import Scheduler; import os; q=Scheduler(__import__('sys').argv[1],cpus=2,memory=512,workers=2,lease=.15,aging=.05); q.submit('orphan','dead'); q.claim('orphan','dead'); os._exit(7)"
        result = subprocess.run([sys.executable, '-c', code, self.scheduler.path],
                                cwd=Path(__file__).resolve().parents[2]/'scripts', capture_output=True)
        self.assertEqual(result.returncode, 7)
        with self.scheduler._transaction() as db:
            db.execute("UPDATE subscribers SET deadline=0 WHERE key='orphan'")
        def survivor():
            # Reap on the first claim, before executing unrelated work. This
            # is the semantic guarantee; filesystem fsync latency is not one.
            self.assertEqual(self.scheduler.status('orphan')['state'], 'cancelled')
            return {'passed': True}
        with patch.object(self.scheduler, 'wait_for_change',
                          side_effect=AssertionError('dead subscriber blocked first admission')):
            result = self.scheduler.execute('survivor', survivor)
        self.assertTrue(result['passed'])
        self.assertEqual(self.scheduler.status('orphan')['state'], 'cancelled')

    def test_reject_nonfinite_limits(self):
        for value in (float('nan'), float('inf'), -1):
            with self.assertRaises(ValueError):
                Scheduler(Path(self.temporary.name)/'invalid', cpus=value)
            with self.assertRaises(ValueError):
                self.scheduler.submit('invalid', 'client', memory=value)

    def test_distinct_jobs_respect_admission_limits(self):
        lock = threading.Lock()
        overlap = threading.Barrier(2)
        active = 0
        peak = 0
        def execute():
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            try:
                overlap.wait(timeout=120)
            finally:
                with lock:
                    active -= 1
            return {'passed': True}
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda n: self.scheduler.execute(str(n), execute), range(6)))
        self.assertEqual(peak, 2)
        self.assertTrue(all(row['passed'] for row in results))

    def test_last_client_cancel_stops_running_process(self):
        cancel = threading.Event()
        timer = threading.Timer(.1, cancel.set)
        timer.start()
        self.addCleanup(timer.join)
        with self.assertRaises(Cancelled):
            self.scheduler.execute('cancel', lambda: run_process(
                [sys.executable, '-c', 'import time; time.sleep(30)'], cancelled=current_cancelled), cancel=cancel)
        self.assertEqual(self.scheduler.status('cancel')['state'], 'cancelled')

    def test_capacity_lease_fence_and_cancellation(self):
        queue = self.scheduler
        for key in ['a', 'b', 'c']:
            queue.submit(key, 'client')
        first = queue.claim('a', 'dead')
        self.assertIsNotNone(first)
        self.assertIsNotNone(queue.claim('b', 'live'))
        self.assertIsNone(queue.claim('c', 'other'))
        with queue._transaction() as db:
            db.execute("UPDATE jobs SET deadline=0 WHERE state='running'")
        replacement = queue.claim('a', 'replacement')
        self.assertGreater(replacement, first)
        self.assertFalse(queue.publish('a', 'dead', first, {'passed': True}))
        queue.submit('a', 'second')
        queue.cancel('a', 'client')
        self.assertEqual(queue.status('a')['state'], 'running')
        queue.cancel('a', 'second')
        self.assertEqual(queue.status('a')['state'], 'cancelled')
        self.assertFalse(queue.publish('a', 'replacement', replacement, {}))
        with self.assertRaises(ValueError):
            queue.submit('huge', 'client', memory=1000)

    def test_aging_and_exclusive(self):
        queue = self.scheduler
        queue.submit('audit', 'a', priority=2, exclusive=True)
        time.sleep(.12)
        queue.submit('interactive', 'b', priority=0)
        token = queue.claim('audit', 'worker')
        self.assertIsNotNone(token)
        self.assertIsNone(queue.claim('interactive', 'worker2'))
        self.assertTrue(queue.publish('audit', 'worker', token, {}))
        self.assertIsNotNone(queue.claim('interactive', 'worker2'))

    def test_subprocess_cancel(self):
        start = time.monotonic()
        with self.assertRaises(Cancelled):
            run_process([sys.executable, '-c', 'import time; time.sleep(30)'],
                        cancelled=lambda: time.monotonic()-start > .1)
        self.assertLess(time.monotonic()-start, 3)

    def test_worktree_fair_share_preserves_fifo_and_aging(self):
        queue = Scheduler(Path(self.temporary.name)/'fair.db', cpus=1, memory=512,
                          workers=1, lease=30, aging=60)
        queue.submit('a1', 'client', worktree='a')
        token = queue.claim('a1', 'owner')
        queue.submit('a2', 'client', worktree='a')
        queue.submit('a3', 'client', worktree='a')
        queue.submit('b1', 'client', worktree='b')
        self.assertTrue(queue.publish('a1', 'owner', token, {}))
        self.assertIsNone(queue.claim('a2', 'owner'))
        token = queue.claim('b1', 'owner')
        self.assertIsNotNone(token)
        self.assertTrue(queue.publish('b1', 'owner', token, {}))
        self.assertIsNone(queue.claim('a3', 'owner'))
        self.assertIsNotNone(queue.claim('a2', 'owner'))

    def test_disjoint_timing_and_builds_share_tokens(self):
        queue = Scheduler(Path(self.temporary.name)/'cpus.db', cpus=3, memory=1024,
                          workers=3, lease=30)
        queue.submit('timing', 'client', kind='timing', cpu_set=[0])
        queue.submit('build1', 'client', kind='build', cpu_set=[1, 2])
        queue.submit('build2', 'client', kind='build', cpu_set=[1, 2])
        queue.submit('overlap', 'client', kind='build', cpu_set=[0, 1])
        self.assertIsNotNone(queue.claim('timing', 'owner'))
        self.assertIsNotNone(queue.claim('build1', 'owner'))
        self.assertIsNotNone(queue.claim('build2', 'owner'))
        self.assertIsNone(queue.claim('overlap', 'owner'))

    def test_dead_process_subscriber_releases_without_waiting_for_lease(self):
        queue = self.scheduler
        queue.submit('dead', 'client', process='previous-boot:1:1')
        queue.submit('next', 'client')
        self.assertIsNotNone(queue.claim('next', 'owner'))
        self.assertEqual(queue.status('dead')['state'], 'cancelled')

    def test_busy_budget_is_thirty_seconds_unless_the_environment_says_otherwise(self):
        with patch.dict(os.environ, clear=False):
            os.environ.pop('SELKA_SCHEDULER_BUSY_SECONDS', None)
            self.assertEqual(scheduler_backend.busy_seconds(), 30)
            os.environ['SELKA_SCHEDULER_BUSY_SECONDS'] = '600'
            self.assertEqual(scheduler_backend.busy_seconds(), 600)
            os.environ['SELKA_SCHEDULER_BUSY_SECONDS'] = 'soon'
            self.assertEqual(scheduler_backend.busy_seconds(), 30)
            os.environ['SELKA_SCHEDULER_BUSY_SECONDS'] = '0'
            self.assertEqual(scheduler_backend.busy_seconds(), 1)

    def test_claimable_names_the_jobs_a_claim_can_take(self):
        queue = self.scheduler
        now = time.time()
        live = {'state': 'running', 'deadline': now + 100, 'process': None}
        self.assertTrue(Scheduler.claimable(None))
        self.assertTrue(Scheduler.claimable({'state': 'queued', 'deadline': 0, 'process': None}))
        self.assertFalse(Scheduler.claimable(live, now))
        self.assertTrue(Scheduler.claimable(dict(live, deadline=now - 1), now), 'lease ran out')
        self.assertTrue(Scheduler.claimable(dict(live, process='previous-boot:1:1'), now), 'owner process died')
        self.assertFalse(Scheduler.claimable({'state': 'done', 'deadline': 0, 'process': None}, now))
        self.assertFalse(Scheduler.claimable({'state': 'cancelled', 'deadline': 0, 'process': None}, now))
        # The same answer from a real queue: claimable until claimed, not after, not once published.
        queue.submit('job', 'client')
        self.assertTrue(Scheduler.claimable(queue.status('job')))
        token = queue.claim('job', 'owner')
        self.assertFalse(Scheduler.claimable(queue.status('job')))
        self.assertTrue(queue.publish('job', 'owner', token, {}))
        self.assertFalse(Scheduler.claimable(queue.status('job')))


class DetachedSubscriptions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        # The lock wait is on a condition too: a holder stalled by a loaded machine (a worker still being started or
        # paged in while it holds the write lock) must not be taken for a stuck one at the product's 30 seconds.
        environment = dict(os.environ, SELKA_SLOT_DIR=str(self.root / 'slots'),
                           SELKA_SCHEDULER_BUSY_SECONDS=str(CONDITION_SECONDS))
        for name in build_admission.MARKERS:
            environment.pop(name, None)
        self.patch = patch.dict(os.environ, environment, clear=True)
        self.patch.start()
        self.addCleanup(self.cleanup_fixture)
        self.command = [sys.executable, '-c',
                        "from pathlib import Path; import os,time\n"
                        "Path('worker.pid').write_text(str(os.getpid()))\n"
                        "with Path('executions').open('a') as stream: stream.write('execute\\n')\n"
                        "deadline=time.monotonic()+" + str(2 * CONDITION_SECONDS) + "\n"
                        "while not Path('release').exists():\n"
                        "    if time.monotonic() >= deadline: raise TimeoutError('fixture release was never delivered')\n"
                        "    time.sleep(.02)\n"
                        "print('published')"]

    def cleanup_fixture(self):
        try:
            (self.root / 'release').touch()
            self.wait_for_workers()
            self.temporary.cleanup()
        finally:
            self.patch.stop()

    def wait_for_workers(self):
        script = os.fsencode(Path(build_admission.__file__).resolve())
        executable = Path(sys.executable).resolve()
        slots = b'SELKA_SLOT_DIR=' + os.fsencode((self.root / 'slots').resolve())
        def owned(entry):
            argv = (entry / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
            if (len(argv) != 4 or argv[1:] != [b'-B', script, b'--keyed-worker']
                    or Path(os.fsdecode(argv[0])).resolve() != executable):
                return None
            values = [item for item in (entry / 'environ').read_bytes().split(b'\0')
                      if item.startswith(b'SELKA_SLOT_DIR=')]
            return (tuple(argv), tuple(values)) if values == [slots] else None
        deadline = time.monotonic() + CONDITION_SECONDS
        while True:
            found = False
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    ownership = owned(entry)
                    if ownership is None:
                        continue
                    pid = int(entry.name)
                    before = build_admission.process_identity(pid)
                    if before is None:
                        continue
                    descriptor = os.pidfd_open(pid)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
                try:
                    if build_admission.process_identity(pid) != before or owned(entry) != ownership:
                        continue
                    found = True
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, f'private worker still active: {before}')
                    self.assertTrue(select.select([descriptor], [], [], remaining)[0],
                                    f'private worker did not exit: {before}')
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
                finally:
                    os.close(descriptor)
            if not found:
                return

    def subscriptions(self, workers, cancellations):
        return fixture_pool(workers, release=lambda: (self.root / 'release').touch(),
                            cancellations=cancellations)

    def wait_for(self, predicate, *, futures=(), timeout=CONDITION_SECONDS, description='detached subscription readiness'):
        deadline = time.monotonic() + timeout
        while not predicate():
            for future in futures:
                if future.done():
                    error = future.exception()
                    if error is not None:
                        raise error
            if time.monotonic() >= deadline:
                self.fail(description + ' did not reach synchronization point')
            time.sleep(.02)

    def test_ten_subscribers_share_one_detached_worker_without_gate_slots(self):
        queue = build_admission.keyed_scheduler()
        cancellations = [threading.Event() for _ in range(10)]
        # A subscriber claims only a job nobody holds. Counting its claims (each one takes the database write lock) is
        # independent of how fast the machine is, unlike waiting for the lock: with every wake-up of every subscriber
        # claiming, a loaded machine ran contenders past the 30 second busy timeout (`database is locked`).
        claims = []
        counted = Scheduler.claim
        def counting(scheduler, key, *arguments, **options):
            claims.append(key)
            return counted(scheduler, key, *arguments, **options)
        with patch.object(Scheduler, 'claim', counting), self.subscriptions(10, cancellations) as submit:
            futures = [submit(build_admission.subscribe, 'same', self.command,
                              cwd=self.root, kind=None, cancel=cancel) for cancel in cancellations]
            self.wait_for(lambda: (queue.status('same') or {}).get('subscribers') == 10, futures=futures)
            self.wait_for(lambda: (self.root / 'worker.pid').exists(), futures=futures)
            (self.root / 'release').touch()
            results = [future.result(timeout=CONDITION_SECONDS) for future in futures]
        self.assertLessEqual(len(claims), 2 * len(futures), f'{len(claims)} claims, each one a write transaction')
        self.assertEqual((self.root / 'executions').read_text().splitlines(), ['execute'])
        self.assertEqual(sum(row['executed'] for row in results), 1)
        self.assertEqual(sum(row['coalesced'] for row in results), 9)
        self.assertTrue(all(row['passed'] for row in results))
        self.assertEqual(list((self.root / 'slots').glob('gate*.lock')), [])

    def test_cancel_one_subscriber_keeps_work_for_peer(self):
        cancel = threading.Event()
        peer_cancel = threading.Event()
        queue = build_admission.keyed_scheduler()
        with self.subscriptions(2, [cancel, peer_cancel]) as submit:
            first = submit(build_admission.subscribe, 'same', self.command,
                           cwd=self.root, kind=None, cancel=cancel)
            self.wait_for(lambda: (self.root / 'worker.pid').exists(), futures=[first])
            second = submit(build_admission.subscribe, 'same', self.command,
                            cwd=self.root, kind=None, cancel=peer_cancel)
            self.wait_for(lambda: queue.status('same')['subscribers'] == 2, futures=[first, second])
            cancel.set()
            with self.assertRaises(Cancelled):
                first.result(timeout=CONDITION_SECONDS)
            self.assertEqual(queue.status('same')['state'], 'running')
            (self.root / 'release').touch()
            self.assertTrue(second.result(timeout=CONDITION_SECONDS)['passed'])
        self.assertEqual((self.root / 'executions').read_text().splitlines(), ['execute'])

    def test_killed_first_subscriber_does_not_kill_peer_worker(self):
        code = ('import json,sys; sys.path.insert(0,sys.argv[1]); '
                'from build_admission import subscribe; '
                'print(json.dumps(subscribe("same",json.loads(sys.argv[2]),cwd=sys.argv[3],kind=None)))')
        first = subprocess.Popen([sys.executable, '-c', code,
                                  str(Path(build_admission.__file__).parent),
                                  json.dumps(self.command), str(self.root)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        def stop_first():
            if first.poll() is None:
                first.kill()
            first.communicate(timeout=CONDITION_SECONDS)
        self.addCleanup(stop_first)
        queue = build_admission.keyed_scheduler()
        self.wait_for(lambda: (self.root / 'worker.pid').exists())
        cancel = threading.Event()
        with self.subscriptions(1, [cancel]) as submit:
            peer = submit(build_admission.subscribe, 'same', self.command,
                          cwd=self.root, kind=None, cancel=cancel)
            self.wait_for(lambda: queue.status('same')['subscribers'] == 2, futures=[peer])
            first.kill()
            first.communicate(timeout=CONDITION_SECONDS)
            self.wait_for(lambda: queue.status('same')['subscribers'] == 1, futures=[peer])
            (self.root / 'release').touch()
            self.assertTrue(peer.result(timeout=CONDITION_SECONDS)['passed'])
        self.assertEqual((self.root / 'executions').read_text().splitlines(), ['execute'])

    def test_readiness_failure_releases_worker_and_preserves_failure(self):
        cancel = threading.Event()
        with self.assertRaisesRegex(AssertionError, 'injected readiness failure'):
            with self.subscriptions(1, [cancel]) as submit:
                future = submit(build_admission.subscribe, 'same', self.command,
                                cwd=self.root, kind=None, cancel=cancel)
                self.wait_for(lambda: (self.root / 'worker.pid').exists(), futures=[future])
                self.wait_for(lambda: False, timeout=0, description='injected readiness failure')
        self.assertTrue(future.done())
        self.assertTrue(cancel.is_set())
        self.assertTrue((self.root / 'release').exists())
        self.wait_for_workers()
        self.assertEqual((self.root / 'executions').read_text().splitlines(), ['execute'])


if __name__ == '__main__':
    unittest.main()
