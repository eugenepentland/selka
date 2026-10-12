#!/usr/bin/env python3
"""Transparent pinned Zig test-protocol proxy with advisory interval observations.

The measured interval starts when test_started is received and ends when the
matching test_results arrives. It includes runner reporting and pipe scheduling;
it is NOT pure test-body duration. Malformed telemetry disables observation,
never forwarding. The original runner owns selection, output and test verdicts.
"""
import argparse
import os
from pathlib import Path
import signal
import select
import struct
import subprocess
import sys
import threading
import time

import verification_telemetry as telemetry

PINNED_ZIG = '0.17.0-dev.1683+5ceec001b'
MAX_FRAME = telemetry.MAX_BYTES
MAX_FRAMES = telemetry.MAX_TESTS * 5 + 16
CLIENT_EXIT, CLIENT_RUN_TEST = 0, 5
SERVER_VERSION, SERVER_METADATA, SERVER_RESULTS, SERVER_STARTED = 0, 3, 4, 5
INTERVAL_SCOPE = 'runner-protocol-interval'


class Frames:
    """Observe bounded little-endian protocol frames without owning transport."""
    def __init__(self, callback, failed):
        self.callback = callback
        self.failed = failed
        self.buffer = bytearray()
        self.count = 0
        self.enabled = True

    def feed(self, data):
        if not self.enabled:
            return
        self.buffer.extend(data)
        while len(self.buffer) >= 8:
            tag, length = struct.unpack_from('<II', self.buffer)
            if length > MAX_FRAME or self.count >= MAX_FRAMES:
                self.disable()
                return
            if len(self.buffer) < 8 + length:
                return
            body = bytes(self.buffer[8:8 + length])
            del self.buffer[:8 + length]
            self.count += 1
            try:
                self.callback(tag, body)
            except (ValueError, UnicodeError, struct.error, OverflowError):
                self.disable()
                return

    def disable(self):
        self.enabled = False
        self.buffer.clear()
        self.failed()

    def finish(self):
        if self.buffer:
            self.disable()


class Observation:
    """Match actual dispatched indices to complete producer metadata and results."""
    def __init__(self, root, clock=time.monotonic_ns):
        self.root = root
        self.clock = clock
        self.lock = threading.Lock()
        self.names = None
        self.pending = []
        self.requested = set()
        self.started = None
        self.rows = []
        self.exit_seen = False
        self.supported = False
        self.malformed = False

    def fail(self):
        with self.lock:
            self.malformed = True

    def client(self, tag, body):
        with self.lock:
            if tag == CLIENT_EXIT:
                if body:
                    raise ValueError('exit body')
                self.exit_seen = True
            elif tag == CLIENT_RUN_TEST:
                if len(body) != 4 or self.names is None:
                    raise ValueError('dispatch shape')
                index, = struct.unpack('<I', body)
                if index >= len(self.names) or index in self.requested or len(self.requested) >= telemetry.MAX_TESTS:
                    raise ValueError('dispatch identity')
                self.requested.add(index)
                self.pending.append(index)

    def server(self, tag, body):
        with self.lock:
            if tag == SERVER_VERSION:
                if body.decode('utf-8') != PINNED_ZIG or self.supported:
                    raise ValueError('unsupported protocol version')
                self.supported = True
            elif tag == SERVER_METADATA:
                if not self.supported or self.names is not None or len(body) < 8:
                    raise ValueError('metadata state')
                string_length, count = struct.unpack_from('<II', body)
                if count > telemetry.MAX_TESTS or len(body) != 8 + count * 8 + string_length:
                    raise ValueError('metadata bound')
                strings = body[8 + count * 8:]
                names = []
                for index in range(count):
                    offset, = struct.unpack_from('<I', body, 8 + index * 4)
                    if offset >= len(strings):
                        raise ValueError('name offset')
                    end = strings.find(b'\0', offset)
                    if end < 0:
                        raise ValueError('unterminated name')
                    name = strings[offset:end].decode('utf-8')
                    identity = self.root + '::' + name
                    if not name or len(identity) > telemetry.MAX_LABEL:
                        raise ValueError('name bound')
                    names.append(identity)
                if len(set(names)) != len(names):
                    raise ValueError('duplicate names')
                self.names = names
            elif tag == SERVER_STARTED:
                if body or not self.pending or self.started is not None:
                    raise ValueError('start without dispatch')
                self.started = self.clock()
            elif tag == SERVER_RESULTS:
                if len(body) != 12 or not self.pending or self.started is None:
                    raise ValueError('result without start')
                index, flags = struct.unpack('<IQ', body)
                if index != self.pending.pop(0):
                    raise ValueError('result identity')
                status = flags & 3
                if status == 3 or flags & 4:
                    raise ValueError('unsupported fuzz/status')
                log_errors = (flags >> 3) & ((1 << 30) - 1)
                leaks = flags >> 33
                state = 'skipped' if status == 2 else 'failed' if status == 1 or log_errors or leaks else 'passed'
                elapsed = self.clock() - self.started
                if elapsed < 0:
                    raise ValueError('clock order')
                self.rows.append(dict(test_id=self.names[index], state=state,
                                      elapsed_ns=None if state == 'skipped' else elapsed,
                                      elapsed_scope=INTERVAL_SCOPE))
                self.started = None

    def document(self, action, member, returncode):
        with self.lock:
            complete = (self.supported and not self.malformed and self.names is not None
                        and self.exit_seen and not self.pending and self.started is None
                        and len(self.rows) == len(self.requested) and returncode == 0)
            return dict(version=1, producer='zig-test-protocol-v1', action_id=action,
                        member_id=telemetry.member_id(action, member),
                        selected=len(self.requested), complete=complete, tests=list(self.rows),
                        elapsed_scope=INTERVAL_SCOPE, body_duration_ns=None,
                        selection_scope='actual-client-dispatch',
                        malformed=self.malformed or not self.supported or self.names is None)


