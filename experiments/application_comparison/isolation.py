"""Linux namespace execution with bounded capture and namespace-wide termination.

Only the trusted coordinator selects mounts. Participant commands cannot select
host paths. This isolates filesystem/process/network access; it is not a VM or a
complete cgroup resource controller. Per-process rlimits are reported as such.
"""
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time
from .runtime_policy import SYSTEM_PATHS

BOOTSTRAP = Path(__file__).with_name('isolation_bootstrap.py')
LAUNCHER = Path(__file__).with_name('isolation_launcher.py')


@dataclass(frozen=True)
class Limits:
    wall_seconds: float = 30
    output_bytes: int = 2 * 1024 * 1024
    memory_bytes: int = 2 * 1024 * 1024 * 1024
    file_bytes: int = 256 * 1024 * 1024
    cpu_seconds: int = 30

    def validate(self):
        if not math.isfinite(self.wall_seconds) or not 0 < self.wall_seconds <= 7200:
            raise ValueError('invalid wall limit')
        for value in (self.output_bytes, self.memory_bytes, self.file_bytes, self.cpu_seconds):
            if type(value) is not int or value <= 0:
                raise ValueError('limits must be positive integers')


def kill(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def capture(process, ready_fd, limits):
    started = time.monotonic()
    streams = {'stdout': bytearray(), 'stderr': bytearray(), 'ready': bytearray()}
    reason = None
    with selectors.DefaultSelector() as selector:
        for stream, name in ((process.stdout, 'stdout'), (process.stderr, 'stderr'), (ready_fd, 'ready')):
            fd = stream if isinstance(stream, int) else stream.fileno()
            os.set_blocking(fd, False)
            selector.register(fd, selectors.EVENT_READ, name)
        while selector.get_map():
            remaining = limits.wall_seconds - (time.monotonic() - started)
            if remaining <= 0:
                reason = 'timeout'
                break
            for key, _ in selector.select(min(remaining, 0.1)):
                data = os.read(key.fd, 65536)
                if not data:
                    selector.unregister(key.fd)
                    continue
                buffer = streams[key.data]
                capacity = 32 if key.data == 'ready' else limits.output_bytes - len(streams['stdout']) - len(streams['stderr'])
                buffer.extend(data[:max(0, capacity)])
                if len(data) > capacity:
                    reason = 'output-limit'
                    break
            if reason:
                break
    # PID 1 exiting terminates all processes in the private PID namespace.
    # --kill-child also ensures killing the unshare parent kills namespace PID 1.
    if reason:
        kill(process)
    try:
        process.wait(timeout=max(0.01, limits.wall_seconds - (time.monotonic() - started)))
    except subprocess.TimeoutExpired:
        reason = reason or 'timeout'
        kill(process)
        process.wait(timeout=5)
    return streams, reason


def run(work, argv, *, tools=None, cache=None, limits=None, input_bytes=b''):
    """Execute one candidate command; return raw bounded streams and measured status."""
    limits = limits or Limits()
    limits.validate()
    work = Path(work).resolve(strict=True)
    if not work.is_dir() or not argv or any(not isinstance(arg, str) or '\x00' in arg for arg in argv):
        raise ValueError('a work directory and nonempty argument vector are required')
    tools = tools or {}
    if any(not re.fullmatch('[a-z][a-z0-9_-]*', name) for name in tools):
        raise ValueError('tool names must be plain identifiers')
    tool_paths = {name: str(Path(path).resolve(strict=True)) for name, path in tools.items()}
    if not isinstance(input_bytes, bytes) or len(input_bytes) > limits.file_bytes:
        raise ValueError('invalid or oversized command input')
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='comparison-isolation-') as temporary:
        parent = Path(temporary)
        root = parent / 'root'
        root.mkdir()
        scratch = Path(cache).resolve(strict=True) if cache is not None else parent / 'cache'
        if cache is None:
            scratch.mkdir()
        if not scratch.is_dir():
            raise ValueError('cache must be a directory')
        ready_read, ready_write = os.pipe()
        config = {'root': str(root), 'work': str(work), 'cache': str(scratch),
                  'system_mounts': {path: str(Path(path).resolve(strict=True)) for path in SYSTEM_PATHS if Path(path).exists()},
                  'tools': tool_paths, 'argv': list(argv), 'ready_fd': ready_write,
                  'memory_bytes': limits.memory_bytes, 'file_bytes': limits.file_bytes,
                  'cpu_seconds': limits.cpu_seconds}
        command = [sys.executable, '-I', '-S', str(LAUNCHER), str(os.getpid()), '/usr/bin/unshare', '--user', '--map-root-user', '--mount', '--net',
                   '--pid', '--fork', '--kill-child', sys.executable, '-I', '-S',
                   str(BOOTSTRAP), json.dumps(config)]
        try:
            with tempfile.TemporaryFile() as stdin:
                stdin.write(input_bytes)
                stdin.seek(0)
                with subprocess.Popen(command, stdin=stdin, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, pass_fds=(ready_write,),
                                      start_new_session=True,
                                      env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}) as process:
                    os.close(ready_write)
                    ready_write = None
                    try:
                        streams, reason = capture(process, ready_read, limits)
                    finally:
                        if process.poll() is None:
                            kill(process)
                            process.wait(timeout=5)
        finally:
            os.close(ready_read)
            if ready_write is not None:
                os.close(ready_write)
    isolated = streams['ready'] == b'isolated\n'
    return {'version': 'comparison-execution-v1', 'isolated': isolated,
            'outcome': reason or ('exited' if isolated else 'isolation-failed'),
            'returncode': process.returncode, 'elapsed_seconds': time.monotonic() - started,
            'stdout': bytes(streams['stdout']), 'stderr': bytes(streams['stderr']),
            'argv': list(argv), 'system_mounts': config['system_mounts'], 'bootstrap_sha256': hashlib.sha256(BOOTSTRAP.read_bytes()).hexdigest(),
            'launcher_sha256': hashlib.sha256(LAUNCHER.read_bytes()).hexdigest(),
            'limits': limits.__dict__, 'resource_scope': 'per-process rlimits plus command wall/output bounds'}
