import concurrent.futures
import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from verification.scheduler import Cancelled, Scheduler, current_cancelled, run_process


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.scheduler = Scheduler(Path(self.temporary.name)/'queue.db', cpus=2, memory=512, workers=2, lease=.15, aging=.05)

    def test_ten_clients_coalesce(self):
        barrier = threading.Barrier(10)
        calls = []
        def execute():
            calls.append(1)
            deadline = time.monotonic() + 5
            while self.scheduler.status('same')['subscribers'] < 10:
                if time.monotonic() > deadline:
                    raise AssertionError('clients did not subscribe')
                time.sleep(.01)
            return {'passed': True}
        def client(index):
            barrier.wait()
            return self.scheduler.execute('same', execute, client=str(index))
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
            results = list(pool.map(client, range(10)))
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
        time.sleep(.18)
        token = queue.claim('crash', 'replacement')
        self.assertGreater(token, old)
        self.assertTrue(queue.publish('crash', 'replacement', token, {'passed': True}))

    def test_dead_only_client_does_not_block_unrelated_job(self):
        code = "from verification.scheduler import Scheduler; import os; q=Scheduler(__import__('sys').argv[1],cpus=2,memory=512,workers=2,lease=.15,aging=.05); q.submit('orphan','dead'); q.claim('orphan','dead'); os._exit(7)"
        result = subprocess.run([sys.executable, '-c', code, self.scheduler.path],
                                cwd=Path(__file__).resolve().parents[2]/'scripts', capture_output=True)
        self.assertEqual(result.returncode, 7)
        time.sleep(.18)
        start = time.monotonic()
        result = self.scheduler.execute('survivor', lambda: {'passed': True})
        self.assertTrue(result['passed'])
        self.assertLess(time.monotonic()-start, 3)
        self.assertEqual(self.scheduler.status('orphan')['state'], 'cancelled')

    def test_reject_nonfinite_limits(self):
        for value in (float('nan'), float('inf'), -1):
            with self.assertRaises(ValueError):
                Scheduler(Path(self.temporary.name)/'invalid', cpus=value)
            with self.assertRaises(ValueError):
                self.scheduler.submit('invalid', 'client', memory=value)

    def test_distinct_jobs_respect_admission_limits(self):
        lock = threading.Lock()
        active = 0
        peak = 0
        def execute():
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            time.sleep(.05)
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
        time.sleep(.18)
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


if __name__ == '__main__':
    unittest.main()
