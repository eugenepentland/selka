#!/usr/bin/env python3
"""Bounded campaign cache tests; no compiler or server admission is needed."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

import fuzz_campaign_store as storage
from fuzz_campaign_store import CorpusError, InputsChanged, Store


def identity(value):
    return hashlib.sha256(value.encode()).hexdigest()


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
        self.assertFalse(self.store.publish_success(self.key, {'passed': 7},
                                                   [self.blob], lambda: True))
        self.assertEqual(self.success_path().read_bytes(), original)
        replies = iter([True, False])
        with self.assertRaises(InputsChanged):
            self.publish(lambda: next(replies))
        self.assertEqual(self.success_path().read_bytes(), original)

    def test_concurrent_publication_first_writer_cas(self):
        start = threading.Barrier(2)

        def publish(count):
            independent = Store(self.root)
            start.wait(timeout=5)
            return independent.publish_success(self.key, {'passed': count}, [], lambda: True)

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(publish, count) for count in (11, 22)]
            outcomes = [future.result(timeout=5) for future in futures]
        self.assertEqual(sum(outcomes), 1)
        self.assertEqual(self.store.load_success(self.key),
                         {'passed': (11, 22)[outcomes.index(True)]})

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


if __name__ == '__main__':
    unittest.main()
