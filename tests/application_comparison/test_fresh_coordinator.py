from pathlib import Path
import subprocess
import importlib.util
import sys
import tempfile
import unittest
from experiments.application_comparison import coordinator_receipt, fresh_coordinator
from experiments.application_comparison.storage import read_json, write_json

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class FreshCoordinatorTests(unittest.TestCase):
    def test_imports_use_captured_bytes_and_reject_unlisted_modules(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'worker.py'
            source.write_bytes(b'value = 42')
            loader = fresh_coordinator.VerifiedImports(root, {'worker.py': source.read_bytes()})
            source.write_bytes(b'raise AssertionError("unverified disk source ran")')
            spec = loader.find_spec(loader.prefix + '.worker')
            module = importlib.util.module_from_spec(spec)
            loader.exec_module(module)
            self.assertEqual(module.value, 42)
            with self.assertRaisesRegex(ImportError, 'outside verified inventory'):
                loader.find_spec(loader.prefix + '.unlisted')

    def test_fresh_probe_and_unverified_invocations_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            request = Path(temporary) / 'request.json'
            receipt = coordinator_receipt.capture('fixture-probe')
            write_json(request, {'operation': 'probe', 'coordinator': receipt, 'transport_identity': 'fixture-probe'})
            command = [sys.executable, '-I', '-S', '-B', str(ROOT / 'fresh_coordinator.py'), str(request)]
            result = subprocess.run(command, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            import json
            report = json.loads(result.stdout)
            self.assertEqual(report['coordinator_sha256'], receipt['sha256'])
            self.assertEqual(report['source_imports'], 'verified-in-memory-bytes')
            self.assertEqual(report['model_calls'], 0)
            result = subprocess.run([sys.executable, str(ROOT / 'fresh_coordinator.py'), str(request)], capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            changed = read_json(request)
            changed['transport_identity'] = 'different'
            write_json(request, changed)
            result = subprocess.run(command, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'transport identity mismatch', result.stderr)


if __name__ == '__main__':
    unittest.main()
