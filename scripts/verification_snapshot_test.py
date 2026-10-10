#!/usr/bin/env python3
"""Adversarial immutable-input evidence tests, without compiler builds."""
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from verification_snapshot import Snapshot, SnapshotError


class InputSnapshot(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[1] / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='snapshot-test-', dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def file(self, name, data=b'original'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_identity_is_json_safe_stable_and_content_sensitive(self):
        path = self.file('input.txt')
        with Snapshot(self.root, ['input.txt']) as first:
            identity = json.dumps(first.identity, sort_keys=True)
            self.assertTrue(first.unchanged())
        with Snapshot(self.root, ['input.txt']) as second:
            self.assertEqual(json.dumps(second.identity, sort_keys=True), identity)
        path.write_bytes(b'different')
        with Snapshot(self.root, ['input.txt']) as changed:
            self.assertNotEqual(json.dumps(changed.identity, sort_keys=True), identity)

    def test_membership_is_direct_inclusive_and_does_not_hash_or_follow_children(self):
        self.file('loader/.hidden')
        self.file('loader/cache.pyc')
        nested = self.file('loader/nested/input')
        (self.root / 'loader/broken').symlink_to('/no-such-loader-target')
        (self.root / 'loader/alias').symlink_to('nested', target_is_directory=True)
        with patch.object(Snapshot, '_hash_file', side_effect=AssertionError('membership hash')):
            with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
                identity = snapshot.identity
                rows = identity['directory_membership'][0]['entries']
                self.assertEqual([row['name'] for row in rows],
                                 ['.hidden', 'alias', 'broken', 'cache.pyc', 'nested'])
                self.assertEqual(rows[1]['target'], 'nested')
                nested.write_bytes(b'nested change')
                self.assertTrue(snapshot.unchanged())
            with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
                self.assertEqual(snapshot.identity, identity)

    def test_membership_optional_argument_preserves_default_identity(self):
        with Snapshot(self.root, []) as snapshot:
            self.assertNotIn('directory_membership', snapshot.identity)
        with Snapshot(self.root, [], directory_membership=[]) as snapshot:
            self.assertNotIn('directory_membership', snapshot.identity)

    def test_membership_direct_hidden_and_python_cache_addition_aba(self):
        (self.root / 'loader').mkdir()
        for name in ['.hidden', 'cache.pyc', '__pycache__']:
            with self.subTest(name=name):
                with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
                    path = self.file('loader/' + name)
                    path.unlink()
                    self.assertFalse(snapshot.unchanged())

    def test_membership_direct_content_aba_is_latched(self):
        path = self.file('loader/provider.so')
        before = path.stat()
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            path.write_bytes(b'modified')
            path.write_bytes(b'original')
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
            self.assertFalse(snapshot.unchanged())

    def test_membership_new_snapshot_binds_direct_file_metadata(self):
        path = self.file('loader/provider.so')
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            before = snapshot.identity
        path.write_bytes(b'modified')
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            self.assertNotEqual(snapshot.identity, before)

    def test_missing_membership_intermediate_directory_creation_aba(self):
        missing = self.root / 'loader/glibc-hwcaps/x86-64-v4'
        with Snapshot(self.root, [], directory_membership=[missing]) as snapshot:
            self.assertEqual(snapshot.identity['directory_membership'][0]['status'], 'missing')
            missing.mkdir(parents=True)
            missing.rmdir()
            missing.parent.rmdir()
            missing.parent.parent.rmdir()
            self.assertFalse(snapshot.unchanged())

    def test_missing_membership_unrelated_parent_entry_is_ignored(self):
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            self.file('unrelated')
            self.assertTrue(snapshot.unchanged())

    def test_membership_alias_retarget_aba_is_latched(self):
        (self.root / 'one').mkdir()
        (self.root / 'two').mkdir()
        alias = self.root / 'loader'
        alias.symlink_to('one', target_is_directory=True)
        with Snapshot(self.root, [], directory_membership=[alias]) as snapshot:
            self.assertEqual(snapshot.identity['symlinks']['loader'], 'one')
            alias.unlink()
            alias.symlink_to('two', target_is_directory=True)
            alias.unlink()
            alias.symlink_to('one', target_is_directory=True)
            self.assertFalse(snapshot.unchanged())

    def test_membership_external_candidate_target_content_aba_is_latched(self):
        target = self.file('external/candidate.so', b'wrong ELF class')
        (self.root / 'loader').mkdir()
        (self.root / 'loader/libcandidate.so').symlink_to(target)
        before = target.stat()
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            alias = snapshot.identity['directory_membership'][0]['entries'][0]
            self.assertEqual(alias['resolved_target']['path'], 'external/candidate.so')
            target.write_bytes(b'valid ELF class')
            target.write_bytes(b'wrong ELF class')
            os.utime(target, ns=(before.st_atime_ns, before.st_mtime_ns))
            self.assertFalse(snapshot.unchanged())

    def test_membership_external_candidate_target_metadata_changes_new_identity(self):
        target = self.file('external/candidate.so')
        (self.root / 'loader').mkdir()
        (self.root / 'loader/libcandidate.so').symlink_to(target)
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            before = snapshot.identity
        target.write_bytes(b'modified')
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            self.assertNotEqual(snapshot.identity, before)

    def test_membership_external_candidate_target_file_directory_aba_is_latched(self):
        target = self.file('external/candidate.so')
        (self.root / 'loader').mkdir()
        (self.root / 'loader/libcandidate.so').symlink_to(target)
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            target.unlink()
            target.mkdir()
            target.rmdir()
            target.write_bytes(b'original')
            self.assertFalse(snapshot.unchanged())

    def test_membership_dangling_child_alias_target_creation_aba_is_latched(self):
        (self.root / 'loader').mkdir()
        (self.root / 'external').mkdir()
        target = self.root / 'external/candidate.so'
        (self.root / 'loader/libcandidate.so').symlink_to(target)
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            alias = snapshot.identity['directory_membership'][0]['entries'][0]
            self.assertEqual(alias['resolved_target']['status'], 'missing')
            target.write_bytes(b'new candidate')
            target.unlink()
            self.assertFalse(snapshot.unchanged())

    def test_membership_directory_alias_target_is_not_recursively_watched(self):
        target = self.file('external/nested/input')
        (self.root / 'loader').mkdir()
        (self.root / 'loader/unrelated').symlink_to(target.parent.parent,
                                                  target_is_directory=True)
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            identity = snapshot.identity
            target.write_bytes(b'nested edit')
            self.file('external/new')
            self.assertTrue(snapshot.unchanged())
        with Snapshot(self.root, [], directory_membership=[Path('loader')]) as snapshot:
            self.assertEqual(snapshot.identity, identity)

    def test_missing_membership_alias_creation_aba_is_latched(self):
        (self.root / 'target').mkdir()
        with Snapshot(self.root, [], directory_membership=[Path('alias')]) as snapshot:
            alias = self.root / 'alias'
            alias.symlink_to('target', target_is_directory=True)
            alias.unlink()
            self.assertFalse(snapshot.unchanged())

    def test_dangling_membership_alias_watches_missing_target_creation_aba(self):
        alias = self.root / 'alias'
        alias.symlink_to('missing/deeper', target_is_directory=True)
        with Snapshot(self.root, [], directory_membership=[alias]) as snapshot:
            self.assertEqual(snapshot.identity['symlinks']['alias'], 'missing/deeper')
            target = self.root / 'missing'
            target.mkdir()
            target.rmdir()
            self.assertFalse(snapshot.unchanged())

    def test_membership_file_instead_of_directory_and_blocked_parent_are_watched(self):
        path = self.file('loader')
        with Snapshot(self.root, [], directory_membership=[path, path / 'caps']) as snapshot:
            self.assertEqual([row['status'] for row in snapshot.identity['directory_membership']],
                             ['not-directory', 'missing'])
            path.unlink()
            path.mkdir()
            path.rmdir()
            path.write_bytes(b'original')
            self.assertFalse(snapshot.unchanged())

    def test_membership_explicit_provider_still_hashes_and_guards_content(self):
        provider = self.file('loader/nested/provider.so')
        with Snapshot(self.root, [], [provider], directory_membership=[Path('loader')]) as snapshot:
            self.assertEqual(snapshot.identity['files'][0]['sha256'],
                             hashlib.sha256(b'original').hexdigest())
            provider.write_bytes(b'modified')
            self.assertFalse(snapshot.unchanged())

    def test_membership_initial_listing_aba_is_rejected(self):
        directory = self.root / 'loader'
        directory.mkdir()
        original = os.scandir

        def changed(path):
            if path == directory:
                injected = directory / '.hidden'
                injected.write_bytes(b'change')
                injected.unlink()
            return original(path)

        with patch('verification_snapshot.os.scandir', changed):
            with self.assertRaisesRegex(SnapshotError, 'changed while constructing'):
                with Snapshot(self.root, [], directory_membership=[directory]):
                    pass

    def test_membership_inventory_bounds_reject_excess(self):
        self.file('loader/one')
        self.file('loader/two')
        with patch('verification_snapshot._MAX_MEMBERSHIP_ENTRIES', 1):
            with self.assertRaisesRegex(SnapshotError, 'too many directory membership entries'):
                with Snapshot(self.root, [], directory_membership=[Path('loader')]):
                    pass
        with patch('verification_snapshot._MAX_MEMBERSHIP_ROOTS', 1):
            with self.assertRaisesRegex(SnapshotError, 'too many directory membership roots'):
                Snapshot(self.root, [], directory_membership=[Path('one'), Path('two')])

    def test_content_edit_permanently_invalidates_live_snapshot(self):
        path = self.file('input.txt')
        with Snapshot(self.root, ['input.txt']) as snapshot:
            path.write_bytes(b'changed!')
            self.assertFalse(snapshot.unchanged())
            path.write_bytes(b'original')
            self.assertFalse(snapshot.unchanged())

    def test_chmod_changes_live_snapshot_and_new_content_identity_includes_ownership(self):
        path = self.file('tool')
        path.chmod(0o644)
        with Snapshot(self.root, ['tool']) as snapshot:
            original = snapshot.identity
            item = original['files'][0]
            metadata = path.stat()
            self.assertEqual(item['mode'], 0o644)
            self.assertEqual(item['uid'], metadata.st_uid)
            self.assertEqual(item['gid'], metadata.st_gid)
            path.chmod(0o755)
            self.assertFalse(snapshot.unchanged())
        with Snapshot(self.root, ['tool']) as snapshot:
            changed = snapshot.identity['files'][0]
            self.assertEqual(changed['sha256'], item['sha256'])
            self.assertEqual(changed['size'], item['size'])
            self.assertEqual(changed['mode'], 0o755)
            self.assertNotEqual(snapshot.identity, original)
            self.assertTrue(snapshot.unchanged())

    def test_same_size_edit_with_restored_mtime_is_detected(self):
        path = self.file('input.txt')
        original = path.stat()
        with Snapshot(self.root, ['input.txt']) as snapshot:
            path.write_bytes(b'changed!')
            os.utime(path, ns=(original.st_atime_ns, original.st_mtime_ns))
            self.assertEqual(path.stat().st_size, original.st_size)
            self.assertEqual(path.stat().st_mtime_ns, original.st_mtime_ns)
            self.assertFalse(snapshot.unchanged())

    def test_aba_restores_bytes_and_mtime_before_first_validation(self):
        path = self.file('input.txt')
        original = path.stat()
        with Snapshot(self.root, ['input.txt']) as snapshot:
            path.write_bytes(b'changed!')
            path.write_bytes(b'original')
            os.utime(path, ns=(original.st_atime_ns, original.st_mtime_ns))
            self.assertEqual(path.read_bytes(), b'original')
            self.assertEqual(path.stat().st_mtime_ns, original.st_mtime_ns)
            self.assertFalse(snapshot.unchanged())

    def test_directory_inventory_addition_is_detected(self):
        self.file('inputs/first.txt')
        with Snapshot(self.root, ['inputs/']) as snapshot:
            self.file('inputs/new.txt')
            self.assertFalse(snapshot.unchanged())

    def test_inclusive_scope_binds_hidden_and_python_cache_inputs(self):
        self.file('inputs/.hidden/data')
        self.file('inputs/__pycache__/code.pyc')
        with Snapshot(self.root, ['inputs/'], include_hidden=True) as snapshot:
            self.assertEqual([item['path'] for item in snapshot.identity['files']],
                             ['inputs/.hidden/data', 'inputs/__pycache__/code.pyc'])
            self.assertTrue(snapshot.unchanged())
            self.file('inputs/.new')
            self.assertFalse(snapshot.unchanged())

    def test_inclusive_scope_rejects_untracked_directory_symlinks(self):
        self.file('outside/file')
        self.file('inputs/first')
        (self.root / 'inputs/linked').symlink_to(self.root / 'outside', target_is_directory=True)
        with self.assertRaisesRegex(SnapshotError, 'directory symlink'):
            with Snapshot(self.root, ['inputs/'], include_hidden=True):
                pass

    def test_recursive_inventory_addition_under_new_directory_is_detected(self):
        self.file('inputs/first.txt')
        with Snapshot(self.root, ['inputs/**/*.txt']) as snapshot:
            self.file('inputs/new/deep/second.txt')
            self.assertFalse(snapshot.unchanged())

    def test_empty_tool_sentinel_glob_rejects_unmatched_visible_addition(self):
        (self.root / 'tools').mkdir()
        with Snapshot(self.root, ['tools/*.verification-tool-membership']) as snapshot:
            self.assertEqual(snapshot.identity['files'], [])
            self.file('tools/new-executable')
            self.assertFalse(snapshot.unchanged())

    def test_queue_overflow_fails_closed_and_remains_failed_after_read_recovers(self):
        self.file('input.txt')
        overflow = struct.pack('iIII', -1, 0x4000, 0, 0)
        with Snapshot(self.root, ['input.txt']) as snapshot:
            with patch('verification_snapshot.os.read', side_effect=[overflow, BlockingIOError()]) as reader:
                with self.assertRaisesRegex(SnapshotError, 'queue overflow'):
                    snapshot.unchanged()
                self.assertEqual(reader.call_count, 1)
            # A later successful read cannot establish the missing input history.
            with self.assertRaisesRegex(SnapshotError, 'queue overflow'):
                snapshot.unchanged()

    def test_mutation_of_already_hashed_input_during_construction_is_rejected(self):
        first = self.file('inputs/a.txt')
        second = self.file('inputs/b.txt')
        original_hash = Snapshot._hash_file
        hashed = []

        def hash_then_mutate(snapshot, path):
            result = original_hash(snapshot, path)
            hashed.append(path)
            if path == second:
                first.write_bytes(b'changed!')
            return result

        snapshot = Snapshot(self.root, ['inputs/*.txt'])
        with patch.object(Snapshot, '_hash_file', hash_then_mutate):
            with self.assertRaisesRegex(SnapshotError, 'changed while constructing'):
                with snapshot:
                    self.fail('snapshot admitted an input mutated after its digest')
        self.assertEqual(hashed, [first, second])
        with self.assertRaisesRegex(SnapshotError, 'active context'):
            _ = snapshot.identity

    def test_directory_inventory_deletion_is_detected(self):
        path = self.file('inputs/first.txt')
        with Snapshot(self.root, ['inputs/']) as snapshot:
            path.unlink()
            self.assertFalse(snapshot.unchanged())

    def test_rename_invalidates_membership_even_with_identical_file_bytes(self):
        path = self.file('inputs/first.txt')
        with Snapshot(self.root, ['inputs/*.txt']) as snapshot:
            path.rename(path.with_name('renamed.txt'))
            self.assertFalse(snapshot.unchanged())

    def test_missing_required_file_fails_closed(self):
        with self.assertRaises(SnapshotError):
            with Snapshot(self.root, ['missing.txt']):
                self.fail('a missing required input was accepted')

    def test_explicit_file_deletion_fails_validation_and_new_snapshot(self):
        path = self.file('input.txt')
        with Snapshot(self.root, ['input.txt']) as snapshot:
            path.unlink()
            self.assertFalse(snapshot.unchanged())
        with self.assertRaises(SnapshotError):
            with Snapshot(self.root, ['input.txt']):
                self.fail('a deleted required input was accepted')

    def test_symlink_target_content_change_is_detected(self):
        target = self.file('targets/original.txt')
        (self.root / 'input.txt').symlink_to(target)
        with Snapshot(self.root, ['input.txt']) as snapshot:
            target.write_bytes(b'changed!')
            self.assertFalse(snapshot.unchanged())

    def test_symlink_retargeting_same_bytes_is_detected(self):
        target = self.file('targets/original.txt')
        other = self.file('targets/other.txt')
        link = self.root / 'input.txt'
        link.symlink_to(target)
        with Snapshot(self.root, ['input.txt']) as snapshot:
            link.unlink()
            link.symlink_to(other)
            self.assertEqual(link.read_bytes(), b'original')
            self.assertFalse(snapshot.unchanged())

    def test_symlink_target_atomic_replacement_with_same_bytes_is_detected(self):
        target = self.file('targets/original.txt')
        (self.root / 'input.txt').symlink_to(target)
        replacement = self.file('targets/replacement.txt')
        with Snapshot(self.root, ['input.txt']) as snapshot:
            os.replace(replacement, target)
            self.assertEqual(target.read_bytes(), b'original')
            self.assertFalse(snapshot.unchanged())

    def test_unrelated_sibling_writes_do_not_invalidate_explicit_file(self):
        self.file('inputs/required.txt')
        sibling = self.file('inputs/unrelated.txt')
        with Snapshot(self.root, ['inputs/required.txt']) as snapshot:
            sibling.write_bytes(b'other contents')
            created = self.file('inputs/new-unrelated.txt')
            created.unlink()
            self.assertTrue(snapshot.unchanged())

    def test_extra_tool_file_outside_root_is_part_of_live_snapshot(self):
        self.file('input.txt')
        with tempfile.TemporaryDirectory(prefix='snapshot-tool-', dir=self.root.parent) as external:
            tool = Path(external) / 'tool'
            tool.write_bytes(b'original')
            with Snapshot(self.root, ['input.txt'], extra_files=[tool]) as snapshot:
                tool.write_bytes(b'changed!')
                self.assertFalse(snapshot.unchanged())

    def test_large_file_hash_is_correct_and_reads_bounded_chunks(self):
        payload = b'0123456789abcdef' * (3 * 1024 * 1024 // 16)
        self.file('large.bin', payload)
        original_fdopen = os.fdopen
        reads = []

        class BoundedReader:
            def __init__(self, stream):
                self.stream = stream

            def __enter__(self):
                self.stream.__enter__()
                return self

            def __exit__(self, *args):
                return self.stream.__exit__(*args)

            def __getattr__(self, name):
                return getattr(self.stream, name)

            def read(self, size=-1):
                if size <= 0 or size > 1024 * 1024:
                    raise AssertionError(f'unbounded snapshot hash read: {size}')
                data = self.stream.read(size)
                reads.append(len(data))
                return data

        def opened(descriptor, *args, **kwargs):
            return BoundedReader(original_fdopen(descriptor, *args, **kwargs))

        with patch('verification_snapshot.os.fdopen', opened), patch.object(Path, 'read_bytes', side_effect=AssertionError('whole-file read')):
            with Snapshot(self.root, ['large.bin']) as snapshot:
                self.assertTrue(snapshot.unchanged())
                item = next(item for item in snapshot.identity['files'] if item['path'] == 'large.bin')
                self.assertEqual(item['sha256'], hashlib.sha256(payload).hexdigest())
                self.assertEqual(item['size'], len(payload))
        self.assertGreaterEqual(len(reads), 4)
        self.assertGreaterEqual(sum(reads), len(payload))
        self.assertEqual(sum(reads) % len(payload), 0)


if __name__ == '__main__':
    unittest.main()
