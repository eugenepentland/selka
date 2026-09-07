#!/usr/bin/env python3
"""Watch immutable application snapshots through one persistent bytecode host.

No build tools are invoked. Each request gets fresh guest state; active frames and
heap layouts are never patched. The adjacent .status.json is authoritative about
preview freshness. Snapshot roots are private to this coordinator.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import select
import signal
import stat
import subprocess
import tempfile
import time

MAX_SOURCE = 16 * 1024 * 1024


def bounded_read(path, limit):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('snapshot inputs must be regular files')
        data = source.read(limit + 1)
        if len(data) > limit:
            raise ValueError('snapshot input exceeds byte limit')
        return data


def source_paths(project):
    pending = [project]
    paths = []
    visited = 0
    while pending:
        with os.scandir(pending.pop()) as entries:
            for entry in entries:
                visited += 1
                if visited > 8192:
                    raise ValueError('source traversal exceeds 8192 entries')
                if entry.is_symlink():
                    raise ValueError('source symlinks are unsupported')
                if entry.is_dir(follow_symlinks=False):
                    pending.append(Path(entry.path))
                elif entry.name.endswith('.my'):
                    paths.append(Path(entry.path))
                    if len(paths) > 256:
                        raise ValueError('project exceeds 256 source files')
    return sorted(paths)


def capture(project, documents):
    """Include all modules and membership, including newly added imports."""
    files = {}
    total = 0
    for path in source_paths(project):
        data = bounded_read(path, 4 * 1024 * 1024)
        total += len(data)
        if total > MAX_SOURCE:
            raise ValueError('source snapshot exceeds project byte limits')
        files['project/' + path.relative_to(project).as_posix()] = data
    for index, path in enumerate(documents):
        files['document-' + str(index)] = bounded_read(path, 1024 * 1024)
    digest = hashlib.sha256()
    for name, data in sorted(files.items()):
        digest.update(len(name.encode()).to_bytes(8, 'big'))
        digest.update(name.encode())
        digest.update(len(data).to_bytes(8, 'big'))
        digest.update(data)
    return digest.hexdigest(), files


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class Host:
    """A single host process with bounded active/prepared generation ownership."""
    def __init__(self, runner):
        self.process = subprocess.Popen([str(runner), '--dev-session'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.timeout = 180
        self.response_limit = 32 * 1024 * 1024

    def request(self, action, **fields):
        self.process.stdin.write((json.dumps(dict(action=action, **fields)) + '\n').encode())
        self.process.stdin.flush()
        deadline = time.monotonic() + self.timeout
        chunks = bytearray()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise RuntimeError('development host response timed out')
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('development host exited')
            chunks.extend(chunk)
            if len(chunks) > self.response_limit:
                raise RuntimeError('development host response exceeds limit')
            if b'\n' in chunk:
                if not chunks.endswith(b'\n') or chunks.count(b'\n') != 1:
                    raise RuntimeError('development host sent invalid response framing')
                return json.loads(chunks)

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        self.process.stdout.close()


def prepare(host, files):
    with tempfile.TemporaryDirectory(prefix='mylang-generation-') as folder:
        root = Path(folder)
        for name, data in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(0o400)
        return host.request('prepare', project=str(root / 'project'),
                            documents=[str(root / ('document-' + str(i))) for i in range(3)])


def watch(args):
    status_path = Path(str(args.output) + '.status.json')
    host = Host(args.runner)
    attempted = None
    active = None

    def status(state, source=None, failure=None):
        atomic_write(status_path, json.dumps(dict(state=state, source=source,
                     active=active, failure=failure, host_pid=host.process.pid)).encode())
        print(state + (': ' + failure if failure else ''), flush=True)

    try:
        while True:
            try:
                key, files = capture(args.project, args.documents)
                if key != attempted:
                    status('stale', key)
                    time.sleep(args.debounce)
                    if capture(args.project, args.documents)[0] != key:
                        continue
                    response = prepare(host, files)
                    if capture(args.project, args.documents)[0] != key:
                        host.request('discard')
                        continue
                    attempted = key
                    if response['status'] == 'prepared':
                        committed = host.request('commit')
                        if committed['status'] != 'active':
                            raise RuntimeError('host refused prepared generation')
                        if capture(args.project, args.documents)[0] != key:
                            attempted = None
                            continue
                        atomic_write(args.output, response['svg'].encode())
                        active = key
                        status('fresh', key)
                    else:
                        status('stale', key, response['failure'])
                    if args.once:
                        return 0 if response['status'] == 'prepared' else 1
            except (OSError, ValueError) as error:
                status('stale', failure=str(error))
                if args.once:
                    return 1
            time.sleep(args.interval)
    finally:
        host.close()
        status('stopped')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interval', type=float, default=0.25)
    parser.add_argument('--debounce', type=float, default=0.1)
    parser.add_argument('--once', action='store_true')
    parser.add_argument('documents', type=Path, nargs=3)
    args = parser.parse_args()
    for name in ('runner', 'project', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    args.documents = [path.resolve() for path in args.documents]
    if not all(math.isfinite(v) for v in (args.interval, args.debounce)) or args.interval <= 0 or args.debounce < 0:
        parser.error('interval must be positive and debounce nonnegative')
    def terminate(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, terminate)
    try:
        return watch(args)
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
