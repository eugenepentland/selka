"""Lifecycle tests are fixtures, never measured agent repair attempts."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from experiments.application_comparison import session
from experiments.application_comparison.storage import source_files, snapshot, verify_snapshot


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / 'base'
        self.base.mkdir()
        (self.base / 'main.txt').write_text('source')
        (self.base / 'policy.json').write_text('{}')

    def prepare(self, language='python', **kwargs):
        root = self.root / language
        session.prepare(root, self.base, language=language, block='task-1', cohort='fixture-1',
                        participant=language, model='fixture', protected=('policy.json',), **kwargs)
        return root

    def begin(self, language='python'):
        root = self.prepare(language)
        self.assertFalse((root / 'work').exists())
        session.start_preparation(root)
        session.start_task(root, 'failed')
        return root

    def checked(self, root):
        row = session.submit(root)
        session.record_check(root, row['index'], {'source_sha256': row['source']['sha256'], 'passed': False})
        return row

    def test_multifile_edits_new_files_deletion_and_frozen_submission(self):
        root = self.begin()
        (root / 'work/main.txt').unlink()
        (root / 'work/new').mkdir()
        (root / 'work/new/module.txt').write_text('new implementation')
        row = self.checked(root)
        self.assertEqual(row['changed_files'], ['main.txt', 'new/module.txt'])
        sealed = session.seal(root, 'completed')
        self.assertEqual(sealed['preparation']['outcome'], 'failed')
        (root / 'work/new/module.txt').write_text('later edit')
        self.assertEqual((root / 'submissions/000/source/new/module.txt').read_text(), 'new implementation')
        with self.assertRaises(ValueError):
            session.submit(root)

    def test_pending_final_edits_and_protected_policy_reject_completion(self):
        root = self.begin()
        self.checked(root)
        (root / 'work/main.txt').write_text('unchecked')
        with self.assertRaisesRegex(ValueError, 'not been submitted'):
            session.seal(root, 'completed')
        (root / 'work/policy.json').write_text('{"weaken":true}')
        row = self.checked(root)
        self.assertEqual(row['scope_violations'], ['policy.json'])
        with self.assertRaises(ValueError):
            session.seal(root, 'completed')
        self.assertEqual(session.seal(root, 'abandoned')['seal_reason'], 'abandoned')

    def test_wrong_receipt_and_overwrite_are_rejected(self):
        root = self.begin()
        row = session.submit(root)
        with self.assertRaises(ValueError):
            session.record_check(root, 0, {'source_sha256': 'wrong'})
        result = {'source_sha256': row['source']['sha256'], 'passed': True}
        session.record_check(root, 0, result)
        with self.assertRaises(ValueError):
            session.record_check(root, 0, result)

    def test_trios_require_matched_sealed_conditions(self):
        roots = [self.begin(language) for language in ('my', 'python', 'zig')]
        for root in roots:
            session.seal(root, 'budget')
        self.assertEqual(len(session.matched_trio(roots)), 3)
        with self.assertRaises(ValueError):
            session.matched_trio([roots[0], roots[0], roots[2]])
        with self.assertRaises(ValueError):
            session.matched_trio(roots[:2])

    def test_timing_reboot_and_deadline(self):
        root = self.begin()
        manifest = session.load(root)
        future = dict(manifest['task_started'])
        future['monotonic_ns'] += 1801 * 1_000_000_000
        with patch.object(session, 'clock', return_value=future):
            with self.assertRaisesRegex(ValueError, 'time budget'):
                session.submit(root)
            self.assertEqual(session.seal(root, 'budget')['participant_seconds'], 1801)
        with self.assertRaises(ValueError):
            session.elapsed({'boot_id': 'a'}, {'boot_id': 'b'})

    def test_snapshot_tampering_special_files_and_byte_limits(self):
        receipt = snapshot(self.base, self.root / 'snapshot')
        (self.root / 'snapshot/main.txt').write_text('changed')
        with self.assertRaises(ValueError):
            verify_snapshot(self.root / 'snapshot', receipt)
        with self.assertRaises(ValueError):
            source_files(self.base, max_bytes=2)
        (self.base / 'link').symlink_to(self.root)
        with self.assertRaises(OSError):
            source_files(self.base)
        (self.base / 'link').unlink()
        import os
        os.mkfifo(self.base / 'fifo')
        with self.assertRaises(ValueError):
            source_files(self.base)


if __name__ == '__main__':
    unittest.main()
