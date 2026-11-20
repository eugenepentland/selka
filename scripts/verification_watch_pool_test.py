"""Real inotify authority boundaries for the process-local shared transport."""
import ctypes
import os
from pathlib import Path
import struct
import select
import signal
import tempfile
import threading
import unittest
from unittest.mock import patch

import verification_watch_pool as pool


MASK = 0x2 | 0x4 | 0x8 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800


class Consumer:
    def __init__(self, case, names=()):
        self.dirty = False
        self.failure = None
        self.events = []
        self.names = set(names)
        library = ctypes.CDLL(None, use_errno=True)
        library.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self.lease = pool.acquire(library, self.event, self.fail)
        case.addCleanup(self.lease.close)

    def event(self, descriptor, mask, name, installing):
        self.events.append((descriptor, mask, name, installing))
        if installing or not name or name in self.names:
            self.dirty = True

    def fail(self, message):
        self.failure = message

    def add(self, path, install=lambda descriptor: descriptor):
        return self.lease.add(path, MASK, install)

    def drain(self):
        self.lease.drain()


class SharedWatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.file = self.root / 'input'
        self.file.write_text('old')

    def test_ten_consumers_hold_one_kernel_watch_with_independent_lifetimes(self):
        clients = [Consumer(self) for _ in range(10)]
        for client in clients:
            client.add(self.file)
            client.drain()
        self.assertEqual(len({client.lease.fd for client in clients}), 1)
        info = Path(f'/proc/self/fdinfo/{clients[0].lease.fd}').read_text()
        self.assertEqual(sum(line.startswith('inotify wd:') for line in info.splitlines()), 1)
        clients[0].lease.close()
        self.file.write_text('changed')
        clients[-1].drain()
        self.assertTrue(all(client.dirty for client in clients[1:]))
        self.assertFalse(clients[0].dirty)

    def test_selectors_stay_independent_and_may_change(self):
        first, second = Consumer(self, [b'a']), Consumer(self, [b'b'])
        first.add(self.root)
        second.add(self.root)
        first.drain()
        second.drain()
        (self.root / 'a').touch()
        second.drain()
        self.assertTrue(first.dirty)
        self.assertFalse(second.dirty)
        second.names = {b'c'}
        (self.root / 'c').touch()
        first.drain()
        self.assertTrue(second.dirty)

    def test_late_subscriber_does_not_rebase_earlier_subscriber(self):
        first = Consumer(self)
        first.add(self.file)
        first.drain()
        self.file.write_text('changed')
        late = Consumer(self)
        late.add(self.file)
        late.drain()
        self.assertTrue(first.dirty)
        self.assertFalse(late.dirty)

    def test_mutation_during_selector_installation_is_retained(self):
        client = Consumer(self, [b'new'])
        def install(descriptor):
            (self.root / 'new').touch()
            return descriptor
        client.add(self.root, install)
        client.drain()
        self.assertTrue(client.dirty)

    def test_deferred_events_use_completed_selectors_and_ignore_other_paths(self):
        client, drainer = Consumer(self), Consumer(self)
        client.add(self.root)
        drainer.add(self.file)
        (self.root / 'relevant').touch()
        drainer.drain()
        self.assertFalse(client.dirty)
        client.names.add(b'relevant')
        client.drain()
        self.assertTrue(client.dirty)
        other = Consumer(self, [b'selected'])
        other.add(self.root)
        (self.root / 'unrelated').touch()
        drainer.drain()
        other.drain()
        self.assertFalse(other.dirty)

    def test_deferred_overflow_revokes_consumer(self):
        client, drainer = Consumer(self), Consumer(self)
        client.add(self.root)
        drainer.add(self.file)
        with patch.object(pool, '_MAX_DEFERRED', 1):
            (self.root / 'one').touch()
            (self.root / 'two').touch()
            drainer.drain()
        self.assertIn('deferred event bound', client.failure)
        with self.assertRaisesRegex(pool.WatchPoolError, 'deferred event bound'):
            client.drain()

    def test_hardlink_aba_reaches_all_subscribers(self):
        link = self.root / 'alias'
        os.link(self.file, link)
        first, second = Consumer(self), Consumer(self)
        self.assertEqual(first.add(self.file), second.add(link))
        first.drain()
        second.drain()
        link.write_text('new')
        link.write_text('old')
        first.drain()
        self.assertTrue(first.dirty and second.dirty)

    def test_later_watch_cannot_remove_an_earlier_event_mask(self):
        first, second = Consumer(self), Consumer(self)
        first.lease.add(self.file, 0x2, lambda descriptor: descriptor)
        first.drain()
        second.lease.add(self.file, 0x4, lambda descriptor: descriptor)
        second.drain()
        self.file.write_text('changed')
        first.drain()
        self.assertTrue(first.dirty)

    def test_retired_ignored_event_does_not_poison_survivor_or_next_add(self):
        first, survivor = Consumer(self), Consumer(self)
        first.add(self.file)
        survivor.add(self.root)
        first.drain()
        survivor.drain()
        first.lease.close()
        replacement = Consumer(self)
        replacement.add(self.file)
        replacement.drain()
        survivor.drain()
        self.assertFalse(survivor.dirty or replacement.dirty)
        self.assertFalse(replacement.failure or survivor.failure)
        self.file.write_text('new')
        replacement.drain()
        self.assertTrue(replacement.dirty)

    def test_overflow_revokes_every_consumer_and_new_transport_is_distinct(self):
        first, second = Consumer(self), Consumer(self)
        first.add(self.file)
        second.add(self.file)
        overflow = struct.pack('iIII', -1, 0x4000, 0, 0)
        with patch.object(pool.os, 'read', return_value=overflow):
            with self.assertRaisesRegex(pool.WatchPoolError, 'overflow'):
                first.drain()
        self.assertIn('overflow', first.failure)
        self.assertIn('overflow', second.failure)
        replacement = Consumer(self)
        self.assertNotEqual(replacement.lease.fd, first.lease.fd)
        replacement.add(self.file)
        replacement.drain()
        with self.assertRaisesRegex(pool.WatchPoolError, 'overflow'):
            second.drain()

    def test_read_error_and_unknown_descriptor_fail_closed(self):
        for event in (OSError('read lost'), struct.pack('iIII', 987654, 2, 0, 0)):
            with self.subTest(event=repr(event)):
                client = Consumer(self)
                client.add(self.file)
                kwargs = {'side_effect': event} if isinstance(event, Exception) else {'return_value': event}
                with patch.object(pool.os, 'read', **kwargs):
                    with self.assertRaises(pool.WatchPoolError):
                        client.drain()
                self.assertIsNotNone(client.failure)
                client.lease.close()

    def test_revoked_borrower_close_cannot_close_fresh_transport(self):
        old = Consumer(self)
        old.add(self.file)
        with patch.object(pool.os, 'read', side_effect=OSError('lost queue')):
            with self.assertRaises(pool.WatchPoolError):
                old.drain()
        fresh = Consumer(self)
        fresh.add(self.file)
        fresh.drain()
        old.lease.close()
        self.file.write_text('changed')
        fresh.drain()
        self.assertTrue(fresh.dirty)

    def test_interrupted_fanout_revokes_all_consumers_before_reraising(self):
        first, second = Consumer(self), Consumer(self)
        first.add(self.file)
        second.add(self.file)
        first.drain()
        second.drain()
        self.file.write_text('changed')
        with patch.object(first.lease, 'event', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                second.drain()
        for client in (first, second):
            self.assertIn('delivery interrupted', client.failure)
            with self.assertRaisesRegex(pool.WatchPoolError, 'delivery interrupted'):
                client.drain()

    def test_interrupted_deferred_delivery_revokes_its_consumer(self):
        first, drainer = Consumer(self), Consumer(self)
        first.add(self.file)
        drainer.add(self.root)
        drainer.drain()
        self.file.write_text('changed')
        drainer.drain()
        with patch.object(first.lease, 'event', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                first.drain()
        self.assertIn('deferred delivery interrupted', first.failure)
        with self.assertRaisesRegex(pool.WatchPoolError, 'deferred delivery interrupted'):
            first.drain()
        self.assertIsNone(drainer.failure)

    def test_interrupted_installation_releases_lease_without_harming_peer(self):
        first, peer = Consumer(self), Consumer(self)
        peer.add(self.root)
        peer.drain()
        def interrupted(descriptor):
            raise KeyboardInterrupt
        with self.assertRaises(KeyboardInterrupt):
            first.add(self.file, interrupted)
        self.assertTrue(first.lease.closed)
        peer.names.add(b'input')
        self.file.write_text('changed')
        peer.drain()
        self.assertTrue(peer.dirty)

    def test_fork_cannot_drain_or_remove_parent_authority(self):
        client = Consumer(self)
        client.add(self.file)
        client.drain()
        child = os.fork()
        if child == 0:
            try:
                try:
                    client.drain()
                except pool.WatchPoolError:
                    client.lease.close()
                    os._exit(0)
                os._exit(1)
            except BaseException:
                os._exit(2)
        self.assertEqual(os.waitpid(child, 0)[1], 0)
        self.file.write_text('changed')
        client.drain()
        self.assertTrue(client.dirty)

    def test_fork_rejects_authority_without_waiting_on_inherited_locks(self):
        client = Consumer(self)
        client.add(self.file)
        client.drain()
        held, release = threading.Event(), threading.Event()
        def hold():
            with pool._global_lock, client.lease.pool.lock:
                held.set()
                release.wait(15)
        thread = threading.Thread(target=hold)
        thread.start()
        self.assertTrue(held.wait(5))
        read_fd, write_fd = os.pipe()
        child = os.fork()
        if child == 0:
            try:
                os.close(read_fd)
                try:
                    client.drain()
                except pool.WatchPoolError:
                    client.lease.close()
                    fresh = Consumer(self)
                    fresh.add(self.file)
                    fresh.drain()
                    fresh.lease.close()
                    os.write(write_fd, b'R')
                    os._exit(0)
                os._exit(1)
            except BaseException:
                os._exit(2)
        os.close(write_fd)
        try:
            self.assertTrue(select.select([read_fd], [], [], 5)[0], 'fork waited on inherited lock')
            self.assertEqual(os.read(read_fd, 1), b'R')
            self.assertEqual(os.waitpid(child, 0)[1], 0)
        finally:
            release.set()
            thread.join(5)
            os.close(read_fd)
            try:
                os.kill(child, signal.SIGKILL)
                os.waitpid(child, 0)
            except ProcessLookupError:
                pass


if __name__ == '__main__':
    unittest.main()
