#!/usr/bin/env python3
"""Independent candidate review; every fixture stays in the reviewer's tree."""
import hashlib
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / 'scripts'))


def candidate(name, variable):
    path = Path(os.environ.get(variable, ROOT / 'scripts')) / (name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


storage = candidate('fuzz_campaign_store', 'F10_STORE_SCRIPTS')
snapshot_module = candidate('verification_snapshot', 'F10_SNAPSHOT_SCRIPTS')
Snapshot, DigestSession = snapshot_module.Snapshot, snapshot_module.DigestSession


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def stage_and_wait(root, channel):
    store = storage.Store(Path(root))
    entries = [(digest(str(i)), {'passed': i}, [], digest('generation' + str(i)))
               for i in range(5)]
    commit = digest('never committed')
    def stage(key):
        if key == entries[3][0]:
            channel.send('three staged')
            channel.recv()
    store.publish_success_batch(entries, lambda: True, commit, guard=lambda: True, stage=stage)


class IndependentReuseReview(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / '.tmp' / 'f10-review'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.input = self.root / 'input'
        self.input.write_bytes(b'original')
        self.record = self.root / '.digest' / 'record'
        self.store = storage.Store(self.root / '.store')
        self.entries = [(digest(str(i)), {'passed': i}, [], digest('generation' + str(i)))
                        for i in range(5)]
        self.commit_bytes = b'unpredictable fixture commit ' + os.urandom(32)
        self.commit = hashlib.sha256(self.commit_bytes).hexdigest()

    def session(self):
        return DigestSession(root=self.root, record_path=self.record)

    def assert_misses(self):
        for key, _, _, _ in self.entries:
            self.assertIsNone(self.store.load_success(key))

    def test_real_snapshot_batch_has_two_full_scans_and_no_early_visibility(self):
        validations = []
        with Snapshot(self.root, ['input']) as snapshot:
            def validate():
                validations.append(True)
                return snapshot.unchanged()
            def stage(_key):
                self.assert_misses()
            before = snapshot.statistics['validation_calls']
            self.assertTrue(self.store.publish_success_batch(
                self.entries, validate, self.commit, guard=snapshot.events_unchanged, stage=stage))
            self.assertEqual(len(validations), 2)
            self.assertEqual(snapshot.statistics['validation_calls'] - before, 2)
            self.assert_misses()
            self.assertTrue(snapshot.events_unchanged())
            self.store.put_blob(self.commit_bytes)
            self.assertTrue(snapshot.events_unchanged())
            for key, result, _, _ in self.entries:
                self.assertEqual(self.store.load_success(key), result)

    def test_real_hardlink_aba_between_batch_entries_cannot_be_committed(self):
        alias = self.root / '.alias'
        os.link(self.input, alias)
        with Snapshot(self.root, ['input']) as snapshot:
            def stage(key):
                if key == self.entries[2][0]:
                    stamp = alias.stat()
                    alias.write_bytes(b'mutation')
                    alias.write_bytes(b'original')
                    os.utime(alias, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaises(storage.InputsChanged):
                self.store.publish_success_batch(self.entries, snapshot.unchanged, self.commit,
                                                guard=snapshot.events_unchanged, stage=stage)
            self.assertFalse(snapshot.events_unchanged())
        # Even an erroneously late marker cannot resurrect aborted generations.
        self.store.put_blob(self.commit_bytes)
        self.assert_misses()

    def test_sigkill_after_partial_staging_leaves_no_visible_receipt(self):
        context = multiprocessing.get_context('spawn')
        parent, child = context.Pipe()
        process = context.Process(target=stage_and_wait, args=(str(self.store.root), child))
        process.start()
        child.close()
        try:
            self.assertTrue(parent.poll(15), 'child did not reach partial publication')
            self.assertEqual(parent.recv(), 'three staged')
            self.assertEqual(len(list((self.store.root / 'success').glob('*.json'))), 3)
            process.kill()
            process.join(15)
            self.assertEqual(process.exitcode, -signal.SIGKILL)
            self.assert_misses()
        finally:
            if process.is_alive():
                process.kill()
                process.join(15)
            parent.close()

    def test_marker_revocation_preserves_independent_later_peer_batch(self):
        self.assertTrue(self.store.publish_success_batch(self.entries, lambda: True, self.commit,
                                                        guard=lambda: True))
        self.store.put_blob(self.commit_bytes)
        peer_bytes = b'peer batch ' + os.urandom(32)
        peer_commit = hashlib.sha256(peer_bytes).hexdigest()
        key, result, blobs, _ = self.entries[0]
        peer = storage.Store(self.store.root)
        self.assertTrue(peer.publish_success_batch([(key, result, blobs, digest('peer'))],
                                                    lambda: True, peer_commit, guard=lambda: True))
        peer.put_blob(peer_bytes)
        self.store.revoke_success_batch(self.commit)
        for action, _, _, generation in self.entries:
            self.store.invalidate_success(action, publication=generation)
        self.assertEqual(peer.load_success(key), result)
        for action, _, _, _ in self.entries[1:]:
            self.assertIsNone(peer.load_success(action))

    def test_old_digest_writer_cannot_overwrite_new_bytes_with_a_stale_hit(self):
        # Exercise real disk timestamps and separate sessions, with an older
        # session committing its index after the newer session has finished.
        if snapshot_module._timestamp_granularity_ns(self.input) is None:
            self.skipTest('persistent reuse unavailable on this filesystem')
        time.sleep(2.05)
        old = self.session()
        with Snapshot(self.root, ['input'], digest_session=old):
            pass
        stamp = self.input.stat()
        self.input.write_bytes(b'mutation')
        os.utime(self.input, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        with self.session() as newer:
            with Snapshot(self.root, ['input'], digest_session=newer):
                pass
        old.__exit__(None, None, None)
        with self.session() as reader:
            with Snapshot(self.root, ['input'], digest_session=reader) as actual:
                self.assertEqual(actual.statistics['files_hashed'], 1)
                self.assertEqual(actual.statistics['digest_reuses'], 0)
                self.assertEqual(actual.identity['files'][0]['sha256'], hashlib.sha256(b'mutation').hexdigest())

    def test_digest_record_symlinks_cannot_redirect_writes(self):
        target = self.root / 'valuable-input'
        target.write_bytes(b'preserve this input')
        self.record.parent.mkdir()
        self.record.symlink_to(target)
        with self.session() as session:
            with Snapshot(self.root, ['input'], digest_session=session):
                pass
        self.assertEqual(target.read_bytes(), b'preserve this input')
        self.record.unlink(missing_ok=True)
        self.record.parent.rmdir()
        directory_target = self.root / 'valuable-directory'
        directory_target.mkdir()
        self.record.parent.symlink_to(directory_target, target_is_directory=True)
        with self.session() as session:
            with Snapshot(self.root, ['input'], digest_session=session):
                pass
        self.assertEqual(list(directory_target.iterdir()), [])

    def test_digest_record_parent_replacement_cannot_redirect_saved_index(self):
        self.record.parent.mkdir()
        target = self.root / 'valuable-directory'
        target.mkdir()
        with self.session() as session:
            with Snapshot(self.root, ['input'], digest_session=session):
                pass
            self.record.parent.rename(self.root / '.old-record-directory')
            self.record.parent.symlink_to(target, target_is_directory=True)
        self.assertEqual(list(target.iterdir()), [])

    def test_persistent_reuse_retains_live_publication_authority(self):
        if snapshot_module._timestamp_granularity_ns(self.input) is None:
            self.skipTest('persistent reuse unavailable on this filesystem')
        time.sleep(2.05)
        with self.session() as session:
            with Snapshot(self.root, ['input'], digest_session=session):
                pass
        with self.session() as session:
            with Snapshot(self.root, ['input'], digest_session=session) as snapshot:
                self.assertEqual(snapshot.statistics['files_hashed'], 0)
                self.assertEqual(snapshot.statistics['digest_reuses'], 1)
                count = 0
                def validate():
                    nonlocal count
                    count += 1
                    stable = snapshot.unchanged()
                    if count == 2:
                        self.input.write_bytes(b'mutation')
                        self.input.write_bytes(b'original')
                    return stable
                self.assertTrue(self.store.publish_success_batch(self.entries, validate, self.commit,
                                                                guard=snapshot.events_unchanged))
                # The caller's required post-validation event guard revokes
                # authority before making the batch marker visible.
                self.assertFalse(snapshot.events_unchanged())
                self.assert_misses()


if __name__ == '__main__':
    unittest.main()
