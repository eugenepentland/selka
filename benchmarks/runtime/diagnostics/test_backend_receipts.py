"""Fail closed when recorded CLI options did not select the intended backend."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('effective_backends', Path(__file__).with_name('backend_receipts.py'))
backends = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backends)


class BackendReceiptTests(unittest.TestCase):
    def test_effective_backend_and_optimization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / 'runtime.a'
            runtime.write_bytes(b'native archive')
            binary = root / 'guest'
            path = Path(str(binary) + '.qbe-manifest.json')
            document = {'backend': 'llvm', 'optimization': '3', 'lto': True,
                        'runtime_object': str(runtime), 'link_identity': 'known-link'}
            path.write_text(json.dumps(document))
            self.assertEqual(backends.capture({'before/my-llvm': binary})['before/my-llvm']['backend'], 'llvm')
            for change, value in (('backend', 'qbe'), ('optimization', '2'), ('lto', False)):
                bad = {**document, change: value}
                path.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    backends.capture({'before/my-llvm': binary})


if __name__ == '__main__':
    unittest.main()
