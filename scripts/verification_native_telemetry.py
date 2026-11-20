#!/usr/bin/env python3
"""Transparent pinned Zig test-protocol proxy with advisory interval observations.

The measured interval starts when test_started is received and ends when the
matching test_results arrives. It includes runner reporting and pipe scheduling;
it is NOT pure test-body duration. Malformed telemetry disables observation,
never forwarding. The original runner owns selection, output and test verdicts,
with one exception: a test is killed when it is hung or over its wall limit. Hung
means its process tree (the runner's session) shows no CPU progress for
SELKA_TEST_IDLE_SECONDS; over its wall limit means SELKA_TEST_DEADLINE_SECONDS
(a backstop for polling loops) has passed. CPU progress, not wall time, is what
a hang lacks, so a test slowed by other gates keeps its interval. The proxy kills
the runner's process group, records that test as `timed_out`, prints one line
naming it (`test deadline:`) and exits non-zero.

The runner's stderr is held back while every test passes, so a green step leaves
no `failed command:` block. It is replayed whenever the runner exits non-zero or
the protocol shows a failed, timed-out or unreported test, because a server-mode
runner exits 0 after a failing test.

The build runner prints a failure only when the whole build is over, so the first
failed or timed-out test also leaves a beacon in the telemetry directory the moment
its result is seen: `fail-fast.<action>.member.<n>.txt`, the block a build log would
show for it, and the member document with the rows so far. `verify_cache.py
--fail-fast` ends the build when it finds one; without the option nothing reads it.
"""
import argparse
import ctypes
import math
import os
from pathlib import Path
import signal
import select
import struct
import subprocess
import sys
import tempfile
import threading
import time

import verification_telemetry as telemetry

PINNED_ZIG = '0.17.1'
MAX_FRAME = telemetry.MAX_BYTES
MAX_FRAMES = telemetry.MAX_TESTS * 5 + 16
CLIENT_EXIT, CLIENT_RUN_TEST = 0, 5
SERVER_VERSION, SERVER_METADATA, SERVER_RESULTS, SERVER_STARTED = 0, 3, 4, 5
INTERVAL_SCOPE = 'runner-protocol-interval'
DEADLINE_ENVIRONMENT = 'SELKA_TEST_DEADLINE_SECONDS'
IDLE_ENVIRONMENT = 'SELKA_TEST_IDLE_SECONDS'
# Wall backstop per test interval, well under the 30-minute step deadline so that a spinning test names
# itself before its whole step is killed. Hangs are caught by the idle limit; this bounds what keeps
# consuming some CPU without finishing, such as a polling loop that sleeps between checks.
DEFAULT_DEADLINE_SECONDS = '900'
# No CPU progress for this long means hung. A blocked test shows none; a test that computes or waits on
# a busy child shows some, whatever the load.
DEFAULT_IDLE_SECONDS = '300'
# CPU is sampled at most this often, and at least three times per idle window (so a short test limit
# still sees progress in time).
CPU_SAMPLE_SECONDS = 5.0
DEADLINE_STATUS = 124
# The build runner reads the runner's stderr and stdout pipes concurrently and
# attaches to a failed test only the stderr it has read when the result arrives;
# a short pause after a failure's stderr keeps a long trace under its test.
FAILURE_ORDERING_SECONDS = 0.05
# A beacon carries at most this much of the failing test's own stderr, from its end.
BEACON_STDERR_BYTES = 32 * 1024


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
        self.current = None
        self.rows = []
        self.progressed = None
        self.exit_seen = False
        self.supported = False
        self.malformed = False
        self.timed_out = False
        self.runner_interval = None

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
                self.progressed = self.started
                self.current = self.pending[0]
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
                ended = self.clock()
                elapsed = ended - self.started
                if elapsed < 0:
                    raise ValueError('clock order')
                self.rows.append(dict(test_id=self.names[index], state=state,
                                      elapsed_ns=None if state == 'skipped' else elapsed,
                                      elapsed_scope=INTERVAL_SCOPE,
                                      started_monotonic_ns=self.started, ended_monotonic_ns=ended))
                self.started = None
                self.current = None

    def progress(self, now):
        """Record CPU progress by the running test's process tree at `now`."""
        with self.lock:
            if self.started is not None:
                self.progressed = now

    def overdue(self, now, idle_ns, wall_ns):
        """Return (identity, reason, elapsed, quiet) once the running test breaches a limit, else None.

        `reason` is 'idle' when no CPU progress came for `idle_ns`, or 'wall' when the interval has run
        `wall_ns`. A limit of None is off.
        """
        with self.lock:
            if self.started is None or self.current is None:
                return None
            elapsed = now - self.started
            quiet = now - self.progressed
            name = self.names[self.current]
            if wall_ns is not None and elapsed >= wall_ns:
                return name, 'wall', elapsed, quiet
            if idle_ns is not None and quiet >= idle_ns:
                return name, 'idle', elapsed, quiet
            return None

    def timeout(self):
        """Close the running test's row as `timed_out`; return its identity or None."""
        with self.lock:
            if self.started is None or self.current is None:
                return None, 0
            index = self.current
            if self.pending and self.pending[0] == index:
                self.pending.pop(0)
            ended = self.clock()
            elapsed = ended - self.started
            self.rows.append(dict(test_id=self.names[index], state='timed_out', elapsed_ns=elapsed,
                                  elapsed_scope=INTERVAL_SCOPE,
                                  started_monotonic_ns=self.started, ended_monotonic_ns=ended))
            self.started = None
            self.current = None
            self.timed_out = True
            return self.names[index], elapsed

    def rows_since(self, index):
        """The result rows recorded after the first `index` ones."""
        with self.lock:
            return list(self.rows[index:])

    def needs_diagnostics(self):
        """Whether the runner's stderr must reach the build log despite exit status 0.

        Guardian's runner reports a failing test over the protocol and still exits
        0 in server mode, so the exit status alone would hide a failure's message.
        A failed, leaking, error-logging or timed-out test, an unreadable protocol
        or a dispatched test that never reported all keep the diagnostics.
        """
        with self.lock:
            return (self.malformed or self.timed_out or len(self.rows) < len(self.requested)
                    or any(row['state'] in ('failed', 'timed_out') for row in self.rows))

    def document(self, action, member, returncode):
        with self.lock:
            complete = (self.supported and not self.malformed and not self.timed_out and self.names is not None
                        and self.exit_seen and not self.pending and self.started is None
                        and len(self.rows) == len(self.requested) and returncode == 0)
            return dict(version=1, producer='zig-test-protocol-v1', action_id=action,
                        member_id=telemetry.member_id(action, member),
                        selected=len(self.requested), complete=complete, tests=list(self.rows),
                        runner_interval=self.runner_interval, timed_out=self.timed_out,
                        elapsed_scope=INTERVAL_SCOPE, body_duration_ns=None,
                        selection_scope='actual-client-dispatch',
                        malformed=self.malformed or not self.supported or self.names is None)


