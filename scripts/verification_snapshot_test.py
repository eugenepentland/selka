#!/usr/bin/env python3
"""Adversarial immutable-input evidence tests, without compiler builds."""
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
from contextlib import ExitStack
import unittest
from unittest.mock import patch

from verification_snapshot import DigestSession, RetainedSession, Snapshot, SnapshotError


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

    def test_selected_files_matches_detached_projection_without_observations(self):
        self.file('a/input')
        self.file('b/input')
        with Snapshot(self.root, ['a/', 'b/']) as snapshot:
            expected = [row for row in snapshot.identity['files'] if row['path'].startswith('a/')]
            before = snapshot.statistics
            selected = snapshot.selected_files(lambda path: path.startswith('a/'))
            self.assertEqual(selected, expected)
            self.assertEqual(snapshot.statistics, before)
            selected[0]['sha256'] = 'caller mutation'
            self.assertEqual(snapshot.selected_files(lambda path: path.startswith('a/')), expected)
            self.assertIsInstance(json.dumps(snapshot.selected_files(lambda path: True)), str)
            self.assertTrue(snapshot.unchanged())

    def test_selected_files_preserves_borrowed_authority_and_rejects_closed_context(self):
        path = self.file('input')
        with RetainedSession() as retained, retained.activate():
            with Snapshot(self.root, ['input']) as snapshot:
                expected = snapshot.identity['files']
                self.assertEqual(snapshot.selected_files(lambda path: True), expected)
                path.write_bytes(b'mutated')
                self.assertFalse(snapshot.unchanged())
                self.assertEqual(snapshot.selected_files(lambda path: True), expected)
                snapshot.close()
                with self.assertRaisesRegex(SnapshotError, 'not active'):
                    snapshot.selected_files(lambda path: True)

    def test_selected_files_path_only_predicate_empty_and_alias_projection(self):
        self.file('real/input')
        (self.root / 'alias').symlink_to(self.root / 'real/input')
        with Snapshot(self.root, ['alias']) as snapshot:
            seen = []
            def include(path):
                self.assertIsInstance(path, str)
                seen.append(path)
                return True
            selected = snapshot.selected_files(include)
            self.assertEqual(selected, snapshot.identity['files'])
            self.assertEqual(seen, ['alias'])
            self.assertIn('resolved', selected[0])
            self.assertEqual(snapshot.selected_files(lambda path: False), [])
            self.assertTrue(snapshot.unchanged())

    def test_session_reads_overlapping_bytes_once_without_changing_identity(self):
        self.file('input', b'content')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            with Snapshot(self.root, ['input'], digest_session=session) as second:
                self.assertEqual(first.identity, second.identity)
                self.assertEqual(first.statistics['bytes_hashed'], 7)
                self.assertEqual(second.statistics['bytes_hashed'], 0)
                self.assertEqual(second.statistics['digest_reuses'], 1)
                self.assertTrue(first.unchanged() and second.unchanged())

    def test_session_closed_owner_requires_content_read(self):
        self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            expected = first.identity
        with Snapshot(self.root, ['input'], digest_session=session) as second:
            self.assertEqual(second.identity, expected)
            self.assertEqual(second.statistics['files_hashed'], 1)
            self.assertEqual(second.statistics['digest_reuses'], 0)

    def test_session_inherited_by_a_new_process_requires_content_read(self):
        self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            with patch('verification_snapshot.os.getpid', return_value=os.getpid() + 1):
                with Snapshot(self.root, ['input'], digest_session=session) as second:
                    self.assertEqual(second.identity, first.identity)
                    self.assertEqual(second.statistics['files_hashed'], 1)
                    self.assertEqual(second.statistics['digest_reuses'], 0)

    def test_session_restored_bytes_and_mtime_reject_old_watch(self):
        path = self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            before = path.stat()
            path.write_bytes(b'mutation')
            path.write_bytes(b'original')
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
            with Snapshot(self.root, ['input'], digest_session=session) as second:
                self.assertEqual(second.identity, first.identity)
                self.assertEqual(second.statistics['files_hashed'], 1)
                self.assertFalse(first.unchanged())
                self.assertTrue(second.unchanged())

    def test_session_same_size_restored_mtime_cannot_reuse_old_digest(self):
        path = self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            before = path.stat()
            path.write_bytes(b'mutation')
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
            with Snapshot(self.root, ['input'], digest_session=session) as second:
                self.assertNotEqual(first.identity, second.identity)
                self.assertEqual(second.statistics['bytes_hashed'], 8)
                self.assertFalse(first.unchanged())

    def test_session_watch_failure_cannot_supply_a_hash(self):
        self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            first._watcher.failure = 'injected event loss'
            with self.assertRaisesRegex(SnapshotError, 'event loss'):
                with Snapshot(self.root, ['input'], digest_session=session):
                    pass

    def test_session_receiver_keeps_own_watch_after_owner_closes(self):
        path = self.file('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            with Snapshot(self.root, ['input'], digest_session=session) as second:
                first.close()
                path.write_bytes(b'mutation')
                self.assertFalse(second.unchanged())

    def test_session_bound_eviction_only_costs_reads(self):
        self.file('a')
        self.file('b')
        session = DigestSession(max_entries=1)
        with Snapshot(self.root, ['a', 'b'], digest_session=session) as first:
            with Snapshot(self.root, ['a', 'b'], digest_session=session) as second:
                self.assertEqual(first.identity, second.identity)
                self.assertEqual(second.statistics['files_hashed'], 1)
                self.assertEqual(second.statistics['digest_reuses'], 1)
                self.assertEqual(len(session._entries), 1)

    def test_session_shares_alias_bytes_but_keeps_alias_identity(self):
        self.file('input')
        (self.root / 'alias').symlink_to('input')
        session = DigestSession()
        with Snapshot(self.root, ['input'], digest_session=session) as first:
            with Snapshot(self.root, ['alias'], digest_session=session) as second:
                self.assertEqual(second.statistics['digest_reuses'], 1)
                self.assertNotEqual(first.identity, second.identity)
                (self.root / 'alias').unlink()
                (self.root / 'alias').symlink_to('input')
                self.assertFalse(second.unchanged())

    def test_statistics_are_detached_and_not_semantic_inputs(self):
        self.file('input')
        with Snapshot(self.root, ['input']) as snapshot:
            before = snapshot.identity
            stats = snapshot.statistics
            stats['bytes_hashed'] = -1
            self.assertGreaterEqual(snapshot.statistics['bytes_hashed'], 0)
            self.assertEqual(snapshot.identity, before)

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


class RetainedSnapshots(unittest.TestCase):
    setUp = InputSnapshot.setUp
    file = InputSnapshot.file
    def test_warm_request_keeps_watcher_identity_and_reports_only_new_work(self):
        self.file('scope/input')
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['scope/']) as first:
                expected = first.identity
                owner = first._lease[1]
                self.assertEqual(first.statistics['files_hashed'], 1)
            with patch('verification_snapshot.os.scandir', side_effect=AssertionError('enumeration')):
                with Snapshot(self.root, ['scope/']) as second:
                    self.assertIs(second._lease[1], owner)
                    self.assertEqual(second.identity, expected)
                    self.assertEqual(second.statistics['files_hashed'], 0)
                    self.assertEqual(second.statistics['directories_enumerated'], 0)
                    self.assertEqual(second.statistics['snapshot_reuses'], 1)
                    self.assertGreater(second.statistics['metadata_observations'], 0)
                    second.identity['files'].clear()
                    self.assertEqual(second.identity, expected)
            self.assertIsNotNone(owner._watcher)
        self.assertIsNone(owner._watcher)

    def test_edit_invalidates_only_affected_scope(self):
        changed = self.file('a/input')
        self.file('b/input')
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['a/']), Snapshot(self.root, ['b/']):
                pass
            changed.write_bytes(b'new')
            with Snapshot(self.root, ['a/']) as a, Snapshot(self.root, ['b/']) as b:
                self.assertEqual(a.statistics['files_hashed'], 1)
                self.assertEqual(a.statistics['snapshot_reuses'], 0)
                self.assertEqual(b.statistics['files_hashed'], 0)
                self.assertEqual(b.statistics['snapshot_reuses'], 1)

    def test_nested_dirty_borrowers_never_rebase_or_close_each_other(self):
        path = self.file('input')
        with RetainedSession() as session, session.activate(), ExitStack() as stack:
            first = stack.enter_context(Snapshot(self.root, ['input']))
            second = stack.enter_context(Snapshot(self.root, ['input']))
            original = first.identity
            owner = first._lease[1]
            path.write_bytes(b'new')
            with Snapshot(self.root, ['input']) as fresh:
                self.assertNotEqual(fresh.identity, original)
                self.assertFalse(first.unchanged())
                first.close()
                self.assertIsNotNone(owner._watcher)
                self.assertEqual(second.identity, original)
                self.assertFalse(second.unchanged())
            second.close()
            self.assertIsNone(owner._watcher)

    def test_membership_rename_alias_and_aba_rescan(self):
        path = self.file('scope/input')
        target = self.file('target')
        alias = self.root / 'scope/alias'
        alias.symlink_to(target)
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['scope/'], directory_membership=['scope']) as original:
                identity = original.identity
            old = path.stat()
            path.write_bytes(b'modified')
            path.write_bytes(b'original')
            os.utime(path, ns=(old.st_atime_ns, old.st_mtime_ns))
            with Snapshot(self.root, ['scope/'], directory_membership=['scope']) as aba:
                self.assertEqual(aba.statistics['snapshot_reuses'], 0)
            path.rename(path.with_name('renamed'))
            alias.unlink()
            alias.symlink_to(path.with_name('renamed'))
            with Snapshot(self.root, ['scope/'], directory_membership=['scope']) as renamed:
                self.assertEqual(renamed.statistics['snapshot_reuses'], 0)
                self.assertNotEqual(renamed.identity, identity)
            self.file('scope/new')
            with Snapshot(self.root, ['scope/'], directory_membership=['scope']) as added:
                self.assertEqual(added.statistics['snapshot_reuses'], 0)

    def test_lost_closed_and_overflow_watchers_are_fresh(self):
        self.file('input')
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['input']) as first:
                owner = first._lease[1]
            owner._watcher.failure = 'inotify queue overflow'
            with Snapshot(self.root, ['input']) as overflow:
                self.assertEqual(overflow.statistics['files_hashed'], 1)
                owner = overflow._lease[1]
            owner.close()
            with Snapshot(self.root, ['input']) as closed:
                self.assertEqual(closed.statistics['files_hashed'], 1)
                owner = closed._lease[1]
            owner._watcher.close()
            with Snapshot(self.root, ['input']) as lost:
                self.assertEqual(lost.statistics['snapshot_reuses'], 0)

    def test_fork_rejects_inherited_borrower_and_reconstructs_session(self):
        self.file('input')
        actual_pid = os.getpid()
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['input']) as first:
                with patch('verification_snapshot.os.getpid', return_value=actual_pid + 1):
                    self.assertRaises(SnapshotError, first.unchanged)
                    with Snapshot(self.root, ['input']) as child:
                        self.assertEqual(child.statistics['files_hashed'], 1)
                        self.assertEqual(child.statistics['snapshot_reuses'], 0)

    def test_bounds_evict_idle_and_allow_transient_busy_or_oversized(self):
        self.file('a')
        self.file('b')
        with RetainedSession(max_snapshots=1) as session, session.activate():
            with Snapshot(self.root, ['a']) as a:
                owner = a._lease[1]
                with Snapshot(self.root, ['b']) as b:
                    self.assertIsNone(b._lease[2])
                    transient = b._lease[1]
                    self.assertTrue(a.unchanged())
                self.assertIsNone(transient._watcher)
            with Snapshot(self.root, ['b']):
                self.assertIsNone(owner._watcher)
            self.assertEqual(len(session._owners), 1)
        with RetainedSession(max_entries=1) as tiny, tiny.activate():
            with Snapshot(self.root, ['a']) as oversized:
                self.assertIsNone(oversized._lease[2])
            self.assertEqual(len(tiny._owners), 0)
        with RetainedSession(max_snapshots=0) as disabled, disabled.activate():
            with Snapshot(self.root, ['a']) as transient:
                self.assertIsNone(transient._lease[2])

    def test_declaration_slots_and_long_payloads_are_bounded(self):
        self.file('input')
        with RetainedSession(max_entries=100) as pool, pool.activate():
            with Snapshot(self.root, ['input'] * 1000) as repeated:
                self.assertIsNone(repeated._lease[2])
                self.assertGreater(pool._cost(repeated._lease[1]), 100)
            self.assertEqual(len(pool._owners), 0)
        with RetainedSession() as pool, pool.activate():
            with Snapshot(self.root, ['input'], [self.root / 'input'] * 1000) as repeated:
                self.assertGreaterEqual(pool._cost(repeated._lease[1]), 2000)
                owner = repeated._lease[1]
                before = pool._cost(owner)
                owner.recipes = ['x' * 1025]
                self.assertGreaterEqual(pool._cost(owner), before + 4)

    def test_reset_and_close_invalidate_active_transient_borrowers(self):
        self.file('input')
        with RetainedSession(max_entries=0) as pool, pool.activate():
            with Snapshot(self.root, ['input']) as transient:
                owner = transient._lease[1]
                self.assertIn(owner, pool._transient)
                pool.reset()
                self.assertIsNone(owner._watcher)
                self.assertRaises(SnapshotError, transient.unchanged)
                self.assertRaises(SnapshotError, lambda: transient.identity)
                self.assertEqual(len(pool._transient), 0)
            self.assertEqual(len(pool._owners), 0)
            with Snapshot(self.root, ['input']) as transient:
                owner = transient._lease[1]
                pool.close()
                self.assertIsNone(owner._watcher)
                self.assertRaises(SnapshotError, transient.unchanged)
            self.assertEqual(len(pool._retired), 0)
            self.assertEqual(len(pool._transient), 0)

    def test_busy_transient_release_and_reset_do_not_retain_it(self):
        self.file('a')
        self.file('b')
        with RetainedSession(max_snapshots=1) as pool, pool.activate():
            with Snapshot(self.root, ['a']) as retained:
                with Snapshot(self.root, ['b']) as transient:
                    owner = transient._lease[1]
                    self.assertIn(owner, pool._transient)
                self.assertIsNone(owner._watcher)
                self.assertEqual(len(pool._transient), 0)
                with Snapshot(self.root, ['b']) as transient:
                    pool.reset()
                    self.assertRaises(SnapshotError, transient.unchanged)
                    self.assertRaises(SnapshotError, retained.unchanged)
            self.assertEqual(len(pool._owners), 0)
            self.assertEqual(len(pool._retired), 0)
            self.assertEqual(len(pool._transient), 0)

    def test_reset_close_and_nested_activation(self):
        self.file('input')
        with RetainedSession() as outer, outer.activate():
            with Snapshot(self.root, ['input']) as first:
                owner = first._lease[1]
            with RetainedSession() as inner, inner.activate():
                with Snapshot(self.root, ['input']) as nested:
                    self.assertIsNot(nested._lease[1], owner)
            with Snapshot(self.root, ['input']) as warm:
                self.assertEqual(warm.statistics['snapshot_reuses'], 1)
                outer.reset()
                self.assertRaises(SnapshotError, warm.unchanged)
            with Snapshot(self.root, ['input']) as cold:
                self.assertEqual(cold.statistics['files_hashed'], 1)
        self.assertRaises(SnapshotError, outer.__enter__)
        self.assertRaises(ValueError, RetainedSession, max_entries=-1)


