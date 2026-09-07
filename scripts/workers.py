"""Bounded process workers. Only copied source/request/result bytes cross boundaries.

The coordinator belongs to its creating thread. A context-manager scope joins all
children, including cancelled jobs, before deleting its private snapshots. Guest
spawn syntax, provider sharing and shared-memory execution are not exposed.
"""
from collections import deque
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import tempfile
import threading
import time

from worker_snapshot import Identity, canonical, request_snapshot, schema_identity, sources_snapshot


@dataclass(frozen=True)
class Limits:
    workers: int = 2
    pending: int = 8
    source_bytes: int = 2 * 1024 * 1024
    message_bytes: int = 1024 * 1024
    output_bytes: int = 1024 * 1024
    diagnostic_bytes: int = 64 * 1024
    seconds: float = 10
    steps: int = 1000000
    frames: int = 128
    calls: int = 256
    codec_bytes: int = 32 * 1024 * 1024

    def validate(self):
        integers = [self.workers, self.pending, self.source_bytes, self.message_bytes, self.output_bytes,
                    self.diagnostic_bytes, self.steps, self.frames, self.calls, self.codec_bytes]
        if any(type(value) is not int for value in integers):
            raise ValueError('worker counts and byte/instruction budgets must be integers')
        if not 1 <= self.workers <= 32 or not self.workers <= self.pending <= 256:
            raise ValueError('workers must be 1..32 and pending must be workers..256')
        sizes = [self.source_bytes, self.message_bytes, self.output_bytes, self.diagnostic_bytes, self.codec_bytes]
        if any(not 1 <= value <= 128 * 1024 * 1024 for value in sizes):
            raise ValueError('byte limits must be 1..128 MiB')
        if not 0 < self.seconds <= 3600 or any(value <= 0 for value in [self.steps, self.frames, self.calls]):
            raise ValueError('deadline and guest budgets must be positive')


@dataclass(frozen=True)
class Result:
    state: str
    identity: Identity
    output: bytes = b''
    diagnostics: bytes = b''
    returncode: int | None = None


class Job:
    """A pool-owned handle; no child pointers, descriptors or guest values escape."""
    def __init__(self, owner, directory, identity, kind, entry):
        self._owner, self._directory = owner, directory
        self.identity, self.kind, self.entry = identity, kind, entry
        self._process = None
        self._streams = 0
        self._output, self._diagnostics = bytearray(), bytearray()
        self._started = None
        self.result = None

    @property
    def running(self):
        return self._process is not None and self.result is None


