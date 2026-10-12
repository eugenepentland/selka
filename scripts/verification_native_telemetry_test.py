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

import verification_native_telemetry as native
import verification_report as report


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
        self.assertEqual((result['selected'], result['executed'], result['timed']), (3, 2, 2))
        self.assertTrue(result['complete'])
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
            env = dict(os.environ, MYLANG_TEST_TELEMETRY_DIR=directory)
            completed = subprocess.run([sys.executable, str(script), '--action-id', 'unit', '--member', '0',
                                        '--root-id', 'root', '--', sys.executable, '-c', runner],
                                       input=payload, capture_output=True, env=env, timeout=5)
            self.assertEqual(completed.returncode, 7)
            self.assertEqual(completed.stdout, payload)
            self.assertEqual(completed.stderr, b'runner stderr\n')
            document = json.loads((Path(directory) / 'unit.member.0.json').read_text())
            self.assertFalse(document['complete'])
            self.assertTrue(document['malformed'])

    def test_cancellation_reaps_noncooperating_runner(self):
        runner = "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); os.write(2,b'ready\\n'); time.sleep(60)"
        process = subprocess.Popen([sys.executable, native.__file__, '--action-id', 'unit', '--member', '0',
                                    '--root-id', 'root', '--', sys.executable, '-c', runner],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(process.stderr.readline(), b'ready\n')
            process.send_signal(signal.SIGTERM)
            output, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143)
            self.assertEqual(output, b'')
            self.assertEqual(error, b'')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
