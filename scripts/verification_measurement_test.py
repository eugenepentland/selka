#!/usr/bin/env python3
"""Measurement admission, deadline, cancellation and incomplete-publication checks."""
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import select
import signal
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import verification_measurement as measurement
import verify_cache


class MeasurementWindow(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[1] / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='measurement-test-', dir=scratch)
        self.addCleanup(self.cleanup_fixture)
        self.root = Path(self.temporary.name)
        self.slots = self.root / 'slots'
        self.environment = dict(os.environ, SELKA_SLOT_DIR=str(self.slots),
                                SELKA_SLOT_SETTLE='0', SELKA_SLOT_POLL='1',
                                SELKA_TIMING_MEM='0', SELKA_BUILD_MEM='0', SELKA_GATE_MEM='0')
        for name in measurement.build_admission.MARKERS:
            self.environment.pop(name, None)
        self.patch = patch.dict(os.environ, self.environment, clear=True)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.observer_environment = {
            b'SELKA_SLOT_DIR': os.fsencode(self.slots.resolve()),
            b'SELKA_ADMISSION_PARENT_PID': str(os.getpid()).encode(),
            b'SELKA_ADMISSION_PARENT_START': measurement.build_admission.process_identity().split(':')[-1].encode(),
        }

    def owned_observer(self, entry):
        argv = (entry / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
        script = os.fsencode(Path(measurement.build_admission.__file__).resolve())
        if (len(argv) != 4 or argv[1] != b'-B' or argv[2] != script
                or argv[3] not in (b'--shadow-watch', b'--lease-watch')
                or Path(os.fsdecode(argv[0])).resolve() != Path(sys.executable).resolve()):
            return None
        selected = []
        for item in (entry / 'environ').read_bytes().split(b'\0'):
            name, separator, value = item.partition(b'=')
            if separator and name in self.observer_environment:
                selected.append((name, value))
        if sorted(selected) != sorted(self.observer_environment.items()):
            return None
        return tuple(argv), tuple(sorted(selected))

    def wait_for_observers(self):
        identity = measurement.build_admission.process_identity
        deadline = time.monotonic() + 240
        while True:
            found = False
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    ownership = self.owned_observer(entry)
                    if ownership is None:
                        continue
                    pid = int(entry.name)
                    before = identity(pid)
                    if before is None:
                        continue
                    descriptor = os.pidfd_open(pid)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
                try:
                    if identity(pid) != before or self.owned_observer(entry) != ownership:
                        continue
                    found = True
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, f'private measurement observer still active: {before}')
                    self.assertTrue(select.select([descriptor], [], [], remaining)[0],
                                    f'private measurement observer did not exit: {before}')
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
                finally:
                    os.close(descriptor)
            if not found:
                return

    def cleanup_fixture(self):
        # The reaped timing holder can leave its detached observer finishing
        # SQLite/log writes. Keep this fixture's directory until that writer exits.
        self.wait_for_observers()
        self.temporary.cleanup()

    def assert_released(self):
        for name in ('admit.lock', 'timing1.lock'):
            with (self.slots / name).open('a') as stream:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_real_holder_blocks_peers_and_restores_process_state(self):
        original = os.sched_getaffinity(0)
        previous = signal.getsignal(signal.SIGALRM)
        with measurement.timing_window(60) as window:
            self.assertIs(measurement.current(), window)
            self.assertEqual(window.report()['kind'], 'exclusive-coordinator-request')
            with (self.slots / 'admit.lock').open('a') as stream:
                self.assertRaises(BlockingIOError, fcntl.flock, stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            child_env = measurement.worker_environment({'VALUE': 'retained'})
            self.assertEqual(child_env['VALUE'], 'retained')
            self.assertEqual(child_env['SELKA_ADMISSION_KIND'], 'timing')
        self.assertIsNone(measurement.current())
        self.assertEqual(os.sched_getaffinity(0), original)
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
        self.assert_released()

    def test_ambient_markers_do_not_authorize_bypass(self):
        with patch.dict(os.environ, SELKA_ADMISSION_KIND='timing', SELKA_ADMISSION_DIR=str(self.slots)):
            self.assertIsNone(measurement.current())
            with self.assertRaisesRegex(ValueError, 'outer admission'):
                with measurement.timing_window(1):
                    self.fail('ambient markers granted admission')

    def test_invalid_bounds_and_existing_alarm_rejected_before_admission(self):
        for value in (0, -1, float('inf'), float('nan'), True, '1'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                with measurement.timing_window(value):
                    self.fail('invalid bound admitted')
        signal.setitimer(signal.ITIMER_REAL, 30)
        try:
            with self.assertRaisesRegex(ValueError, 'existing process deadline'):
                with measurement.timing_window(1):
                    self.fail('replaced another deadline')
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)

    def test_deadline_bounds_python_work_and_releases_holder(self):
        with self.assertRaises(measurement.WindowExpired):
            with measurement.timing_window(30):
                self.assertGreater(signal.getitimer(signal.ITIMER_REAL)[0], 0)
                signal.raise_signal(signal.SIGALRM)
        self.assert_released()
        self.assertIsNone(measurement.current())

    def test_cleanup_waits_for_owned_shadow_observer_after_window_release(self):
        self.slots.mkdir()
        log = self.slots / 'scheduler-shadow.jsonl'
        boundary = threading.Event()
        errors = []
        original_select = select.select
        def selecting(*args, **kwargs):
            boundary.set()
            return original_select(*args, **kwargs)
        def cleanup():
            try:
                self.cleanup_fixture()
            except BaseException as error:
                errors.append(error)
            finally:
                boundary.set()
        thread = None
        with log.open('a') as stream, patch.dict(os.environ, SELKA_ADMISSION_BACKEND='shadow'):
            inode = os.fstat(stream.fileno())
            try:
                with measurement.timing_window(120):
                    # Register the observer before blocking its later writes.
                    fcntl.flock(stream, fcntl.LOCK_EX)
                # Wait until the real observer has opened this locked log.
                # Its admission/release writes must outlive the holder.
                deadline = time.monotonic() + 120
                opened = False
                while not opened:
                    for entry in Path('/proc').iterdir():
                        if not entry.name.isdigit():
                            continue
                        try:
                            if self.owned_observer(entry) is None:
                                continue
                            for descriptor in (entry / 'fd').iterdir():
                                observed = descriptor.stat()
                                if (observed.st_dev, observed.st_ino) == (inode.st_dev, inode.st_ino):
                                    opened = True
                                    break
                        except (FileNotFoundError, ProcessLookupError, PermissionError):
                            continue
                    if not opened:
                        self.assertLess(time.monotonic(), deadline, 'shadow observer never opened its log')
                        time.sleep(.01)
                self.assert_released()
                with patch.object(select, 'select', side_effect=selecting):
                    thread = threading.Thread(target=cleanup)
                    thread.start()
                    try:
                        self.assertTrue(boundary.wait(120), 'fixture cleanup never reached its observer wait')
                        self.assertTrue(self.root.exists(), 'fixture was deleted while its shadow observer could still write')
                    finally:
                        fcntl.flock(stream, fcntl.LOCK_UN)
                        thread.join(timeout=120)
                        self.assertFalse(thread.is_alive(), 'fixture cleanup did not finish after observer release')
                if errors:
                    raise errors[0]
                self.assertFalse(self.root.exists())
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)
                if thread is not None:
                    thread.join(timeout=120)
                # Preserve deterministic failing-before cleanup as well: the
                # old fixture can delete and recreate its directory meanwhile.
                self.wait_for_observers()
                self.temporary.cleanup()

    def test_deadline_cannot_be_swallowed_by_advisory_io_error_handler(self):
        with patch.object(verify_cache, 'atomic_record', side_effect=lambda *_: signal.raise_signal(signal.SIGALRM)):
            with self.assertRaises(measurement.WindowExpired):
                with measurement.timing_window(30):
                    verify_cache.diagnostic_record(self.root / 'report.json', {'success': True})
                    self.fail('diagnostic OSError handler swallowed the deadline')
        self.assert_released()

    def test_queue_wait_is_outside_deadline(self):
        original = measurement.build_admission.admission
        clock = [10.0]
        @contextmanager
        def delayed(kind):
            with original(kind) as holder:
                clock[0] = 70.0
                yield holder
        with patch.object(measurement.build_admission, 'admission', delayed), \
                patch.object(measurement, 'time', SimpleNamespace(monotonic=lambda: clock[0])):
            with measurement.timing_window(30) as window:
                self.assertEqual(window.report()['admission_wait_seconds'], 60.0)
                clock[0] = 99.0
                window.check()
                clock[0] = 100.0
                self.assertRaises(measurement.WindowExpired, window.check)
                clock[0] = 70.0
                window.check()

    def test_owned_commands_execute_without_nested_admission_and_expiry_cleans_up(self):
        timings = []
        with measurement.timing_window(60):
            status, _ = verify_cache.run_admitted(
                self.root, 'gate', [sys.executable, '-c', 'print("measured")'],
                dict(os.environ), lambda: True, timings=timings)
        self.assertEqual(status, 0)
        self.assertEqual(timings[0]['admission_scope'], 'request-timing-window')
        pidfile = self.root / 'child.pid'
        # Exercise the real expiry handler only after the owned child is ready.
        # A short startup deadline races scheduler load and can expire before
        # there is a child to clean up. Separate tests cover timer-driven expiry.
        code = ('import os,signal,time\n'
                'with open(%r,"w") as stream: stream.write(str(os.getpid()))\n'
                'os.kill(%d,signal.SIGALRM)\ntime.sleep(30)') % (str(pidfile), os.getpid())
        with self.assertRaises(measurement.WindowExpired):
            with measurement.timing_window(10):
                verify_cache.run_admitted(self.root, 'gate', [sys.executable, '-c', code],
                                          dict(os.environ), lambda: True)
        self.assertTrue(pidfile.exists())
        self.assertFalse(Path('/proc/' + pidfile.read_text()).exists())
        self.assert_released()

    def test_lost_holder_and_forked_capability_fail_closed(self):
        with self.assertRaises((measurement.WindowLost, RuntimeError)):
            with measurement.timing_window(60) as window:
                window.holder.terminate()
                window.holder.wait(timeout=120)
                measurement.current()
        with measurement.timing_window(60) as window:
            with patch.object(measurement.os, 'getpid', return_value=window.pid + 1):
                self.assertRaises(RuntimeError, measurement.current)
        self.assert_released()

    def test_holder_loss_after_report_overwrites_success_and_revokes_receipts(self):
        class Holder:
            status = None
            def poll(self):
                return self.status
        holder = Holder()
        @contextmanager
        def admission(_kind):
            yield holder
        report = self.root / verify_cache.CACHE_DIRECTORY / 'last-run.json'
        receipt = self.root / 'receipt'
        def execute(*_args, **_kwargs):
            verify_cache.atomic_record(report, {'success': True, 'status': 0})
            receipt.write_text('success')
            measurement.current().rollbacks.append(lambda: receipt.unlink(missing_ok=True))
            holder.status = 1
            return 0
        with patch.object(verify_cache, 'ROOT', self.root), patch.object(verify_cache, 'execute', execute), \
                patch.object(measurement.build_admission, 'admission', admission):
            self.assertEqual(verify_cache.main(['--zig', sys.executable, '--timing-window-seconds', '5']), 2)
        self.assertFalse(receipt.exists())
        self.assertFalse(verify_cache.read_record(report)['success'])
        self.assertEqual(verify_cache.read_record(report)['stage'], 'measurement_authority')

    def test_holder_release_failure_revokes_success(self):
        class Holder:
            def poll(self):
                return None
        @contextmanager
        def admission(_kind):
            yield Holder()
            raise measurement.build_admission.AdmissionLost('release failure')
        receipt = self.root / 'receipt'
        with patch.object(measurement.build_admission, 'admission', admission):
            with self.assertRaises(measurement.WindowLost):
                with measurement.timing_window(60) as window:
                    receipt.write_text('success')
                    window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
        self.assertFalse(receipt.exists())

    def test_revocation_failure_still_attempts_every_publication(self):
        receipt = self.root / 'receipt'
        receipt.write_text('success')
        def failed_cleanup():
            raise OSError('injected receipt cleanup failure')
        with self.assertRaises(measurement.WindowLost):
            with measurement.timing_window(60) as window:
                window.rollbacks.extend([lambda: receipt.unlink(missing_ok=True), failed_cleanup])
                raise measurement.WindowExpired('incomplete request')
        self.assertFalse(receipt.exists())
        self.assert_released()

    def test_late_deadline_revokes_published_evidence_but_success_keeps_it(self):
        receipt = self.root / 'published'
        with measurement.timing_window(60) as window:
            receipt.write_text('completed')
            window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
        self.assertEqual(receipt.read_text(), 'completed')
        with self.assertRaises(measurement.WindowExpired):
            with measurement.timing_window(30) as window:
                window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
                signal.raise_signal(signal.SIGALRM)
        self.assertFalse(receipt.exists())
        self.assert_released()


if __name__ == '__main__':
    unittest.main()