class Pool:
    """Separate compiler processes with bounded admission and atomic result publication."""
    def __init__(self, compiler, limits=Limits(), *, directory=None):
        limits.validate()
        if os.name != "posix":
            raise RuntimeError("process workers currently require POSIX process groups")
        self.limits = limits
        self._thread = threading.get_ident()
        self._temporary = tempfile.TemporaryDirectory(prefix='mylang-workers-', dir=directory)
        self._root = Path(self._temporary.name)
        self._compiler = self._root / 'compiler'
        try:
            shutil.copyfile(Path(compiler).resolve(strict=True), self._compiler)
            self._compiler.chmod(0o500)
            with self._compiler.open('rb') as binary:
                self.compiler_sha256 = hashlib.file_digest(binary, 'sha256').hexdigest()
        except BaseException:
            self._temporary.cleanup()
            raise
        self._selector = selectors.DefaultSelector()
        self._queued, self._jobs = deque(), set()
        self._next, self._closed = 0, False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def _check(self, job=None):
        if threading.get_ident() != self._thread:
            raise RuntimeError('worker coordinator is owned by another thread')
        if self._closed:
            raise RuntimeError('worker pool is closed')
        if job is not None and job._owner is not self:
            raise ValueError('worker belongs to another pool')

    def submit(self, sources, request, *, entry='main.my'):
        """Copy and enqueue a schema-pinned request, without borrowing caller storage."""
        self._check()
        message, schema = request_snapshot(request, self.limits.message_bytes)
        return self._submit(sources, entry, 'invoke-project', message, schema)

    def schema(self, sources, *, entry='main.my'):
        """Produce a schema using the exact compiler/source snapshot used by workers."""
        job = self._submit(sources, entry, 'schema-project', b'', '')
        return self.wait(job)

    def _submit(self, sources, entry, kind, message, schema):
        self._check()
        if len(self._jobs) == self.limits.pending:
            raise RuntimeError('worker queue is full')
        copied, source_hash = sources_snapshot(sources, entry, self.limits.source_bytes)
        directory = self._root / str(self._next)
        self._next += 1
        directory.mkdir(mode=0o700)
        try:
            for name, data in copied.items():
                target = directory / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod(0o400)
            (directory / 'request.json').write_bytes(message)
            (directory / 'request.json').chmod(0o400)
            identity = Identity(self.compiler_sha256, source_hash, hashlib.sha256(message).hexdigest(), schema)
            job = Job(self, directory, identity, kind, entry)
            self._queued.append(job)
            self._jobs.add(job)
            self._launch()
            return job
        except BaseException:
            shutil.rmtree(directory, ignore_errors=True)
            raise

    def _launch(self):
        active = sum(job.running for job in self._jobs)
        while self._queued and active < self.limits.workers:
            job = self._queued.popleft()
            if job.result is not None:
                continue
            command = [str(self._compiler), job.kind, str(job._directory / job.entry)]
            if job.kind == 'invoke-project':
                command += ['--request=' + str(job._directory / 'request.json'),
                            f'--max-codec-steps={self.limits.steps}', f'--max-codec-frames={self.limits.frames}',
                            f'--max-codec-calls={self.limits.calls}', f'--max-codec-bytes={self.limits.codec_bytes}']
            try:
                job._process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, cwd=job._directory, env={'LANG': 'C.UTF-8'}, close_fds=True, start_new_session=True)
                job._started = time.monotonic()
                for stream, output in [(job._process.stdout, True), (job._process.stderr, False)]:
                    os.set_blocking(stream.fileno(), False)
                    self._selector.register(stream, selectors.EVENT_READ, (job, output))
                    job._streams += 1
                active += 1
            except OSError as error:
                job._diagnostics.extend(str(error).encode()[:self.limits.diagnostic_bytes])
                self._stop(job, 'launch_failed')

    def poll(self, seconds=0):
        """Drain bounded messages and enforce deadlines; never publishes partial output."""
        self._check()
        if not 0 <= seconds <= 0.05:
            raise ValueError('poll wait must be 0..0.05 seconds')
        for key, _ in self._selector.select(seconds):
            job, output = key.data
            if job.result is not None:
                continue
            try:
                chunk = os.read(key.fileobj.fileno(), 65536)
            except BlockingIOError:
                continue
            if not chunk:
                self._selector.unregister(key.fileobj)
                key.fileobj.close()
                job._streams -= 1
                continue
            buffer = job._output if output else job._diagnostics
            limit = self.limits.output_bytes if output else self.limits.diagnostic_bytes
            if len(buffer) + len(chunk) > limit:
                self._stop(job, 'output_limit')
            else:
                buffer.extend(chunk)
        now = time.monotonic()
        for job in tuple(self._jobs):
            if not job.running:
                continue
            if now - job._started >= self.limits.seconds:
                self._stop(job, 'time_limit')
            elif job._process.poll() is not None and job._streams == 0:
                self._finish(job, 'succeeded' if job._process.returncode == 0 else 'failed')
        self._launch()

    def wait(self, job):
        """Join one result while servicing other workers; its arena and files are gone."""
        self._check(job)
        while job.result is None:
            self.poll(0.05)
        return job.result

    def cancel(self, job):
        """Terminate and reap a running process or discard a queued request."""
        self._check(job)
        if job.result is None:
            self._stop(job, 'cancelled')
            self._launch()
        return job.result

    def _stop(self, job, state):
        if job._process is not None and job._process.poll() is None:
            try:
                os.killpg(job._process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                job._process.wait(timeout=0.25)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(job._process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                job._process.wait()
        self._finish(job, state)

    def _finish(self, job, state, diagnostics=None):
        process = job._process
        if process is not None:
            for stream in [process.stdout, process.stderr]:
                if not stream.closed:
                    try:
                        self._selector.unregister(stream)
                    except KeyError:
                        pass
                    stream.close()
            process.wait()
        output = bytes(job._output) if state == 'succeeded' else b''
        if state == 'succeeded':
            try:
                value = json.loads(output)
                if job.kind == 'invoke-project' and value.get('version') != 'typed-json-v1':
                    raise ValueError('invalid worker response envelope')
            except (ValueError, AttributeError):
                state, output = 'protocol_error', b''
        job.result = Result(state, job.identity, output,
                            bytes(job._diagnostics) if diagnostics is None else diagnostics,
                            process.returncode if process is not None else None)
        job._output.clear()
        job._diagnostics.clear()
        self._jobs.discard(job)
        shutil.rmtree(job._directory)

    def close(self):
        """Cancel and join every remaining worker before removing the compiler snapshot."""
        if self._closed:
            return
        self._check()
        for job in tuple(self._jobs):
            self._stop(job, 'cancelled')
        self._queued.clear()
        self._selector.close()
        self._temporary.cleanup()
        self._closed = True
