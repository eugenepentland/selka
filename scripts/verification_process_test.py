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

from verification_process import BoundedProcessLogs, ProcessLimits, terminate_owned, wait_owned, _kill_identity, _process_starttime


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

    def supervised(self, source, **kwargs):
        argv = [sys.executable, '-c', source]
        command = ('import os; from scripts.verification_process import run_supervised; '
                   f'raise SystemExit(run_supervised({argv!r},dict(os.environ)))')
        return self.spawn(command, **kwargs)

    def test_supervisor_kills_detached_sessions_and_reaps(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            source = ('import subprocess,time; child=subprocess.Popen('
                      '["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); time.sleep(60)')
            child = self.supervised(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            result = wait_owned(child, limits=ProcessLimits(.2,.5), logs=logs)
            self.assertTrue(result.timed_out)
            self.assertTrue(logs.capture_complete)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_path.read_text()), 0)
            child.stdout.close()
            child.stderr.close()

    def test_supervisor_preserves_inherited_descriptors(self):
        read_fd, write_fd = os.pipe()
        child = self.supervised(f'import os; os.write({write_fd},b"preserved")', pass_fds=(write_fd,))
        os.close(write_fd)
        result = wait_owned(child)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(os.read(read_fd, 32), b'preserved')
        os.close(read_fd)

    def test_supervisor_preserves_signal_exit_status(self):
        result = wait_owned(self.supervised('import os,signal; os.kill(os.getpid(),signal.SIGTERM)'))
        self.assertEqual(result.returncode, 143)

    def test_pid_identity_mismatch_never_signals(self):
        child = self.spawn('import time; time.sleep(60)')
        try:
            _kill_identity(child.pid, _process_starttime(child.pid) + 1)
            self.assertIsNone(child.poll())
        finally:
            terminate_owned(child, grace_seconds=.05)

    def test_thread_owned_detached_child(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            source = ('import subprocess,threading,time; '
                      '\ndef fork():\n child=subprocess.Popen(["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); time.sleep(60)'
                      '\nthreading.Thread(target=fork).start(); time.sleep(60)')
            child = self.supervised(source)
            result = wait_owned(child, limits=ProcessLimits(.2,.5))
            self.assertTrue(result.timed_out)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_path.read_text()), 0)

    def test_supervisor_leader_exit_is_incomplete(self):
        result = wait_owned(self.supervised('import subprocess; subprocess.Popen(["sleep","60"],start_new_session=True)'),
                            limits=ProcessLimits(1,.5))
        self.assertEqual(result.returncode, 125)
        self.assertFalse(result.complete)

    def test_unsupervised_escaped_writer_is_bounded_diagnostic(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            source = ('import subprocess; child=subprocess.Popen(["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid))')
            child = self.spawn(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            try:
                started = time.monotonic()
                result = wait_owned(child, logs=logs)
                self.assertLess(time.monotonic()-started, 1)
                self.assertTrue(result.complete)
                self.assertEqual(result.returncode, 0)
                self.assertFalse(logs.capture_complete)
                self.assertTrue(logs.capture_errors)
            finally:
                os.kill(int(pid_path.read_text()), signal.SIGKILL)
                child.stdout.close()
                child.stderr.close()

    def test_slow_log_drain_does_not_change_success(self):
        class SlowLogs(BoundedProcessLogs):
            def _drain(self, seconds=0):
                time.sleep(.4)
                super()._drain(seconds)
        with tempfile.TemporaryDirectory() as temporary:
            logs = SlowLogs(Path(temporary)/'out', Path(temporary)/'err')
            child = self.spawn('print("done")', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            result = wait_owned(child, logs=logs)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(result.complete)
            self.assertFalse(logs.capture_complete)
            self.assertTrue(logs.capture_errors)
            child.stdout.close()
            child.stderr.close()

    def test_stuck_console_tee_does_not_block(self):
        release = threading.Event()
        class Tee:
            def write(self, data):
                release.wait()
            def flush(self):
                pass
        with tempfile.TemporaryDirectory() as temporary:
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err', stdout_tee=Tee())
            child = self.spawn('print("hi")', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            started = time.monotonic()
            result = wait_owned(child, logs=logs)
            self.assertLess(time.monotonic()-started, 1)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(logs.capture_errors)
            release.set()
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
