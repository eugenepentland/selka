#!/usr/bin/env python3
"""The compiler watch loop an agent can block on (lane DL-3 part 2; docs/tooling/development-loop.md).

    python3 scripts/dev_loop.py start              start this worktree's watcher and build once
    python3 scripts/dev_loop.py wait               block until a build that holds the newest edit has finished
    python3 scripts/dev_loop.py test ROOT FILTER   wait, then run units|core|cli tests matching FILTER; compiles nothing
    python3 scripts/dev_loop.py stop               end the watcher (it also ends after twenty idle minutes)
    python3 scripts/dev_loop.py status             what the watcher is doing
    python3 scripts/dev_loop.py compare [--all] [--roots units,core,cli,lang]
                                                   watch-built against normal binaries, verdicts by test name
                                                   (the edit check's selection; --all: every test)

`start` launches `scripts/build-slot.sh watch python3 scripts/dev_loop.py --daemon` detached: the daemon is the
process the wrapper execs, so it holds a watch slot (no build slot) for its life. The daemon runs
`zig build --watch -fincremental -Dwatch-identity=true install unit-test-binary core-test-binary cli-test-binary`
(the Maker) in a process group of its own and keeps it frozen (SIGSTOP) except while a `wait` holds an ordinary build
admission, so every build is a build to the slots, the memory rule and a timing request. The lock order is one for
everyone: thaw before ticket before slot. The daemon takes `.selka-cache/dev-loop/thaw.lock` exclusively, then its
ticket and slot (`build_admission.admission('build')`, whose helper process holds the slot), then continues the Maker.

The Maker is frozen only at a verified idle: its main thread blocked in `poll` with no timeout on fanotify
descriptors only (`/proc/PID/syscall`, the pollfd array read from `/proc/PID/mem`). The first build checks that
signature: busy during the build and idle after it. Otherwise one line says so and the daemon runs without freezing,
holding its build slot as a watcher did before (`no-freeze`). The signature is qualified for the pinned Zig
(`QUALIFIED_ZIG`); a test fails when `.zigversion` moves.

`wait` snapshots the build inputs (path, size, mtime, ctime and inode of every file under `src`, `test` and `selfhost`,
and the build files) and accepts the first build summary after the thaw whose end snapshot equals the snapshot at the
end of the build before it: no build after a thaw started before it, builds run one at a time, and a change during a
build fails the equality, for which Zig builds again. So the build the watch triggers by itself (the live identity run
rewrites `identity.zig`) is never taken for the edit's: it starts after the accepted one. A change that starts no build
(outside the build graph) leaves the last result standing once the Maker has been idle for `QUIET_SECONDS`.
"""
import argparse
import contextlib
import ctypes
import fcntl
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import build_admission  # noqa: E402  (ordinary build admissions for the watcher's builds)
import failure_report  # noqa: E402  (what a test run prints: the failing tests only)
import worktree_cache_trim  # noqa: E402  (the coordinator lock: a gate is running)

# The Zig whose Maker's idle signature was qualified (13 November 2026). A pin change re-qualifies it.
QUALIFIED_ZIG = "0.17.1"
STATE = Path(".selka-cache/dev-loop")
STEPS = ("install", "unit-test-binary", "core-test-binary", "cli-test-binary")
BINARIES = {"units": "unit-tests", "core": "core-tests", "cli": "cli-tests"}
INSTALLED = ("zig-out/bin/selka", "zig-out/focus/unit-tests", "zig-out/focus/core-tests", "zig-out/focus/cli-tests")
INPUT_DIRS = ("src", "test", "selfhost")


def setting(name, default):
    """A duration or count the tests shorten; seconds as a float."""
    return float(os.environ.get(name, default))


# A daemon with no request for this long stops itself: lanes are agents that can end without `stop`.
IDLE_STOP_SECONDS = 1200
# While frozen, MemAvailable is looked at about once a minute; below the gate's own requirement (SELKA_GATE_MEM, the
# admission scripts' default 6G) for a minute, the Maker is stopped to free its memory; the next `wait` restarts it.
MEMORY_CHECK_SECONDS = 60
MEMORY_GRACE_SECONDS = 60
# After a thaw with no build summary, an idle Maker for this long means the change started no build.
QUIET_SECONDS = 1.0
# How long a plain `zig build` may hold the thaw lock shared before a `wait` gives up, as the wrapper's own bound.
THAW_WAIT_SECONDS = 600
# The most a `wait` waits for its build.
WAIT_SECONDS = 1800
# A snapshot with more changed files than this, or a moved HEAD, restarts the Maker: fanotify's queue can overflow.
RESTART_CHANGED_FILES = 1000
# How long a `wait` waits for a process running one of the watch's products to end before it refuses.
BUSY_WAIT_SECONDS = 60
# A child the Maker leaves a zombie this long means a compile server exited and the Maker is stuck.
WEDGE_SECONDS = 10
# How long after an answer the daemon tries to freeze the Maker before it stops it and gives its locks back.
FREEZE_SECONDS = 300
# A Maker whose process tree used no CPU this long while a build was awaited is stuck. The time counts only while every
# thread of the tree sleeps: a thread that is runnable or in disk wait is held up by the machine, not stuck, and starts
# the clock again (a Maker frozen for minutes, its pages swapped out, was stopped as "stalled" on 15 November when its
# first page-ins took 2 s at load 27: no CPU was used, and nothing was wrong).
STALL_SECONDS = 30
# The most one look at the Maker counts toward a stall or a wedge. The daemon looks every SAMPLE_SECONDS; a gap longer than
# this means the daemon itself was not running (starved, in disk wait), and a daemon that could not look for a minute did
# not see the Maker be quiet for that minute.
QUIET_STEP_SECONDS = 0.5
# The process tree is read at most this often: a tree of compilers has hundreds of threads.
TREE_LOOK_SECONDS = 0.1
MAX_LINES = 20
# A Unix socket's path, terminating zero included, fits in 108 bytes.
SOCKET_PATH_LIMIT = 108
# The parts of a build record the daemon keeps to itself: input snapshots, thousands of entries each.
PRIVATE = ("snapshot", "end_snapshot", "follow_snapshot")
SAMPLE_SECONDS = 0.02
ERROR = re.compile(r"^(\S+:\d+:\d+): error: (.*)$")
SUMMARY = re.compile(r"Build Summary: (\d+)/(\d+) steps succeeded(?: \((\d+) failed\))?")
IMPORT = re.compile(r'@import\("([^"]+\.(?:zig|zon))"\)')


def now():
    return time.monotonic()


# ----------------------------------------------------------------------------------------------------------- inputs

def snapshot(worktree):
    """The build inputs as a dict path -> (size, mtime_ns, ctime_ns, inode): every file under INPUT_DIRS and the build
    files at the root. Statting 2,100 files takes about 10 ms."""
    entries = {}
    for directory in INPUT_DIRS:
        for root, dirs, files in os.walk(worktree / directory):
            dirs[:] = [name for name in dirs if not name.startswith(".zig-cache")]
            for name in files:
                path = os.path.join(root, name)
                try:
                    status = os.lstat(path)
                except OSError:
                    continue
                entries[path] = (status.st_size, status.st_mtime_ns, status.st_ctime_ns, status.st_ino)
    for path in configure_inputs(worktree):
        try:
            status = os.lstat(path)
        except OSError:
            continue
        entries[str(path)] = (status.st_size, status.st_mtime_ns, status.st_ctime_ns, status.st_ino)
    return entries


def configure_inputs(worktree):
    """The files the configure phase reads, which watch mode never reads again: the root build files and the Zig and
    ZON files they import, transitively."""
    found = set()
    pending = [path for path in worktree.glob("build*.zig")] + [worktree / "build.zig.zon", worktree / ".zigversion"]
    while pending:
        path = pending.pop()
        if path in found or not path.is_file():
            continue
        found.add(path)
        if path.suffix == ".zig":
            try:
                text = path.read_text(errors="replace")
            except OSError:
                continue
            for name in IMPORT.findall(text):
                pending.append((path.parent / name).resolve())
    return sorted(found)


