from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import coordinator_receipt as coordinator


class CoordinatorReceiptTests(unittest.TestCase):
    def test_runtime_receipt_and_source_inventory_drift(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module = root / 'worker.py'
            module.write_text('print(1)')
            (root / 'recovery-policy.md').write_text('Retain interrupted attempts.')
            receipt = coordinator.capture('fixture-transport', source_root=root)
            self.assertEqual(coordinator.verify(receipt, transport_identity='fixture-transport', source_root=root), receipt)
            with self.assertRaisesRegex(ValueError, 'transport identity'):
                coordinator.verify(receipt, transport_identity='different', source_root=root)
            module.write_text('print(2)')
            with self.assertRaisesRegex(ValueError, 'runtime changed'):
                coordinator.verify(receipt, transport_identity='fixture-transport', source_root=root)
            module.write_text('print(1)')
            (root / 'extra.py').write_text('print(3)')
            with self.assertRaisesRegex(ValueError, 'runtime changed'):
                coordinator.verify(receipt, transport_identity='fixture-transport', source_root=root)
            (root / 'extra.py').unlink()
            module.unlink()
            with self.assertRaisesRegex(ValueError, 'source inventory'):
                coordinator.verify(receipt, transport_identity='fixture-transport', source_root=root)

    def test_alias_and_altered_receipt_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'worker.py').write_text('pass')
            (root / 'recovery-policy.md').write_text('Retain interrupted attempts.')
            (root / 'alias.py').symlink_to('worker.py')
            with self.assertRaisesRegex(ValueError, 'regular files'):
                coordinator.source_inventory(root)
            (root / 'alias.py').unlink()
            receipt = coordinator.capture('fixture', source_root=root)
            receipt['python']['version'] = 'changed'
            with self.assertRaisesRegex(ValueError, 'receipt changed'):
                coordinator.validate(receipt, transport_identity='fixture')

    def test_policy_changes_invalidate_receipt_and_legacy_is_still_readable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'worker.py').write_text('pass')
            policy = root / 'recovery-policy.md'
            policy.write_text('Keep all attempts.')
            receipt = coordinator.capture('fixture', source_root=root)
            self.assertEqual(receipt['recovery_policy']['content'], 'Keep all attempts.')
            legacy = coordinator._capture('fixture', source_root=root, version='application-coordinator-v1')
            policy.write_text('Discard failures.')
            with self.assertRaisesRegex(ValueError, 'runtime changed'):
                coordinator.verify(receipt, transport_identity='fixture', source_root=root)
            self.assertEqual(coordinator.verify(legacy, transport_identity='fixture', source_root=root), legacy)


if __name__ == '__main__':
    unittest.main()
