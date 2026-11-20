#!/usr/bin/env python3
"""Independent real Snapshot tests over the process-local watch transport."""
from contextlib import ExitStack
import importlib.util
import os
from pathlib import Path
import signal
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(os.environ.get('F10_POOL_SCRIPTS', ROOT / 'scripts')), str(ROOT / 'scripts')]
path = Path(os.environ.get('F10_SNAPSHOT_SCRIPTS', ROOT / 'scripts')) / 'verification_snapshot.py'
spec = importlib.util.spec_from_file_location('verification_snapshot', path)
snapshot = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = snapshot
spec.loader.exec_module(snapshot)
import verification_watch_pool as pool


class WatchPoolReview(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / '.tmp/f10-watch-pool'
        scratch.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ('a', 'b'):
            (self.root / name).write_bytes(b'original')
        self.stack = self.enterContext(ExitStack())

    def capture(self, name='a'):
        return self.stack.enter_context(snapshot.Snapshot(self.root, [name]))

    def aba(self, name='a'):
        path = self.root / name
        stamp = path.stat()
        path.write_bytes(b'mutation')
        path.write_bytes(b'original')
        os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))

    def test_independent_selectors_and_close_keep_all_live_aba_history(self):
        first, unrelated, peer = self.capture(), self.capture('b'), self.capture()
        self.assertEqual(len({item._watcher.fd for item in (first, unrelated, peer)}), 1)
        first.close()
        self.aba()
        self.assertTrue(unrelated.events_unchanged())
        self.assertFalse(peer.events_unchanged())
        self.assertFalse(peer.unchanged())
        self.assertTrue(unrelated.unchanged())

    def test_new_snapshot_cannot_rebase_earlier_snapshot(self):
        old = self.capture()
        self.aba()
        new = self.capture()
        self.assertTrue(new.events_unchanged())
        self.assertFalse(old.events_unchanged())
        self.aba()
        self.assertFalse(new.events_unchanged())

    def test_overflow_revokes_all_and_old_close_cannot_poison_replacement(self):
        old, peer = self.capture(), self.capture('b')
        overflow = struct.pack('iIII', -1, 0x4000, 0, 0)
        with patch.object(pool.os, 'read', return_value=overflow):
            with self.assertRaisesRegex(snapshot.SnapshotError, 'overflow'):
                old.events_unchanged()
        with self.assertRaises(snapshot.SnapshotError):
            peer.events_unchanged()
        new = self.capture()
        old.close()
        peer.close()
        self.assertTrue(new.events_unchanged())
        self.aba()
        self.assertFalse(new.events_unchanged())

    def test_interrupted_delivery_never_leaves_peer_authority_reusable(self):
        first, peer = self.capture(), self.capture()
        lease = next(client for client in pool._current.clients
                     if getattr(client.event, '__self__', None) is first._watcher)
        self.aba()
        with patch.object(lease, 'event', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                peer.events_unchanged()
        for item in (first, peer):
            with self.assertRaises(snapshot.SnapshotError):
                item.events_unchanged()

    def test_interrupted_construction_releases_only_its_borrower(self):
        survivor = self.capture()
        borrowers = len(pool._current.clients)
        with patch.object(snapshot.Snapshot, '_hash_file', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                snapshot.Snapshot(self.root, ['b']).__enter__()
        self.assertEqual(len(pool._current.clients), borrowers)
        self.assertTrue(survivor.events_unchanged())
        self.aba()
        self.assertFalse(survivor.events_unchanged())

    def test_fork_while_pool_lock_held_refuses_without_hanging_or_revoking_parent(self):
        original = self.capture()
        locked, release = threading.Event(), threading.Event()
        def hold():
            with pool._current.lock:
                locked.set()
                release.wait(15)
        holder = threading.Thread(target=hold)
        holder.start()
        self.assertTrue(locked.wait(5))
        read, write = os.pipe()
        child = os.fork()
        if child == 0:
            os.close(read)
            try:
                try:
                    original.events_unchanged()
                except snapshot.SnapshotError:
                    os.write(write, b'refused')
                    os._exit(0)
                os._exit(2)
            finally:
                os._exit(3)
        os.close(write)
        try:
            deadline = time.monotonic() + 60
            result = None
            while time.monotonic() < deadline:
                pid, status = os.waitpid(child, os.WNOHANG)
                if pid:
                    result = status
                    break
                time.sleep(.01)
            if result is None:
                os.kill(child, signal.SIGKILL)
                os.waitpid(child, 0)
                self.fail('forked snapshot waited on an inherited pool lock')
            self.assertEqual(os.waitstatus_to_exitcode(result), 0)
            self.assertEqual(os.read(read, 32), b'refused')
        finally:
            os.close(read)
            release.set()
            holder.join(5)
        self.assertTrue(original.events_unchanged())
        self.aba()
        self.assertFalse(original.events_unchanged())


if __name__ == '__main__':
    unittest.main()
