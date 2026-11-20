#!/usr/bin/env python3
"""Keep retained mutation authority live throughout long admitted commands."""
import fcntl
import os
from pathlib import Path
import struct
import sys
import textwrap
import threading
import time
import unittest
from unittest.mock import patch

import verify_cache as coordinator
import verify_cache_test as fixtures
from verification_snapshot import Snapshot, SnapshotError

# Paced churn. The child writes one batch of at most a sixteenth of the kernel queue, then waits
# for a heartbeat that began after the batch. Two undrained batches stay below the queue bound,
# so the result no longer depends on how promptly the parent's heartbeat is scheduled under load.
# Only the undrained test and the injected-overflow test below overflow the queue on purpose.
PACED_LOOP = '''def acknowledged():
    while True:
        try:
            return int(ack.read_text())
        except FileNotFoundError:
            return 0
        except ValueError:
            time.sleep(0.001)
deadline = time.monotonic() + 60
for start in range(0, cycles, per_batch):
    for _ in range(min(per_batch, cycles - start)):
        noise.write_bytes(b'x')
        noise.unlink()
    seen = acknowledged()
    while acknowledged() <= seen:
        if time.monotonic() > deadline:
            raise SystemExit('heartbeat did not drain the churn')
        time.sleep(0.001)
'''
PACED_CHILD = '''from pathlib import Path
import sys,time
source=Path(sys.argv[1]); noise=source.parent/'unselected-output'; ack=Path(sys.argv[2])/'.heartbeat-ack'
cycles=int(sys.argv[3]); per_batch=int(sys.argv[4]); mode=sys.argv[5]
''' + PACED_LOOP + '''if mode:
    original=source.read_bytes(); source.write_bytes(b'changed')
    if mode=='aba': source.write_bytes(original)
    time.sleep(30)
'''
IN_Q_OVERFLOW = 0x4000