def write_all(fd, data):
    while data:
        count = os.write(fd, data)
        data = data[count:]


# Loaded in the parent: the forked child may only make the prctl call.
_LIBC = ctypes.CDLL(None, use_errno=True)
_PRCTL = _LIBC.prctl


def child_parent_death_signal():
    """PDEATHSIG in the forked child, before exec: a killed proxy kills its runner.

    SIGKILL on the proxy leaves no Python cleanup to run, so the kernel must own
    the runner's fate. The signal survives exec.
    """
    _PRCTL(1, signal.SIGKILL, 0, 0, 0)


def kill_group(child):
    """Kill the runner's own session, never a process outside it."""
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        child.kill()


def children_of(pid):
    """The pids that `pid` has forked and not yet reaped, from each thread's `children` list."""
    kids = []
    try:
        tasks = os.listdir('/proc/%d/task' % pid)
    except OSError:
        return kids
    for task in tasks:
        try:
            with open('/proc/%d/task/%s/children' % (pid, task)) as handle:
                kids.extend(int(text) for text in handle.read().split())
        except OSError:
            continue
    return kids


def scanned_children():
    """Map each parent pid to its live children by reading every `/proc/PID/stat`.

    Costs one read per process on the machine, so it is only the fallback for kernels without `children` files.
    """
    kids_by_parent = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open('/proc/%s/stat' % entry, 'rb') as handle:
                raw = handle.read()
        except OSError:
            continue
        fields = raw[raw.rfind(b')') + 2:].split()
        if len(fields) >= 2:
            kids_by_parent.setdefault(int(fields[1]), []).append(int(entry))
    return kids_by_parent


CHILDREN_FILES = os.path.exists('/proc/self/task/%d/children' % os.getpid())


def tree_pids(root):
    """`root` and every process below it, by ancestry, whatever session or group each one is in.

    A child that calls setsid or setpgid still belongs to the tree, so its CPU counts and a kill reaches it.
    """
    found = [root]
    frontier = [root]
    kids_by_parent = None if CHILDREN_FILES else scanned_children()
    while frontier:
        parent = frontier.pop()
        kids = children_of(parent) if CHILDREN_FILES else kids_by_parent.get(parent, [])
        for kid in kids:
            if kid not in found:
                found.append(kid)
                frontier.append(kid)
    return found


