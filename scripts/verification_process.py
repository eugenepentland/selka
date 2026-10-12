"""Watch admitted, independently owned POSIX process groups without scheduling work."""
from __future__ import annotations

from dataclasses import dataclass
import math
import hashlib
import marshal
import sys
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
import threading
import queue
from typing import BinaryIO


def _positive(value: float, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be a positive finite number")
    return float(value)


@dataclass(frozen=True)
class ProcessLimits:
    timeout_seconds: float | None = None
    terminate_grace_seconds: float = 0.5

    def __post_init__(self):
        if self.timeout_seconds is not None:
            _positive(self.timeout_seconds, "timeout_seconds")
        _positive(self.terminate_grace_seconds, "terminate_grace_seconds")

    def execution_identity(self) -> dict:
        """Only execution controls belong to cache identity; targets live elsewhere."""
        return {"timeout_seconds": self.timeout_seconds,
                "terminate_grace_seconds": self.terminate_grace_seconds}


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    elapsed_seconds: float
    timed_out: bool = False
    cancelled: bool = False
    incomplete: bool = False

    @property
    def complete(self) -> bool:
        return not self.timed_out and not self.cancelled and not self.incomplete


class BoundedProcessLogs:
    """Drain PIPE output to separate capped files; optionally tee every byte live.

    File truncation is explicit in ``truncated``. Tee destinations are synchronous
    using a bounded asynchronous backlog; stalled tees cannot block execution.
    """
    def __init__(self, stdout_path: Path, stderr_path: Path, *, max_bytes: int = 8 * 1024 * 1024,
                 stdout_tee: BinaryIO | None = None, stderr_tee: BinaryIO | None = None):
        if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
            raise ValueError("max_bytes must be a positive integer")
        if Path(stdout_path).resolve() == Path(stderr_path).resolve():
            raise ValueError("stdout and stderr paths must differ")
        self.paths = (Path(stdout_path), Path(stderr_path))
        self.max_bytes = max_bytes
        self.tees = (stdout_tee, stderr_tee)
        self.truncated = [False, False]
        self.bytes_seen = [0, 0]
        self.capture_errors = []
        self._files = []
        self._selector = selectors.DefaultSelector()
        self._thread = None
        self._stop = threading.Event()
        self._error = None
        self.capture_complete = True
        self.capture_available = [False, False]
        self._tee_queues = [queue.Queue(maxsize=8), queue.Queue(maxsize=8)]
        self._tee_threads = []

    def attach(self, process):
        try:
            for index, stream in enumerate((process.stdout, process.stderr)):
                if stream is None:
                    raise ValueError("bounded logs require stdout=PIPE and stderr=PIPE")
                try:
                    file = self.paths[index].open("wb")
                    self.capture_available[index] = True
                except OSError as error:
                    self.capture_errors.append(str(error))
                    file = open(os.devnull, "wb")
                self._files.append(file)
                self._selector.register(stream, selectors.EVENT_READ, index)
        except BaseException:
            self.close()
            raise

    def start(self, process):
        """Begin capture immediately after Popen, including admission queue output."""
        self.attach(process)
        for index, tee in enumerate(self.tees):
            if tee is not None:
                try:
                    original_fd = tee.fileno()
                except (AttributeError, OSError, ValueError):
                    tee_fd = None
                else:
                    try:
                        # Snapshot the request destination before a retained session
                        # restores stdout to its JSONL protocol descriptor.
                        tee_fd = os.dup(original_fd)
                        os.set_inheritable(tee_fd, False)
                    except OSError as error:
                        self.capture_errors.append(str(error))
                        self.tees = tuple(None if item == index else sink for item, sink in enumerate(self.tees))
                        continue
                def tee_pump(index=index, tee=tee, tee_fd=tee_fd):
                    try:
                        while not self._stop.is_set() or not self._tee_queues[index].empty():
                            try:
                                chunk = self._tee_queues[index].get(timeout=0.02)
                            except queue.Empty:
                                continue
                            if tee_fd is None:
                                tee.write(chunk)
                                tee.flush()
                            else:
                                # Avoid holding Python buffered IO locks in a daemon
                                # if a real console pipe blocks through shutdown.
                                view = memoryview(chunk)
                                while view:
                                    view = view[os.write(tee_fd, view):]
                    except OSError as error:
                        self.capture_errors.append(str(error))
                    finally:
                        if tee_fd is not None:
                            os.close(tee_fd)
                thread = threading.Thread(target=tee_pump, daemon=True)
                thread.start()
                self._tee_threads.append((index, thread))
        def pump():
            try:
                while not self._stop.is_set() and self._selector.get_map():
                    self._drain(0.02)
            except BaseException as error:
                self._error = error
        self._thread = threading.Thread(target=pump, daemon=True)
        self._thread.start()

    def drain(self, seconds=0):
        if self._error is not None:
            raise self._error
        if self._thread is None:
            self._drain(seconds)
        elif seconds:
            time.sleep(seconds)

    def _drain(self, seconds=0):
        for key, _ in self._selector.select(seconds):
            data = os.read(key.fileobj.fileno(), 65536)
            if not data:
                self._selector.unregister(key.fileobj)
                continue
            index = key.data
            remaining = max(0, self.max_bytes - self.bytes_seen[index])
            try:
                self._files[index].write(data[:remaining])
            except OSError as error:
                if len(self.capture_errors) < 16:
                    self.capture_errors.append(str(error))
            self.bytes_seen[index] += len(data)
            self.truncated[index] = self.bytes_seen[index] > self.max_bytes
            if self.tees[index] is not None:
                try:
                    self._tee_queues[index].put_nowait(data)
                except queue.Full:
                    if len(self.capture_errors) < 16:
                        self.capture_errors.append("live tee backlog dropped; file capture retained")

    def close(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=0.25)
            if self._thread.is_alive():
                self.capture_complete = False
        for index, thread in self._tee_threads:
            thread.join(timeout=0.05)
            if thread.is_alive() and len(self.capture_errors) < 16:
                self.capture_errors.append("live tee did not finish; file capture retained")
        self._selector.close()
        for file in self._files:
            try:
                file.close()
            except OSError as error:
                if len(self.capture_errors) < 16:
                    self.capture_errors.append(str(error))


def _signal_group(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass


def _group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def _cleanup(process, grace, logs):
    # Do not stop escalating when the leader exits: grandchildren still own pipes
    # and admission resources. Only this separately created session is signalled.
    _signal_group(process.pid, signal.SIGTERM)
    until = time.monotonic() + grace
    while _group_exists(process.pid) and time.monotonic() < until:
        process.poll()
        if logs is not None:
            logs.drain(min(0.02, max(0, until - time.monotonic())))
        else:
            time.sleep(0.01)
    _signal_group(process.pid, signal.SIGKILL)
    process.wait()


def wait_owned(process: subprocess.Popen, *, limits: ProcessLimits = ProcessLimits(),
               execution_started: float | None = None, cancel_event=None,
               logs: BoundedProcessLogs | None = None) -> ProcessResult:
    """Wait after admission; timeout excludes queue time and returns status 124.

    The caller must launch with start_new_session=True and retain exclusive group
    ownership. Use run_supervised in the admitted child for detached descendants. Cancellation returns
    130; exceptions (including KeyboardInterrupt) clean up then propagate.
    ``execution_started`` is a monotonic timestamp at the admission handshake.
    Never publish success evidence for a result whose ``complete`` is false.
    """
    if not isinstance(limits, ProcessLimits):
        raise TypeError("limits must be ProcessLimits")
    started = time.monotonic() if execution_started is None else execution_started
    if isinstance(started, bool) or not isinstance(started, (int, float)) or not math.isfinite(started) or started > time.monotonic():
        raise ValueError("execution_started must be a past finite monotonic timestamp")
    try:
        if os.getpgid(process.pid) != process.pid or os.getsid(process.pid) != process.pid:
            raise ValueError("process must own an independent session")
    except ProcessLookupError:
        # Popen may already have exited; its dedicated group can still exist.
        pass
    timed_out = cancelled = False
    try:
        if logs is not None:
            if not logs._files:
                logs.start(process)
        while True:
            cancelled = cancel_event is not None and cancel_event.is_set()
            timed_out = limits.timeout_seconds is not None and time.monotonic() - started >= limits.timeout_seconds
            if cancelled or timed_out or process.poll() is not None:
                break
            if logs is not None:
                logs.drain(0.02)
            else:
                time.sleep(0.02)
        if _group_exists(process.pid):
            _cleanup(process, limits.terminate_grace_seconds, logs)
        else:
            process.wait()
        if logs is not None:
            # All writers in the owned group have been killed; drain buffered data.
            if logs._thread is not None:
                logs._thread.join(timeout=0.25)
                if logs._thread.is_alive():
                    logs.capture_complete = False
                    logs.capture_errors.append("output writer survived owned process group cleanup")
                logs.drain()
            else:
                drain_until = time.monotonic() + 0.25
                while logs._selector.get_map() and time.monotonic() < drain_until:
                    logs.drain(0.02)
                if logs._selector.get_map():
                    logs.capture_complete = False
        incomplete = process.returncode == 125
        return ProcessResult(130 if cancelled else 124 if timed_out else 125 if incomplete else process.returncode,
                             time.monotonic() - started, timed_out, cancelled, incomplete)
    except BaseException:
        _cleanup(process, limits.terminate_grace_seconds, None)
        raise
    finally:
        if logs is not None:
            logs.close()


def terminate_owned(process: subprocess.Popen, *, grace_seconds: float = 0.5):
    """Cancel a dedicated session during admission without starting a deadline."""
    _positive(grace_seconds, "grace_seconds")
    try:
        if os.getpgid(process.pid) != process.pid or os.getsid(process.pid) != process.pid:
            raise ValueError("process must own an independent session")
    except ProcessLookupError:
        pass
    _cleanup(process, grace_seconds, None)




def _process_starttime(pid):
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return int(stat[stat.rfind(")") + 2:].split()[19])
    except FileNotFoundError:
        return None


def arm_parent_death(parent_pid: int, parent_start: int) -> bool:
    """Arm Linux parent-death cancellation, then reject a lost/replaced parent.

    Call only in a fresh owned launcher, before handshake or work starts. The
    expected identity is wrapper-only metadata, never action environment/key
    data. Kernel cancellation closes the race after this identity check; checking
    after prctl closes the race where the parent died before registration.
    """
    if (type(parent_pid) is not int or parent_pid <= 1
        or type(parent_start) is not int or parent_start <= 0):
        raise ValueError('parent identity must contain positive PID and birth')
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return os.getppid() == parent_pid and _process_starttime(parent_pid) == parent_start


def _descendants(pid):
    """Snapshot all thread-owned descendants and their kernel birth identities."""
    result = {}
    pending = [pid]
    while pending:
        parent = pending.pop()
        try:
            tasks = list(Path(f"/proc/{parent}/task").iterdir())
        except FileNotFoundError:
            continue
        for task in tasks:
            try:
                children = (task / "children").read_text().split()
            except FileNotFoundError:
                continue
            for child in map(int, children):
                if child not in result:
                    birth = _process_starttime(child)
                    if birth is not None:
                        result[child] = birth
                        pending.append(child)
    return result


def _signal_identity(pid, birth, sig):
    """Pin a process with pidfd, verify birth, then signal that exact process."""
    try:
        descriptor = os.pidfd_open(pid)
    except ProcessLookupError:
        return
    try:
        if _process_starttime(pid) != birth:
            return
        signal.pidfd_send_signal(descriptor, sig)
    except ProcessLookupError:
        pass
    finally:
        os.close(descriptor)


def _kill_identity(pid, birth):
    _signal_identity(pid, birth, signal.SIGSTOP)
    _signal_identity(pid, birth, signal.SIGKILL)


def _close_lineage():
    """Freeze the complete lineage before killing; reaping reveals adopted children."""
    deadline = time.monotonic() + 0.3
    leftovers = _descendants(os.getpid())
    while leftovers and time.monotonic() < deadline:
        # Killing parents one at a time lets an unvisited child fork indefinitely.
        # Stop every discovered process, then include any child born during freeze.
        frozen = {}
        while leftovers != frozen and time.monotonic() < deadline:
            for pid, birth in leftovers.items():
                _signal_identity(pid, birth, signal.SIGSTOP)
            frozen = leftovers
            leftovers = _descendants(os.getpid())
        for pid, birth in leftovers.items():
            _signal_identity(pid, birth, signal.SIGKILL)
        _reap_adopted()
        leftovers = _descendants(os.getpid())
        if leftovers:
            time.sleep(0.005)
    return leftovers


def _reap_adopted():
    while True:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
            if pid == 0:
                return
        except ChildProcessError:
            return


def _run_lineage(argv: list[str], env: dict[str, str], restore_mask, parent_pid, parent_start) -> int:
    """Run inside the admitted child, retaining and reaping its entire lineage.

    Linux subreaping is enabled here only, never in the shared coordinator.
    Detached sessions remain descendants of this supervisor. A leftover child
    after the two-second natural closeout window makes a successful action
    incomplete (125). The closeout window counts against execution deadlines. SIGTERM/SIGINT
    cancellation yields 130. Parent watchdog grace must be at least 0.5 seconds.
    """
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    interrupted = False
    def interrupt(signum, frame):
        nonlocal interrupted
        interrupted = True
    previous = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGTERM, signal.SIGINT)}
    worker = None
    try:
        # Pending fork-window cancellation reaches this handler before work starts.
        parent_alive = arm_parent_death(parent_pid, parent_start)
        signal.pthread_sigmask(signal.SIG_SETMASK, restore_mask)
        if interrupted or not parent_alive:
            return 130
        worker = subprocess.Popen(argv, env=env, close_fds=False)
        while worker.poll() is None and not interrupted:
            time.sleep(0.01)
        status = worker.poll()
        _reap_adopted()
        leftovers = _descendants(os.getpid())
        # Known build cleanup helpers poll their former parent once per second.
        # Their closeout is execution: the outer watchdog remains active here.
        natural_drain_until = time.monotonic() + 2.0
        while leftovers and not interrupted and time.monotonic() < natural_drain_until:
            time.sleep(0.01)
            _reap_adopted()
            leftovers = _descendants(os.getpid())
        incomplete = status is not None and bool(leftovers)
        leftovers = _close_lineage()
        if worker.returncode is None:
            # waitpid above may have reaped it; preserve only incomplete status.
            worker.poll()
        if leftovers:
            return 125
        if interrupted:
            return 130
        if incomplete and status == 0:
            return 125
        return 128 - status if status < 0 else status
    finally:
        # An exception must not orphan a detached worker or publish completion.
        _close_lineage()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def run_supervised(argv: list[str], env: dict[str, str]) -> int:
    """Isolate admitted work in a subreaper with no inherited child ownership.

    The outer launcher may already own admission helpers. Their later children
    belong to that launcher, including after their parent exits. A dedicated
    inner process owns only the action lineage, so cleanup cannot mistake these
    helpers for action children. Admission descriptors remain inherited.
    Call in the fresh admitted launcher, never in a multithreaded coordinator.
    Kernel parent-death cancellation covers a hard coordinator/launcher crash.
    The parent watchdog must allow at least 0.5 seconds for lineage cleanup.
    """
    parent_pid = os.getppid()
    parent_start = _process_starttime(parent_pid)
    own_pid = os.getpid()
    own_start = _process_starttime(own_pid)
    interrupted = False
    child = None
    def interrupt(signum, frame):
        nonlocal interrupted
        interrupted = True
        if child is not None and child != 0:
            try:
                os.kill(child, signum)
            except ProcessLookupError:
                pass
    previous = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGTERM, signal.SIGINT)}
    restore_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
    try:
        if parent_start is None or not arm_parent_death(parent_pid, parent_start):
            return 130
        child = os.fork()
        if child == 0:
            try:
                status = 130 if interrupted else _run_lineage(argv, env, restore_mask, own_pid, own_start)
            except BaseException:
                status = 125
            os._exit(status)
        signal.pthread_sigmask(signal.SIG_SETMASK, restore_mask)
        while True:
            pid, status = os.waitpid(child, 0)
            if pid == child:
                result = os.waitstatus_to_exitcode(status)
                return 130 if interrupted else 128 - result if result < 0 else result
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, restore_mask)
        for sig, handler in previous.items():
            signal.signal(sig, handler)


LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