def configure_digest(worktree):
    """The configure inputs' bytes, digested: a change means the Maker must restart."""
    import hashlib
    digest = hashlib.sha256()
    for path in configure_inputs(worktree):
        digest.update(str(path).encode() + b"\0")
        try:
            digest.update(path.read_bytes())
        except OSError:
            pass
    return digest.hexdigest()


def head(worktree):
    completed = subprocess.run(["git", "-C", str(worktree), "rev-parse", "HEAD"], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
    return completed.stdout.strip() if completed.returncode == 0 else ""


def changed(before, after):
    """How many paths differ between two snapshots."""
    return sum(1 for path in before.keys() | after.keys() if before.get(path) != after.get(path))


# ---------------------------------------------------------------------------------------------------- the Maker

def maker_state(pid):
    """`idle` when the Maker's main thread waits in `poll` with no timeout on fanotify descriptors only, `debounce`
    when it waits there with a timeout, `busy` otherwise, and `unknown` when the kernel will not say."""
    try:
        fields = Path(f"/proc/{pid}/syscall").read_text().split()
    except OSError:
        return "unknown"
    if fields and fields[0] == "219":
        # restart_syscall: a poll interrupted by the freeze resumes through it, and its arguments are gone.
        return "restart"
    if not fields or fields[0] != "7" or len(fields) < 4:
        return "busy" if fields else "unknown"
    pointer, count, timeout = (int(value, 16) for value in fields[1:4])
    if count == 0 or count > 64:
        return "busy"
    try:
        with open(f"/proc/{pid}/mem", "rb") as memory:
            memory.seek(pointer)
            data = memory.read(8 * count)
    except (OSError, ValueError, OverflowError):
        return "unknown"
    if len(data) != 8 * count:
        return "unknown"
    for index in range(count):
        descriptor = struct.unpack_from("<i", data, 8 * index)[0]
        try:
            if os.readlink(f"/proc/{pid}/fd/{descriptor}") != "anon_inode:[fanotify]":
                return "busy"
        except OSError:
            return "busy"
    return "idle" if timeout & 0xFFFFFFFF == 0xFFFFFFFF else "debounce"


def stopped(pid):
    try:
        text = Path(f"/proc/{pid}/stat").read_text()
    except OSError:
        return True
    return text.rsplit(")", 1)[1].split()[0] in ("T", "t", "Z", "X")


def tree_rss(pid):
    """Resident bytes of a process and its descendants."""
    total = 0
    pending = [pid]
    while pending:
        current = pending.pop()
        try:
            for line in Path(f"/proc/{current}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1]) * 1024
            for task in os.listdir(f"/proc/{current}/task"):
                pending.extend(int(child) for child in Path(f"/proc/{current}/task/{task}/children").read_text().split())
        except (OSError, ValueError):
            continue
    return total


class Maker:
    """The watched `zig build` in a process group of its own, its output read and timestamped by a thread."""

    def __init__(self, worktree, log):
        self.worktree = worktree
        self.log = log
        self.summaries = []
        self.condition = threading.Condition()
        self.pending_errors = []
        self.ended = None
        override = os.environ.get("SELKA_DEV_LOOP_MAKER")
        if override:
            argv = json.loads(override)
        else:
            zig = os.environ.get("ZIG") or "zig"
            argv = [zig, "build", "--watch", "-fincremental", "-Dwatch-identity=true", *STEPS, "--summary", "all"]
        # Started from the daemon's main thread through a fresh interpreter that sets the parent-death signal before
        # it execs, so the Maker dies with the daemon; its own group lets the daemon freeze it and its compilers.
        self.process = subprocess.Popen(
            [sys.executable, "-B", str(Path(__file__).resolve()), "--exec-guard", str(os.getpid()), *argv],
            cwd=worktree, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            process_group=0)
        self.pid = self.process.pid
        self.frozen = False
        self.resumed_idle = False
        self.started = now()
        self.reaped = False
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.watch_exit, daemon=True).start()

    def read(self):
        for raw in self.process.stdout:
            line = raw.decode(errors="replace").rstrip("\n")
            stamp = now()
            self.resumed_idle = False
            self.log.write("%.3f %s\n" % (time.time(), line))
            self.log.flush()
            text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\([0B]", "", line)
            match = ERROR.match(text)
            if match:
                self.pending_errors.append([match.group(1) + ": error: " + match.group(2)])
            elif text.startswith("error: ") and not text.startswith(("error: process exited", "error: the following")) \
                    and "compilation errors" not in text:
                # A step that failed without a source location (a linker's FileBusy, say): its own line.
                self.pending_errors.append([text.strip(), ""])
            elif self.pending_errors and len(self.pending_errors[-1]) == 1 and text.strip() and \
                    not text.startswith(("error:", "failed command")):
                self.pending_errors[-1].append(text.rstrip())
            summary = SUMMARY.search(text)
            if summary:
                ended = snapshot(self.worktree)
                with self.condition:
                    failed = int(summary.group(3) or 0)
                    self.summaries.append(dict(index=len(self.summaries) + 1, end=stamp, failed=failed,
                                               text=text.strip(), errors=self.pending_errors, end_snapshot=ended))
                    self.pending_errors = []
                    self.condition.notify_all()

    def watch_exit(self):
        """Learn of the Maker's exit without reaping it (WNOWAIT): until `stop` reaps it, its process id and so its
        group id stay its own, so no signal the daemon sends later can reach another session's processes."""
        try:
            info = os.waitid(os.P_PID, self.pid, os.WEXITED | os.WNOWAIT)
            status = info.si_status if info is not None else None
        except ChildProcessError:
            status = None
        with self.condition:
            self.ended = status if status is not None else -1
            self.condition.notify_all()

    def alive(self):
        return self.ended is None

    def wedged(self):
        """The pid of a child the Maker has left a zombie for WEDGE_SECONDS (a compile server that exited, which
        the Maker then waits for for ever), else 0. A zombie's age counts only the looks at which the Maker's whole tree
        slept (QUIET_STEP_SECONDS at most each): a Maker held up by the machine, runnable or in disk wait, has not
        reaped it yet and may in the next moment."""
        zombies = set()
        try:
            for task in os.listdir(f"/proc/{self.pid}/task"):
                for child in Path(f"/proc/{self.pid}/task/{task}/children").read_text().split():
                    with contextlib.suppress(OSError):
                        if Path(f"/proc/{child}/stat").read_text().rsplit(")", 1)[1].split()[0] == "Z":
                            zombies.add(int(child))
        except OSError:
            return 0
        _ticks, awake = self.sample_tree()
        stamp = now()
        step = min(stamp - getattr(self, "zombie_looked", stamp), QUIET_STEP_SECONDS)
        self.zombie_looked = stamp
        seen = getattr(self, "zombies", {})
        self.zombies = {pid: 0.0 if awake else seen.get(pid, 0.0) + step for pid in zombies}
        limit = setting("SELKA_DEV_LOOP_WEDGE_SECONDS", WEDGE_SECONDS)
        return next((pid for pid, age in self.zombies.items() if age >= limit), 0)

    def sample_tree(self):
        """(CPU ticks the Maker's whole process tree has used, whether any thread of it is awake: runnable, in disk wait or
        stopped). One walk of /proc, repeated at most every TREE_LOOK_SECONDS."""
        stamp = now()
        looked = getattr(self, "tree_looked", None)
        if looked is not None and stamp - looked < TREE_LOOK_SECONDS:
            return self.tree_sample
        ticks, awake = 0, False
        pending = [self.pid]
        while pending:
            current = pending.pop()
            try:
                fields = Path(f"/proc/{current}/stat").read_text().rsplit(")", 1)[1].split()
                ticks += int(fields[11]) + int(fields[12])
                for task in os.listdir(f"/proc/{current}/task"):
                    if not awake:
                        with contextlib.suppress(OSError, IndexError):
                            state = Path(f"/proc/{current}/task/{task}/stat").read_text().rsplit(")", 1)[1].split()[0]
                            awake = state in ("R", "D", "T", "t")
                    pending.extend(int(c) for c in Path(f"/proc/{current}/task/{task}/children").read_text().split())
            except (OSError, ValueError, IndexError):
                continue
        self.tree_looked, self.tree_sample = stamp, (ticks, awake)
        return self.tree_sample

    def thread_states(self):
        """Every thread of the Maker's process tree: pid, tid, command, state and /proc syscall line (the daemon is
        their ancestor, so it may read them), for the record of a stall."""
        found = []
        pending = [self.pid]
        while pending:
            current = pending.pop()
            try:
                command = Path(f"/proc/{current}/cmdline").read_bytes().split(b"\0")
                name = " ".join(part.decode(errors="replace") for part in command[:3])[:120]
                for task in os.listdir(f"/proc/{current}/task"):
                    with contextlib.suppress(OSError):
                        state = Path(f"/proc/{current}/task/{task}/stat").read_text().rsplit(")", 1)[1].split()[0]
                        call = Path(f"/proc/{current}/task/{task}/syscall").read_text().split()[:4]
                        found.append([current, int(task), name, state, " ".join(call)])
                    pending.extend(int(c) for c in Path(f"/proc/{current}/task/{task}/children").read_text().split())
            except (OSError, ValueError):
                continue
        return found

    def stalled(self, counting=True):
        """Whether the Maker's whole process tree has been quiet for STALL_SECONDS while a build was awaited: no CPU used and
        every thread asleep, a real build never is, and twice on 13 November a Maker waited for its compilers for ever after
        a product had run. Time is counted look by look (QUIET_STEP_SECONDS at most each), and it starts again whenever the
        tree used CPU, a thread was runnable, in disk wait or stopped, or COUNTING is false (no build is awaited): load
        makes processes wait to run or for the disk, and never makes a stuck Maker's threads anything but asleep."""
        ticks, awake = self.sample_tree()
        stamp = now()
        looked = getattr(self, "quiet_looked", None)
        self.quiet_looked = stamp
        if not counting or awake or looked is None or ticks != getattr(self, "last_ticks", None):
            self.last_ticks, self.quiet = ticks, 0.0
            return False
        self.quiet += min(stamp - looked, QUIET_STEP_SECONDS)
        return self.quiet >= setting("SELKA_DEV_LOOP_STALL_SECONDS", STALL_SECONDS)

    def state(self):
        """maker_state, with `restart` read as idle while the Maker has printed nothing since it was continued from a
        verified idle: its poll on fanotify resumes through restart_syscall, whose arguments cannot be checked."""
        state = maker_state(self.pid)
        if state == "restart":
            return "idle" if self.resumed_idle else "busy"
        return state

    def signal(self, number):
        if self.reaped:
            return
        try:
            os.killpg(self.pid, number)
        except ProcessLookupError:
            pass

    def freeze_if_idle(self):
        """Stop the group only at a verified idle; whether it is frozen now."""
        if self.state() != "idle":
            return False
        self.signal(signal.SIGSTOP)
        deadline = now() + 2
        while not stopped(self.pid) and now() < deadline:
            time.sleep(0.002)
        if stopped(self.pid) and self.state() == "idle":
            self.frozen = True
            return True
        self.signal(signal.SIGCONT)
        return False

    def thaw(self):
        # The stall clock starts again: frozen, the Maker used no CPU, which is no stall.
        self.last_ticks = None
        self.quiet_looked = None
        self.tree_looked = None
        self.resumed_idle = self.frozen
        self.signal(signal.SIGCONT)
        self.frozen = False

    def stop(self):
        """Signal the group (the Maker, alive or a zombie, still owns its id), then reap the Maker, once."""
        if self.reaped:
            return
        self.signal(signal.SIGINT)
        self.signal(signal.SIGCONT)
        for number, patience in ((signal.SIGTERM, 3), (signal.SIGKILL, 3), (None, 10)):
            try:
                self.process.wait(timeout=patience)
                break
            except subprocess.TimeoutExpired:
                if number is not None:
                    self.signal(number)
        self.reaped = self.process.returncode is not None
        self.frozen = False


# --------------------------------------------------------------------------------------------------- the daemon

class SlotHolder:
    """An ordinary build admission held by a helper process (`build-slot.sh build python3 build_admission.py --hold`):
    that process holds the slot, and its stdin is a pipe from the daemon, so the slot is freed when the daemon closes
    the pipe or dies, and when the helper itself dies. The daemon checks it while thawed."""

    def __init__(self):
        start = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        env = dict(os.environ, SELKA_ADMISSION_PARENT_PID=str(os.getpid()), SELKA_ADMISSION_PARENT_START=start)
        self.process = subprocess.Popen(
            [str(SCRIPTS / "build-slot.sh"), "build", sys.executable, "-B", str(SCRIPTS / "build_admission.py"), "--hold"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True, env=env)
        line = self.process.stdout.readline()
        if not line:
            status = self.process.wait()
            raise RuntimeError("the build admission failed (exit %d)" % status)
        self.pid = self.process.pid

    def alive(self):
        return self.process.poll() is None

    def close(self):
        with contextlib.suppress(OSError):
            self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        self.process.stdout.close()


class Daemon:
    def __init__(self, worktree):
        self.worktree = worktree
        self.dir = worktree / STATE
        self.dir.mkdir(parents=True, exist_ok=True)
        self.events = (self.dir / "events.jsonl").open("a")
        self.log = (self.dir / "watch.log").open("a")
        self.maker = None
        self.mode = "freeze"
        self.thaw_stream = None
        self.admission = None
        self.accepted = None
        self.stopped_for = None
        self.configure = None
        self.head = None
        self.last_request = now()
        self.below_since = None
        self.next_memory = now()
        self.next_state = 0.0
        self.self_check = dict(busy=False, idle=False)

    def event(self, kind, **values):
        self.events.write(json.dumps(dict(kind=kind, wall=round(time.time(), 4), mono=round(now(), 4), **values)) + "\n")
        self.events.flush()

    # ----- locks and admission, in the one order: thaw, then ticket and slot
    def hold(self):
        """Take the thaw lock exclusively, then an ordinary build admission; the seconds each waited."""
        started = now()
        if self.thaw_stream is None:
            stream = (self.dir / "thaw.lock").open("a")
            deadline = now() + setting("SELKA_DEV_LOOP_THAW_SECONDS", THAW_WAIT_SECONDS)
            while True:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if now() > deadline:
                        stream.close()
                        raise RuntimeError("a build of this worktree held thaw.lock too long")
                    time.sleep(0.05)
            self.thaw_stream = stream
        thawed = now()
        self.event("thaw-locked", seconds=round(thawed - started, 4))
        if self.admission is None:
            self.admission = SlotHolder()
        admitted = now()
        self.event("admitted", seconds=round(admitted - thawed, 4))
        return thawed - started, admitted - thawed

    def release(self):
        """Give the slot back, then the thaw lock (the reverse of `hold`).

        The state file is written after this, never before: `start` and every reader wait for the state ("frozen",
        "stopped") and then count on the slot and the lock being free. A reader that waits for the locks instead can
        still read the state from before the release.
        """
        if self.admission is not None:
            self.admission.close()
            self.admission = None
        if self.thaw_stream is not None:
            self.thaw_stream.close()
            self.thaw_stream = None
        self.event("released")

    def helper_alive(self):
        """Whether the process that holds this daemon's build slot is still there."""
        return self.admission is None or self.admission.alive()

    # ----- the Maker's life
    def start_maker(self, reason):
        self.maker = Maker(self.worktree, self.log)
        self.configure = configure_digest(self.worktree)
        self.head = head(self.worktree)
        self.accepted = None
        self.self_check = dict(busy=False, idle=False)
        self.event("maker-started", pid=self.maker.pid, reason=reason)

    def stop_maker(self, reason):
        if self.maker is not None:
            self.maker.stop()
            self.event("maker-stopped", reason=reason)
        self.maker = None
        self.accepted = None
        if self.mode == "no-freeze" or self.admission is not None or self.thaw_stream is not None:
            self.release()

    def freeze(self, limit=None):
        """Freeze at a verified idle, then release the slot and the thaw lock. In no-freeze mode keep the slot."""
        if self.maker is None or not self.maker.alive():
            self.release()
            return True
        if self.mode == "no-freeze":
            if self.thaw_stream is not None:
                self.thaw_stream.close()
                self.thaw_stream = None
            return True
        deadline = None if limit is None else now() + limit
        seen = None
        while deadline is None or now() < deadline:
            state = self.maker.state()
            if state != seen and limit is not None and limit > 1:
                self.event("state", state=state)
                seen = state
            if self.maker.freeze_if_idle():
                self.event("frozen")
                self.release()
                self.write_state()
                return True
            if not self.maker.alive():
                self.release()
                return True
            time.sleep(SAMPLE_SECONDS)
        return False

    def write_state(self, force=False):
        slot = os.environ.get("SELKA_WATCH_SLOT")
        state = self.describe()
        rss = tree_rss(self.maker.pid) if self.maker is not None and self.maker.alive() else 0
        record = dict(state=state, pid=os.getpid(), maker=self.maker.pid if self.maker else None, rss=rss,
                      mode=self.mode, accepted=self.accepted and {k: v for k, v in self.accepted.items() if k not in PRIVATE},
                      stopped_for=self.stopped_for, written=time.time())
        temporary = self.dir / ("state.json.%d" % os.getpid())
        temporary.write_text(json.dumps(record))
        os.replace(temporary, self.dir / "state.json")
        if slot:
            with contextlib.suppress(OSError):
                Path(slot + ".state").write_text("%s %d %d\n" % (state, rss, int(time.time())))
        self.next_state = now() + 30

    def describe(self):
        if self.maker is None:
            return "stopped"
        if not self.maker.alive():
            return "ended"
        if self.mode == "no-freeze":
            return "no-freeze"
        return "frozen" if self.maker.frozen else "thawed"

    # ----- a wait
    def wait(self):
        """Bring the binaries up to the newest edit; returns (exit code, lines)."""
        lines = []
        if worktree_cache_trim.coordinator_running(self.worktree):
            return 2, ["dev-loop: a gate is running in this worktree (its coordinator lock is held); wait after it"]
        request = now()
        current = snapshot(self.worktree)
        if self.maker is not None and not self.maker.alive():
            lines.append("dev-loop: the watcher ended (exit %s); restarting it, a full first build" % self.maker.ended)
            self.stop_maker("ended")
        if self.maker is not None:
            moved = head(self.worktree) != self.head
            reconfigure = configure_digest(self.worktree) != self.configure
            many = self.accepted is not None and changed(self.accepted["snapshot"], current) > RESTART_CHANGED_FILES
            if moved or reconfigure or many:
                why = "HEAD moved" if moved else "a configure input changed" if reconfigure else "over %d files changed" \
                    % RESTART_CHANGED_FILES
                lines.append("dev-loop: %s; restarting the watcher, a full first build" % why)
                self.stop_maker(why)
        # One rule, with the Maker frozen at a verified idle (every change before the freeze has been built): the answer
        # is the newest build whose inputs at its end equal the inputs now, with that build's verdict; else build.
        answered = self.newest_matching(current)
        if answered is not None:
            self.accepted = answered
            return self.report(answered, lines + ["dev-loop: nothing changed since build %d" % answered["index"]])
        try:
            thaw_seconds, slot_seconds = self.hold()
        except RuntimeError as error:
            self.release()
            return 2, lines + ["dev-loop: " + str(error)]
        if self.maker is not None:
            # The watch's products are links to what the incremental linker rewrites in place: it cannot rewrite an
            # executable a process runs (FileBusy), and that failure leaves its compiler gone and the Maker stuck.
            deadline = now() + setting("SELKA_DEV_LOOP_BUSY_SECONDS", BUSY_WAIT_SECONDS)
            busy = running_products(self.worktree)
            while busy and now() < deadline:
                time.sleep(0.2)
                busy = running_products(self.worktree)
            if busy:
                self.release()
                pid, relative = busy[0]
                return 2, lines + ["dev-loop: process %d runs %s, which the watcher rewrites in place; wait after it ends "
                                   "(dev_loop.py test waits for you)" % (pid, relative)]
        first = False
        # The inputs again, now that the admission and any wait for a running product are over: an edit made while
        # the request queued is part of what this wait must answer for.
        current = snapshot(self.worktree)
        if self.maker is None:
            if self.stopped_for:
                lines.append("dev-loop: restarting the watcher, which was stopped: %s" % self.stopped_for)
                self.stopped_for = None
            current = snapshot(self.worktree)
            self.start_maker("first build")
            first = True
        else:
            self.maker.thaw()
        self.event("continued", first=first)
        self.write_state()
        thawed = now()
        base = thaw_base = len(self.maker.summaries)
        previous = current
        quiet_since = None
        last_state = None
        deadline = now() + setting("SELKA_DEV_LOOP_WAIT_SECONDS", WAIT_SECONDS)
        result = None
        while result is None:
            with self.maker.condition:
                if len(self.maker.summaries) <= base and self.maker.ended is None:
                    self.maker.condition.wait(SAMPLE_SECONDS)
                fresh = self.maker.summaries[base:]
                ended = self.maker.ended
            state = self.maker.state()
            if state != last_state:
                self.event("state", state=state)
                last_state = state
            if first:
                if state in ("busy", "debounce") and not fresh:
                    self.self_check["busy"] = True
            if fresh:
                summary = fresh[0]
                base += 1
                end_snapshot = snapshot(self.worktree)
                self.event("summary", index=summary["index"], failed=summary["failed"],
                           same=end_snapshot == previous)
                if end_snapshot == previous:
                    result = dict(summary, snapshot=end_snapshot)
                else:
                    previous = end_snapshot
                quiet_since = None
                continue
            if ended is not None:
                self.event("maker-ended", status=ended)
                self.release()
                return 2, lines + ["dev-loop: the watcher ended (exit %s) before a build finished; see %s"
                                   % (ended, self.dir / "watch.log")]
            if self.mode == "no-freeze" and not first and self.maker.summaries:
                # Unfrozen, the Maker builds an edit as it lands, and its idle cannot be read: take the newest build
                # when nothing changed since it ended and no build followed it for twice the quiet time.
                latest = self.maker.summaries[-1]
                if latest["end_snapshot"] == snapshot(self.worktree) and now() - latest["end"] >= 2 * QUIET_SECONDS \
                        and now() - thawed >= 2 * QUIET_SECONDS:
                    result = dict(latest, snapshot=latest["end_snapshot"])
                    continue
            if not first and thaw_base and base == thaw_base and state == "idle" and now() - thawed > QUIET_SECONDS:
                # No build at all since the thaw: the change is outside the build graph, and the newest build stands.
                # Once any build has ended after the thaw, only the snapshot rule answers.
                quiet_since = quiet_since or now()
                if now() - quiet_since >= QUIET_SECONDS:
                    result = dict(self.maker.summaries[-1], snapshot=current, quiet=True)
                    lines.append("dev-loop: the change started no build (outside the build graph)")
            elif state != "idle":
                quiet_since = None
            wedged = self.maker.wedged()
            if not wedged and self.maker.stalled(counting=not fresh and state != "idle"):
                wedged = self.maker.pid
                self.event("stalled", threads=self.maker.thread_states())
            if wedged:
                self.stop_maker("a compiler of the watch ended")
                self.stopped_for = "the watch stopped making progress (pid %d) at %s" % (wedged, time.strftime("%H:%M:%S"))
                return 2, lines + ["dev-loop: the watch stopped making progress (pid %d: a compiler ended, or no process of "
                                   "the Maker used CPU for %d s); the watcher was stopped, and the next wait restarts it"
                                   % (wedged, setting("SELKA_DEV_LOOP_STALL_SECONDS", STALL_SECONDS))]
            if not self.helper_alive():
                self.stop_maker("the build slot's holder ended")
                return 2, lines + ["dev-loop: the process holding the build slot ended; the watcher was stopped"]
            if now() > deadline:
                return 2, lines + ["dev-loop: no build finished within %d s" % (deadline - thawed)]
        result["seconds"] = round(now() - request, 3)
        result["slot_seconds"] = round(slot_seconds, 3)
        result["thaw_seconds"] = round(thaw_seconds, 3)
        result["installed"] = installed_stamp(self.worktree)
        self.accepted = result
        self.event("accepted", index=result["index"], failed=result["failed"], seconds=result["seconds"],
                   slot_seconds=result["slot_seconds"])
        if first:
            self.check_signature(lines)
        return self.report(result, lines)

    def newest_matching(self, current):
        """The newest build, as an answer, when the Maker is frozen at a verified idle and that build's inputs at its
        end equal CURRENT; else None."""
        if self.maker is None or not self.maker.frozen or not self.maker.alive() or not self.maker.summaries:
            return None
        newest = self.maker.summaries[-1]
        if newest["end_snapshot"] != current:
            return None
        return dict(newest, snapshot=current, seconds=0.0, slot_seconds=0.0, installed=installed_stamp(self.worktree))

    def check_signature(self, lines):
        """The first build's self-check: busy during the build, idle after it; otherwise no freezing."""
        deadline = now() + setting("SELKA_DEV_LOOP_SELF_CHECK_SECONDS", 120)
        while now() < deadline and self.maker.alive():
            if self.maker.state() == "idle":
                self.self_check["idle"] = True
                break
            time.sleep(SAMPLE_SECONDS)
        if not (self.self_check["busy"] and self.self_check["idle"]):
            self.mode = "no-freeze"
            lines.append("dev-loop: the Maker's idle signature was not seen (busy %s, idle %s); running without "
                         "freezing, holding a build slot" % (self.self_check["busy"], self.self_check["idle"]))
            self.event("no-freeze", **self.self_check)

    def report(self, result, lines):
        if result["failed"]:
            lines.append("dev-loop: build %d failed (%d steps; %.2f s, slot wait %.2f s)"
                         % (result["index"], result["failed"], result.get("seconds", 0), result.get("slot_seconds", 0)))
            seen = set()
            for error in result["errors"]:
                if error[0] in seen:
                    continue
                seen.add(error[0])
                lines.extend(line for line in error[:2] if line)
            return 1, lines[:MAX_LINES]
        lines.append("dev-loop: build %d passed (%.2f s, slot wait %.2f s); zig-out holds it"
                     % (result["index"], result.get("seconds", 0), result.get("slot_seconds", 0)))
        return 0, lines[:MAX_LINES]

    # ----- housekeeping and the request loop
    def housekeeping(self):
        if self.maker is not None and self.mode == "freeze" and not self.maker.frozen and self.maker.alive():
            self.freeze(limit=0.5)
        if self.mode == "freeze" and self.maker is not None and self.maker.frozen and now() >= self.next_memory:
            self.next_memory = now() + setting("SELKA_DEV_LOOP_MEMORY_CHECK_SECONDS", MEMORY_CHECK_SECONDS)
            need = build_admission._bytes(os.environ.get("SELKA_GATE_MEM", "6G"))
            if build_admission._available() < need:
                self.below_since = self.below_since or now()
                if now() - self.below_since >= setting("SELKA_DEV_LOOP_MEMORY_GRACE_SECONDS", MEMORY_GRACE_SECONDS):
                    self.stopped_for = ("MemAvailable stayed below the gate's %s (SELKA_GATE_MEM) at %s"
                                        % (os.environ.get("SELKA_GATE_MEM", "6G"), time.strftime("%H:%M:%S")))
                    self.stop_maker("memory")
                    self.below_since = None
            else:
                self.below_since = None
        if now() >= self.next_state:
            self.write_state()

    def serve(self):
        path = self.dir / "sock"
        with contextlib.suppress(FileNotFoundError):
            path.unlink()
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if len(os.fsencode(str(path))) >= SOCKET_PATH_LIMIT:
            print("dev-loop: the socket path %s is longer than a Unix socket allows (%d bytes); use a shorter worktree "
                  "path" % (path, SOCKET_PATH_LIMIT - 1), file=sys.stderr)
            return
        server.bind(str(path))
        server.listen(4)
        server.settimeout(0.2)
        self.event("daemon-started", pid=os.getpid())
        self.write_state()
        idle_limit = setting("SELKA_DEV_LOOP_IDLE_SECONDS", IDLE_STOP_SECONDS)
        running = True
        while running:
            try:
                connection, _ = server.accept()
            except socket.timeout:
                self.housekeeping()
                if now() - self.last_request > idle_limit:
                    self.event("idle-stop")
                    break
                continue
            with connection:
                connection.settimeout(None)
                request = json.loads(connection.makefile().readline() or "{}")
                operation = request.get("op")
                self.last_request = now()
                running = self.answer(connection, operation)
            if running and operation == "wait":
                limit = setting("SELKA_DEV_LOOP_FREEZE_SECONDS", FREEZE_SECONDS)
                if not self.freeze(limit=limit):
                    # A Maker that never comes back to its watch poll (stuck on FileBusy, say) must not keep the build
                    # slot and the exclusive thaw lock, which every ordinary build of the worktree waits on.
                    self.stopped_for = ("the watcher could not be frozen within %d s at %s"
                                        % (limit, time.strftime("%H:%M:%S")))
                    self.stop_maker("could not be frozen")
            self.write_state()
        self.stop_maker("daemon stopping")
        self.release()
        with contextlib.suppress(FileNotFoundError):
            path.unlink()
        self.write_state()
        self.event("daemon-stopped")

    def answer(self, connection, operation):
        """Carry out one request and send its answer; whether the daemon keeps running.

        The state file is written before the answer is sent, not after: a client that reads it the moment its `wait`
        returns (an agent checking "stopped", the tests) must find the state the answer describes. Written after, it
        showed the state from before the wait whenever the daemon was slow to get back to it, which on a loaded machine
        was often (15 November: "the watcher was stopped" with the file still saying "thawed").
        """
        running = True
        if operation == "wait":
            code, lines = self.wait()
        elif operation == "status":
            code, lines = 0, self.status_lines()
        elif operation == "stop":
            code, lines, running = 0, ["dev-loop: the watcher is stopping"], False
        else:
            code, lines = 2, ["dev-loop: unknown request %r" % operation]
        if operation == "wait":
            self.write_state()
        with contextlib.suppress(OSError):
            connection.sendall((json.dumps(dict(code=code, lines=lines,
                                                accepted=self.public_accepted())) + "\n").encode())
        return running

    def public_accepted(self):
        if self.accepted is None:
            return None
        return {key: value for key, value in self.accepted.items() if key not in PRIVATE}

    def status_lines(self):
        lines = ["dev-loop: daemon pid %d, watcher %s, mode %s" % (os.getpid(), self.describe(), self.mode)]
        if self.maker is not None and self.maker.alive():
            lines.append("dev-loop: Maker pid %d, %.1f GiB resident" % (self.maker.pid, tree_rss(self.maker.pid) / 2 ** 30))
        if self.accepted is not None:
            lines.append("dev-loop: last build %d %s" % (self.accepted["index"],
                                                       "failed" if self.accepted["failed"] else "passed"))
        if self.stopped_for:
            lines.append("dev-loop: stopped: %s" % self.stopped_for)
        return lines


def running_products(worktree):
    """(pid, product) for each process whose executable is one of the installed products (resolved through the
    watch's links), from /proc/PID/exe."""
    targets = {}
    for relative in INSTALLED:
        with contextlib.suppress(OSError):
            targets[os.path.realpath(worktree / relative)] = relative
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.readlink(f"/proc/{entry}/exe")
        except OSError:
            continue
        if executable.endswith(" (deleted)"):
            continue
        if executable in targets:
            found.append((int(entry), targets[executable]))
    return found


def installed_stamp(worktree):
    """Size and mtime of each installed product, so `test` can tell a watch build from a later normal build."""
    stamp = {}
    for relative in INSTALLED:
        with contextlib.suppress(OSError):
            status = os.stat(worktree / relative)
            stamp[relative] = [status.st_size, status.st_mtime_ns]
    return stamp


def run_daemon():
    worktree = Path.cwd().resolve()
    directory = worktree / STATE
    directory.mkdir(parents=True, exist_ok=True)
    lock = (directory / "daemon.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("dev-loop: this worktree already has a daemon", file=sys.stderr)
        return 3
    (directory / "thaw.lock").touch()
    def leave(*_):
        raise SystemExit(0)
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, leave)
    daemon = Daemon(worktree)
    try:
        daemon.serve()
    finally:
        daemon.stop_maker("daemon exit")
        daemon.release()
    return 0


def exec_guard(argv):
    """In a fresh single-threaded process: die with the daemon (parent-death SIGKILL), then become the Maker."""
    parent = int(argv[0])
    library = ctypes.CDLL(None, use_errno=True)
    if library.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "cannot set the parent-death signal")
    if os.getppid() != parent:
        return 143
    os.execvp(argv[1], argv[1:])


# --------------------------------------------------------------------------------------------------- the client

def worktree_root():
    completed = subprocess.run(["git", "rev-parse", "--show-toplevel"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True)
    return Path(completed.stdout.strip() or os.getcwd()).resolve()


def daemon_alive(worktree):
    return worktree_cache_trim.held(worktree / STATE / "daemon.lock")


def request(worktree, operation, timeout=None):
    """One request to the daemon; a reply with exit 2 and a reason when the daemon cannot be reached or does not
    answer in time (a `wait` gets the longest a wait may take, plus its admission)."""
    if timeout is None:
        timeout = WAIT_SECONDS + THAW_WAIT_SECONDS + 300
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(timeout)
    try:
        connection.connect(str(worktree / STATE / "sock"))
        with connection:
            connection.sendall((json.dumps(dict(op=operation)) + "\n").encode())
            reply = connection.makefile().readline()
    except (OSError, socket.timeout) as error:
        return dict(code=2, lines=["dev-loop: the daemon did not answer %s (%s); see %s"
                                   % (operation, error.__class__.__name__, worktree / STATE / "events.jsonl")])
    if not reply:
        return dict(code=2, lines=["dev-loop: the daemon closed the connection; see %s" % (worktree / STATE / "events.jsonl")])
    return json.loads(reply)


def connect_when_ready(worktree, wrapper, limit=60):
    deadline = now() + limit
    while now() < deadline:
        if (worktree / STATE / "sock").exists() and daemon_alive(worktree):
            return True
        if wrapper.poll() is not None:
            return False
        time.sleep(0.05)
    return False


def start(worktree):
    if len(os.fsencode(str(worktree / STATE / "sock"))) >= SOCKET_PATH_LIMIT:
        print("dev-loop: this worktree's path is too long for the daemon's Unix socket (%s, at most %d bytes); use a "
              "shorter worktree path" % (worktree / STATE / "sock", SOCKET_PATH_LIMIT - 1))
        return 2
    if daemon_alive(worktree):
        print("dev-loop: this worktree already has a watcher")
        return status(worktree)
    directory = worktree / STATE
    directory.mkdir(parents=True, exist_ok=True)
    with contextlib.suppress(FileNotFoundError):
        (directory / "sock").unlink()
    output = (directory / "daemon.out").open("a")
    wrapper = subprocess.Popen([str(SCRIPTS / "build-slot.sh"), "watch", sys.executable, "-B", str(Path(__file__).resolve()),
                                "--daemon"], cwd=worktree, stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                               start_new_session=True)
    if not connect_when_ready(worktree, wrapper):
        code = wrapper.poll()
        output.flush()
        tail = (directory / "daemon.out").read_text(errors="replace").splitlines()[-3:]
        for line in tail:
            print(line)
        return code if code not in (None, 0) else 2
    print("dev-loop: watcher started (daemon pid %d); building once" % wrapper.pid)
    return wait(worktree)


def wait(worktree, out=print):
    if not daemon_alive(worktree):
        out("dev-loop: no watcher in this worktree; python3 scripts/dev_loop.py start")
        return 2
    reply = request(worktree, "wait")
    for line in reply["lines"]:
        out(line)
    return reply["code"]


def status(worktree):
    if not daemon_alive(worktree):
        state = worktree / STATE / "state.json"
        if state.exists():
            record = json.loads(state.read_text())
            print("dev-loop: no watcher running (the last daemon, pid %s, wrote %s at %s)"
                  % (record.get("pid"), record.get("state"), time.strftime("%H:%M:%S", time.localtime(record["written"]))))
        else:
            print("dev-loop: no watcher in this worktree")
        return 0
    record = json.loads((worktree / STATE / "state.json").read_text())
    accepted = record.get("accepted") or {}
    print("dev-loop: daemon pid %s, watcher %s, mode %s, Maker pid %s, %.1f GiB resident"
          % (record["pid"], record["state"], record["mode"], record["maker"], record["rss"] / 2 ** 30))
    if accepted:
        print("dev-loop: last build %d %s" % (accepted["index"], "failed" if accepted["failed"] else "passed"))
    if record.get("stopped_for"):
        print("dev-loop: stopped: %s" % record["stopped_for"])
    return 0


def stop(worktree):
    if not daemon_alive(worktree):
        print("dev-loop: no watcher in this worktree")
        return 0
    for line in request(worktree, "stop", timeout=60)["lines"]:
        print(line)
    deadline = now() + 60
    while daemon_alive(worktree) and now() < deadline:
        time.sleep(0.05)
    print("dev-loop: stopped" if not daemon_alive(worktree) else "dev-loop: the daemon did not stop within 60 s")
    return 0 if not daemon_alive(worktree) else 2


def test_environment(worktree, scratch, compiler=None):
    """The environment the test binaries run in, as the edit check gives them (`edit_check.test_environment`)."""
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "LANG", "USER", "ZIG_GLOBAL_CACHE_DIR", "TMPDIR")}
    env.update({
        "SELKA_TEST_COMPILER": str(compiler or worktree / "zig-out" / "bin" / "selka"),
        "SELKA_ZIG": os.environ.get("ZIG", "zig"),
        "SELKA_COMPONENT_DIR": str(worktree / "zig-out" / "libexec" / "selka" / "components"),
        "SELKA_TEST_COMPONENT_BUILDER": str(worktree / "zig-out" / "tools" / "selka-components"),
        "SELKA_COMPILER_SHARED_CACHE": "",
        "SELKA_TEST_SHARED_CACHE": "",
        "SELKA_STAGE_SHARED_CACHE": "",
        "ZIG_LOCAL_CACHE_DIR": str(Path(scratch) / "zig-local"),
    })
    (Path(scratch) / "zig-local").mkdir(parents=True, exist_ok=True)
    return env


def binary_kind(worktree, relative):
    """`watch build N` when the installed product is the one the last accepted watch build left, else `normal build`."""
    record = worktree / STATE / "state.json"
    try:
        accepted = json.loads(record.read_text()).get("accepted") or {}
        status_now = os.stat(worktree / relative)
    except (OSError, ValueError):
        return "unknown build"
    if accepted.get("installed", {}).get(relative) == [status_now.st_size, status_now.st_mtime_ns]:
        return "watch build %d" % accepted["index"]
    return "normal build"


def thaw_shared(worktree, out=print):
    """Hold this worktree's thaw lock shared while binaries the watcher links in place run: a `wait` (which takes it
    exclusively) then waits for them, and the incremental linker never writes a running executable."""
    stream = (worktree / STATE / "thaw.lock").open("a")
    try:
        fcntl.flock(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except BlockingIOError:
        out("dev-loop: waiting for the watcher's rebuild to finish")
        deadline = now() + THAW_WAIT_SECONDS
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if now() > deadline:
                    stream.close()
                    raise RuntimeError("the watcher held thaw.lock for %d s" % THAW_WAIT_SECONDS)
                time.sleep(0.05)
    return stream


def daemon_mode(worktree):
    """The running daemon's mode (`freeze` or `no-freeze`) from its state file, or None."""
    try:
        return json.loads((worktree / STATE / "state.json").read_text()).get("mode") if daemon_alive(worktree) else None
    except (OSError, ValueError):
        return None


def run_tests(worktree, root, test_filter, out=print):
    """Wait, then run ROOT's installed binary with Guardian's runtime filter in one build admission; the exit code."""
    if daemon_mode(worktree) == "no-freeze":
        out("dev-loop: this watcher cannot be frozen (no-freeze mode), so it may relink a test binary while it runs; "
            "build and test normally: python3 scripts/focused_test.py %s '%s' --no-watch" % (root, test_filter))
        return 2
    code = wait(worktree, out)
    if code != 0:
        return code
    relative = "zig-out/focus/" + BINARIES[root]
    scratch = worktree / STATE / "test-scratch"
    started = time.time()
    with contextlib.closing(thaw_shared(worktree, out)), build_admission.admission("build"):
        kind = binary_kind(worktree, relative)
        completed = subprocess.run([str(worktree / relative), "--test-filter=" + test_filter],
                                   cwd=worktree, env=test_environment(worktree, scratch), stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, errors="replace")
        failed = FAILED.findall(completed.stdout)
        refused = []
        if failed and kind.startswith("watch build"):
            compiler = worktree / "zig-out" / "bin" / "selka"
            refused = [name for name in failed[:3]
                       if ceiling_refusal(worktree / relative, worktree, compiler, scratch / "ceiling", name)]
    log = worktree / STATE / "last-test.log"
    log.write_text(completed.stdout)
    out("dev-loop: %s on the %s (%s)" % (relative, kind, "filter " + test_filter))
    # The verdict is the exit status; failure_report only chooses what to print: each failing test's full name, its
    # message and the file:line of the test (at most 30 lines), the last 20 lines when no failure form is known.
    for line in failure_report.render(completed.stdout, completed.returncode, "filter " + test_filter,
                                      time.time() - started):
        out(line)
    compiler = worktree / "zig-out" / "bin" / "selka"
    for name in refused:
        out(watch_only_line(name, compiler, None))
    if completed.returncode != 0 and kind.startswith("watch build"):
        out("dev-loop: a failure on a watch build is the watch build's until a normal build confirms it: "
            "python3 scripts/focused_test.py %s '%s' --no-watch" % ({"units": "units", "cli": "cli"}.get(root, root),
                                                                     test_filter))
    out("dev-loop: " + failure_report.closing(completed.returncode, log))
    return completed.returncode


# --------------------------------------------------------------------------------------------------- the comparison

FAILED = re.compile(r"^\d+ (.+?)\.\.\.FAIL \(", re.M)
# The known watch-only case (13 November): an incrementally linked compiler reserves room in its segments to patch
# them in place, so it maps 433.7 MiB against a normal build's 77.9 MiB, and under a low SELKA_HOST_MEMORY_LIMIT
# (whose address-space headroom is 256 MiB) that mapping alone reaches the ceiling. The heap is the same.
CEILING_MESSAGE = "reached its own memory ceiling"
PADDING_BYTES = 64 << 20


def load_segments(path):
    """(bytes mapped, bytes in the file) over an ELF executable's LOAD segments; (0, 0) for anything else."""
    try:
        stream = open(path, "rb")
    except OSError:
        return 0, 0
    with stream:
        header = stream.read(64)
        if header[:4] != b"\x7fELF" or header[4] != 2:
            return 0, 0
        offset, = struct.unpack_from("<Q", header, 32)
        size, count = struct.unpack_from("<HH", header, 54)
        stream.seek(offset)
        table = stream.read(size * count)
    mapped = stored = 0
    for index in range(count):
        kind, _, _, _, _, filesz, memsz, _ = struct.unpack_from("<IIQQQQQQ", table, index * size)
        if kind == 1:
            mapped += memsz
            stored += filesz
    return mapped, stored


def padded(path):
    """Whether an executable maps much more than it stores: the incremental linker's room to patch in place."""
    mapped, stored = load_segments(path)
    return mapped - stored > PADDING_BYTES


def ceiling_refusal(binary, worktree, compiler, scratch, name):
    """Run one test again with a compiler wrapper that records every exit 2 carrying the ceiling message: whether the
    test's failure was the watch-built compiler reaching its own memory ceiling, and that compiler is padded."""
    if not padded(compiler):
        return False
    scratch = Path(scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    marks = scratch / "refusals"
    marks.unlink(missing_ok=True)
    wrapper = scratch / "selka"
    wrapper.write_text("#!/bin/sh\nerr=$(mktemp '%s/err.XXXXXX')\n'%s' \"$@\" 2>\"$err\"\nstatus=$?\ncat \"$err\" >&2\n"
                       "if [ \"$status\" = 2 ] && grep -q '%s' \"$err\"; then echo ceiling >> '%s'; fi\n"
                       "rm -f \"$err\"\nexit $status\n" % (scratch, Path(compiler).resolve(), CEILING_MESSAGE, marks))
    wrapper.chmod(0o755)
    listing = scratch / "name.list"
    listing.write_text(name + "\n")
    completed = subprocess.run([str(binary), "--test-list=" + str(listing)], cwd=worktree,
                               env=test_environment(worktree, scratch / "env", wrapper), stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, errors="replace")
    # The refusal must be the test's unexpected outcome: an exit status other than 2 expected and 2 found. A test
    # that expects the refusal and fails for another reason is no watch-only case.
    unexpected = re.search(r"expected (\d+), found 2\b", completed.stdout)
    return completed.returncode != 0 and marks.exists() and unexpected is not None and unexpected.group(1) != "2"


def watch_only_line(name, watch_compiler, normal_compiler):
    mapped = load_segments(watch_compiler)[0] / 2 ** 20
    normal = (" against %.1f MiB for the normal build" % (load_segments(normal_compiler)[0] / 2 ** 20)
              if normal_compiler else "")
    return ("dev-loop: watch-only: %s: the watch-built compiler maps %.1f MiB of executable%s and reached its own "
            "memory ceiling (SELKA_HOST_MEMORY_LIMIT); confirm on a normal build (focused_test.py --no-watch)"
            % (name, mapped, normal))


def verdicts(binary, worktree, compiler, scratch, names=None, shards=4):
    """Per-test verdicts of one binary over NAMES (every test when None): {name: pass|fail|skip|crash}, in SHARDS
    concurrent processes, each given its share of the names as an exact list."""
    import edit_check_collect
    scratch = Path(scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    if names is None:
        names = edit_check_collect.list_tests(str(binary), str(worktree))
    names = sorted(names)
    env = test_environment(worktree, scratch, compiler)
    processes = []
    for shard in range(min(shards, len(names))):
        share = names[shard::shards]
        log = scratch / ("%s.%d.log" % (Path(binary).name, shard))
        listing = scratch / ("%s.%d.list" % (Path(binary).name, shard))
        listing.write_text("\n".join(share) + "\n")
        argv = [str(binary), "--test-list=" + str(listing), "--cache-dir=" + str(log) + ".fuzz-cache"]
        handle = log.open("w")
        shard_env = dict(env, ZIG_LOCAL_CACHE_DIR=str(scratch / ("zig-local-%d" % shard)))
        processes.append((subprocess.Popen(argv, cwd=worktree, env=shard_env, stdout=handle, stderr=subprocess.STDOUT),
                          handle, log))
    result = {name: "pass" for name in names}
    for process, handle, log in processes:
        status = process.wait()
        handle.close()
        text = log.read_text(errors="replace")
        for match in re.finditer(r"^\d+ (.+?)\.\.\.(FAIL|SKIP)", text, re.M):
            result[match.group(1)] = match.group(2).lower()
        if status != 0 and "test: FAIL" not in text:
            result["<shard crashed: %s>" % log] = "crash"
    return result


def lang_verdicts(worktree, compiler, scratch):
    """`selka test tests/lang` with COMPILER as the gate runs it (leak check, facts verified), forced, in private
    stores: {name: status} from its `native-tests-v1` JSON report."""
    scratch = Path(scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, SELKA_CORE_LEAKCHECK="1", SELKA_STAGE_SHARED_CACHE="", SELKA_TEST_SHARED_CACHE="",
               SELKA_COMPILER_SHARED_CACHE="", XDG_CACHE_HOME=str(scratch / "xdg"),
               SELKA_CORE_RUNTIME_CACHE=str(scratch / "runtime"),
               SELKA_COMPONENT_DIR=str(worktree / "zig-out" / "libexec" / "selka" / "components"))
    completed = subprocess.run([str(compiler), "test", "tests/lang", "--verify-facts", "--force", "--json",
                                "--cache-dir", str(scratch / "lang-cache")], cwd=worktree, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, errors="replace")
    (scratch / "lang.json").write_text(completed.stdout)
    (scratch / "lang.err").write_text(completed.stderr)
    result = {}
    try:
        report = json.loads(completed.stdout)
    except ValueError:
        report = {}
    for item in report.get("tests", []):
        result[item["name"]] = item["status"]
    if not result:
        result["<exit %d, no report>" % completed.returncode] = "no report"
    return result


def edit_check_selection(worktree):
    """The newest edit check's selection in this worktree ({root: names}, and whether guest files were selected); the
    edit check's `--select-only` writes one when there is none."""
    roots = [Path(os.environ.get("TMPDIR", "")) / "edit-check", worktree / ".tmp" / "work" / "edit-check"]
    found = sorted((path for root in roots if root.is_dir() for path in root.glob("*/selection.tsv")),
                   key=lambda path: path.stat().st_mtime)
    if not found:
        completed = subprocess.run([sys.executable, str(SCRIPTS / "edit_check.py"), "--select-only"], cwd=worktree,
                                   env=dict(os.environ, SELKA_EDIT_CHECK_NO_REFRESH="1"), stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, errors="replace")
        match = re.search(r"^selection file: (.+)$", completed.stdout, re.M)
        if not match:
            raise RuntimeError("the edit check wrote no selection:\n" + completed.stdout[-2000:])
        found = [Path(match.group(1))]
    selected = {root: [] for root in BINARIES}
    guests = False
    for line in found[-1].read_text().splitlines():
        root, kind, name = (line.split("\t") + ["", "", ""])[:3]
        if root in selected and kind != "unnamed" and name:
            selected[root].append(name)
        elif root not in selected and name:
            guests = True
    return selected, guests, found[-1]


def compare(worktree, roots, everything=False):
    """Watch-built against normal binaries, verdicts by name: the newest edit check's selection, or with EVERYTHING
    every test of ROOTS. One ordinary build admission per root, released between roots. Exit 0 when every verdict
    matches or differs only by the known watch-only case, which is named."""
    code = wait(worktree)
    if code not in (0, 1):
        return code
    stale = [relative for relative in INSTALLED if not binary_kind(worktree, relative).startswith("watch build")]
    if stale:
        # A normal build installed over the watcher's products since its last build: a fresh watcher reinstalls them.
        print("dev-loop: compare: zig-out holds a later normal build (%s); restarting the watcher" % ", ".join(stale))
        stop(worktree)
        code = start(worktree)
        if code != 0:
            return code
        stale = [relative for relative in INSTALLED if not binary_kind(worktree, relative).startswith("watch build")]
        if stale:
            print("dev-loop: compare: the watcher did not reinstall %s" % ", ".join(stale))
            return 2
    base = worktree / STATE / "compare"
    shutil.rmtree(base, ignore_errors=True)
    for kind in ("watch", "normal"):
        (base / kind).mkdir(parents=True)
    with contextlib.closing(thaw_shared(worktree)):
        for relative in INSTALLED:
            shutil.copy2(worktree / relative, base / "watch" / Path(relative).name)
    print("dev-loop: compare: the watch binaries are copied; building normally (-fno-incremental)", flush=True)
    zig = os.environ.get("ZIG") or "zig"
    build = subprocess.run([str(SCRIPTS / "build-slot.sh"), "build", zig, "build", "-fno-incremental", *STEPS],
                           cwd=worktree, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    (base / "normal-build.log").write_text(build.stdout)
    if build.returncode != 0:
        print("dev-loop: compare: the normal build failed; see %s" % (base / "normal-build.log"))
        return 2
    for relative in INSTALLED:
        shutil.copy2(worktree / relative, base / "normal" / Path(relative).name)
    if everything:
        chosen = {root: None for root in roots if root in BINARIES}
        lang = "lang" in roots
    else:
        try:
            selected, lang, path = edit_check_selection(worktree)
        except RuntimeError as error:
            print("dev-loop: compare: " + str(error))
            return 2
        chosen = {root: names for root, names in selected.items() if names and root in roots}
        print("dev-loop: compare: the edit check's selection (%s): %s%s" % (path, ", ".join(
            "%s %d" % (root, len(names)) for root, names in chosen.items()) or "no Zig tests", ", tests/lang" if lang else ""),
              flush=True)
    differences, watch_only = [], []
    for root in [*chosen, *(["lang"] if lang else [])]:
        with build_admission.admission("build"):
            if root == "lang":
                found = {kind: lang_verdicts(worktree, base / kind / "selka", base / kind / root)
                         for kind in ("watch", "normal")}
            else:
                found = {kind: verdicts(base / kind / BINARIES[root], worktree, base / kind / "selka",
                                        base / kind / root, chosen[root]) for kind in ("watch", "normal")}
            names = sorted(found["watch"].keys() | found["normal"].keys())
            different = [name for name in names if found["watch"].get(name) != found["normal"].get(name)]
            known = [name for name in different if root in BINARIES and found["watch"].get(name) == "fail"
                     and found["normal"].get(name) == "pass" and not padded(base / "normal" / "selka")
                     and ceiling_refusal(base / "watch" / BINARIES[root], worktree, base / "watch" / "selka",
                                         base / "watch" / root / "ceiling", name)]
        counts = {kind: {} for kind in found}
        for kind, table in found.items():
            for verdict in table.values():
                counts[kind][verdict] = counts[kind].get(verdict, 0) + 1
        print("dev-loop: compare %s: %d names; watch %s; normal %s; %d different, %d watch-only"
              % (root, len(names), json.dumps(counts["watch"], sort_keys=True), json.dumps(counts["normal"], sort_keys=True),
                 len(different) - len(known), len(known)), flush=True)
        watch_only.extend(watch_only_line(name, base / "watch" / "selka", base / "normal" / "selka") for name in known)
        differences.extend("%s: %s: watch %s, normal %s" % (root, name, found["watch"].get(name), found["normal"].get(name))
                           for name in different if name not in known)
        (base / ("%s-verdicts.json" % root)).write_text(json.dumps(found, sort_keys=True, indent=1))
    for line in (differences + watch_only)[:MAX_LINES]:
        print(line)
    print("dev-loop: compare: %s%s; verdicts in %s" % ("%d differences" % len(differences) if differences
                                                       else "identical verdicts",
                                                       ", %d watch-only" % len(watch_only) if watch_only else "", base))
    return 1 if differences else 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--daemon"]:
        return run_daemon()
    if argv[:1] == ["--exec-guard"]:
        return exec_guard(argv[1:])
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("start", "wait", "stop", "status"):
        commands.add_parser(name)
    tests = commands.add_parser("test")
    tests.add_argument("root", choices=sorted(BINARIES))
    tests.add_argument("filter")
    comparison = commands.add_parser("compare")
    comparison.add_argument("--roots", default="units,core,cli,lang")
    comparison.add_argument("--all", action="store_true", help="every test of the roots, not the edit check's selection")
    options = parser.parse_args(argv)
    worktree = worktree_root()
    if options.command == "test":
        if not options.filter.strip():
            parser.error("test needs a non-empty filter")
        return run_tests(worktree, options.root, options.filter)
    if options.command == "compare":
        return compare(worktree, [root for root in options.roots.split(",") if root], options.all)
    return {"start": start, "wait": wait, "stop": stop, "status": status}[options.command](worktree)


if __name__ == "__main__":
    raise SystemExit(main())