def tree_cpu_ticks(root):
    """CPU ticks used by the live processes below `root`, each with the children it has reaped.

    Sums utime, stime, cutime and cstime (`/proc/PID/stat` fields 14-17). A child's ticks move into its
    parent's cutime and cstime when reaped, so the sum keeps growing while the tree works. Orphans reaped
    by init can lower it; the caller reads a fall as no progress for that sample.
    """
    total = 0
    for pid in tree_pids(root):
        try:
            with open('/proc/%d/stat' % pid, 'rb') as handle:
                raw = handle.read()
        except OSError:
            continue
        # Fields after the command name, which is parenthesised and may contain spaces or ')'.
        fields = raw[raw.rfind(b')') + 2:].split()
        if len(fields) >= 15:
            total += sum(int(fields[index]) for index in (11, 12, 13, 14))
    return total


def captured_size(captured):
    try:
        return os.fstat(captured.fileno()).st_size
    except (OSError, ValueError):
        return 0


def emit_captured(captured, start, end):
    """Write captured runner stderr [start, end) without moving the file offset.

    The runner shares the file's offset, so a seek here would redirect its writes.
    """
    while start < end:
        try:
            data = os.pread(captured.fileno(), min(end - start, 1 << 20), start)
        except (OSError, ValueError):
            return
        if not data:
            return
        try:
            write_all(sys.stderr.fileno(), data)
        except (OSError, BrokenPipeError):
            return
        start += len(data)


def captured_tail(captured, start, end):
    """The last `BEACON_STDERR_BYTES` of captured runner stderr [start, end), decoded; empty when it cannot be read."""
    start = max(start, end - BEACON_STDERR_BYTES)
    try:
        return os.pread(captured.fileno(), max(0, end - start), start).decode('utf-8', 'replace')
    except (OSError, ValueError):
        return ''


def beacon_text(test_id, state, stderr_text, command_line):
    """The block a build log shows for one failed test: its `error:` line, what it printed, and the `failed command:` line."""
    verdict = 'timed out' if state == 'timed_out' else 'failed'
    body = stderr_text.rstrip('\n')
    lines = ["error: '%s' %s" % (test_id, verdict)] + ([body] if body else []) + ['failed command: ' + command_line]
    return '\n'.join(lines) + '\n'


def write_beacon(directory, name, text):
    """Publish a beacon whole: written under a dotted name, then moved to `fail-fast.<name>.txt`. A failure changes no verdict."""
    temporary = None
    try:
        path = Path(directory)
        with tempfile.NamedTemporaryFile(dir=path, prefix='.fail-fast.', delete=False) as output:
            temporary = output.name
            output.write(text.encode('utf-8', 'replace'))
        os.replace(temporary, path / ('fail-fast.%s.txt' % name))
        temporary = None
    except OSError:
        pass
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def forward_failures(captured, observer, progress, on_failure=None):
    """Write a failing test's own stderr before its result reaches the build runner.

    The build runner attaches stderr that arrives before a result to that test, so
    the failure keeps its message under its own name. A test's stderr is what the
    runner wrote since the previous result: a server-mode runner starts the next
    test only after the build runner answers the last one.
    """
    rows = observer.rows_since(progress['seen'])
    if not rows:
        return
    size = captured_size(captured)
    emitted = False
    for row in rows:
        if row['state'] in ('failed', 'timed_out'):
            if on_failure is not None:
                on_failure(row, captured_tail(captured, max(progress['boundary'], progress['printed']), size))
            emit_captured(captured, max(progress['boundary'], progress['printed']), size)
            emitted = emitted or size > max(progress['boundary'], progress['printed'])
            progress['printed'] = size
        progress['boundary'] = size
    progress['seen'] += len(rows)
    if emitted:
        time.sleep(FAILURE_ORDERING_SECONDS)


def replay_stderr(captured, progress):
    """Re-emit the runner's captured diagnostics not yet written, once it has failed."""
    emit_captured(captured, progress['printed'], captured_size(captured))


