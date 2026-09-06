#!/usr/bin/env python3
"""Recheck a module project on content changes using one compiler session."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time


class Stopped(Exception):
    def __init__(self, number):
        self.code = 128 + number


def snapshot(root, manifests, max_entries=10000, max_bytes=64 * 1024 * 1024):
    """Bound traversal and hashing; include errors so repair triggers a check."""
    result = {}
    entries = 0
    remaining = max_bytes

    def content(path):
        nonlocal remaining
        try:
            # Nonblocking open avoids hanging on a source replaced by a FIFO.
            descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            with os.fdopen(descriptor, 'rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    return ('error', 'NotRegularFile')
                digest = hashlib.sha256()
                while True:
                    chunk = stream.read(min(65536, remaining + 1))
                    if not chunk:
                        return ('sha256', digest.hexdigest())
                    remaining -= len(chunk)
                    if remaining < 0:
                        raise ValueError('watch byte budget exceeded')
                    digest.update(chunk)
        except OSError as error:
            return ('error', error.errno)

    def walk(directory, ancestors):
        nonlocal entries
        if len(ancestors) >= 256:
            raise ValueError('watch directory depth budget exceeded')
        try:
            info = directory.stat()
            identity = info.st_dev, info.st_ino
            if identity in ancestors:
                raise ValueError('watch directory symlink cycle')
            with os.scandir(directory) as children:
                for child in children:
                    entries += 1
                    if entries > max_entries:
                        raise ValueError('watch entry budget exceeded')
                    path = directory / child.name
                    if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', child.name) and child.is_dir():
                        walk(path, ancestors | {identity})
                    elif re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*\.my', child.name):
                        result[str(path)] = content(path)
        except OSError as error:
            result[str(directory)] = ('error', error.errno)

    walk(root, set())
    for path in manifests:
        result[str(path)] = content(path)
    return result


class Session:
    def __init__(self, command, timeout):
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.timeout = timeout
        self.ready = selectors.DefaultSelector()
        self.ready.register(self.process.stdout, selectors.EVENT_READ)

    def check(self):
        self.process.stdin.write(b'check\n')
        self.process.stdin.flush()
        deadline = time.monotonic() + self.timeout
        data = bytearray()
        while b'\n' not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.ready.select(remaining):
                raise ValueError('compiler check timed out')
            chunk = os.read(self.process.stdout.fileno(), 4096)
            if not chunk:
                raise ValueError('compiler session ended before its reply')
            data.extend(chunk)
            if len(data) > 65536:
                raise ValueError('compiler reply budget exceeded')
        reply = json.loads(data)
        if not isinstance(reply, dict):
            raise ValueError('invalid compiler session reply')
        if reply.get('version') != 'check-session-v1' or reply.get('action') != 'check' or type(reply.get('status')) is not int or reply['status'] not in (0, 1, 2):
            raise ValueError('invalid compiler session reply')
        return reply

    def close(self):
        self.ready.close()
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        self.process.stdout.close()


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('must be finite and positive')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--compiler', type=Path, default=Path('zig-out/bin/mylang'))
    parser.add_argument('--inputs', type=Path, action='append', default=[])
    parser.add_argument('--interval', type=positive, default=0.25, help='content polling interval in seconds')
    parser.add_argument('--timeout', type=positive, default=60, help='per-check reply timeout in seconds')
    parser.add_argument('--once', action='store_true', help='check once and exit with the check status')
    args = parser.parse_args()
    # Keep lexical paths: resolving source symlinks changes the compiler import root.
    source = args.source.absolute()
    manifests = [path.absolute() for path in args.inputs]
    if not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*\.my', source.name):
        parser.error('source must be an identifier.my file')
    if len(manifests) > 16:
        parser.error('at most 16 input manifests may be watched')
    session = None
    previous_handlers = {}

    def stop(number, frame):
        raise Stopped(number)

    try:
        for number in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[number] = signal.signal(number, stop)
        previous = None
        while True:
            current = snapshot(source.parent, manifests)
            if current != previous:
                if session is None:
                    command = [str(args.compiler.absolute()), 'check-session', str(source)]
                    command.extend('--inputs=' + str(path) for path in manifests)
                    session = Session(command, args.timeout)
                reply = session.check()
                print(json.dumps(reply, separators=(',', ':')), flush=True)
                if args.once:
                    return reply['status']
                # Retain the pre-check snapshot so edits during checking aren't lost.
                previous = current
            time.sleep(args.interval)
    except Stopped as stopped:
        return stopped.code
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'watch: {error}', file=sys.stderr)
        return 2
    finally:
        if session is not None:
            session.close()
        for number, handler in previous_handlers.items():
            signal.signal(number, handler)


if __name__ == '__main__':
    sys.exit(main())
