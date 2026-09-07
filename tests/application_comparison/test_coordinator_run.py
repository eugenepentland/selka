from pathlib import Path
import sys
import subprocess
import time
import tempfile
import unittest
from experiments.application_comparison import coordinator_receipt, coordinator_run
from experiments.application_comparison.storage import read_json


class CoordinatorRunTests(unittest.TestCase):
    def test_probe_records_request_output_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'run'
            request = {'operation': 'probe', 'coordinator': coordinator_receipt.capture('fixture'), 'transport_identity': 'fixture'}
            result = coordinator_run.run(request, directory, wall_seconds=10)
            self.assertEqual(result['outcome'], 'completed')
            self.assertEqual(read_json(directory / 'result.json'), result)
            self.assertEqual(read_json(directory / 'request.json'), request)
            identity = read_json(directory / 'process.json')['identity']
            self.assertIsNotNone(identity)
            self.assertEqual(identity['pid'], read_json(directory / 'process.json')['pid'])
            self.assertEqual(coordinator_run.process_identity.observe(identity)['status'], 'not-running')
            self.assertEqual(read_json(directory / 'stdout')['source_imports'], 'verified-in-memory-bytes')
            with self.assertRaises(FileExistsError):
                coordinator_run.run(request, directory)

    def test_timeout_and_output_limit_preserve_bounded_artifacts(self):
        for code, wall, limit, expected in [
            ('import time; print("started", flush=True); time.sleep(60)', .2, 1024, 'timeout'),
            ('import os\nwhile True: os.write(1,b"x"*65536)', 5, 1024, 'output-limit')]:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                result = coordinator_run.execute([sys.executable, '-I', '-S', '-c', code], root,
                                                 wall_seconds=wall, output_bytes=limit)
                self.assertEqual(result['outcome'], expected)
                self.assertLessEqual((root / 'stdout').stat().st_size + (root / 'stderr').stat().st_size, limit)
                self.assertGreater((root / 'stdout').stat().st_size, 0)

    def test_parent_death_kills_fresh_worker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            worker = "from pathlib import Path; import time; Path(" + repr(str(root / 'started')) + ").write_text('yes'); time.sleep(1); Path(" + repr(str(root / 'escaped')) + ").write_text('bad')"
            code = "import os; from pathlib import Path; from experiments.application_comparison import coordinator_run as r; r.execute([" + repr(sys.executable) + ", '-I', '-S', str(r.ROOT / 'isolation_launcher.py'), str(os.getpid()), " + repr(sys.executable) + ", '-I', '-S', '-c', " + repr(worker) + "], Path(" + repr(str(root)) + "), wall_seconds=10, output_bytes=1024)"
            process = subprocess.Popen([sys.executable, '-c', code], cwd=coordinator_run.ROOT.parents[1],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not (root / 'started').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((root / 'started').exists())
                process.kill()
                process.wait(timeout=5)
                time.sleep(1.2)
                self.assertFalse((root / 'escaped').exists())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)

    def test_changed_receipt_retains_failure_before_spawn(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'run'
            receipt = coordinator_receipt.capture('fixture')
            request = {'operation': 'probe', 'coordinator': receipt, 'transport_identity': 'different'}
            with self.assertRaisesRegex(ValueError, 'transport identity'):
                coordinator_run.run(request, root)
            self.assertTrue((root / 'request.json').exists())
            self.assertTrue((root / 'interrupted.json').exists())
            self.assertFalse((root / 'process.json').exists())


if __name__ == '__main__':
    unittest.main()