class OwnershipWatchHeartbeat(fixtures.VerificationCoordinator):
    def private_environment(self):
        return dict(os.environ, SELKA_SLOT_DIR=str(self.root / '.heartbeat-slots'),
                    SELKA_GATE_SLOTS='1', SELKA_GATE_MEM='0',
                    SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0', SELKA_TIMING_CPUS='')

    def cycles(self):
        limit = int(Path('/proc/sys/fs/inotify/max_queued_events').read_text())
        if limit > 65536:
            self.skipTest('private overflow control is bounded to 65536 kernel events')
        return limit // 4 + 1024

    def churn(self, after_batch=None):
        noise = self.input.parent / 'unselected-output'
        cycles = self.cycles()
        limit = int(Path('/proc/sys/fs/inotify/max_queued_events').read_text())
        # A create/write/close/unlink emits four events. Queued tests leave
        # room for scheduling delays, then require the real heartbeat to drain
        # each batch; the overflow control still emits one unpaced burst.
        batch = cycles if after_batch is None else max(1, limit // 16)
        batches = 0
        for start in range(0, cycles, batch):
            for _ in range(min(batch, cycles - start)):
                noise.write_bytes(b'x')
                noise.unlink()
            batches += 1
            if after_batch is not None:
                after_batch(batches)
        return batches

    def batch(self):
        """Cycles per paced batch: a sixteenth of the queue, so two undrained batches never overflow it."""
        return max(1, int(Path('/proc/sys/fs/inotify/max_queued_events').read_text()) // 16)

    def acknowledger(self):
        """A heartbeat that publishes one count per drain, atomically, for the paced child to await."""
        ack = self.root / '.heartbeat-ack'
        ack.write_text('0')
        count = 0
        def acknowledge():
            nonlocal count
            count += 1
            temporary = self.root / '.heartbeat-ack.tmp'
            temporary.write_text(str(count))
            os.replace(temporary, ack)
        return acknowledge

    def command(self, mutation=''):
        return [sys.executable, '-c', PACED_CHILD, str(self.input), str(self.root),
                str(self.cycles()), str(self.batch()), mutation]

    def test_undrained_ignored_sibling_churn_really_overflows_and_revokes_both_borrowers(self):
        with Snapshot(self.root, [], [self.input]) as first, Snapshot(self.root, [], [self.input]) as second:
            self.churn()
            for snapshot in (first, second):
                with self.assertRaisesRegex(SnapshotError, 'queue overflow'):
                    snapshot.events_unchanged()

    def test_injected_overflow_event_revokes_both_borrowers_without_churn(self):
        """The fail-closed path itself, deterministically: an overflow the kernel never had to queue."""
        with Snapshot(self.root, [], [self.input]) as first, Snapshot(self.root, [], [self.input]) as second:
            descriptor = first._watcher.fd
            read = os.read
            injected = []
            def overflow_once(fd, size):
                if fd == descriptor and not injected:
                    injected.append(fd)
                    return struct.pack('iIII', -1, IN_Q_OVERFLOW, 0, 0)
                return read(fd, size)
            with patch.object(os, 'read', overflow_once):
                for snapshot in (first, second):
                    with self.assertRaisesRegex(SnapshotError, 'queue overflow'):
                        snapshot.events_unchanged()
            self.assertEqual(injected, [descriptor])
            for snapshot in (first, second):
                with self.assertRaisesRegex(SnapshotError, 'queue overflow'):
                    snapshot.unchanged()

    def exercise_worker(self, publication):
        with Snapshot(self.root, [], [self.input]) as first, Snapshot(self.root, [], [self.input]) as second:
            finalized = []
            def finalize(status, authority):
                self.assertTrue(authority())
                self.assertTrue(first.unchanged() and second.unchanged())
                finalized.append(status)
                return status
            acknowledge = self.acknowledger()
            def heartbeat():
                acknowledge()
                coordinator.drain_events([first, second])
            result = fixtures.REAL_ADMISSION(
                self.root, 'gate', self.command(), self.private_environment(),
                lambda: first.unchanged() and second.unchanged(),
                heartbeat=heartbeat,
                finalize=finalize if publication else None)
            self.assertEqual(result[0], 0)
            self.assertEqual(finalized, [0] if publication else [])
            self.assertTrue(first.unchanged() and second.unchanged())

    def test_completion_handshake_drains_churn_before_original_publication_proof(self):
        self.exercise_worker(True)

    def test_nonpublication_worker_wait_also_drains_churn(self):
        self.exercise_worker(False)

    def test_coordinator_wires_heartbeat_and_publishes_only_the_stable_request(self):
        acknowledge = self.acknowledger()
        original_drain = coordinator.drain_events
        def acknowledged_drain(snapshots):
            acknowledge()
            original_drain(snapshots)
        header = ("from pathlib import Path\nimport time\n"
                  f"noise=root/'.heartbeat-noise'; ack=Path({str(self.root / '.heartbeat-ack')!r})\n"
                  f"cycles={self.cycles()}; per_batch={self.batch()}\n")
        with self.zig.open('a') as script:
            script.write("\nif phase=='gate':\n" + textwrap.indent(header + PACED_LOOP, '    '))
        with patch.dict(os.environ, self.private_environment()), \
                patch.object(coordinator, 'run_admitted', fixtures.REAL_ADMISSION), \
                patch.object(coordinator, 'drain_events', acknowledged_drain):
            self.assertEqual(self.execute(), 0)
            self.assertEqual(len(self.receipts()), 2)
            self.assertTrue(all(coordinator.valid_receipt(path, path.stem) for path in self.receipts()))
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})

    def test_worker_mutation_and_aba_abort_without_publishing_or_rebasing(self):
        for mutation in ('change', 'aba'):
            for publication in (False, True):
                with self.subTest(mutation=mutation, publication=publication):
                    self.input.write_text('original')
                    acknowledge = self.acknowledger()
                    with Snapshot(self.root, [], [self.input]) as snapshot:
                        finalized = []
                        def heartbeat():
                            acknowledge()
                            coordinator.drain_events([snapshot])
                        with self.assertRaisesRegex(SnapshotError, 'inputs changed'):
                            fixtures.REAL_ADMISSION(
                                self.root, 'gate', self.command(mutation), self.private_environment(),
                                snapshot.unchanged,
                                heartbeat=heartbeat,
                                finalize=(lambda status, authority: finalized.append(status)) if publication else None)
                        self.assertEqual(finalized, [])
                        self.assertFalse(snapshot.events_unchanged())
                        self.assertFalse(snapshot.unchanged())

    def exercise_queue(self, mutate):
        environment = self.private_environment()
        slots = Path(environment['SELKA_SLOT_DIR'])
        slots.mkdir(exist_ok=True)
        marker = self.root / '.heartbeat-worker-started'
        command = [sys.executable, '-c', 'from pathlib import Path; import sys; Path(sys.argv[1]).touch()', str(marker)]
        results, errors = [], []
        drained = threading.Condition()
        requested_batch = acknowledged_batch = 0
        with (slots / 'gate1.lock').open('w') as lock, Snapshot(self.root, [], [self.input]) as snapshot:
            fcntl.flock(lock, fcntl.LOCK_EX)
            def heartbeat():
                nonlocal acknowledged_batch
                with drained:
                    batch = requested_batch
                coordinator.drain_events([snapshot])
                with drained:
                    acknowledged_batch = max(acknowledged_batch, batch)
                    drained.notify_all()
            def admitted():
                try:
                    results.append(fixtures.REAL_ADMISSION(
                        self.root, 'gate', command, environment, snapshot.unchanged,
                        heartbeat=heartbeat))
                except BaseException as error:
                    errors.append(error)
            thread = threading.Thread(target=admitted, daemon=True)
            thread.start()
            def await_drain(batch):
                nonlocal requested_batch
                with drained:
                    requested_batch = batch
                    self.assertTrue(drained.wait_for(lambda: acknowledged_batch >= batch, timeout=60),
                                    'queued heartbeat did not drain churn batch')
                self.assertTrue(thread.is_alive(), errors)
                self.assertEqual(errors, [])
                self.assertEqual(results, [])
                self.assertFalse(marker.exists())
                self.assertTrue(list((slots / 'queue-gate').glob('*.wait')),
                                'private request stopped queueing during churn')
            deadline = time.monotonic() + 60
            try:
                while not list((slots / 'queue-gate').glob('*.wait')):
                    self.assertLess(time.monotonic(), deadline, 'private request did not queue')
                    self.assertTrue(thread.is_alive(), errors)
                    time.sleep(.01)
                batches = self.churn(await_drain)
                self.assertGreater(batches, 1)
                self.assertEqual(acknowledged_batch, batches)
                self.assertGreater(self.cycles() * 4,
                                   int(Path('/proc/sys/fs/inotify/max_queued_events').read_text()))
                if mutate:
                    original = self.input.read_bytes()
                    self.input.write_bytes(b'transient')
                    self.input.write_bytes(original)
                    thread.join(timeout=60)
                    self.assertFalse(thread.is_alive(), 'queued mutation was not observed')
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
                thread.join(timeout=60)
            self.assertFalse(thread.is_alive(), 'private admission did not finish')
            if mutate:
                self.assertEqual(results, [])
                self.assertEqual(len(errors), 1)
                self.assertIsInstance(errors[0], SnapshotError)
                self.assertFalse(marker.exists())
                self.assertFalse(snapshot.unchanged())
            else:
                self.assertEqual(errors, [])
                self.assertEqual(results[0][0], 0)
                self.assertTrue(marker.exists())
                self.assertTrue(snapshot.unchanged())

    def test_queued_request_drains_ignored_churn_before_admission(self):
        self.exercise_queue(False)

    def test_queued_aba_never_starts_the_worker(self):
        self.exercise_queue(True)


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(OwnershipWatchHeartbeat(name) for name in
                              sorted(OwnershipWatchHeartbeat.__dict__) if name.startswith('test_'))


if __name__ == '__main__':
    unittest.main()
