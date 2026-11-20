"""Watch admitted, independently owned POSIX process groups without scheduling work."""
from __future__ import annotations

from dataclasses import dataclass
import math
import hashlib
if __package__:
    from . import verification_code_identity as code_identity
else:
    import verification_code_identity as code_identity
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


# How many leftovers a 125 lists before it says how many more there are.
MAX_REPORTED_LEFTOVERS = 8
# Exported to everything a supervised action starts: the directory it runs in. `scripts/worktree_cache_trim.py` reads
# it (the name is repeated there, which cannot import this module) and leaves that directory's caches alone.
SUPERVISED_ROOT = "SELKA_ADMISSION_SUPERVISED"


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
    stopped: bool = False

    @property
    def complete(self) -> bool:
        return not self.timed_out and not self.cancelled and not self.incomplete and not self.stopped


# A step of a gate that fails leaves a beacon, `fail-fast.<name>.txt`, in the gate's telemetry directory: the text a build log would
# show for that step (its `error:` line, what it printed, and the `failed command:` line), written whole and moved into place, so a
# reader never sees half of one. A name that starts with a dot is a beacon still being written. The pinned build runner prints every
# failure only when the whole build is over; this is how the coordinator learns of the first one while the rest still runs.
FAIL_FAST_PREFIX = "fail-fast."
FAIL_FAST_SUFFIX = ".txt"
FAIL_FAST_MAX_BEACONS = 4
FAIL_FAST_MAX_BYTES = 64 * 1024
FAIL_FAST_STATUS = 1