class SnapshotValidationWork(unittest.TestCase):
    setUp = InputSnapshot.setUp
    file = InputSnapshot.file

    def test_dirty_short_circuit_avoids_metadata_and_never_rebases(self):
        path = self.file('input')
        with Snapshot(self.root, ['input']) as snapshot:
            before = snapshot.statistics
            path.write_bytes(b'modified')
            self.assertFalse(snapshot.unchanged())
            self.assertEqual(snapshot.statistics['metadata_observations'], before['metadata_observations'])
            path.write_bytes(b'original')
            self.assertFalse(snapshot.unchanged())
            self.assertEqual(snapshot.statistics['metadata_observations'], before['metadata_observations'])

    def test_missing_path_and_metadata_fallback_diagnostics(self):
        with Snapshot(self.root, [], directory_membership=['missing']) as snapshot:
            self.file('missing')
            with patch.object(snapshot._watcher, 'drain', side_effect=lambda: not snapshot._watcher.dirty):
                self.assertFalse(snapshot.unchanged())
            self.assertTrue(any(row['name'] == 'missing' and row['reason'] == 'missing path appeared'
                                for row in snapshot.stability_diagnostics()['reasons']))

    def test_diagnostic_bounds_and_detachment_do_not_read_or_clear_dirty(self):
        from verification_snapshot import _DirtyReasons
        collector = _DirtyReasons()
        for index in range(100):
            collector.add('path', str(self.root / str(index)), 'x' * 700)
        report = collector.report('r' * 700, lambda path: str(path))
        self.assertEqual(len(report['reasons']), 64)
        self.assertTrue(report['truncated'])
        self.assertTrue(all(len(row['reason']) <= 512 and len(row['role']) <= 512
                            for row in report['reasons']))
        self.file('input')
        with Snapshot(self.root, ['input']) as snapshot:
            snapshot._dirty_reasons = collector
            with patch.object(Path, 'lstat', side_effect=AssertionError('diagnostic read')):
                detached = snapshot.stability_diagnostics()
            detached['reasons'].clear()
            self.assertEqual(len(snapshot.stability_diagnostics()['reasons']), 64)
            self.assertTrue(snapshot.unchanged())

    def test_diagnostics_unknown_after_reset_and_fork(self):
        self.file('input')
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['input']) as borrower:
                session.reset()
                self.assertRaises(SnapshotError, borrower.unchanged)
                self.assertTrue(borrower.stability_diagnostics()['unknown'])
        with Snapshot(self.root, ['input']) as snapshot:
            with patch('verification_snapshot.os.getpid', return_value=os.getpid() + 1):
                self.assertRaises(SnapshotError, snapshot.unchanged)
            self.assertTrue(snapshot.stability_diagnostics()['unknown'])

    def test_construction_resolves_each_inventory_file_once(self):
        self.file('scope/one')
        self.file('scope/two')
        original = Snapshot._required_file
        resolved = []
        def resolve(snapshot, path):
            resolved.append(path)
            return original(snapshot, path)
        with patch.object(Snapshot, '_required_file', resolve):
            with Snapshot(self.root, ['scope/']) as snapshot:
                self.assertEqual(len(resolved), 2)
                self.assertEqual(len(snapshot.identity['files']), 2)
                self.assertEqual(snapshot._resolved_files, {})
                self.assertTrue(snapshot.unchanged())

    def test_alias_retarget_between_resolution_and_hashing_rejects(self):
        target = self.file('one')
        other = self.file('two')
        alias = self.root / 'alias'
        alias.symlink_to(target)
        original = Snapshot._hash_file
        def retarget_then_hash(snapshot, path):
            alias.unlink()
            alias.symlink_to(other)
            return original(snapshot, path)
        snapshot = Snapshot(self.root, ['alias'])
        with patch.object(Snapshot, '_hash_file', retarget_then_hash):
            self.assertRaises(SnapshotError, snapshot.__enter__)
        self.assertEqual(snapshot._resolved_files, {})
        self.assertTrue(snapshot.stability_diagnostics()['unknown'])
        self.assertTrue(any(row['name'] == 'alias' for row in snapshot.stability_diagnostics()['reasons']))

    def test_metadata_checks_remain_fresh_without_watch_events(self):
        path = self.file('input')
        with Snapshot(self.root, ['input']) as first, Snapshot(self.root, ['input']) as second:
            self.assertTrue(first.unchanged())
            path.write_bytes(b'metadata-only replacement')
            # Emulate a filesystem which changes metadata without local events.
            with patch.object(second._watcher, 'drain', side_effect=lambda: not second._watcher.dirty):
                self.assertFalse(second.unchanged())
            self.assertTrue(any(row['reason'] == 'metadata identity changed'
                                for row in second.stability_diagnostics()['reasons']))

    def test_borrower_diagnostics_survive_context_cleanup(self):
        path = self.file('input')
        with RetainedSession() as session, session.activate():
            with Snapshot(self.root, ['input']) as borrower:
                path.write_bytes(b'modified')
                self.assertFalse(borrower.unchanged())
                before = borrower.stability_diagnostics('source')
            self.assertEqual(borrower.stability_diagnostics('source'), before)

    def test_overflow_diagnostic_remains_unknown_after_read_recovers(self):
        self.file('input')
        overflow = struct.pack('iIII', -1, 0x4000, 0, 0)
        with Snapshot(self.root, ['input']) as snapshot:
            with patch('verification_snapshot.os.read', side_effect=[overflow, BlockingIOError()]):
                self.assertRaises(SnapshotError, snapshot.unchanged)
            first = snapshot.stability_diagnostics('tools')
            self.assertTrue(first['unknown'])
            self.assertTrue(any('queue overflow' in row['reason'] for row in first['reasons']))
            self.assertRaises(SnapshotError, snapshot.unchanged)
            self.assertEqual(snapshot.stability_diagnostics('tools'), first)

    def test_path_membership_and_alias_reasons_name_observed_inputs(self):
        self.file('tools/one')
        self.file('target')
        alias = self.root / 'alias'
        alias.symlink_to('target')
        with Snapshot(self.root, ['tools/*.sentinel', 'alias']) as snapshot:
            self.file('tools/shadowing-executable')
            alias.unlink()
            alias.symlink_to('target')
            self.assertFalse(snapshot.unchanged())
            reasons = snapshot.stability_diagnostics('tools')['reasons']
            self.assertTrue(any(row['name'] == 'tools/shadowing-executable' for row in reasons))
            self.assertTrue(any(row['name'] == 'alias' for row in reasons))

    def test_unattributed_dirty_authority_is_unknown(self):
        self.file('input')
        with Snapshot(self.root, ['input']) as snapshot:
            snapshot._watcher.dirty = True
            self.assertFalse(snapshot.unchanged())
            report = snapshot.stability_diagnostics()
            self.assertTrue(report['unknown'])
            self.assertEqual(report['reasons'][0]['reason'], 'dirty cause unavailable')

    def test_profile_fixture_preserves_warm_identity_and_rejects_all_aba_consumers(self):
        from verification_snapshot_profile import profile
        result = profile(Path(__file__).with_name('verification_snapshot.py'), files=4, snapshots=2)
        self.assertTrue(result['warm_valid'])
        self.assertTrue(result['warm_identity_equal'])
        self.assertEqual(result['warm']['files_hashed'], 0)
        self.assertEqual(result['warm']['directories_enumerated'], 0)
        self.assertEqual(result['warm']['snapshot_reuses'], 2)
        self.assertEqual(result['edited_valid'], [False, False])
        self.assertEqual(result['edited']['metadata_observations'], 0)


if __name__ == '__main__':
    unittest.main()
