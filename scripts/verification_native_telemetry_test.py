#!/usr/bin/env python3
"""Pinned wire parsing, transparent forwarding and cancellation regressions."""
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import verification_native_telemetry as native
import verification_report as report


def isolated_environment(**overrides):
    """Nested collectors cannot publish into the invoking gate's namespace."""
    environment = dict(os.environ)
    environment.pop('SELKA_TEST_TELEMETRY_DIR', None)
    environment.pop('SELKA_VERIFICATION_TELEMETRY_DIR', None)
    environment.update(overrides)
    return environment


def process_finished(pid):
    """A killed child may stay a zombie until the nearest subreaper reaps it."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    try:
        state = Path('/proc') / str(pid) / 'stat'
        return state.read_text().split(') ', 1)[1].split()[0] == 'Z'
    except (OSError, IndexError):
        return True


def frame(tag, body=b''):
    return struct.pack('<II', tag, len(body)) + body


def metadata(names):
    strings = b'\0'
    offsets = []
    for name in names:
        offsets.append(len(strings))
        strings += name.encode() + b'\0'
    return struct.pack('<II', len(strings), len(names)) + struct.pack('<' + 'I' * len(names), *offsets) + b'\0' * (len(names) * 4) + strings


def ready(names=('test.pass',)):
    clock = iter((100, 200, 300, 400, 500, 600)).__next__
    observed = native.Observation('fixture/root.zig', clock=clock)
    observed.server(0, native.PINNED_ZIG.encode())
    observed.server(3, metadata(names))
    return observed


class NativeTelemetryTests(unittest.TestCase):
    def test_full_selected_outcomes_and_explicit_protocol_scope(self):
        observed = ready(('test.pass', 'test.fail', 'test.skip'))
        for index, status in enumerate((0, 1, 2)):
            observed.client(5, struct.pack('<I', index))
            observed.server(5, b'')
            observed.server(4, struct.pack('<IQ', index, status))
        observed.client(0, b'')
        result = report.test_timings()
        self.assertEqual(result['status'], 'unknown')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.json'
            path.write_text(json.dumps(observed.document('unit', 0, 0)))
            result = report.test_timings(path, action_id='unit', member='unit/member/0')
        self.assertEqual([row['state'] for row in result['tests']], ['passed', 'failed', 'skipped'])
        self.assertEqual([row['elapsed_ns'] for row in result['tests']], [100, 100, None])
        self.assertEqual(result['tests'][0]['elapsed_scope'], native.INTERVAL_SCOPE)
        self.assertEqual([(row['started_monotonic_ns'], row['ended_monotonic_ns']) for row in result['tests']], [(100, 200), (300, 400), (500, 600)])
        self.assertEqual((result['selected'], result['executed'], result['timed']), (3, 2, 2))
        self.assertTrue(result['complete'])
        self.assertEqual(result['selection_scope'], 'actual-client-dispatch')
        self.assertEqual(result['timing_coverage'], 'partial')

    def test_leak_and_logged_error_preserve_failure(self):
        for flags in (1 << 3, 1 << 33):
            observed = ready()
            observed.client(5, struct.pack('<I', 0))
            observed.server(5, b'')
            observed.server(4, struct.pack('<IQ', 0, flags))
            self.assertEqual(observed.rows[0]['state'], 'failed')

    def test_finite_fragmented_and_malformed_stream_handling(self):
        observed = ready()
        parsed = native.Frames(observed.client, observed.fail)
        bytes_ = frame(5, struct.pack('<I', 0))
        for byte in bytes_:
            parsed.feed(bytes([byte]))
        self.assertEqual(observed.pending, [0])
        parsed.feed(frame(5, struct.pack('<I', 0)))
        self.assertFalse(parsed.enabled)
        self.assertTrue(observed.malformed)
        parsed.feed(b'x' * 100)
        self.assertEqual(parsed.buffer, bytearray())
        bounds = native.Frames(observed.client, observed.fail)
        bounds.feed(struct.pack('<II', 0, native.MAX_FRAME + 1))
        self.assertFalse(bounds.enabled)
        truncated = native.Frames(observed.client, observed.fail)
        truncated.feed(b'\x00')
        truncated.finish()
        self.assertFalse(truncated.enabled)

    def test_unsupported_version_metadata_and_result_never_complete(self):
        observed = native.Observation('root')
        parsed = native.Frames(observed.server, observed.fail)
        parsed.feed(frame(0, b'other-version'))
        self.assertTrue(observed.malformed)
        self.assertFalse(observed.document('unit', 0, 0)['complete'])
        self.assertTrue(native.Observation('root').document('unit', 0, 0)['malformed'])
        for body in (b'', metadata(('duplicate', 'duplicate')), struct.pack('<II', 1, native.telemetry.MAX_TESTS + 1)):
            observed = native.Observation('root')
            observed.server(0, native.PINNED_ZIG.encode())
            with self.assertRaises(ValueError):
                observed.server(3, body)
        observed = ready()
        with self.assertRaises(ValueError):
            observed.server(4, struct.pack('<IQ', 0, 0))
        self.assertFalse(observed.document('unit', 0, 0)['complete'])

    def test_byte_exact_transport_and_runner_status_with_unknown_protocol(self):
        script = Path(native.__file__).resolve()
        payload = b'not-protocol\x00\xff'
        runner = "import os,sys; data=sys.stdin.buffer.read(); os.write(1,data); os.write(2,b'runner stderr\\n'); sys.exit(7)"
        with tempfile.TemporaryDirectory() as directory:
            legacy = Path(directory) / 'legacy'
            legacy.mkdir()
            env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=directory,
                                       SELKA_TEST_TELEMETRY_DIR=str(legacy))
            completed = subprocess.run([sys.executable, str(script), '--action-id', 'unit', '--member', '0',
                                        '--root-id', 'root', '--', sys.executable, '-c', runner],
                                       input=payload, capture_output=True, env=env, timeout=60)
            self.assertEqual(completed.returncode, 7)
            self.assertEqual(completed.stdout, payload)
            self.assertEqual(completed.stderr, b'runner stderr\n')
            document = json.loads((Path(directory) / 'unit.member.0.json').read_text())
            self.assertFalse(document['complete'])
            self.assertTrue(document['malformed'])
            self.assertEqual(list(legacy.iterdir()), [])

    def test_inherited_progress_and_other_descriptors_reach_original_runner(self):
        reader, writer = os.pipe()
        try:
            runner = "import os; os.write(int(os.environ['TELEMETRY_FIXTURE_FD']),b'side-channel')"
            completed = subprocess.run([sys.executable, native.__file__, '--action-id', 'unit',
                                        '--member', '0', '--root-id', 'root', '--', sys.executable, '-c', runner],
                                       input=b'', capture_output=True, pass_fds=(writer,),
                                       env=isolated_environment(TELEMETRY_FIXTURE_FD=str(writer)), timeout=60)
            self.assertEqual(completed.returncode, 0)
            self.assertEqual(os.read(reader, 12), b'side-channel')
        finally:
            os.close(reader)
            os.close(writer)

    def test_all_nested_proxies_preserve_parent_gate_sidecars(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            sidecar = parent / 'unit.member.0.json'
            authentic = b'parent gate telemetry must remain byte-exact'
            sidecar.write_bytes(authentic)
            with patch.dict(os.environ, SELKA_TEST_TELEMETRY_DIR=directory,
                            SELKA_VERIFICATION_TELEMETRY_DIR=directory):
                self.assertNotIn('SELKA_TEST_TELEMETRY_DIR', isolated_environment())
                self.assertNotIn('SELKA_VERIFICATION_TELEMETRY_DIR', isolated_environment())
                self.test_byte_exact_transport_and_runner_status_with_unknown_protocol()
                self.test_inherited_progress_and_other_descriptors_reach_original_runner()
                self.test_cancellation_reaps_noncooperating_runner()
            self.assertEqual(sidecar.read_bytes(), authentic)
            self.assertEqual(sorted(path.name for path in parent.iterdir()), ['unit.member.0.json'])

    def test_cancellation_reaps_noncooperating_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / 'ready'
            runner = ("import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                      "open(os.environ['READY_FILE'],'w').close(); time.sleep(60)")
            process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit', '--member', '0',
                                        '--root-id', 'root', '--', sys.executable, '-c', runner],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       env=isolated_environment(READY_FILE=str(ready)))
            try:
                deadline = time.monotonic() + 60
                while not ready.exists():
                    self.assertLess(time.monotonic(), deadline, 'runner never started')
                    time.sleep(.02)
                process.send_signal(signal.SIGTERM)
                output, error = process.communicate(timeout=60)
                self.assertEqual(process.returncode, 143)
                self.assertEqual(output, b'')
                self.assertEqual(error, b'')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_green_step_stderr_is_suppressed_and_a_failure_replays_it(self):
        green = "import sys; sys.stdin.buffer.read(); sys.stderr.write('progress\\n'); sys.exit(0)"
        red = "import sys; sys.stdin.buffer.read(); sys.stderr.write('diagnostic\\n'); sys.exit(3)"
        for runner, code, expected in ((green, 0, b''), (red, 3, b'diagnostic\n')):
            completed = subprocess.run([sys.executable, native.__file__, '--action-id', 'unit',
                                        '--member', '0', '--root-id', 'root', '--',
                                        sys.executable, '-c', runner],
                                       input=b'', capture_output=True,
                                       env=isolated_environment(), timeout=60)
            self.assertEqual(completed.returncode, code)
            self.assertEqual(completed.stderr, expected)

    def test_deadline_kills_the_test_group_records_timed_out_and_spares_a_sibling(self):
        import base64
        header = frame(0, native.PINNED_ZIG.encode()) + frame(3, metadata(('slow.test',)))
        runner = ("import os,sys,time,base64; "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['DEADLINE_HEADER'])); "
                  "sys.stdout.buffer.flush(); sys.stdin.buffer.read(12); "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['DEADLINE_STARTED'])); "
                  "sys.stdout.buffer.flush(); time.sleep(60)")
        sibling = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        try:
            with tempfile.TemporaryDirectory() as directory:
                env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=directory,
                                           SELKA_TEST_DEADLINE_SECONDS='0.4',
                                           DEADLINE_HEADER=base64.b64encode(header).decode(),
                                           DEADLINE_STARTED=base64.b64encode(frame(5, b'')).decode())
                process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit',
                                            '--member', '0', '--root-id', 'root', '--',
                                            sys.executable, '-c', runner],
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, env=env)
                try:
                    self.assertEqual(process.stdout.read(len(header)), header)
                    process.stdin.write(frame(5, struct.pack('<I', 0)))
                    process.stdin.flush()
                    output, error = process.communicate(timeout=60)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                self.assertEqual(process.returncode, native.DEADLINE_STATUS)
                self.assertIn(b'test deadline: root::slow.test ran ', error)
                self.assertIn(b'(limit 0.4 s); killed\n', error)
                document = json.loads((Path(directory) / 'unit.member.0.json').read_text())
                self.assertTrue(document['timed_out'])
                self.assertFalse(document['complete'])
                self.assertEqual([(row['test_id'], row['state']) for row in document['tests']],
                                 [('root::slow.test', 'timed_out')])
                self.assertIsNone(sibling.poll(), 'a process outside the runner group must survive')
        finally:
            sibling.kill()
            sibling.wait()

    def run_one_test(self, body, **overrides):
        """Run one test interval whose runner starts the test, then runs `body` (Python statements).

        Returns (returncode, stderr, the unit's telemetry document). The body may write `DEADLINE_RESULT`
        (a passed result frame) to finish the test.
        """
        import base64
        header = frame(0, native.PINNED_ZIG.encode()) + frame(3, metadata(('slow.test',)))
        runner = ("import os,sys,time,base64; "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['DEADLINE_HEADER'])); "
                  "sys.stdout.buffer.flush(); sys.stdin.buffer.read(12); "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['DEADLINE_STARTED'])); "
                  "sys.stdout.buffer.flush(); " + body)
        with tempfile.TemporaryDirectory() as directory:
            env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=directory,
                                       DEADLINE_HEADER=base64.b64encode(header).decode(),
                                       DEADLINE_STARTED=base64.b64encode(frame(5, b'')).decode(),
                                       DEADLINE_RESULT=base64.b64encode(frame(4, struct.pack('<IQ', 0, 0))).decode(),
                                       **overrides)
            process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit',
                                        '--member', '0', '--root-id', 'root', '--',
                                        sys.executable, '-c', runner],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, env=env)
            try:
                self.assertEqual(process.stdout.read(len(header)), header)
                process.stdin.write(frame(5, struct.pack('<I', 0)))
                process.stdin.flush()
                _, error = process.communicate(timeout=60)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            document = json.loads((Path(directory) / 'unit.member.0.json').read_text())
        return process.returncode, error, document

    def test_a_hung_test_is_killed_once_its_process_tree_stops_using_cpu(self):
        # A blocked test shows no CPU progress, so the idle limit kills it well inside its bound.
        started = time.monotonic()
        returncode, error, document = self.run_one_test('time.sleep(60)', SELKA_TEST_IDLE_SECONDS='1.5',
                                                        SELKA_TEST_DEADLINE_SECONDS='0')
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual(returncode, native.DEADLINE_STATUS)
        self.assertIn(b'test deadline: root::slow.test made no CPU progress for ', error)
        self.assertIn(b'(limit 1.5 s); killed\n', error)
        self.assertTrue(document['timed_out'])
        self.assertEqual([(row['test_id'], row['state']) for row in document['tests']],
                         [('root::slow.test', 'timed_out')])

    def test_a_test_that_keeps_computing_outlives_the_idle_limit_and_passes(self):
        # Its interval is about three times the idle limit, but CPU progress resets that limit every sample.
        returncode, error, document = self.run_one_test('end = time.monotonic() + 3.0\n'
                                                        'while time.monotonic() < end: pass\n'
                                                        'sys.stdout.buffer.write(base64.b64decode(os.environ["DEADLINE_RESULT"])); '
                                                        'sys.stdout.buffer.flush()',
                                                        SELKA_TEST_IDLE_SECONDS='1.5',
                                                        SELKA_TEST_DEADLINE_SECONDS='0')
        self.assertEqual(returncode, 0)
        self.assertNotIn(b'test deadline:', error)
        self.assertFalse(document['timed_out'])
        self.assertEqual([(row['test_id'], row['state']) for row in document['tests']],
                         [('root::slow.test', 'passed')])

    def test_a_child_that_leaves_the_session_still_counts_as_progress(self):
        # The child is a descendant of the runner in its own session; its CPU keeps the test alive past the idle limit.
        child = 'import time\nend = time.monotonic() + 3.0\nwhile time.monotonic() < end: pass\n'
        returncode, error, document = self.run_one_test(
            "import subprocess\n"
            "subprocess.run([sys.executable, '-c', os.environ['CHILD_SCRIPT']], start_new_session=True)\n"
            "sys.stdout.buffer.write(base64.b64decode(os.environ['DEADLINE_RESULT'])); sys.stdout.buffer.flush()",
            CHILD_SCRIPT=child, SELKA_TEST_IDLE_SECONDS='1.5', SELKA_TEST_DEADLINE_SECONDS='0')
        self.assertEqual(returncode, 0)
        self.assertNotIn(b'test deadline:', error)
        self.assertFalse(document['timed_out'])
        self.assertEqual([(row['test_id'], row['state']) for row in document['tests']],
                         [('root::slow.test', 'passed')])

    def test_a_hung_test_takes_down_a_child_that_left_the_session(self):
        # The grandchild sleeps in its own session; the kill must reach it through the tree, not the group.
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'grandchild-pid'
            returncode, error, document = self.run_one_test(
                "import subprocess\n"
                "grand = subprocess.Popen([sys.executable, '-c', os.environ['CHILD_SCRIPT']], start_new_session=True)\n"
                "open(os.environ['GRANDCHILD_FILE'], 'w').write(str(grand.pid))\n"
                "time.sleep(60)",
                CHILD_SCRIPT='import time\ntime.sleep(60)\n', GRANDCHILD_FILE=str(marker),
                SELKA_TEST_IDLE_SECONDS='1.5', SELKA_TEST_DEADLINE_SECONDS='0')
            self.assertEqual(returncode, native.DEADLINE_STATUS)
            self.assertIn(b'made no CPU progress for ', error)
            grandchild = int(marker.read_text())
            deadline = time.monotonic() + 60
            while not process_finished(grandchild) and time.monotonic() < deadline:
                time.sleep(.05)
            self.assertTrue(process_finished(grandchild), 'a child outside the runner session survived its test')

    def test_a_busy_loop_that_never_returns_is_stopped_by_the_wall_backstop(self):
        # With the idle limit off, a loop that keeps the CPU busy is bounded by the wall backstop.
        started = time.monotonic()
        returncode, error, document = self.run_one_test('\nwhile True: pass', SELKA_TEST_IDLE_SECONDS='0',
                                                        SELKA_TEST_DEADLINE_SECONDS='1.0')
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual(returncode, native.DEADLINE_STATUS)
        self.assertIn(b'test deadline: root::slow.test ran ', error)
        self.assertIn(b'(limit 1.0 s); killed\n', error)
        self.assertTrue(document['timed_out'])

    def test_a_failing_test_reported_with_exit_status_zero_keeps_its_diagnostics(self):
        # Guardian's server-mode runner reports a failure on the wire and exits 0;
        # only a passing run may lose its stderr.
        import base64
        header = frame(0, native.PINNED_ZIG.encode()) + frame(3, metadata(('probe.test',)))
        runner = ("import os,sys,base64,struct; "
                  "out=sys.stdout.buffer; "
                  "out.write(base64.b64decode(os.environ['PROBE_HEADER'])); out.flush(); "
                  "sys.stdin.buffer.read(12); "
                  "sys.stderr.write('expected 1, found 2\\n'); sys.stderr.flush(); "
                  "flags=int(os.environ['PROBE_FLAGS']); "
                  "out.write(struct.pack('<II',5,0)); "
                  "out.write(struct.pack('<II',4,12)+struct.pack('<IQ',0,flags)); out.flush(); "
                  "sys.stdin.buffer.read(8); sys.exit(0)")
        for flags, expected in ((0, b''), (1, b'expected 1, found 2\n'), (1 << 3, b'expected 1, found 2\n')):
            env = isolated_environment(PROBE_HEADER=base64.b64encode(header).decode(), PROBE_FLAGS=str(flags))
            process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit',
                                        '--member', '0', '--root-id', 'root', '--',
                                        sys.executable, '-c', runner],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, env=env)
            try:
                self.assertEqual(process.stdout.read(len(header)), header)
                process.stdin.write(frame(5, struct.pack('<I', 0)))
                process.stdin.flush()
                self.assertEqual(len(process.stdout.read(28)), 28)
                process.stdin.write(frame(0))
                process.stdin.close()
                process.wait(timeout=60)
                error = process.stderr.read()
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            self.assertEqual(process.returncode, 0)
            self.assertEqual(error, expected, 'flags %d' % flags)

    def test_only_the_failing_tests_own_stderr_reaches_the_build_runner(self):
        import base64
        header = frame(0, native.PINNED_ZIG.encode()) + frame(3, metadata(('green.test', 'red.test')))
        runner = ("import os,sys,base64,struct; "
                  "out=sys.stdout.buffer; "
                  "out.write(base64.b64decode(os.environ['PROBE_HEADER'])); out.flush(); "
                  "notes=['green noise\\n','expected 1, found 2\\n']; "
                  "[(sys.stdin.buffer.read(12), sys.stderr.write(notes[i]), sys.stderr.flush(), "
                  "out.write(struct.pack('<II',5,0)+struct.pack('<II',4,12)+struct.pack('<IQ',i,i)), out.flush()) "
                  "for i in range(2)]; "
                  "sys.stdin.buffer.read(8); sys.exit(0)")
        env = isolated_environment(PROBE_HEADER=base64.b64encode(header).decode())
        process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit',
                                    '--member', '0', '--root-id', 'root', '--',
                                    sys.executable, '-c', runner],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=env)
        try:
            self.assertEqual(process.stdout.read(len(header)), header)
            process.stdin.write(frame(5, struct.pack('<I', 0)))
            process.stdin.flush()
            self.assertEqual(len(process.stdout.read(28)), 28)
            process.stdin.write(frame(5, struct.pack('<I', 1)))
            process.stdin.flush()
            self.assertEqual(len(process.stdout.read(28)), 28)
            process.stdin.write(frame(0))
            process.stdin.close()
            process.wait(timeout=60)
            error = process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        self.assertEqual(process.returncode, 0)
        self.assertEqual(error, b'expected 1, found 2\n')

    def test_quiet_driver_keeps_a_green_step_silent_and_replays_a_failure(self):
        driver = Path(native.__file__).resolve().with_name('quiet-driver.sh')
        green = subprocess.run(['sh', str(driver), 'sh', '-c', 'echo progress; echo noise >&2; exit 0'],
                               capture_output=True, text=True, timeout=60, env=isolated_environment())
        self.assertEqual((green.returncode, green.stdout, green.stderr), (0, '', ''))
        red = subprocess.run(['sh', str(driver), 'sh', '-c', 'echo detail; echo problem >&2; exit 4'],
                             capture_output=True, text=True, timeout=60, env=isolated_environment())
        self.assertEqual(red.returncode, 4)
        self.assertEqual(red.stdout, '')
        self.assertEqual(red.stderr, 'detail\nproblem\n')

    def test_a_failed_driver_leaves_a_beacon_and_a_green_one_does_not(self):
        driver = Path(native.__file__).resolve().with_name('quiet-driver.sh')
        with tempfile.TemporaryDirectory() as directory:
            env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=directory)
            subprocess.run(['sh', str(driver), 'sh', '-c', 'echo fine'], capture_output=True, env=env, timeout=60)
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), [])
            red = subprocess.run(['sh', str(driver), 'sh', '-c', 'echo detail; echo "FAIL: test_x" >&2; exit 4'],
                                 capture_output=True, text=True, env=env, timeout=60)
            self.assertEqual(red.returncode, 4)
            self.assertEqual(red.stderr, 'detail\nFAIL: test_x\n')
            beacons = sorted(path.name for path in Path(directory).iterdir())
            self.assertEqual(len(beacons), 1)
            self.assertRegex(beacons[0], r'^fail-fast\.driver\.[0-9]+\.txt$')
            text = (Path(directory) / beacons[0]).read_text()
            self.assertIn('detail\nFAIL: test_x\n', text)
            self.assertTrue(text.endswith('failed command: sh scripts/quiet-driver.sh sh -c echo detail; echo "FAIL: test_x" >&2; exit 4\n'))

    def test_a_driver_with_no_telemetry_directory_fails_as_before(self):
        driver = Path(native.__file__).resolve().with_name('quiet-driver.sh')
        with tempfile.TemporaryDirectory() as directory:
            for value in ('', str(Path(directory) / 'missing')):
                env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=value)
                red = subprocess.run(['sh', str(driver), 'sh', '-c', 'echo problem >&2; exit 4'],
                                     capture_output=True, text=True, env=env, timeout=60)
                self.assertEqual((red.returncode, red.stderr), (4, 'problem\n'))
            self.assertEqual(list(Path(directory).iterdir()), [])

    def failing_runner(self, directory, result_status, after):
        """Start the proxy over a runner that starts one test, writes to stderr, reports `result_status` and then runs `after`."""
        import base64
        header = frame(0, native.PINNED_ZIG.encode()) + frame(3, metadata(('fail.test',)))
        runner = ("import os,sys,time,base64; "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['FF_HEADER'])); sys.stdout.buffer.flush(); "
                  "sys.stdin.buffer.read(12); "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['FF_STARTED'])); sys.stdout.buffer.flush(); "
                  "sys.stderr.write('boom detail\\n'); sys.stderr.flush(); "
                  "sys.stdout.buffer.write(base64.b64decode(os.environ['FF_RESULT'])); sys.stdout.buffer.flush(); " + after)
        env = isolated_environment(SELKA_VERIFICATION_TELEMETRY_DIR=directory,
                                   FF_HEADER=base64.b64encode(header).decode(),
                                   FF_STARTED=base64.b64encode(frame(5, b'')).decode(),
                                   FF_RESULT=base64.b64encode(frame(4, struct.pack('<IQ', 0, result_status))).decode())
        process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit', '--member', '2',
                                    '--root-id', 'root', '--', sys.executable, '-c', runner],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.assertEqual(process.stdout.read(len(header)), header)
        process.stdin.write(frame(5, struct.pack('<I', 0)))
        process.stdin.flush()
        return process

    def test_the_first_failed_test_leaves_a_beacon_and_the_rows_so_far_while_the_runner_still_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            process = self.failing_runner(directory, 1, 'time.sleep(60)')
            try:
                beacon = Path(directory) / 'fail-fast.unit.member.2.txt'
                deadline = time.monotonic() + 60
                while not beacon.exists():
                    self.assertLess(time.monotonic(), deadline, 'no beacon')
                    time.sleep(.02)
                self.assertIsNone(process.poll(), 'the runner is still going: the beacon came before the step ended')
                text = beacon.read_text()
                document = json.loads((Path(directory) / 'unit.member.2.json').read_text())
                dotted = [path.name for path in Path(directory).iterdir() if path.name.startswith('.')]
            finally:
                process.kill()
                process.wait()
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close()
        self.assertTrue(text.startswith("error: 'root::fail.test' failed\nboom detail\n"), text)
        self.assertRegex(text, r'failed command: python3 .*verification_native_telemetry\.py --action-id unit --member 2 ')
        self.assertEqual([(row['test_id'], row['state']) for row in document['tests']], [('root::fail.test', 'failed')])
        self.assertFalse(document['complete'])
        self.assertEqual(dotted, [])

    def test_a_passing_test_leaves_no_beacon(self):
        with tempfile.TemporaryDirectory() as directory:
            process = self.failing_runner(directory, 0, 'sys.stdin.buffer.read()')
            process.stdin.write(frame(0))
            process.stdin.close()
            process.communicate(timeout=60)
            self.assertEqual(process.returncode, 0)
            # The telemetry document and the record of how the step ran (for a flaky rerun, item 4d); no beacon.
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()),
                             ['rerun.unit.member.2.json', 'unit.member.2.json'])

    def test_a_beacon_reads_as_a_failure_block_to_the_gate_summary(self):
        import gate_summary
        text = native.beacon_text('src/root_test.zig::lazy_readers_test.test.audit', 'failed',
                                  'expected: 1\nat src/lazy_readers_test.zig:30\n',
                                  'python3 scripts/verification_native_telemetry.py --action-id unit --member 0 --root-id r -- ./t')
        blocks = gate_summary.failure_details(text)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]['action'], 'unit')
        self.assertEqual(blocks[0]['tests'], ['src/root_test.zig::lazy_readers_test.test.audit'])
        self.assertEqual(blocks[0]['location'], 'src/lazy_readers_test.zig:30')
        timed = native.beacon_text('r::slow', 'timed_out', '', 'python3 x --action-id core --member 1')
        self.assertTrue(timed.startswith("error: 'r::slow' timed out\nfailed command: "))

    def test_killing_the_proxy_leaves_no_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'runner-pid'
            runner = ("import os,time; open(os.environ['RUNNER_PID'],'w').write(str(os.getpid())); "
                      "time.sleep(60)")
            process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit',
                                        '--member', '0', '--root-id', 'root', '--',
                                        sys.executable, '-c', runner],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE,
                                       env=isolated_environment(RUNNER_PID=str(marker),
                                                                SELKA_TEST_DEADLINE_SECONDS='0'))
            try:
                # The runner creates the file and then writes its pid: a reader on a saturated machine can run between the two
                # (the gate of 9 November, with every step started at once, read an empty file).
                deadline = time.monotonic() + 60
                while (not marker.exists() or marker.stat().st_size == 0) and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue(marker.exists() and marker.stat().st_size > 0, 'runner never started')
                runner_pid = int(marker.read_text())
                process.kill()
                process.wait(timeout=60)
                gone = False
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    if process_finished(runner_pid):
                        gone = True
                        break
                    time.sleep(.02)
                self.assertTrue(gone, 'runner survived its killed proxy')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_deadline_environment_is_parsed_and_negative_values_are_refused(self):
        self.assertEqual(native.deadline_seconds('0'), 0)
        self.assertEqual(native.deadline_seconds('12.5'), 12.5)
        for value in ('-1', 'nan', 'infinite', 'soon'):
            with self.assertRaises(native.argparse.ArgumentTypeError):
                native.deadline_seconds(value)


if __name__ == '__main__':
    unittest.main()