class FailFast:
    """Says once that a step of the running gate has failed; `wait_owned` and `run_admitted` take it as `stop`.

    Calling it polls the telemetry directory for beacons at most every `interval` seconds and stays true from the first one. The names
    seen at that first look are the failures it reports (`log_text`): a step killed by the stop that then wrote a beacon of its own is
    not a second failure. `killed` is set by `run_admitted` when it stopped the build because of this watch.
    """

    def __init__(self, directory, interval: float = 0.2, clock=time.monotonic, *, defer=None, limit: int = 0):
        self.directory = None if directory is None else Path(directory)
        self.interval = interval
        self.clock = clock
        self.checked_at = None
        self.triggered_at = None
        self.names: list[str] = []
        self.killed = False
        # `defer(text)` says whether a beacon's failure may wait for the flaky rerun (a named test, item 4d): while every
        # beacon may and there are at most `limit`, the build runs on; anything else stops it as before.
        self.defer = defer
        self.limit = limit
        self.deferred: list[str] = []

    def __call__(self) -> bool:
        if self.triggered_at is not None:
            return True
        if self.directory is None:
            return False
        now = self.clock()
        if self.checked_at is not None and now - self.checked_at < self.interval:
            return False
        self.checked_at = now
        try:
            names = sorted(entry.name for entry in self.directory.iterdir()
                           if entry.name.startswith(FAIL_FAST_PREFIX) and entry.name.endswith(FAIL_FAST_SUFFIX))
        except OSError:
            return False
        if not names:
            return False
        if self.defer is not None and len(names) <= self.limit:
            texts = []
            for name in names:
                try:
                    texts.append((self.directory / name).read_text(errors="replace")[-FAIL_FAST_MAX_BYTES:])
                except OSError:
                    texts.append("")
            if all(self.defer(text) for text in texts):
                self.deferred = names
                return False
        self.names = names[:FAIL_FAST_MAX_BEACONS]
        self.triggered_at = now
        return True

    def log_text(self) -> str:
        """The beacons seen first, as the failure blocks of a build log (each at most `FAIL_FAST_MAX_BYTES` of its end)."""
        blocks = []
        for name in self.names:
            try:
                data = (self.directory / name).read_bytes()[-FAIL_FAST_MAX_BYTES:]
            except OSError:
                continue
            blocks.append(data.decode("utf-8", "replace").rstrip("\n"))
        return "\n".join(blocks) + ("\n" if blocks else "")


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
               logs: BoundedProcessLogs | None = None, heartbeat=None, stop=None) -> ProcessResult:
    """Wait after admission; timeout excludes queue time and returns status 124.

    The caller must launch with start_new_session=True and retain exclusive group
    ownership. Use run_supervised in the admitted child for detached descendants. Cancellation returns
    130; exceptions (including KeyboardInterrupt) clean up then propagate.
    ``execution_started`` is a monotonic timestamp at the admission handshake.
    Never publish success evidence for a result whose ``complete`` is false.
    ``heartbeat`` may drain retained input watches; failures clean up the child.
    ``stop``, a callable polled with the heartbeat, ends a child that is still running the first time it returns true: the group is
    cleaned up like a timeout's and the result is status `FAIL_FAST_STATUS`, ``stopped`` and not complete.
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
    timed_out = cancelled = stopped = False
    try:
        if logs is not None:
            if not logs._files:
                logs.start(process)
        while True:
            if heartbeat is not None:
                heartbeat()
            cancelled = cancel_event is not None and cancel_event.is_set()
            timed_out = limits.timeout_seconds is not None and time.monotonic() - started >= limits.timeout_seconds
            if cancelled or timed_out or process.poll() is not None:
                break
            stopped = stop is not None and stop()
            if stopped:
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
        incomplete = process.returncode == 125 and not stopped
        return ProcessResult(130 if cancelled else 124 if timed_out else FAIL_FAST_STATUS if stopped
                             else 125 if incomplete else process.returncode,
                             time.monotonic() - started, timed_out, cancelled, incomplete, stopped)
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
    """The kernel birth of `pid`, or None once the process is gone.

    A process leaving fails its /proc entry two ways: ENOENT when the entry is already gone at open, and ESRCH when
    the process goes between the open and the read. Both mean it is gone, not that something is wrong.
    """
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return int(stat[stat.rfind(")") + 2:].split()[19])
    except (FileNotFoundError, ProcessLookupError):
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
            except (FileNotFoundError, ProcessLookupError):
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


KILLED_DRAIN_SECONDS = 60.0  # how long a process that was sent SIGKILL may take to die (disk wait) before it "survived"
# The natural closeout: how long what an action left behind may take to finish by itself before the action is incomplete.
# The window counts only time in which no leftover can run. A helper that ends within a second on a calm machine (the
# shadow observer of an admission, a cache cleaner polling its parent) is runnable, or in disk wait, for as long as the
# machine keeps it from running, and a wall-clock window is crossed by load: at load 27, with the disk saturated, a
# helper in state D was called a leftover 14.9 s after it started and ended an action 125 (15 November, the nightly).
NATURAL_DRAIN_SECONDS = 2.0
# The most the natural closeout stretches for leftovers that cannot run, counted from the end of the action: a helper that
# is still runnable after this long is a runaway, not a slow exit. It is the bound KILLED_DRAIN_SECONDS already gives a
# killed process in disk wait.
NATURAL_DRAIN_CEILING_SECONDS = 60.0


def _await_killed(leftovers, seconds=None, *, descendants=None, reap=None, kill=None, clock=time.monotonic,
                  sleep=time.sleep):
    """Wait for processes that were sent SIGKILL to die, at most `seconds` (KILLED_DRAIN_SECONDS). A process in disk wait
    (state D) cannot act on the signal until its I/O completes: under a saturated disk that took minutes on 13 November,
    and the 0.3 s of `_close_lineage` called it a survivor. Signals again whatever is still there, reaps, and returns
    what is still alive at the end (a process that never dies stays a finding)."""
    seconds = KILLED_DRAIN_SECONDS if seconds is None else seconds
    descendants = descendants or (lambda: _descendants(os.getpid()))
    reap = reap or _reap_adopted
    kill = kill or _kill_identity
    deadline = clock() + seconds
    while leftovers and clock() < deadline:
        for pid, birth in leftovers.items():
            kill(pid, birth)
        sleep(0.05)
        reap()
        leftovers = descendants()
    return leftovers


def _held_up(leftovers):
    """Whether any of `leftovers` is runnable (R) or in disk wait (D): the machine, not the process, is what it waits for.
    A leftover that sleeps (S) or is stopped has nothing load could be holding up; one that has gone counts as not held."""
    for pid in leftovers:
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
        except OSError:
            continue
        if stat[stat.rfind(")") + 2:stat.rfind(")") + 3] in ("R", "D"):
            return True
    return False


def _boot_time():
    """Seconds since the epoch at which the kernel booted, or None; /proc start times count from it."""
    try:
        for line in Path("/proc/stat").read_text().splitlines():
            if line.startswith("btime "):
                return int(line.split()[1])
    except (OSError, ValueError):
        pass
    return None


def _describe(pid):
    """One leftover for the diagnostic: who it is, where it came from and for how long it has been running.

    Everything is read from /proc at the moment of the report; a process that is gone by then says so.
    """
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        fields = stat[stat.rfind(")") + 2:].split()
        state, ppid, session, ticks = fields[0], fields[1], fields[3], int(fields[19])
    except (OSError, IndexError, ValueError):
        return f"pid={pid} (gone before it could be described)"
    comm = stat[stat.find("(") + 1:stat.rfind(")")]
    try:
        argv = [item.decode(errors="replace") for item in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if item]
    except OSError:
        argv = []
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = "?"
    started = "?"
    boot = _boot_time()
    if boot is not None:
        begun = boot + ticks / os.sysconf("SC_CLK_TCK")
        started = time.strftime("%H:%M:%SZ", time.gmtime(begun)) + f" age={time.time() - begun:.1f}s"
    return (f"pid={pid} ppid={ppid} sid={session} state={state} started={started} cwd={cwd} "
            f"cmd={' '.join(argv)[:300] if argv else '[' + comm + ']'}")


def _report_leftovers(leftovers, outcome="outlived the closeout"):
    """Say what outlived the closeout. A status of 125 alone names no process and leaves nothing to find in the log.

    One line per leftover, each starting `supervisor: leftover`, so the gate summary can print them as the failure.
    """
    listed = sorted(leftovers)[:MAX_REPORTED_LEFTOVERS]
    print(f"supervisor: {len(leftovers)} descendant(s) {outcome}", file=sys.stderr)
    for pid in listed:
        print(f"supervisor: leftover {_describe(pid)}", file=sys.stderr)
    if len(leftovers) > len(listed):
        print(f"supervisor: leftover ... and {len(leftovers) - len(listed)} more", file=sys.stderr)
    sys.stderr.flush()


def _report_failure(error):
    """One `supervisor:` line for an exception that ended the supervisor, then its traceback."""
    import traceback
    frame = traceback.extract_tb(error.__traceback__)[-1:] or [None]
    where = f" at {Path(frame[0].filename).name}:{frame[0].lineno} in {frame[0].name}" if frame[0] else ""
    print(f"supervisor: failed with {type(error).__name__}: {error}{where}; the action ends 125", file=sys.stderr)
    traceback.print_exception(error, file=sys.stderr)
    sys.stderr.flush()


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
    after the natural closeout window (NATURAL_DRAIN_SECONDS of a leftover that could run and did not, up to
    NATURAL_DRAIN_CEILING_SECONDS) makes a successful action
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
        # The work knows it is supervised, and where: an admission it starts for its own worktree must not run cache
        # maintenance whose background deletions this supervisor would count as leftovers and kill half-done.
        worker = subprocess.Popen(argv, env=dict(env, **{SUPERVISED_ROOT: os.path.realpath(os.getcwd())}), close_fds=False)
        while worker.poll() is None and not interrupted:
            time.sleep(0.01)
        status = worker.poll()
        _reap_adopted()
        leftovers = _descendants(os.getpid())
        # Known build cleanup helpers poll their former parent once per second.
        # Their closeout is execution: the outer watchdog remains active here.
        natural_began = time.monotonic()
        natural_drain_until = natural_began + NATURAL_DRAIN_SECONDS
        while leftovers and not interrupted and time.monotonic() < natural_drain_until:
            time.sleep(0.01)
            _reap_adopted()
            leftovers = _descendants(os.getpid())
            if _held_up(leftovers):
                # Runnable or in disk wait: the window starts again, up to the ceiling. It ends NATURAL_DRAIN_SECONDS
                # after the last time any leftover could not run for want of the machine.
                natural_drain_until = min(max(natural_drain_until, time.monotonic() + NATURAL_DRAIN_SECONDS),
                                          natural_began + NATURAL_DRAIN_CEILING_SECONDS)
        incomplete = status is not None and bool(leftovers)
        if incomplete and not interrupted:
            _report_leftovers(leftovers)
        leftovers = _close_lineage()
        if leftovers:
            # Killed but not yet dead: allow a process in disk wait to finish dying before calling it a survivor.
            began = time.monotonic()
            slow = len(leftovers)
            leftovers = _await_killed(leftovers)
            if not leftovers:
                print(f"supervision note: {slow} killed descendant(s) took {time.monotonic() - began:.1f} s to die "
                      "(disk wait); not survivors", file=sys.stderr, flush=True)
        if worker.returncode is None:
            # waitpid above may have reaped it; preserve only incomplete status.
            worker.poll()
        if leftovers:
            _report_leftovers(leftovers, "survived being killed")
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
            except BaseException as error:
                # The other way to end 125: the supervisor itself failed. Say so, with where, or the log names nothing.
                _report_failure(error)
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


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
