#!/usr/bin/env python3
"""Bounded campaign cache tests; no compiler or server admission is needed."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import fcntl
import json
import multiprocessing
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import fuzz_campaign_store as storage
from fuzz_campaign_store import CorpusError, InputsChanged, Store, DeterminismError, FormatError, RetentionError


def identity(value):
    return hashlib.sha256(value.encode()).hexdigest()


def leased_process(root, channel):
    with Store(Path(root)).lease() as store:
        digest = store.put_blob(b'active unpublished input')
        channel.send(digest)
        channel.recv()


def competing_process(root, key, count, start, channel):
    store = Store(Path(root))
    start.wait(timeout=5)
    try:
        channel.send(store.publish_success(key, {'passed': count}, [], lambda: True))
    except DeterminismError:
        channel.send('conflict')


def gc_process(root, channel):
    channel.send(Store(Path(root)).gc(max_bytes=0, dry_run=False))


def waiting_key_process(root, family, channel):
    store = Store(Path(root))
    original = store._lock_descriptor

    def tracked(path):
        if path.parent.name == 'coordinator':
            channel.send('opening-key')
        return original(path)

    store._lock_descriptor = tracked
    with store.coordinator_lock(family):
        channel.send('acquired-key')
        channel.recv()


class CampaignStore(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='campaign-store-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.store = Store(self.root)
        self.key = identity('one exact shard')
        self.family = identity('stable replay family')
        self.blob = self.store.put_blob(b'concrete corpus case')
        self.result = {'passed': 128, 'corpus': self.blob}

    def success_path(self, key=None):
        return self.root / 'success' / ((key or self.key) + '.json')

    def corpus_path(self):
        return self.root / 'corpus' / (self.family + '.json')

    def publish(self, validate=lambda: True):
        return self.store.publish_success(self.key, self.result, [self.blob], validate)

    def tamper(self, path, transform):
        record = json.loads(path.read_bytes())
        transform(record['payload'])
        path.write_bytes(storage._envelope(record['payload']))

    def test_completed_exact_shard_and_raw_corpus_are_independent(self):
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.load_corpus(self.family), [])
        self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue(self.publish())
        self.assertEqual(self.store.load_success(self.key), self.result)
        self.assertIsNone(self.store.load_success(identity('different target binary')))
        self.store.discard_success(self.key)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.load_corpus(self.family), [self.blob])

    def test_blob_checksum_missing_corruption_and_repair(self):
        self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')
        self.assertTrue(self.publish())
        path = self.root / 'blobs' / self.blob
        path.write_bytes(b'corrupt case')
        self.assertIsNone(self.store.read_blob(self.blob))
        self.assertIsNone(self.store.load_success(self.key))
        self.assertFalse(self.publish())
        self.assertEqual(self.store.put_blob(b'concrete corpus case'), self.blob)
        self.assertEqual(self.store.load_success(self.key), self.result)
        path.unlink()
        self.assertIsNone(self.store.load_success(self.key))

    def test_nonregular_and_symlink_cache_entries_never_block_or_authorize(self):
        blob_path = self.root / 'blobs' / self.blob
        external = self.root / 'external'
        external.write_bytes(b'concrete corpus case')
        blob_path.unlink()
        blob_path.symlink_to(external)
        self.assertIsNone(self.store.read_blob(self.blob))
        self.assertFalse(self.publish())
        blob_path.unlink()
        os.mkfifo(blob_path)
        self.assertIsNone(self.store.read_blob(self.blob))
        # put_blob atomically replaces a malformed path with regular bytes.
        self.assertEqual(self.store.put_blob(b'concrete corpus case'), self.blob)
        self.assertTrue(self.publish())
        real_success = self.success_path().read_bytes()
        self.success_path().unlink()
        os.mkfifo(self.success_path())
        self.assertIsNone(self.store.load_success(self.key))
        self.success_path().unlink()
        external.write_bytes(real_success)
        self.success_path().symlink_to(external)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue(self.publish())
        self.assertEqual(self.store.load_success(self.key), self.result)
        self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        self.corpus_path().unlink()
        os.mkfifo(self.corpus_path())
        with self.assertRaises(CorpusError):
            self.store.load_corpus(self.family)
        self.store.discard_corpus(self.family)
        self.corpus_path().mkdir()
        with self.assertRaises(CorpusError):
            self.store.load_corpus(self.family)

    def test_success_checksum_strict_schema_and_foreign_identity_miss(self):
        self.assertTrue(self.publish())
        original = self.success_path().read_bytes()
        for change in (
                lambda p: p.update(key=identity('foreign')),
                lambda p: p.update(version=True),
                lambda p: p.update(kind='other'),
                lambda p: p.update(extra=1),
                lambda p: p.update(result=[]),
                lambda p: p.update(blobs=[self.blob, self.blob]),
                lambda p: p.update(publication='../outside')):
            with self.subTest(change=change):
                self.success_path().write_bytes(original)
                self.tamper(self.success_path(), change)
                self.assertIsNone(self.store.load_success(self.key))
        self.success_path().write_bytes(original.replace(b'128', b'129'))
        self.assertIsNone(self.store.load_success(self.key))
        self.success_path().write_bytes(b'{"payload":{},"payload":{},"checksum":"' +
                                        b'0' * 64 + b'"}')
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue(self.publish())  # Corruption is a replaceable cache miss.

    def test_malformed_identifiers_duplicate_refs_and_non_json_results_rejected(self):
        for value in ('../outside', 'A' * 64, '0' * 63, '0' * 64 + '/', None, 1):
            with self.subTest(value=value):
                for operation in (self.store.read_blob, self.store.load_success,
                                  self.store.discard_success, self.store.load_corpus,
                                  self.store.discard_corpus, self.store.coordinator_lock):
                    with self.assertRaises(ValueError):
                        operation(value)
        with self.assertRaises(ValueError):
            self.store.publish_success(self.key, self.result,
                                       [self.blob, self.blob], lambda: True)
        with self.assertRaises(ValueError):
            self.store.retain_corpus(self.family, [self.blob, self.blob])
        for result in ([], {1: 'numeric key'}, {'nan': float('nan')}, {'data': b'bytes'}):
            with self.subTest(result=result), self.assertRaises(ValueError):
                self.store.publish_success(self.key, result, [], lambda: True)
        self.assertIsNone(self.store.load_success(self.key))

    def test_validator_false_before_and_after_publication(self):
        with self.assertRaises(InputsChanged):
            self.publish(lambda: False)
        self.assertFalse(self.success_path().exists())
        calls = []

        def changed_after():
            calls.append(1)
            return len(calls) == 1

        with self.assertRaises(InputsChanged):
            self.publish(changed_after)
        self.assertEqual(len(calls), 2)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertFalse(self.success_path().exists())

    def test_validator_exception_cleans_only_own_exact_publication(self):
        other = identity('other concurrent shard')
        self.assertTrue(self.store.publish_success(other, {'passed': 7}, [], lambda: True))
        calls = []

        def cancelled_after():
            calls.append(1)
            if len(calls) == 2:
                raise KeyboardInterrupt('cancelled')
            return True

        with self.assertRaises(KeyboardInterrupt):
            self.publish(cancelled_after)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.load_success(other), {'passed': 7})
        # Even a writer bypassing the lock cannot have its different bytes removed.
        replacement = {'version': 1, 'kind': 'fuzz-success', 'key': self.key,
                       'publication': identity('other publication'),
                       'result': {'passed': 3}, 'blobs': []}
        calls.clear()

        def replace_after():
            calls.append(1)
            if len(calls) == 2:
                self.success_path().write_bytes(storage._envelope(replacement))
                return False
            return True

        with self.assertRaises(InputsChanged):
            self.publish(replace_after)
        self.assertEqual(self.store.load_success(self.key), {'passed': 3})

    def test_blob_removed_by_final_guard_cannot_be_success(self):
        calls = []

        def remove_after():
            calls.append(1)
            if len(calls) == 2:
                (self.root / 'blobs' / self.blob).unlink()
            return True

        self.assertFalse(self.publish(remove_after))
        self.assertIsNone(self.store.load_success(self.key))

    def test_existing_receipt_still_requires_both_guards_and_never_overwritten(self):
        self.assertTrue(self.publish())
        original = self.success_path().read_bytes()
        self.assertTrue(self.publish())
        self.assertEqual(self.success_path().read_bytes(), original)
        replies = iter([True, False])
        with self.assertRaises(InputsChanged):
            self.publish(lambda: next(replies))
        self.assertEqual(self.success_path().read_bytes(), original)
        with self.assertRaises(DeterminismError):
            self.store.publish_success(self.key, {'passed': 7}, [self.blob], lambda: True)
        self.assertEqual(self.success_path().read_bytes(), original)
        self.assertIsNone(self.store.load_success(self.key))
        self.store.discard_success(self.key)
        with self.assertRaises(DeterminismError):
            self.publish()
        self.store.clear_conflict(self.key)
        self.assertTrue(self.publish())

    def test_concurrent_publication_first_writer_cas(self):
        start = threading.Barrier(2)

        def publish(count):
            independent = Store(self.root)
            start.wait(timeout=5)
            try:
                return independent.publish_success(self.key, {'passed': count}, [], lambda: True)
            except DeterminismError:
                return 'conflict'

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(publish, count) for count in (11, 22)]
            outcomes = [future.result(timeout=5) for future in futures]
        self.assertCountEqual(outcomes, [True, 'conflict'])
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue((self.root / 'conflicts' / (self.key + '.json')).is_file())

    def test_load_cannot_observe_publication_before_post_guard(self):
        published = threading.Event()
        release = threading.Event()
        reader_started = threading.Event()
        reader_finished = threading.Event()
        calls = []

        def guard():
            calls.append(1)
            if len(calls) == 2:
                published.set()
                if not release.wait(timeout=5):
                    raise TimeoutError('reader did not start')
                return False
            return True

        def reader():
            reader_started.set()
            result = Store(self.root).load_success(self.key)
            reader_finished.set()
            return result

        with ThreadPoolExecutor(max_workers=2) as pool:
            publication = pool.submit(self.publish, guard)
            self.assertTrue(published.wait(timeout=5))
            lookup = pool.submit(reader)
            self.assertTrue(reader_started.wait(timeout=5))
            self.assertFalse(reader_finished.wait(timeout=0.05))
            release.set()
            with self.assertRaises(InputsChanged):
                publication.result(timeout=5)
            self.assertIsNone(lookup.result(timeout=5))

    def test_concurrent_corpus_union_and_failed_campaign_retention(self):
        second = self.store.put_blob(b'a second failing case')
        start = threading.Barrier(2)

        def retain(blob):
            start.wait(timeout=5)
            return Store(self.root).retain_corpus(self.family, [blob])

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(retain, blob) for blob in (self.blob, second)]
            self.assertTrue(all(future.result(timeout=5) for future in futures))
        self.assertEqual(self.store.load_corpus(self.family), sorted([self.blob, second]))
        self.assertIsNone(self.store.load_success(self.key))

    def test_corrupt_or_partial_corpus_requires_explicit_reset(self):
        self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        original = self.corpus_path().read_bytes()
        for change in (
                lambda p: p.update(family=identity('foreign family')),
                lambda p: p.update(version=True),
                lambda p: p.update(blobs=[self.blob, self.blob]),
                lambda p: p.update(extra=7)):
            with self.subTest(change=change):
                self.corpus_path().write_bytes(original)
                self.tamper(self.corpus_path(), change)
                with self.assertRaises(CorpusError):
                    self.store.load_corpus(self.family)
        self.corpus_path().write_bytes(original)
        (self.root / 'blobs' / self.blob).unlink()
        with self.assertRaises(CorpusError):
            self.store.load_corpus(self.family)
        self.store.put_blob(b'concrete corpus case')
        self.corpus_path().write_bytes(b'{"unfinished":')
        with self.assertRaises(CorpusError):
            self.store.retain_corpus(self.family, [self.blob])
        with self.store.coordinator_lock(self.family):
            self.store.discard_corpus(self.family)
            self.assertEqual(self.store.load_corpus(self.family), [])
            self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')

    def test_bounds_reject_blob_metadata_and_union_without_regressing_old_evidence(self):
        with patch.object(storage, 'BLOB_MAX_BYTES', 8):
            with self.assertRaises(ValueError):
                self.store.put_blob(b'ninebytes')
            self.assertIsNone(self.store.read_blob(self.blob))
        self.assertTrue(self.publish())
        original = self.success_path().read_bytes()
        with patch.object(storage, 'METADATA_MAX_BYTES', 512):
            with self.assertRaises(ValueError):
                self.store.publish_success(self.key, {'huge': 'x' * 513}, [], lambda: True)
            self.success_path().write_bytes(b'x' * 513)
            self.assertIsNone(self.store.load_success(self.key))
        self.success_path().write_bytes(original)
        self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        second = self.store.put_blob(b'another corpus')
        with patch.object(storage, 'CORPUS_MAX_ENTRIES', 1):
            with self.assertRaises(ValueError):
                self.store.retain_corpus(self.family, [self.blob, second])
            with self.assertRaises(ValueError):
                self.store.retain_corpus(self.family, [second])
        self.assertEqual(self.store.load_corpus(self.family), [self.blob])
        self.assertEqual(self.store.load_success(self.key), self.result)

    def test_interrupted_atomic_replace_preserves_committed_prefix_only(self):
        first = identity('completed earlier shard')
        self.assertTrue(self.store.publish_success(first, {'passed': 5}, [], lambda: True))
        with patch.object(storage.os, 'replace', side_effect=KeyboardInterrupt('cancelled')):
            with self.assertRaises(KeyboardInterrupt):
                self.publish()
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.load_success(first), {'passed': 5})
        self.assertEqual(list((self.root / 'success').glob('.*')), [])
        self.assertTrue(self.store.retain_corpus(self.family, [self.blob]))
        second = self.store.put_blob(b'next shard raw case')
        with patch.object(storage.os, 'replace', side_effect=KeyboardInterrupt('cancelled')):
            with self.assertRaises(KeyboardInterrupt):
                self.store.retain_corpus(self.family, [second])
        self.assertEqual(self.store.load_corpus(self.family), [self.blob])
        self.assertEqual(self.store.read_blob(second), b'next shard raw case')

    def test_coordinator_lock_serializes_same_family_but_not_other_families(self):
        started = threading.Event()
        entered = threading.Event()

        def contender():
            started.set()
            with Store(self.root).coordinator_lock(self.family):
                entered.set()

        with ThreadPoolExecutor(max_workers=1) as pool:
            with self.store.coordinator_lock(self.family):
                future = pool.submit(contender)
                self.assertTrue(started.wait(timeout=5))
                self.assertFalse(entered.wait(timeout=0.05))
                with Store(self.root).coordinator_lock(identity('independent family')):
                    self.assertFalse(entered.is_set())
            future.result(timeout=5)
        self.assertTrue(entered.is_set())

    def process(self, target, *args):
        process = multiprocessing.get_context('fork').Process(target=target, args=args)
        process.start()

        def cleanup():
            if process.is_alive():
                process.kill()
            process.join(timeout=5)

        self.addCleanup(cleanup)
        return process

    def test_format_rejection_empty_initialization_and_interrupted_marker_recovery(self):
        marker = self.root / 'format.json'
        self.assertEqual(storage._decode(marker.read_bytes()), storage._FORMAT)
        original = marker.read_bytes()
        for value in ({**storage._FORMAT, 'version': True},
                      {**storage._FORMAT, 'version': 2}, {'version': 1}):
            marker.write_bytes(storage._envelope(value))
            with self.assertRaises(FormatError):
                Store(self.root)
            with self.assertRaises(FormatError):
                self.store.read_blob(self.blob)
        marker.write_bytes(original)
        old = self.root / 'old'
        old.mkdir()
        (old / 'blobs').mkdir()
        with self.assertRaisesRegex(FormatError, 'new empty versioned cache root'):
            Store(old)
        recover = self.root / 'recover'
        recover.mkdir()
        (recover / '.format.json-crashed').write_bytes(b'partial marker')
        recovered = Store(recover)
        self.assertTrue((recovered.root / 'format.json').is_file())
        self.assertFalse((recover / '.format.json-crashed').exists())

    def test_canonical_root_alias_uses_same_retention_lock(self):
        alias = self.root.parent / (self.root.name + '-alias')
        alias.symlink_to(self.root, target_is_directory=True)
        self.addCleanup(alias.unlink)
        other = Store(alias)
        self.assertEqual(other.root, self.store.root)
        with self.store.lease():
            self.assertTrue(other.gc(dry_run=False)['skipped_active'])

    def test_category_symlinks_cannot_redirect_collection_outside_store(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.root / 'pins').rmdir()
        (self.root / 'pins').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(FormatError):
            Store(self.root)
        with self.assertRaises(FormatError):
            self.store.gc(dry_run=False)

    def test_replaced_root_alias_cannot_redirect_an_existing_store_or_gc(self):
        other = self.root / 'other-root'
        Store(other)
        moved = self.root.parent / (self.root.name + '-moved')
        self.root.rename(moved)
        self.root.symlink_to(moved / 'other-root', target_is_directory=True)

        def restore():
            self.root.unlink()
            moved.rename(self.root)

        self.addCleanup(restore)
        with self.assertRaises(FormatError):
            self.store.gc(dry_run=False)
        with self.assertRaises(FormatError):
            self.store.read_blob(self.blob)
        self.assertTrue((moved / 'blobs' / self.blob).is_file())

    def test_conflict_post_guard_failure_removes_only_new_tombstone(self):
        self.assertTrue(self.publish())
        replies = iter([True, True, False])
        with self.assertRaises(InputsChanged):
            self.store.publish_success(self.key, {'passed': 7}, [self.blob], lambda: next(replies))
        self.assertEqual(self.store.load_success(self.key), self.result)
        self.assertFalse((self.root / 'conflicts' / (self.key + '.json')).exists())

    def test_invalidated_identical_refresh_restores_hit_and_divergence_poison(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue(self.publish())
        self.assertEqual(self.store.load_success(self.key), self.result)
        self.store.invalidate_success(self.key)
        with self.assertRaises(DeterminismError):
            self.store.publish_success(self.key, {'passed': 7}, [self.blob], lambda: True)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue((self.root / 'conflicts' / (self.key + '.json')).exists())

    def test_invalidated_failed_refresh_never_revives_hit_and_preserves_comparison(self):
        self.assertTrue(self.publish())
        original = self.success_path().read_bytes()
        self.store.invalidate_success(self.key)
        for replies in ([False], [True, False], [True, True, False]):
            answers = iter(replies)
            with self.subTest(replies=replies), self.assertRaises(InputsChanged):
                self.publish(lambda: next(answers))
            self.assertIsNone(self.store.load_success(self.key))
            self.assertEqual(self.success_path().read_bytes(), original)
        self.assertTrue(self.publish())
        self.assertEqual(self.store.load_success(self.key), self.result)

    def test_invalidation_gc_cohort_and_pin_preserve_negative_evidence(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        pin = identity('invalidated reference pin')
        self.store.pin(pin, success=[self.key])
        report = self.store.gc(max_bytes=0, dry_run=False)
        self.assertTrue(report['budget_unmet'])
        self.assertIsNone(self.store.load_success(self.key))
        marker = self.root / 'invalidated' / (self.key + '.json')
        self.assertTrue(marker.exists())
        self.assertTrue(self.success_path().exists())
        self.store.unpin(pin)
        report = self.store.gc(max_bytes=0, dry_run=False)
        self.assertFalse(report['budget_unmet'])
        self.assertFalse(marker.exists())
        self.assertFalse(self.success_path().exists())
        self.assertIsNone(self.store.read_blob(self.blob))

    def test_gc_interruption_deletes_reference_before_invalidation_marker(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        marker = self.root / 'invalidated' / (self.key + '.json')
        original = Path.unlink

        def interrupted(path, *args, **kwargs):
            if path == marker:
                raise KeyboardInterrupt('collector interrupted')
            return original(path, *args, **kwargs)

        with patch.object(Path, 'unlink', interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.store.gc(max_bytes=0, dry_run=False)
        self.assertFalse(self.success_path().exists())
        self.assertTrue(marker.exists())
        self.assertIsNone(self.store.load_success(self.key))
        self.store.gc(max_bytes=0, dry_run=False)
        self.assertFalse(marker.exists())

    def test_orphan_invalidation_marker_is_bounded_by_cache_eviction(self):
        self.store.invalidate_success(self.key)
        marker = self.root / 'invalidated' / (self.key + '.json')
        self.assertTrue(marker.exists())
        self.store.gc(max_bytes=0, dry_run=False)
        self.assertFalse(marker.exists())

    def test_invalidation_restore_io_failure_discards_proof_instead_of_reviving_hit(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        answers = iter([True, True, False])
        with patch.object(storage, '_atomic', side_effect=OSError('restoration failed')):
            with self.assertRaises(OSError):
                self.publish(lambda: next(answers))
        self.assertIsNone(self.store.load_success(self.key))
        self.assertFalse(self.success_path().exists())

    def test_invalidated_marker_unlink_interruption_restores_negative_evidence(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        marker = self.root / 'invalidated' / (self.key + '.json')
        original = Path.unlink

        def interrupted(path, *args, **kwargs):
            result = original(path, *args, **kwargs)
            if path == marker:
                raise KeyboardInterrupt('interrupted after marker unlink')
            return result

        with patch.object(Path, 'unlink', interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.publish()
        self.assertTrue(marker.exists())
        self.assertIsNone(self.store.load_success(self.key))

    def test_missing_old_payload_still_compares_completed_result_identity(self):
        self.assertTrue(self.publish())
        self.store.invalidate_success(self.key)
        (self.root / 'blobs' / self.blob).unlink()
        self.assertIsNone(self.store.load_success(self.key))
        new = self.store.put_blob(b'changed deterministic output')
        with self.assertRaises(DeterminismError):
            self.store.publish_success(self.key, self.result, [new], lambda: True)
        self.assertIsNone(self.store.load_success(self.key))
        self.assertTrue((self.root / 'conflicts' / (self.key + '.json')).exists())

    def test_same_action_blob_manifest_order_is_not_a_conflict(self):
        second = self.store.put_blob(b'second payload')
        self.assertTrue(self.store.publish_success(self.key, self.result, [self.blob, second], lambda: True))
        self.assertTrue(self.store.publish_success(self.key, self.result, [second, self.blob], lambda: True))
        self.assertEqual(self.store.load_success(self.key), self.result)

    def test_different_blob_manifest_poison_survives_discard_and_gc(self):
        self.assertTrue(self.publish())
        second = self.store.put_blob(b'different deterministic payload')
        with self.assertRaises(DeterminismError):
            self.store.publish_success(self.key, self.result, [second], lambda: True)
        self.store.discard_success(self.key)
        result = self.store.gc(max_bytes=0, dry_run=False)
        self.assertTrue(result['budget_unmet'])
        self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')
        self.assertEqual(self.store.read_blob(second), b'different deterministic payload')
        self.assertIsNone(self.store.load_success(self.key))

    def test_multiprocess_divergent_publication_poison_and_atomic_marker_init(self):
        context = multiprocessing.get_context('fork')
        barrier = context.Barrier(2)
        channels, processes = [], []
        root = self.root / 'new-shared-store'
        for count in (11, 22):
            parent, child = context.Pipe()
            channels.append(parent)
            self.addCleanup(parent.close)
            processes.append(self.process(competing_process, root, self.key, count, barrier, child))
            child.close()
        outcomes = []
        for channel in channels:
            self.assertTrue(channel.poll(5))
            outcomes.append(channel.recv())
        for process in processes:
            process.join(timeout=5)
            self.assertEqual(process.exitcode, 0)
        self.assertCountEqual(outcomes, [True, 'conflict'])
        self.assertIsNone(Store(root).load_success(self.key))

    def test_gc_dry_run_preserves_roots_then_collects_unreferenced_blobs(self):
        self.assertTrue(self.publish())
        orphan = self.store.put_blob(b'orphan bytes')
        planned = self.store.gc()
        self.assertFalse(planned['skipped_active'])
        self.assertIn('blobs/' + orphan, planned['paths'])
        self.assertNotIn('blobs/' + self.blob, planned['paths'])
        self.assertNotIn('success/' + self.key + '.json', planned['paths'])
        self.assertEqual(self.store.read_blob(orphan), b'orphan bytes')
        collected = self.store.gc(dry_run=False)
        self.assertEqual(collected['paths'], planned['paths'])
        self.assertIsNone(self.store.read_blob(orphan))
        self.assertEqual(self.store.load_success(self.key), self.result)

    def test_gc_size_eviction_respects_shared_blob_reference_counts(self):
        newer = identity('newer receipt')
        self.assertTrue(self.publish())
        self.assertTrue(self.store.publish_success(newer, {'passed': 7}, [self.blob], lambda: True))
        old_path = self.success_path()
        os.utime(old_path, (time.time() - 100, time.time() - 100))
        total = self.store.gc()['bytes_before']
        result = self.store.gc(max_bytes=total - old_path.stat().st_size, dry_run=False)
        self.assertIn('success/' + self.key + '.json', result['paths'])
        self.assertNotIn('success/' + newer + '.json', result['paths'])
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.load_success(newer), {'passed': 7})
        self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')

    def test_pins_retain_receipt_and_corpus_snapshot_payloads_after_mutation(self):
        self.assertTrue(self.publish())
        second = self.store.put_blob(b'pinned replay input')
        self.assertTrue(self.store.retain_corpus(self.family, [second]))
        pin = identity('user pinned campaign')
        self.store.pin(pin, success=[self.key], corpus=[self.family])
        self.store.discard_corpus(self.family)
        report = self.store.gc(max_bytes=0, max_age=0, dry_run=False)
        self.assertTrue(report['budget_unmet'])
        self.assertGreaterEqual(report['protected_entries'], 4)
        self.assertEqual(self.store.read_blob(second), b'pinned replay input')
        self.assertEqual(self.store.load_success(self.key), self.result)
        self.store.unpin(pin)
        self.store.gc(max_bytes=0, dry_run=False)
        self.assertIsNone(self.store.read_blob(second))
        self.assertIsNone(self.store.load_success(self.key))

    def test_corrupt_manifests_and_pins_fail_closed_before_any_collection(self):
        self.assertTrue(self.publish())
        orphan = self.store.put_blob(b'collectable orphan')
        paths = [self.success_path()]
        self.store.pin(identity('pin'), success=[self.key])
        paths.append(self.root / 'pins' / (identity('pin') + '.json'))
        for path in paths:
            original = path.read_bytes()
            path.write_bytes(b'corrupt')
            with self.assertRaises(RetentionError):
                self.store.gc(max_bytes=0, dry_run=False)
            self.assertEqual(self.store.read_blob(orphan), b'collectable orphan')
            path.write_bytes(original)

    def test_gc_age_filter_and_atomic_leftovers_preserve_permanent_lease_inode(self):
        self.assertTrue(self.publish())
        old = time.time() - 1000
        os.utime(self.success_path(), (old, old))
        temporary = self.root / 'blobs' / ('.' + self.blob + '-crashed')
        temporary.write_bytes(b'uncommitted blob bytes')
        locks = {path: path.stat().st_ino for path in (self.root / 'locks').rglob('*.lock')}
        result = self.store.gc(max_age=500, dry_run=False)
        self.assertFalse(temporary.exists())
        self.assertEqual(result['lock_files'], len(locks))
        self.assertEqual(result['retained_lock_files'], 1)
        self.assertGreater(result['format_bytes'], 0)
        for path, inode in locks.items():
            if path.name == 'retention.lock':
                self.assertEqual(path.stat().st_ino, inode)
            else:
                self.assertFalse(path.exists())
        self.assertIsNone(self.store.load_success(self.key))
        self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')

    def test_gc_inventory_and_metadata_bounds_are_non_destructive(self):
        self.assertTrue(self.publish())
        with self.assertRaises(RetentionError):
            self.store.gc(max_bytes=0, dry_run=False, max_entries=1)
        with patch.object(storage, '_GC_METADATA_MAX_BYTES', 1):
            with self.assertRaises(RetentionError):
                self.store.gc(max_bytes=0, dry_run=False)
        self.assertEqual(self.store.load_success(self.key), self.result)
        for kwargs in ({'max_bytes': -1}, {'max_age': float('nan')}, {'max_entries': 0}, {'dry_run': 1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self.store.gc(**kwargs)

    def test_nested_leases_exclude_gc_until_last_release(self):
        with self.store.lease():
            with self.store.lease():
                self.assertEqual(self.store.read_blob(self.blob), b'concrete corpus case')
                self.assertTrue(Store(self.root).gc(dry_run=False)['skipped_active'])
            self.assertTrue(Store(self.root).gc(dry_run=False)['skipped_active'])
        self.assertFalse(self.store.gc()['skipped_active'])

    def test_live_process_unpublished_input_survives_gc_and_crash_releases_lease(self):
        context = multiprocessing.get_context('fork')
        parent, child = context.Pipe()
        self.addCleanup(parent.close)
        process = self.process(leased_process, self.root, child)
        child.close()
        self.assertTrue(parent.poll(5))
        digest = parent.recv()
        self.assertTrue(self.store.gc(max_bytes=0, dry_run=False)['skipped_active'])
        self.assertEqual(self.store.read_blob(digest), b'active unpublished input')
        process.kill()
        process.join(timeout=5)
        self.assertIsNotNone(process.exitcode)
        self.assertFalse(self.store.gc(max_bytes=0, dry_run=False)['skipped_active'])
        self.assertIsNone(self.store.read_blob(digest))

    def test_other_process_gc_skips_thread_owned_complete_operation(self):
        context = multiprocessing.get_context('fork')
        parent, child = context.Pipe()
        self.addCleanup(parent.close)
        with self.store.coordinator_lock(self.family):
            process = self.process(gc_process, self.root, child)
            child.close()
            self.assertTrue(parent.poll(5))
            self.assertTrue(parent.recv()['skipped_active'])
            process.join(timeout=5)
            self.assertEqual(process.exitcode, 0)

    def test_blocked_per_key_waiter_already_leases_old_inode_before_gc(self):
        with self.store.coordinator_lock(self.family):
            pass
        path = self.root / 'locks/coordinator' / (self.family + '.lock')
        original_inode = path.stat().st_ino
        descriptor = os.open(path, os.O_RDWR | os.O_CLOEXEC)
        self.addCleanup(os.close, descriptor)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        context = multiprocessing.get_context('fork')
        parent, child = context.Pipe()
        self.addCleanup(parent.close)
        process = self.process(waiting_key_process, self.root, self.family, child)
        child.close()
        self.assertTrue(parent.poll(5))
        self.assertEqual(parent.recv(), 'opening-key')
        self.assertTrue(self.store.gc(dry_run=False)['skipped_active'])
        self.assertEqual(path.stat().st_ino, original_inode)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        self.assertTrue(parent.poll(5))
        self.assertEqual(parent.recv(), 'acquired-key')
        self.assertTrue(self.store.gc(dry_run=False)['skipped_active'])
        parent.send('release')
        process.join(timeout=5)
        self.assertEqual(process.exitcode, 0)
        report = self.store.gc(dry_run=False)
        self.assertGreater(report['removed_lock_files'], 0)
        self.assertFalse(path.exists())
        with Store(self.root).coordinator_lock(self.family):
            self.assertTrue(path.is_file())


if __name__ == '__main__':
    unittest.main()
