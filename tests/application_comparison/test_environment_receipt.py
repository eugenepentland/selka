from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from experiments.application_comparison import environment_receipt as environment


class EnvironmentReceiptTests(unittest.TestCase):
    def test_content_modes_and_symlink_targets_are_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tree = root / 'system'
            tree.mkdir()
            binary = tree / 'program'
            binary.write_bytes(b'first')
            binary.chmod(0o755)
            link = tree / 'alias'
            link.symlink_to('program')
            receipt = environment.capture([tree])
            self.assertEqual(environment.verify(receipt)['sha256'], receipt['sha256'])
            self.assertFalse(receipt['immutable_image'])
            with self.assertRaisesRegex(ValueError, 'all runtime system mounts'):
                environment.verify(receipt, require_system=True)
            binary.write_bytes(b'other')
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)
            binary.write_bytes(b'first')
            binary.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)
            binary.chmod(0o755)
            link.unlink()
            link.symlink_to('absent')
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)

    def test_aliases_share_content_hash_and_missing_mount_is_recorded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tree = root / 'system'
            tree.mkdir()
            (tree / 'file').write_text('content')
            alias = root / 'alias'
            alias.symlink_to(tree, target_is_directory=True)
            missing = root / 'missing'
            receipt = environment.capture([tree, alias, missing])
            self.assertEqual(len(receipt['contents']), 1)
            self.assertIsNone(receipt['mounts'][str(missing)])
            missing.write_text('new mount')
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)

    def test_tool_permissions_and_original_alias_are_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tool = root / 'tool'
            tool.write_bytes(b'executable')
            tool.chmod(0o755)
            alias = root / 'selected-tool'
            alias.symlink_to(tool)
            receipt = environment.capture([], tools={'compiler': alias})
            with self.assertRaisesRegex(ValueError, 'session tools'):
                environment.verify(receipt, required_tools={'other': tool})
            self.assertEqual(environment.verify(receipt)['sha256'], receipt['sha256'])
            tool.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)
            tool.chmod(0o755)
            replacement = root / 'replacement'
            replacement.write_bytes(tool.read_bytes())
            replacement.chmod(0o755)
            alias.unlink()
            alias.symlink_to(replacement)
            with self.assertRaisesRegex(ValueError, 'environment changed'):
                environment.verify(receipt)

    def test_unreadable_file_fails_closed_with_actionable_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'unreadable'
            path.write_text('private')
            with patch.object(environment.os, 'open', side_effect=PermissionError(13, 'denied', str(path))):
                with self.assertRaisesRegex(ValueError, 'inventory incomplete: cannot read .*unreadable'):
                    environment.capture([path])

    def test_budget_and_altered_receipt_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'file').write_bytes(b'1234')
            with self.assertRaisesRegex(ValueError, 'byte budget'):
                environment.tree_identity(root, max_bytes=3)
            receipt = environment.capture([root])
            receipt['cpu_count'] += 1
            with self.assertRaisesRegex(ValueError, 'receipt changed'):
                environment.verify(receipt)


if __name__ == '__main__':
    unittest.main()