def write_all(fd, data):
    while data:
        count = os.write(fd, data)
        data = data[count:]


def proxy(command, observer):
    """Forward all wire bytes and inherited stderr; preserve runner exit status."""
    child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=None, bufsize=0, close_fds=False)
    client_frames = Frames(observer.client, observer.fail)
    server_frames = Frames(observer.server, observer.fail)
    cancelled = []

    def cancel(number, _frame):
        cancelled.append((number, time.monotonic()))
        try:
            child.send_signal(number)
        except ProcessLookupError:
            pass

    prior = {}
    for number in (signal.SIGTERM, signal.SIGINT):
        prior[number] = signal.signal(number, cancel)

    def client_forward():
        try:
            while True:
                data = os.read(sys.stdin.fileno(), 65536)
                if not data:
                    break
                client_frames.feed(data)
                write_all(child.stdin.fileno(), data)
        except (OSError, BrokenPipeError):
            observer.fail()
        finally:
            client_frames.finish()
            try:
                child.stdin.close()
            except OSError:
                observer.fail()

    reader = threading.Thread(target=client_forward, daemon=True)
    reader.start()
    try:
        while True:
            if cancelled and time.monotonic() - cancelled[-1][1] >= 1:
                observer.fail()
                if child.poll() is None:
                    child.kill()
                break
            ready, _, _ = select.select([child.stdout.fileno()], [], [], .1)
            if not ready:
                continue
            data = os.read(child.stdout.fileno(), 65536)
            if not data:
                break
            server_frames.feed(data)
            write_all(sys.stdout.fileno(), data)
        server_frames.finish()
        returncode = child.wait()
        return 128 + cancelled[-1][0] if cancelled else returncode
    except (OSError, BrokenPipeError):
        observer.fail()
        child.terminate()
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        return child.returncode
    finally:
        child.stdout.close()
        for number, handler in prior.items():
            signal.signal(number, handler)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action-id', required=True)
    parser.add_argument('--member', type=int, required=True)
    parser.add_argument('--root-id', required=True)
    parser.add_argument('--output-directory-env', default='SELKA_VERIFICATION_TELEMETRY_DIR')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    telemetry.member_id(args.action_id, args.member)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('runner command required')
    observer = Observation(args.root_id)
    status = proxy(command, observer)
    directory = os.environ.get(args.output_directory_env)
    if directory:
        safe_id = args.action_id.replace('/', '_').replace('\\', '_')
        path = Path(directory) / f'{safe_id}.member.{args.member}.json'
        telemetry.write_document(path, observer.document(args.action_id, args.member, status))
    return 128 - status if status < 0 else status


if __name__ == '__main__':
    sys.exit(main())