def proxy(command, observer, limits=(None, None), on_failure=None):
    """Forward wire bytes; emit runner stderr only for a real failure.

    `limits` is (idle_ns, wall_ns); a None limit is off, and a breach kills the test (see `Observation.overdue`).
    `on_failure(row, stderr_text)` is called for each failed or timed-out test as its result is seen, once, before the result
    is forwarded; `stderr_text` is what the runner wrote for it.
    """
    captured = tempfile.TemporaryFile()
    try:
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=captured, bufsize=0, close_fds=False, start_new_session=True,
                                 preexec_fn=child_parent_death_signal)
    except BaseException:
        captured.close()
        raise
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
    deadline_hit = False
    progress = {'seen': 0, 'boundary': 0, 'printed': 0}
    # CPU is sampled only when an idle limit exists: every CPU_SAMPLE_SECONDS, or three times per idle window if that is shorter.
    sample_ns = None if limits[0] is None else min(CPU_SAMPLE_SECONDS * 1e9, limits[0] / 3)
    sampled = None  # (monotonic ns, tree CPU ticks) at the last CPU sample
    try:
        while True:
            if any(limit is not None for limit in limits):
                now = observer.clock()
                if sample_ns is not None and (sampled is None or now - sampled[0] >= sample_ns):
                    ticks = tree_cpu_ticks(child.pid)
                    if sampled is not None and ticks > sampled[1]:
                        observer.progress(now)
                    sampled = (now, ticks)
                breach = observer.overdue(now, *limits)
                if breach:
                    name, reason, elapsed, quiet = breach
                    observer.timeout()
                    if on_failure is not None:
                        on_failure(observer.rows[-1], '')
                    if reason == 'idle':
                        sys.stderr.write('test deadline: %s made no CPU progress for %.1f s (limit %.1f s); killed\n'
                                         % (name, quiet / 1e9, limits[0] / 1e9))
                    else:
                        sys.stderr.write('test deadline: %s ran %.1f s (limit %.1f s); killed\n'
                                         % (name, elapsed / 1e9, limits[1] / 1e9))
                    sys.stderr.flush()
                    # Collect the tree before the group dies: a child that left the session is only reachable this way.
                    victims = tree_pids(child.pid)
                    kill_group(child)
                    for pid in victims:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except (ProcessLookupError, PermissionError):
                            pass
                    deadline_hit = True
                    break
            if cancelled and time.monotonic() - cancelled[-1][1] >= 1:
                observer.fail()
                if child.poll() is None:
                    kill_group(child)
                break
            ready, _, _ = select.select([child.stdout.fileno()], [], [], .1)
            if not ready:
                continue
            data = os.read(child.stdout.fileno(), 65536)
            if not data:
                break
            server_frames.feed(data)
            forward_failures(captured, observer, progress, on_failure)
            write_all(sys.stdout.fileno(), data)
        server_frames.finish()
        returncode = child.wait()
        if deadline_hit:
            replay_stderr(captured, progress)
            return DEADLINE_STATUS
        if cancelled:
            return 128 + cancelled[-1][0]
        if returncode != 0 or observer.needs_diagnostics():
            replay_stderr(captured, progress)
        return returncode
    except (OSError, BrokenPipeError):
        observer.fail()
        child.terminate()
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        replay_stderr(captured, progress)
        return child.returncode
    finally:
        child.stdout.close()
        captured.close()
        for number, handler in prior.items():
            signal.signal(number, handler)


def deadline_seconds(text):
    """Parse a positive deadline in seconds; zero disables it and negatives are refused."""
    try:
        seconds = float(text)
    except (TypeError, ValueError):
        raise argparse.ArgumentTypeError('a deadline must be a number of seconds')
    if not math.isfinite(seconds) or seconds < 0:
        raise argparse.ArgumentTypeError('a deadline must be a finite, non-negative number of seconds')
    return seconds


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
    limits = []
    for environment, default in ((IDLE_ENVIRONMENT, DEFAULT_IDLE_SECONDS), (DEADLINE_ENVIRONMENT, DEFAULT_DEADLINE_SECONDS)):
        try:
            seconds = deadline_seconds(os.environ.get(environment, default))
        except argparse.ArgumentTypeError as error:
            parser.error('%s: %s' % (environment, error))
        limits.append(None if seconds == 0 else int(seconds * 1e9))
    observer = Observation(args.root_id)
    started = time.monotonic_ns()
    directory = os.environ.get(args.output_directory_env)
    telemetry.record_rerun(directory, args.action_id, args.member, "native", argv=command,
                           extra={"root_id": args.root_id})
    safe_id = args.action_id.replace('/', '_').replace('\\', '_')
    command_line = ' '.join(['python3'] + [str(word) for word in (argv if argv is not None else sys.argv)])
    announced = []

    def on_failure(row, stderr_text):
        """The first failed test: publish the rows so far, then the beacon that tells the coordinator."""
        if announced or not directory:
            return
        announced.append(row['test_id'])
        telemetry.write_document(Path(directory) / f'{safe_id}.member.{args.member}.json',
                                 observer.document(args.action_id, args.member, 1))
        write_beacon(directory, f'{safe_id}.member.{args.member}',
                     beacon_text(row['test_id'], row['state'], stderr_text, command_line))

    status = proxy(command, observer, tuple(limits), on_failure)
    observer.runner_interval = dict(started_monotonic_ns=started, ended_monotonic_ns=time.monotonic_ns())
    if directory:
        path = Path(directory) / f'{safe_id}.member.{args.member}.json'
        telemetry.write_document(path, observer.document(args.action_id, args.member, status))
    return 128 - status if status < 0 else status


if __name__ == '__main__':
    sys.exit(main())
