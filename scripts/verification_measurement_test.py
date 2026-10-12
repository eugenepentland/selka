#!/usr/bin/env python3
"""Measurement admission, deadline, cancellation and incomplete-publication checks."""
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import verification_measurement as measurement
import verify_cache


class MeasurementWindow(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[1] / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='measurement-test-', dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.slots = self.root / 'slots'
        self.environment = dict(os.environ, MYLANG_SLOT_DIR=str(self.slots),
                                MYLANG_SLOT_SETTLE='0', MYLANG_SLOT_POLL='1',
                                MYLANG_TIMING_MEM='0', MYLANG_BUILD_MEM='0', MYLANG_GATE_MEM='0')
        for name in measurement.build_admission.MARKERS:
            self.environment.pop(name, None)
        self.patch = patch.dict(os.environ, self.environment, clear=True)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def assert_released(self):
        for name in ('admit.lock', 'timing1.lock'):
            with (self.slots / name).open('a') as stream:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_real_holder_blocks_peers_and_restores_process_state(self):
        original = os.sched_getaffinity(0)
        previous = signal.getsignal(signal.SIGALRM)
        with measurement.timing_window(5) as window:
            self.assertIs(measurement.current(), window)
            self.assertEqual(window.report()['kind'], 'exclusive-coordinator-request')
            with (self.slots / 'admit.lock').open('a') as stream:
                self.assertRaises(BlockingIOError, fcntl.flock, stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            child_env = measurement.worker_environment({'VALUE': 'retained'})
            self.assertEqual(child_env['VALUE'], 'retained')
            self.assertEqual(child_env['MYLANG_ADMISSION_KIND'], 'timing')
        self.assertIsNone(measurement.current())
        self.assertEqual(os.sched_getaffinity(0), original)
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
        self.assert_released()

    def test_ambient_markers_do_not_authorize_bypass(self):
        with patch.dict(os.environ, MYLANG_ADMISSION_KIND='timing', MYLANG_ADMISSION_DIR=str(self.slots)):
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
            with measurement.timing_window(.05):
                time.sleep(5)
        self.assert_released()
        self.assertIsNone(measurement.current())

    def test_deadline_cannot_be_swallowed_by_advisory_io_error_handler(self):
        started = time.monotonic()
        with patch.object(verify_cache, 'atomic_record', side_effect=lambda *_: time.sleep(5)):
            with self.assertRaises(measurement.WindowExpired):
                with measurement.timing_window(.05):
                    verify_cache.diagnostic_record(self.root / 'report.json', {'success': True})
                    self.fail('diagnostic OSError handler swallowed the deadline')
        self.assertLess(time.monotonic() - started, 2)
        self.assert_released()

    def test_queue_wait_is_outside_deadline(self):
        original = measurement.build_admission.admission
        @contextmanager
        def delayed(kind):
            time.sleep(.08)
            with original(kind) as holder:
                yield holder
        with patch.object(measurement.build_admission, 'admission', delayed):
            with measurement.timing_window(.05) as window:
                self.assertGreaterEqual(window.report()['admission_wait_seconds'], .08)
                window.check()

    def test_owned_commands_execute_without_nested_admission_and_expiry_cleans_up(self):
        timings = []
        with measurement.timing_window(5):
            status, _ = verify_cache.run_admitted(
                self.root, 'gate', [sys.executable, '-c', 'print("measured")'],
                dict(os.environ), lambda: True, timings=timings)
        self.assertEqual(status, 0)
        self.assertEqual(timings[0]['admission_scope'], 'request-timing-window')
        pidfile = self.root / 'child.pid'
        code = 'import os,time;open(%r,"w").write(str(os.getpid()));time.sleep(30)' % str(pidfile)
        with self.assertRaises(measurement.WindowExpired):
            with measurement.timing_window(.5):
                verify_cache.run_admitted(self.root, 'gate', [sys.executable, '-c', code],
                                          dict(os.environ), lambda: True)
        self.assertTrue(pidfile.exists())
        self.assertFalse(Path('/proc/' + pidfile.read_text()).exists())
        self.assert_released()

    def test_lost_holder_and_forked_capability_fail_closed(self):
        with self.assertRaises((measurement.WindowLost, RuntimeError)):
            with measurement.timing_window(5) as window:
                window.holder.terminate()
                window.holder.wait(timeout=2)
                measurement.current()
        with measurement.timing_window(5) as window:
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
                with measurement.timing_window(5) as window:
                    receipt.write_text('success')
                    window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
        self.assertFalse(receipt.exists())

    def test_revocation_failure_still_attempts_every_publication(self):
        receipt = self.root / 'receipt'
        receipt.write_text('success')
        def failed_cleanup():
            raise OSError('injected receipt cleanup failure')
        with self.assertRaises(measurement.WindowLost):
            with measurement.timing_window(5) as window:
                window.rollbacks.extend([lambda: receipt.unlink(missing_ok=True), failed_cleanup])
                raise measurement.WindowExpired('incomplete request')
        self.assertFalse(receipt.exists())
        self.assert_released()

    def test_late_deadline_revokes_published_evidence_but_success_keeps_it(self):
        receipt = self.root / 'published'
        with measurement.timing_window(5) as window:
            receipt.write_text('completed')
            window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
        self.assertEqual(receipt.read_text(), 'completed')
        with self.assertRaises(measurement.WindowExpired):
            with measurement.timing_window(.05) as window:
                window.rollbacks.append(lambda: receipt.unlink(missing_ok=True))
                time.sleep(5)
        self.assertFalse(receipt.exists())
        self.assert_released()


if __name__ == '__main__':
    unittest.main()
