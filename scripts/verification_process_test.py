"""Real process coverage for admitted execution watchdogs (no compiler builds)."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from verification_process import BoundedProcessLogs, ProcessLimits, terminate_owned, wait_owned


class WatchdogTests(unittest.TestCase):
    def spawn(self, source, **kwargs):
        return subprocess.Popen([sys.executable, '-c', source], start_new_session=True, **kwargs)

    def wait(self, source, timeout=0.15):
        return wait_owned(self.spawn(source), limits=ProcessLimits(timeout, 0.05))

    def test_success_and_failure(self):
        self.assertEqual(self.wait('pass').returncode, 0)
        self.assertEqual(self.wait('raise SystemExit(7)').returncode, 7)

    def test_cpu_loop_and_blocked_child(self):
        self.assertTrue(self.wait('while True: pass').timed_out)
        result = self.wait("import subprocess; subprocess.run(['sleep','60'])")
        self.assertEqual(result.returncode, 124)
        self.assertFalse(result.complete)

    def test_group_keeps_no_inherited_admission_fd(self):
        read_fd, write_fd = os.pipe()
        source = ('import os,signal,time; pid=os.fork(); '
                  '\nif pid == 0:\n signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'
                  '\nelse:\n time.sleep(60)')
        child = self.spawn(source, pass_fds=(write_fd,))
        os.close(write_fd)
        result = wait_owned(child, limits=ProcessLimits(0.15, 0.05))
        self.assertEqual(result.returncode, 124)
        self.assertEqual(os.read(read_fd, 1), b'')
        os.close(read_fd)
        self.assertIsNotNone(child.returncode)

    def test_leader_exits_before_term_ignoring_grandchild(self):
        read_fd, write_fd = os.pipe()
        child = self.spawn('import os,signal,time; pid=os.fork(); '
                          '\nif pid == 0:\n signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)'
                          '\nelse:\n time.sleep(.05); os._exit(0)', pass_fds=(write_fd,))
        os.close(write_fd)
        result = wait_owned(child, limits=ProcessLimits(None, 0.05))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(os.read(read_fd, 1), b'')
        os.close(read_fd)

    def test_cancellation_does_not_kill_another_session(self):
        other = self.spawn('import time; time.sleep(60)')
        cancel = threading.Event()
        timer = threading.Timer(.1, cancel.set)
        timer.start()
        try:
            result = wait_owned(self.spawn('import time; time.sleep(60)'), cancel_event=cancel,
                                limits=ProcessLimits(None, .05))
            self.assertTrue(result.cancelled)
            self.assertEqual(result.returncode, 130)
            self.assertIsNone(other.poll())
        finally:
            terminate_owned(other, grace_seconds=.05)
            timer.join()

    def test_invalid_controls_and_identity(self):
        for invalid in (0, -1, float('nan'), float('inf'), True, '1'):
            with self.assertRaises(ValueError):
                ProcessLimits(invalid)
        self.assertIsNone(ProcessLimits().timeout_seconds)
        self.assertNotEqual(ProcessLimits(1).execution_identity(), ProcessLimits(2).execution_identity())

    def test_logs_are_bounded_and_preserve_both_streams(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = (Path(temporary)/'out', Path(temporary)/'err')
            logs = BoundedProcessLogs(*paths, max_bytes=4096)
            child = self.spawn("import os; os.write(1,b'A'*200000); os.write(2,b'B'*200000)",
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs.start(child)
            # Admission queue time must not block output or consume execution budget.
            time.sleep(.1)
            result = wait_owned(child, logs=logs, limits=ProcessLimits(1,.05))
            self.assertEqual(result.returncode, 0)
            self.assertEqual(paths[0].read_bytes(), b'A'*4096)
            self.assertEqual(paths[1].read_bytes(), b'B'*4096)
            self.assertEqual(logs.truncated, [True, True])
            self.assertEqual(logs.bytes_seen, [200000,200000])
            child.stdout.close()
            child.stderr.close()

    def test_log_open_failure_is_diagnostic(self):
        with tempfile.TemporaryDirectory() as temporary:
            logs = BoundedProcessLogs(Path(temporary)/"missing"/"out", Path(temporary)/"err")
            child = self.spawn("print(123)", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            result = wait_owned(child, logs=logs)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(logs.capture_errors)
            child.stdout.close()
            child.stderr.close()

    def test_interrupt_cleans_and_propagates(self):
        class Interrupt:
            def is_set(self):
                raise KeyboardInterrupt()
        child = self.spawn('import time; time.sleep(60)')
        with self.assertRaises(KeyboardInterrupt):
            wait_owned(child, cancel_event=Interrupt(), limits=ProcessLimits(None,.05))
        self.assertIsNotNone(child.returncode)


if __name__ == '__main__':
    unittest.main()
