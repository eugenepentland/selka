#!/usr/bin/env python3
"""Batch publication boundaries using the coordinator's existing fake driver."""
import unittest
from unittest.mock import patch

import verify_cache as coordinator
import verify_cache_test as fixtures


class VerificationPublication(fixtures.VerificationCoordinator):
    def admit(self, *args, **controls):
        finalize = controls.get('finalize')
        if finalize is not None:
            def count_validations(*arguments):
                original, count = coordinator.check_all, []
                def full_check(snapshots):
                    stable = original(snapshots)
                    count.append(True)
                    hook = getattr(self, 'publication_validation_hook', None)
                    if hook is not None:
                        hook(len(count))
                    return stable
                with patch.object(coordinator, 'check_all', side_effect=full_check) as checks:
                    result = finalize(*arguments)
                    self.publication_validations = checks.call_count
                    hook = getattr(self, 'publication_return_hook', None)
                    if hook is not None:
                        hook()
                    return result
            controls['finalize'] = count_validations
        return super().admit(*args, **controls)

    def mutate(self, aba):
        original = self.input.read_bytes()
        self.input.write_bytes(b'changed at publication commit')
        if aba:
            self.input.write_bytes(original)

    def assert_no_shared_success(self, shared):
        store = coordinator.fuzz_campaign_store.Store(shared)
        for path in (shared / 'success').glob('*.json'):
            self.assertIsNone(store.load_success(path.stem))

    def test_successful_gate_runs_two_full_publication_validations(self):
        self.assertEqual(self.execute(shared=self.root / '.batch-shared'), 0)
        self.assertEqual(self.publication_validations, 2)
        self.assertEqual(len(self.receipts()), 2)
        self.assertTrue(all(coordinator.valid_receipt(path, path.stem) for path in self.receipts()))

    def test_local_only_gate_runs_two_full_publication_validations(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.publication_validations, 2)

    def test_aba_after_final_full_validation_prevents_commit(self):
        shared = self.root / '.post-validation-shared'
        self.publication_validation_hook = lambda count: self.mutate(True) if count == 2 else None
        self.assertEqual(self.execute(shared=shared), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])
        self.assert_no_shared_success(shared)
        self.assertEqual(list((shared / 'blobs').iterdir()), [])

    def test_mutation_after_finalize_returns_revokes_the_completed_batch(self):
        shared = self.root / '.post-return-shared'
        self.publication_return_hook = lambda: self.mutate(True)
        self.assertEqual(self.execute(shared=shared), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])
        self.assert_no_shared_success(shared)

    def test_shared_marker_mutation_or_aba_revokes_every_receipt(self):
        original = coordinator.fuzz_campaign_store.Store.put_blob
        for aba in (False, True):
            with self.subTest(aba=aba):
                shared = self.root / ('.marker-shared-' + str(aba))
                def put_blob(store, data):
                    digest = original(store, data)
                    if b'verification-publication-v1' in data:
                        self.mutate(aba)
                    return digest
                with patch.object(coordinator.fuzz_campaign_store.Store, 'put_blob', put_blob):
                    self.assertEqual(self.execute(shared=shared), coordinator.RETRY)
                self.assertEqual(self.receipts(), [])
                self.assert_no_shared_success(shared)

    def test_local_marker_mutation_or_aba_revokes_every_receipt(self):
        original = coordinator.atomic_record
        for aba in (False, True):
            with self.subTest(aba=aba):
                shared = self.root / ('.local-marker-shared-' + str(aba))
                def atomic_record(path, value):
                    original(path, value)
                    if path.parent == self.cache / 'commits':
                        self.mutate(aba)
                with patch.object(coordinator, 'atomic_record', atomic_record):
                    self.assertEqual(self.execute(shared=shared), coordinator.RETRY)
                self.assertEqual(self.receipts(), [])
                self.assert_no_shared_success(shared)

    def test_interruption_after_shared_commit_revokes_own_generations(self):
        original = coordinator.fuzz_campaign_store.Store.put_blob
        shared = self.root / '.interrupted-shared'
        def put_blob(store, data):
            digest = original(store, data)
            if b'verification-publication-v1' in data:
                raise KeyboardInterrupt
            return digest
        with patch.object(coordinator.fuzz_campaign_store.Store, 'put_blob', put_blob):
            with self.assertRaises(KeyboardInterrupt):
                self.execute(shared=shared)
        self.assertEqual(self.receipts(), [])
        self.assert_no_shared_success(shared)

    def test_interruption_after_local_commit_revokes_own_generations(self):
        original = coordinator.atomic_record
        shared = self.root / '.interrupted-local'
        def atomic_record(path, value):
            original(path, value)
            if path.parent == self.cache / 'commits':
                raise KeyboardInterrupt
        with patch.object(coordinator, 'atomic_record', atomic_record):
            with self.assertRaises(KeyboardInterrupt):
                self.execute(shared=shared)
        self.assertEqual(self.receipts(), [])
        self.assert_no_shared_success(shared)

    def test_failed_per_key_invalidation_still_hides_entire_shared_batch(self):
        atomic = coordinator.atomic_record
        invalidate = coordinator.fuzz_campaign_store.Store.invalidate_success
        shared = self.root / '.failed-rollback-shared'
        def atomic_record(path, value):
            atomic(path, value)
            if path.parent == self.cache / 'commits':
                self.mutate(True)
        def invalidate_success(store, action_key, **options):
            if options.get('publication') is not None:
                raise OSError('injected invalidation marker write failure')
            return invalidate(store, action_key, **options)
        with patch.object(coordinator, 'atomic_record', atomic_record), \
                patch.object(coordinator.fuzz_campaign_store.Store, 'invalidate_success', invalidate_success):
            with self.assertRaisesRegex(OSError, 'invalidation marker'):
                self.execute(shared=shared)
        self.assert_no_shared_success(shared)
        self.assertFalse(any(coordinator.valid_receipt(path, path.stem) for path in self.receipts()))


def load_tests(loader, tests, pattern):
    # Reuse the fixture without running its inherited suite a second time.
    return unittest.TestSuite(VerificationPublication(name) for name in
                              sorted(VerificationPublication.__dict__) if name.startswith('test_'))


if __name__ == '__main__':
    unittest.main()
