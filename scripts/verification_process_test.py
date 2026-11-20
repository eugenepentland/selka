"""Real process coverage for admitted execution watchdogs (no compiler builds)."""
import os
from pathlib import Path
import signal
import re
import select
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

from verification_process import arm_parent_death, BoundedProcessLogs, FailFast, ProcessLimits, terminate_owned, wait_owned, _descendants, _kill_identity, _process_starttime


class WatchdogTests(unittest.TestCase):
    def spawn(self, source, **kwargs):
        # Every fixture interpreter, including nested supervisors, imports this
        # checkout without changing the working directory under test.
        root = str(Path(__file__).resolve().parents[1])
        environment = dict(kwargs.pop('env', os.environ))
        environment['PYTHONPATH'] = os.pathsep.join(filter(None, (root, environment.get('PYTHONPATH', ''))))
        return subprocess.Popen([sys.executable, '-c', source], start_new_session=True, env=environment, **kwargs)

    def ready_spawn(self, source, *, supervised=False, prefix='', **kwargs):
        """Exclude bounded fixture startup from the watchdog's execution clock."""
        read_fd, write_fd = os.pipe()
        announce = f'import os; os.write({write_fd},b"R"); os.close({write_fd})'
        source = source.replace('__FIXTURE_READY__', announce) if '__FIXTURE_READY__' in source else announce + '\n' + source
        if supervised:
            argv = [sys.executable, '-c', source]
            source = ('import os; from scripts.verification_process import run_supervised; '
                      + prefix + f'raise SystemExit(run_supervised({argv!r},dict(os.environ)))')
        inherited = tuple(kwargs.pop('pass_fds', ())) + (write_fd,)
        child = None
        try:
            child = self.spawn(source, pass_fds=inherited, **kwargs)
            os.close(write_fd)
            write_fd = None
            readable, _, _ = select.select([read_fd], [], [], 15)
            if not readable or os.read(read_fd, 1) != b'R':
                raise AssertionError('fixture did not report readiness within 15 seconds')
            return child
        except BaseException:
            if child is not None:
                terminate_owned(child, grace_seconds=.5)
                for stream in (child.stdout, child.stderr):
                    if stream is not None:
                        stream.close()
            raise
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)

    def await_file(self, path, *, seconds=60):
        deadline = time.monotonic() + seconds
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue(path.exists(), f'fixture marker not ready: {path}')

    def wait(self, source, timeout=0.15):
        return wait_owned(self.ready_spawn(source), limits=ProcessLimits(timeout, 0.05))

    def test_success_and_failure(self):
        # A child that ends on its own gets a budget that a loaded machine's interpreter exit cannot use up; only the
        # tests that expect a timeout keep the short one.
        self.assertEqual(self.wait('pass', timeout=30).returncode, 0)
        self.assertEqual(self.wait('raise SystemExit(7)', timeout=30).returncode, 7)

    def test_cpu_loop_and_blocked_child(self):
        self.assertTrue(self.wait('while True: pass').timed_out)
        result = self.wait("import subprocess; child=subprocess.Popen(['sleep','60']); __FIXTURE_READY__; child.wait()")
        self.assertEqual(result.returncode, 124)
        self.assertFalse(result.complete)

    def test_group_keeps_no_inherited_admission_fd(self):
        read_fd, write_fd = os.pipe()
        source = ('import os,signal,time; pid=os.fork(); '
                  '\nif pid == 0:\n signal.signal(signal.SIGTERM, signal.SIG_IGN); __FIXTURE_READY__; time.sleep(60)'
                  '\nelse:\n time.sleep(60)')
        child = self.ready_spawn(source, pass_fds=(write_fd,))
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
        child = self.ready_spawn('import time; time.sleep(60)')
        timer.start()
        try:
            result = wait_owned(child, cancel_event=cancel,
                                limits=ProcessLimits(None, .05))
            self.assertTrue(result.cancelled)
            self.assertEqual(result.returncode, 130)
            self.assertIsNone(other.poll())
        finally:
            terminate_owned(other, grace_seconds=.05)
            timer.join()

    def test_a_stop_request_ends_a_running_group_and_the_result_is_not_complete(self):
        other = self.spawn('import time; time.sleep(60)')
        stop = threading.Event()
        timer = threading.Timer(.1, stop.set)
        child = self.ready_spawn("import subprocess; sub=subprocess.Popen(['sleep','60']); __FIXTURE_READY__; sub.wait()")
        timer.start()
        try:
            started = time.monotonic()
            result = wait_owned(child, stop=stop.is_set, limits=ProcessLimits(None, .05))
            self.assertLess(time.monotonic() - started, 30)
            self.assertTrue(result.stopped)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(result.complete)
            self.assertFalse(result.timed_out or result.cancelled or result.incomplete)
            self.assertIsNone(other.poll(), 'only the stopped group may be signalled')
        finally:
            terminate_owned(other, grace_seconds=.05)
            timer.join()

    def test_a_stop_request_that_comes_after_the_child_ended_changes_nothing(self):
        result = wait_owned(self.ready_spawn('raise SystemExit(3)'), stop=lambda: False, limits=ProcessLimits(30, .05))
        self.assertEqual((result.returncode, result.stopped, result.complete), (3, False, True))
        late = wait_owned(self.ready_spawn('pass'), stop=lambda: True, limits=ProcessLimits(30, .05))
        # The child may have ended before the first poll or been stopped at it; either way no success is claimed twice.
        self.assertIn((late.returncode, late.stopped), ((0, False), (1, True)))

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
            result = wait_owned(child, logs=logs, limits=ProcessLimits(30,.05))
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
        return self.ready_spawn(source, supervised=True, **kwargs)

    def test_supervisor_kills_detached_sessions_and_reaps(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            source = ('import subprocess,time; child=subprocess.Popen('
                      '["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); __FIXTURE_READY__; time.sleep(60)')
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
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); __FIXTURE_READY__; time.sleep(60)'
                      '\nthreading.Thread(target=fork).start(); time.sleep(60)')
            child = self.supervised(source)
            result = wait_owned(child, limits=ProcessLimits(.2,.5))
            self.assertTrue(result.timed_out)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_path.read_text()), 0)

    def test_supervisor_reaps_zombie_only_success(self):
        result = wait_owned(self.supervised('import os,time; pid=os.fork(); '
                            '\nif pid == 0: os._exit(0)'
                            '\nelse: time.sleep(.1); os._exit(0)'))
        self.assertEqual(result.returncode, 0)

    def test_supervisor_preserves_failed_worker_status(self):
        result = wait_owned(self.supervised('import subprocess; subprocess.Popen(["sleep","60"],start_new_session=True); raise SystemExit(7)'))
        self.assertEqual(result.returncode, 7)

    def test_a_supervisor_that_fails_says_what_failed(self):
        # The other way to end 125. An exception inside the supervisor used to be swallowed into the status.
        with tempfile.TemporaryDirectory() as temporary:
            source = ('import os; from unittest import mock; import scripts.verification_process as process\n'
                      'with mock.patch.object(process, "_descendants", side_effect=PermissionError(13, "denied")):\n'
                      ' raise SystemExit(process.run_supervised(["true"], dict(os.environ)))')
            child = self.spawn(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            result = wait_owned(child, limits=ProcessLimits(30,.5), logs=logs)
            self.assertEqual(result.returncode, 125)
            report = (Path(temporary)/'err').read_text()
            self.assertRegex(report, r'supervisor: failed with PermissionError: .*denied at \w+\.py:\d+ in \w+; the action ends 125')
            self.assertIn('Traceback', report)
            child.stdout.close()
            child.stderr.close()

    def test_supervised_work_is_told_where_it_is_supervised(self):
        # Cache maintenance an admission of this directory would start is a descendant the supervisor kills half done
        # (`worktree_cache_trim.py` reads the variable and leaves the directory alone); the work must be told.
        with tempfile.TemporaryDirectory() as temporary:
            seen = Path(temporary)/'seen'
            result = wait_owned(self.supervised(f'import os; open({str(seen)!r},"w").write(os.environ.get("SELKA_ADMISSION_SUPERVISED", "unset"))'))
            self.assertEqual(result.returncode, 0)
            self.assertEqual(seen.read_text(), os.path.realpath(os.getcwd()))

    def test_supervisor_leader_exit_is_incomplete(self):
        with tempfile.TemporaryDirectory() as temporary:
            child = self.supervised('import subprocess; subprocess.Popen(["sleep","60"],start_new_session=True)',
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            result = wait_owned(child, limits=ProcessLimits(30,.5), logs=logs)
            self.assertEqual(result.returncode, 125)
            self.assertFalse(result.complete)
            # A status of 125 alone names nothing; the log says which descendant outlived the closeout, who started it,
            # where it runs and for how long.
            report = (Path(temporary)/'err').read_text()
            self.assertIn('supervisor: 1 descendant(s) outlived the closeout\n', report)
            self.assertRegex(report, r'supervisor: leftover pid=(\d+) ppid=\d+ sid=(\d+) state=\w started=\d\d:\d\d:\d\dZ age=[\d.]+s '
                                     r'cwd=' + re.escape(os.getcwd()) + r' cmd=sleep 60')
            pid, session = re.search(r'leftover pid=(\d+) ppid=\d+ sid=(\d+)', report).groups()
            self.assertEqual(pid, session)  # it started its own session: the detached shape the report exists to name
            child.stdout.close()
            child.stderr.close()

    def test_a_leftover_that_is_runnable_is_waited_for_past_the_two_second_window(self):
        # What load can cross is not a rule: a helper that ends in a fraction of a second on a calm machine (an admission's
        # shadow observer, in disk wait at load 27) was called a leftover after 2 s of wall time and ended the action 125.
        # A leftover that is runnable (here: it computes for 3 s, longer than the window) is held up by the machine, not
        # stuck, and the closeout waits for it; one that sleeps (`sleep 60` above) is still a leftover after 2 s.
        with tempfile.TemporaryDirectory() as temporary:
            busy = 'import time; end = time.monotonic() + 3\nwhile time.monotonic() < end: pass'
            source = ('import subprocess, sys; subprocess.Popen([sys.executable, "-c", %r], start_new_session=True); '
                      '__FIXTURE_READY__' % busy)
            child = self.supervised(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            result = wait_owned(child, limits=ProcessLimits(60, .5), logs=logs)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(result.complete)
            self.assertEqual((Path(temporary)/'err').read_text(), '')
            child.stdout.close()
            child.stderr.close()

    def test_a_leftover_that_stays_runnable_is_a_runaway_after_the_ceiling(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = ('import subprocess, sys; subprocess.Popen([sys.executable, "-c", "while True: pass"], '
                      'start_new_session=True); __FIXTURE_READY__')
            child = self.supervised(source, prefix='import scripts.verification_process as p; '
                                    'p.NATURAL_DRAIN_CEILING_SECONDS = 3.0; ',
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            began = time.monotonic()
            result = wait_owned(child, limits=ProcessLimits(60, .5), logs=logs)
            self.assertEqual(result.returncode, 125)
            self.assertLess(time.monotonic() - began, 50)
            self.assertIn('supervisor: 1 descendant(s) outlived the closeout\n', (Path(temporary)/'err').read_text())
            child.stdout.close()
            child.stderr.close()

    def test_unsupervised_escaped_writer_is_bounded_diagnostic(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            source = ('import subprocess; child=subprocess.Popen(["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); __FIXTURE_READY__')
            child = self.ready_spawn(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err')
            try:
                logs.start(child)
                # Assert the actual bounded join primitive, independent of
                # interpreter startup and host scheduling/IO stalls. The
                # escaped writer must still be alive when diagnostics return.
                with mock.patch.object(logs._thread, 'join', wraps=logs._thread.join) as joined:
                    result = wait_owned(child, logs=logs)
                self.assertTrue(joined.call_args_list)
                for call in joined.call_args_list:
                    timeout = call.kwargs.get('timeout', call.args[0] if call.args else None)
                    self.assertIsNotNone(timeout)
                    self.assertLessEqual(timeout, .25)
                os.kill(int(pid_path.read_text()), 0)
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
            child = self.ready_spawn('print("done")', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
            # The tee stays blocked until `release`; had the wait depended on it this would not return. The bound is
            # far inside any hang, not a measure of speed.
            self.assertLess(time.monotonic()-started, 30)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(logs.capture_errors)
            release.set()
            child.stdout.close()
            child.stderr.close()

    def test_full_tee_queue_stops_after_responsive_writer(self):
        release = threading.Event()
        class Tee:
            def write(self, data):
                release.wait()
            def flush(self):
                pass
        with tempfile.TemporaryDirectory() as temporary:
            logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err', stdout_tee=Tee())
            child = self.spawn('import os; os.write(1,b"x"*2000000)', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            result = wait_owned(child, logs=logs)
            self.assertEqual(result.returncode, 0)
            release.set()
            for _, thread in logs._tee_threads:
                thread.join(timeout=60)
                self.assertFalse(thread.is_alive())
            child.stdout.close()
            child.stderr.close()

    def test_blocked_raw_console_does_not_hang_interpreter_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            worker_argv = [sys.executable, "-c", "import os; os.write(1,b'x'*2000000)"]
            source = ('import subprocess,sys; from pathlib import Path; '
                      'from scripts.verification_process import BoundedProcessLogs,wait_owned; '
                      f'logs=BoundedProcessLogs(Path({temporary!r})/"out",Path({temporary!r})/"err",stdout_tee=sys.stdout.buffer); '
                      f'p=subprocess.Popen({worker_argv!r},'
                      'stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True); '
                      '__FIXTURE_READY__; raise SystemExit(wait_owned(p,logs=logs).returncode)')
            child = self.ready_spawn(source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                self.assertEqual(child.wait(timeout=60), 0)
            finally:
                if child.poll() is None:
                    terminate_owned(child)
                child.stdout.close()
                child.stderr.close()

    def test_delayed_tee_keeps_request_destination_after_fd_restore(self):
        release = threading.Event()
        writing = threading.Event()
        real_write = os.write
        with tempfile.TemporaryDirectory() as temporary:
            request_path = Path(temporary)/'request'
            protocol_path = Path(temporary)/'protocol'
            with request_path.open('wb') as request, protocol_path.open('wb') as protocol:
                original_fd = request.fileno()
                seen_fds = []
                def delayed_write(fd, data):
                    seen_fds.append(fd)
                    self.assertNotEqual(fd, original_fd)
                    self.assertFalse(os.get_inheritable(fd))
                    writing.set()
                    release.wait(timeout=2)
                    return real_write(fd, data)
                logs = BoundedProcessLogs(Path(temporary)/'out', Path(temporary)/'err', stdout_tee=request)
                child = self.spawn('print("request output")', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                with mock.patch('verification_process.os.write', side_effect=delayed_write):
                    result = wait_owned(child, logs=logs)
                    self.assertEqual(result.returncode, 0)
                    self.assertTrue(writing.wait(timeout=60))
                    os.dup2(protocol.fileno(), original_fd)
                    release.set()
                    for _, thread in logs._tee_threads:
                        thread.join(timeout=60)
                        self.assertFalse(thread.is_alive())
                self.assertEqual(request_path.read_bytes(), b'request output\n')
                self.assertEqual(protocol_path.read_bytes(), b'')
                with self.assertRaises(OSError):
                    os.fstat(seen_fds[0])
                child.stdout.close()
                child.stderr.close()

    def test_existing_inaccessible_log_is_not_available(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)/'out'
            error = Path(temporary)/'err'
            output.write_bytes(b'stale timing evidence')
            real_open = Path.open
            def deny_write(path, mode='r', *args, **kwargs):
                if path == output and mode == 'wb':
                    raise PermissionError('capture destination inaccessible')
                return real_open(path, mode, *args, **kwargs)
            logs = BoundedProcessLogs(output, error)
            child = self.spawn('print("new output")', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with mock.patch('verification_process.Path.open', new=deny_write):
                result = wait_owned(child, logs=logs)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(result.complete)
            self.assertEqual(logs.capture_available, [False, True])
            self.assertEqual(output.read_bytes(), b'stale timing evidence')
            self.assertTrue(logs.capture_errors)
            child.stdout.close()
            child.stderr.close()

    def test_preexisting_detached_admission_helper_survives(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary)/'settled'
            helper_argv = [sys.executable, '-c', f'import time; from pathlib import Path; time.sleep(.4); target=Path({str(marker)!r}); temporary=target.with_suffix(".tmp"); temporary.write_text("settled"); temporary.rename(target)']
            for worker_source, timeout, expected in [('pass', 30, 0), ('import time; time.sleep(60)', .15, 124)]:
                marker.unlink(missing_ok=True)
                prefix = (f'subprocess.Popen({helper_argv!r},start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); ')
                # subprocess is imported by the prefix before run_supervised.
                child = self.ready_spawn(worker_source, supervised=True,
                                         prefix='import subprocess; ' + prefix)
                result = wait_owned(child, limits=ProcessLimits(timeout,.5))
                self.assertEqual(result.returncode, expected)
                self.await_file(marker)
                self.assertEqual(marker.read_text(), 'settled')

    def test_supervisor_allows_background_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary)/'cleaned'
            cleanup = f'import os,time; from pathlib import Path; os.write(int(os.environ["CLEANUP_READY_FD"]),b"R"); time.sleep(.2); Path({str(marker)!r}).write_text("done")'
            source = ('import subprocess,os,select; r,w=os.pipe(); env=dict(os.environ,CLEANUP_READY_FD=str(w)); '
                      f'child=subprocess.Popen({[sys.executable, "-c", cleanup]!r},env=env,pass_fds=(w,)); '
                      'os.close(w); assert select.select([r],[],[],15)[0]; assert os.read(r,1)==b"R"; '
                      'os.close(r); __FIXTURE_READY__')
            result = wait_owned(self.supervised(source), limits=ProcessLimits(30,.5))
            self.assertEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(), 'done')

    def test_timeout_counts_background_cleanup_drain(self):
        source = 'import subprocess; subprocess.Popen(["sleep","60"],start_new_session=True); __FIXTURE_READY__'
        result = wait_owned(self.supervised(source), limits=ProcessLimits(.2,.5))
        self.assertEqual(result.returncode, 124)
        self.assertTrue(result.timed_out)

    def test_cancellation_interrupts_background_cleanup_drain(self):
        source = 'import subprocess; subprocess.Popen(["sleep","60"],start_new_session=True); __FIXTURE_READY__'
        cancel = threading.Event()
        timer = threading.Timer(.2, cancel.set)
        child = self.supervised(source)
        timer.start()
        started = time.monotonic()
        try:
            result = wait_owned(child, cancel_event=cancel, limits=ProcessLimits(None,.5))
            self.assertEqual(result.returncode, 130)
            self.assertTrue(result.cancelled)
            # The background `sleep 60` is the thing that must not be waited for.
            self.assertLess(time.monotonic()-started, 30)
        finally:
            timer.join()

    def test_inherited_helper_later_child_survives_cancellation(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary)/'helper-child-finished'
            ready = Path(temporary)/'helper-child-ready'
            helper_child = (f'from pathlib import Path; import time; Path({str(ready)!r}).write_text("ready"); '
                            f'time.sleep(.6); target=Path({str(marker)!r}); temporary=target.with_suffix(".tmp"); temporary.write_text("finished"); temporary.rename(target)')
            helper = ('import subprocess,time; time.sleep(.1); '
                      f'subprocess.Popen({[sys.executable, "-c", helper_child]!r},start_new_session=True); '
                      'time.sleep(2)')
            prefix = ('import subprocess; '
                      f'subprocess.Popen({[sys.executable, "-c", helper]!r},start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); ')
            child = self.ready_spawn('import time; time.sleep(60)', supervised=True, prefix=prefix)
            self.await_file(ready)
            result = wait_owned(child, limits=ProcessLimits(.15,.5))
            self.assertEqual(result.returncode, 124)
            self.await_file(marker)
            self.assertEqual(marker.read_text(), 'finished')

    def test_sigint_cancels_detached_lineage_and_releases_claim_fd(self):
        with tempfile.TemporaryDirectory() as temporary:
            pid_path = Path(temporary)/'pid'
            read_fd, write_fd = os.pipe()
            source = ('import subprocess,time; child=subprocess.Popen(["sleep","60"],start_new_session=True); '
                      f'open({str(pid_path)!r},"w").write(str(child.pid)); __FIXTURE_READY__; time.sleep(60)')
            child = self.supervised(source, pass_fds=(write_fd,))
            os.close(write_fd)
            os.kill(child.pid, signal.SIGINT)
            result = wait_owned(child, limits=ProcessLimits(30,.5))
            self.assertEqual(result.returncode, 130)
            self.assertEqual(os.read(read_fd, 1), b'')
            os.close(read_fd)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_path.read_text()), 0)

    def test_detached_forking_descendants_are_frozen_before_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            pids = Path(temporary)/'pids'
            source = ('import os,time,signal; os.setsid(); '
                      f'out=open({str(pids)!r},"a",buffering=1); out.write(str(os.getpid())+"\\n"); '
                      'signal.signal(signal.SIGTERM,signal.SIG_IGN); __FIXTURE_READY__; '
                      '\nfor _ in range(24):'
                      '\n pid=os.fork()'
                      '\n if pid == 0:'
                      '\n  out.write(str(os.getpid())+"\\n"); time.sleep(60); os._exit(0)'
                      '\n time.sleep(.002)'
                      '\ntime.sleep(60)')
            child = self.supervised(source)
            result = wait_owned(child, limits=ProcessLimits(.15,.5))
            self.assertEqual(result.returncode, 124)
            for pid in map(int, pids.read_text().splitlines()):
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)

    def test_cancellation_during_supervisor_startup_does_not_start_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            ready = Path(temporary)/'supervisor-ready'
            started = Path(temporary)/'worker-started'
            worker = [sys.executable, '-c', f'from pathlib import Path; Path({str(started)!r}).write_text("started")']
            source = ('import ctypes,os,time; from pathlib import Path; '
                      'from scripts.verification_process import run_supervised; '
                      '\nclass StartupBarrier:'
                      '\n def prctl(self,*args):'
                      f'\n  Path({str(ready)!r}).write_text("ready"); time.sleep(.2); return 0'
                      '\nctypes.CDLL=lambda *args,**kwargs: StartupBarrier()'
                      f'\nraise SystemExit(run_supervised({worker!r},dict(os.environ)))')
            child = self.spawn(source)
            self.await_file(ready)
            os.killpg(child.pid, signal.SIGTERM)
            result = wait_owned(child, limits=ProcessLimits(30,.5))
            self.assertEqual(result.returncode, 130)
            self.assertFalse(started.exists())

    def test_timeout_during_publication_never_returns_complete(self):
        with tempfile.TemporaryDirectory() as temporary:
            staging = Path(temporary)/'staging'
            success = Path(temporary)/'success'
            source = ('from pathlib import Path; import time; '
                      f'Path({str(staging)!r}).write_text("unpublished"); __FIXTURE_READY__; '
                      f'time.sleep(60); Path({str(staging)!r}).rename({str(success)!r})')
            result = wait_owned(self.supervised(source), limits=ProcessLimits(.15,.5))
            self.assertFalse(result.complete)
            self.assertFalse(success.exists())
            retry = self.supervised(f'from pathlib import Path; Path({str(success)!r}).write_text("fresh")')
            self.assertTrue(wait_owned(retry).complete)
            self.assertEqual(success.read_text(), 'fresh')

    def test_parent_identity_mismatch_refuses_work_after_arming(self):
        with mock.patch('ctypes.CDLL') as library:
            library.return_value.prctl.return_value = 0
            self.assertFalse(arm_parent_death(os.getppid(), _process_starttime(os.getppid()) + 1))
            library.return_value.prctl.assert_called_once_with(1, signal.SIGTERM, 0, 0, 0)
        with self.assertRaises(ValueError):
            arm_parent_death(True, 1)

    def test_hard_parent_crash_reaps_detached_action_lineage(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary)/'lineage.json'
            worker = ('import json,os,subprocess,time; from pathlib import Path; '
                      'child=subprocess.Popen(["sleep","60"],start_new_session=True); '
                      f'target=Path({str(marker)!r}); temporary=target.with_suffix(".tmp"); temporary.write_text(json.dumps({{"worker":os.getpid(),"detached":child.pid}})); temporary.rename(target); '
                      'time.sleep(60)')
            launcher = ('import os; from scripts.verification_process import run_supervised; '
                        f'raise SystemExit(run_supervised({[sys.executable, "-c", worker]!r},dict(os.environ)))')
            source = ('import subprocess,time; '
                      f'child=subprocess.Popen({[sys.executable,"-c",launcher]!r},start_new_session=True); '
                      '__FIXTURE_READY__; child.wait()')
            parent = self.ready_spawn(source)
            try:
                self.await_file(marker)
                import json
                lineage = json.loads(marker.read_text())
                os.kill(parent.pid, signal.SIGKILL)
                self.assertEqual(parent.wait(timeout=60), -signal.SIGKILL)
                # The condition is "the whole lineage is gone"; the supervisor ends it within a fraction of a second, and a
                # loaded machine only makes that later, so wait for the condition under a ceiling that is never the budget.
                deadline = time.monotonic() + 60
                while any(_process_starttime(pid) is not None for pid in lineage.values()) and time.monotonic() < deadline:
                    time.sleep(.01)
                for pid in lineage.values():
                    self.assertIsNone(_process_starttime(pid))
            finally:
                if parent.poll() is None:
                    terminate_owned(parent)

    def test_a_process_that_vanishes_while_its_stat_is_read_is_gone_not_an_error(self):
        # /proc/PID/stat answers ESRCH, not ENOENT, to a read that loses the race with the process leaving; the watchdog
        # reads it while the lineage dies, so that answer must read as "gone" (it failed the test above once in 700 runs).
        for error in (FileNotFoundError, ProcessLookupError):
            with mock.patch.object(Path, 'read_text', side_effect=error):
                self.assertIsNone(_process_starttime(os.getpid()))
        self.assertIsInstance(_process_starttime(os.getpid()), int)

    def test_descendants_skip_a_task_that_vanishes_while_its_children_are_read(self):
        child = self.spawn('import time; time.sleep(60)')
        try:
            self.assertIn(child.pid, _descendants(os.getpid()))
            for error in (FileNotFoundError, ProcessLookupError):
                real = Path.read_text
                with mock.patch.object(Path, 'read_text', autospec=True,
                                       side_effect=lambda path, *a, **k: (_ for _ in ()).throw(error()) if path.name == 'children' else real(path, *a, **k)):
                    self.assertEqual(_descendants(os.getpid()), {})
        finally:
            terminate_owned(child)

    def test_interrupt_cleans_and_propagates(self):
        class Interrupt:
            def is_set(self):
                raise KeyboardInterrupt()
        child = self.spawn('import time; time.sleep(60)')
        with self.assertRaises(KeyboardInterrupt):
            wait_owned(child, cancel_event=Interrupt(), limits=ProcessLimits(None,.05))
        self.assertIsNotNone(child.returncode)


class SlowDeathTests(unittest.TestCase):
    """Item 4e: a process sent SIGKILL that takes seconds to die (disk wait) is not a survivor; one that never dies is."""

    def drain(self, dies_after):
        import verification_process as process
        now = [0.0]
        kills = []

        def descendants():
            return {} if dies_after is not None and now[0] >= dies_after else {4242: 'birth'}
        found = process._await_killed({4242: 'birth'}, descendants=descendants, reap=lambda: None,
                                      kill=lambda pid, birth: kills.append(pid), clock=lambda: now[0],
                                      sleep=lambda seconds: now.__setitem__(0, now[0] + seconds))
        return found, kills, now[0]

    def test_a_child_that_dies_five_seconds_after_sigkill_is_not_a_survivor(self):
        found, kills, waited = self.drain(5.0)
        self.assertEqual(found, {})
        self.assertGreater(len(kills), 1, 'it is signalled again while it is still there')
        self.assertLess(waited, 6.0)

    def test_a_child_that_never_dies_is_still_a_survivor_after_the_drain(self):
        import verification_process as process
        found, _, waited = self.drain(None)
        self.assertEqual(found, {4242: 'birth'})
        self.assertGreaterEqual(waited, process.KILLED_DRAIN_SECONDS)


class FailFastTests(unittest.TestCase):
    """The watch over a gate's telemetry directory."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.now = [0.0]
        self.watch = FailFast(self.directory, interval=1.0, clock=lambda: self.now[0])

    def beacon(self, name, text):
        (self.directory / ('fail-fast.' + name + '.txt')).write_text(text)

    def test_quiet_directory_other_files_and_unfinished_beacons_trigger_nothing(self):
        (self.directory / 'unit.member.0.json').write_text('{}')
        (self.directory / '.fail-fast.abc123').write_text('half')
        (self.directory / 'fail-fast.unit.member.0.json').write_text('wrong suffix')
        self.assertFalse(self.watch())
        self.assertIsNone(self.watch.triggered_at)
        self.assertFalse(FailFast(None)())
        self.assertFalse(FailFast(self.directory / 'missing')())

    def test_the_first_beacon_triggers_and_stays_triggered(self):
        self.assertFalse(self.watch())
        self.beacon('unit.member.0', 'error: first\nfailed command: a --action-id unit\n')
        self.assertFalse(self.watch(), 'polled again inside the interval')
        self.now[0] = 1.5
        self.assertTrue(self.watch())
        (self.directory / 'fail-fast.unit.member.0.txt').unlink()
        self.assertTrue(self.watch(), 'latched')
        self.assertEqual(self.watch.names, ['fail-fast.unit.member.0.txt'])

    def test_the_log_text_holds_only_the_failures_seen_first_and_is_bounded(self):
        self.beacon('cli.member.1', 'error: one\nfailed command: x --action-id cli\n')
        self.assertTrue(self.watch())
        self.beacon('core.member.0', 'error: two, written after the stop\nfailed command: y --action-id core\n')
        text = self.watch.log_text()
        self.assertIn('error: one', text)
        self.assertNotIn('two', text)
        for number in range(8):
            self.beacon('many.%d' % number, 'error: %d\n' % number)
        later = FailFast(self.directory, interval=0, clock=lambda: 0.0)
        self.assertTrue(later())
        self.assertEqual(len(later.names), 4)
        self.beacon('huge.member.0', 'x' * 200000 + '\nfailed command: z\n')
        huge = FailFast(self.directory)
        huge.triggered_at, huge.names = 0.0, ['fail-fast.huge.member.0.txt']
        self.assertLessEqual(len(huge.log_text()), 64 * 1024 + 1)
        self.assertTrue(huge.log_text().endswith('failed command: z\n'))


if __name__ == '__main__':
    unittest.main()
