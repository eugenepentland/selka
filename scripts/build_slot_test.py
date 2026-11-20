#!/usr/bin/env python3
"""Exercise shared admission with real processes and private, on-disk locks."""
import contextlib
import ctypes
import fcntl
import io
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from build_admission import admission, process_identity

ROOT = Path(__file__).resolve().parents[1]
SLOT = ROOT / "scripts/build-slot.sh"
# A wait on a condition ends the moment the condition holds, so this ceiling costs nothing on a healthy machine and
# only separates "slow" from "stuck" on a loaded one. Starting a job takes two interpreter starts (the wrapper and its
# shadow observer, which the wrapper waits for up to 30 seconds), and a machine short of memory stretches both: with
# the test's processes held to a 32 MiB memory.high, a start takes more than a minute. A waiter that can see its
# command has exited does not wait for the ceiling (see `wait_for`).
FIXTURE_STARTUP_SECONDS = 240
JOB = """
import os, sys, time
from pathlib import Path
root, name, hold, status = sys.argv[1:]
root = Path(root)
with (root / 'events').open('a') as f:
    f.write(name + '\\n')
# The affinity mask is published before the marker that announces the start: a reader that sees the marker
# must find the mask it promises (the marker used to come first, and a loaded machine could show the gap).
(root / (name + '.affinity')).write_text(','.join(map(str, sorted(os.sched_getaffinity(0)))))
(root / (name + '.started')).write_text(str(time.monotonic()))
while hold == '1' and not (root / (name + '.release')).exists():
    time.sleep(.02)
sys.exit(int(status))
"""


# A watcher's daemon stand-in (`dev_loop.py --daemon MODE ROOT NAME HOLD STATUS`): it records its pid, then runs as
# JOB does (mode `job`) or writes the admission markers it inherited (mode `probe`).
WATCH_DAEMON = """
import os, sys
from pathlib import Path
mode = sys.argv[2]
root, name = Path(sys.argv[3]), sys.argv[4]
(root / (name + '.pid')).write_text(str(os.getpid()))
if mode == 'probe':
    keys = ('SELKA_ADMISSION_DIR', 'SELKA_ADMISSION_KIND', 'SELKA_WATCH_SLOT')
    (root / (name + '.markers')).write_text(repr([os.environ.get(key) for key in keys]))
    sys.exit(0)
sys.argv = [sys.argv[0]] + sys.argv[3:]
exec(compile(%r, 'job', 'exec'))
""" % JOB


# Runs a command the way a gate action runs: under the supervisor, in the current directory.
SUPERVISED = """
import os, sys
sys.path.insert(0, sys.argv[1])
from verification_process import run_supervised
raise SystemExit(run_supervised(sys.argv[2:], dict(os.environ)))
"""


def adopt_orphans():
    """Make this process the adopter of orphans: what a job leaves behind once its parent has gone is then our child."""
    ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER


def live_children():
    """pid -> command line of this process's children that are not zombies, from every thread's `children` list."""
    found = {}
    for task in Path("/proc/self/task").iterdir():
        try:
            pids = (task / "children").read_text().split()
        except OSError:
            continue
        for pid in pids:
            try:
                stat = Path(f"/proc/{pid}/stat").read_text()
                if stat[stat.rfind(")") + 2] == "Z":
                    continue
                found[int(pid)] = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            except OSError:
                continue
    return found


def trim_module():
    """The cache trim helper, imported from this checkout's scripts."""
    import worktree_cache_trim
    return worktree_cache_trim


class Admission(unittest.TestCase):
    def setUp(self):
        adopt_orphans()
        # A gate runs this file as a supervised action, which exports SELKA_ADMISSION_SUPERVISED to it: an admission
        # that sees the variable starts no background process (that is what the supervisor needs, and a test of it
        # sets the variable itself). These tests start such processes on purpose and wait for them (`tearDown`).
        patched = mock.patch.dict(os.environ)
        patched.start()
        self.addCleanup(patched.stop)
        os.environ.pop("SELKA_ADMISSION_SUPERVISED", None)
        self.children_before = set(live_children())
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="slot-test-", dir=scratch)
        self.root = Path(self.temp.name)
        self.slots = self.root / "slots"
        self.slots.mkdir()
        # These jobs run in `self.root` unless a test names a fixture tree, and no cache is bounded unless it asks: an
        # admission trims the worktree it runs in, so a fixture left to the caller's directory would trim (and, in
        # a gate, delete the caches of) the checkout under test.
        self.env = dict(os.environ, SELKA_SLOT_DIR=str(self.slots),
                        SELKA_ZIG_CACHE_CAP_GB="0", SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0",
                        SELKA_BUILD_MEM="0", SELKA_GATE_MEM="0", SELKA_TIMING_MEM="0", SELKA_WATCH_MEM="0",
                        SELKA_BUILD_SLOTS="1", SELKA_GATE_SLOTS="1",
                        SELKA_SLOT_SETTLE="0", SELKA_SLOT_POLL="1",
                        SELKA_TIMING_CPUS="",
                        # A lock holder stalled by a loaded machine is waited for as long as a start is.
                        SELKA_SCHEDULER_BUSY_SECONDS=str(FIXTURE_STARTUP_SECONDS))
        self.jobs = []
        self.holders = []
        self.files = []
        self.named = {}

    def tearDown(self):
        for process in self.jobs:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=FIXTURE_STARTUP_SECONDS)
        for pid in self.holders:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for stream in self.files:
            stream.close()
        self.wait_for_observers()
        self.wait_for_measurements()
        self.temp.cleanup()
        self.assertNoLeftovers()

    def assertNoLeftovers(self, patience=30):
        """Fail a test that leaves a process behind: a stub or helper that outlives it runs on into the gate's
        supervisor, which counts it a leftover and ends the action 125. A process that is exiting gets its moment."""
        deadline = time.monotonic() + patience
        while True:
            left = {pid: command for pid, command in live_children().items() if pid not in self.children_before}
            if not left or time.monotonic() > deadline:
                break
            time.sleep(.05)
        for pid in left:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.assertEqual(left, {}, "the test left these processes running")

    def wait_for_observers(self):
        # An observer may still be recording release after its command exits.
        # Keep the private database/log directory until those writes finish.
        script = os.fsencode((ROOT / 'scripts/build_admission.py').resolve())
        executable = Path(sys.executable).resolve()
        slots = os.fsencode(self.slots.resolve())

        def owned(entry):
            argv = (entry / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
            if (len(argv) != 4 or argv[1] != b'-B' or argv[2] != script
                    or argv[3] not in (b'--shadow-watch', b'--lease-watch')
                    or Path(os.fsdecode(argv[0])).resolve() != executable):
                return None
            selected = [item for item in (entry / 'environ').read_bytes().split(b'\0')
                        if item.startswith(b'SELKA_SLOT_DIR=')]
            if selected != [b'SELKA_SLOT_DIR=' + slots]:
                return None
            return tuple(argv), tuple(selected)

        deadline = time.monotonic() + FIXTURE_STARTUP_SECONDS
        while True:
            found = False
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    ownership = owned(entry)
                    if ownership is None:
                        continue
                    pid = int(entry.name)
                    before = process_identity(pid)
                    if before is None:
                        continue
                    descriptor = os.pidfd_open(pid)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
                try:
                    if process_identity(pid) != before or owned(entry) != ownership:
                        continue
                    found = True
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, f'private observer still active: {before}')
                    self.assertTrue(select.select([descriptor], [], [], remaining)[0],
                                    f'private observer did not exit: {before}')
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
                finally:
                    os.close(descriptor)
            if not found:
                return

    def measurements_running(self):
        """Whether a background cache measurement (`worktree_cache_trim.py --measure-only`) of this test still runs."""
        root = os.fsencode(str(self.root))
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                argv = (entry / "cmdline").read_bytes().split(b"\0")
            except OSError:
                continue
            if b"--measure-only" in argv and any(root in item for item in argv):
                return True
        return False

    def wait_for_measurements(self):
        """A measurement writes into the fixture's trees: it ends before the fixture is deleted under it."""
        self.wait_for(lambda: not self.measurements_running(), "the background cache measurements end")

    def record_size(self, tree, path, kib, stamp=0):
        """Add a row to the worktree's sizes record, as a background measurement would have left it."""
        with (tree / ".git" / "prune-caches.sizes").open("a") as stream:
            stream.write("%s\t%d\t%d\n" % (path, stamp, kib))

    def pressure(self):
        """What the machine said about itself when a wait ran out: load and memory/cpu/io stall times."""
        report = {"loadavg": Path("/proc/loadavg").read_text().strip()}
        for resource in ("memory", "cpu", "io"):
            try:
                report[resource + " pressure"] = Path(f"/proc/pressure/{resource}").read_text().strip()
            except OSError:
                pass
        return report

    def wait_for(self, predicate, description, process=None):
        """Wait for `predicate` to hold. A command that exits first can no longer make it hold (the command is the
        process that writes the marker, or prints the ticket), so the wait fails at once instead of at the ceiling."""
        started = time.monotonic()
        deadline = started + FIXTURE_STARTUP_SECONDS
        while not predicate():
            exited = process is not None and process.poll() is not None
            if exited and predicate():
                return
            if exited or time.monotonic() > deadline:
                logs = {p.name: p.read_text() for p in self.root.glob("*.log")}
                shadow = self.slots / 'scheduler-shadow.jsonl'
                if shadow.exists():
                    logs['scheduler-shadow.jsonl'] = shadow.read_text()
                state = (f"the command exited with status {process.returncode}" if exited
                         else f"waited {time.monotonic() - started:.0f} s")
                self.fail(f"Timed out: {description}; {state}; {self.pressure()}; {logs}")
            time.sleep(.02)

    def start(self, name, kind="gate", hold=False, status=0, cwd=None, command=None, wrapper=None, **environment):
        log = (self.root / (name + ".log")).open("w")
        self.files.append(log)
        argv = command if command is not None else [
            sys.executable, "-c", JOB, str(self.root), name, str(int(hold)), str(status)]
        process = subprocess.Popen(
            [*(wrapper or [str(SLOT)]), kind, *argv], env=dict(self.env, **environment),
            cwd=self.root if cwd is None else cwd,
            stdout=log, stderr=log, start_new_session=True)
        self.jobs.append(process)
        self.named[name] = process
        return process

    def fixture_worktree(self, name, cache_kib=3000):
        tree = self.root / name
        (tree / ".zig-cache" / "o").mkdir(parents=True)
        (tree / ".zig-cache" / "o" / "junk").write_bytes(b"x" * (cache_kib * 1024))
        subprocess.run(["git", "init", "-q", str(tree)], check=True)
        stamp = int((tree / ".zig-cache" / "o").stat().st_mtime)
        (tree / ".git" / "prune-caches.sizes").write_text(
            "%s\t%d\t%d\n" % (tree, stamp, cache_kib))
        return tree

    def test_admission_trims_an_over_cap_worktree_cache_then_builds_cold(self):
        tree = self.fixture_worktree("over", 3000)
        first = self.start("trimmed", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001")
        self.finish(first)
        log = (self.root / "trimmed.log").read_text()
        self.assertIn("trimming", log)
        self.assertIn(str(tree), log)
        self.assertFalse((tree / ".zig-cache" / "o" / "junk").exists())
        (tree / "hello.zig").write_text("pub fn main() void {}\n")
        zig = os.environ.get("ZIG") or shutil.which("zig")
        if zig:
            second = self.start("cold", kind="build", cwd=tree,
                                command=[zig, "build-exe", "hello.zig", "-femit-bin=hello",
                                         "--cache-dir", ".zig-cache"],
                                SELKA_ZIG_CACHE_CAP_GB="0.001")
            self.finish(second)
            self.assertTrue((tree / ".zig-cache").is_dir(), "cold build did not recreate its cache")
        else:
            second = self.start("cold", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001")
            self.finish(second)

    def test_an_active_job_of_the_same_worktree_blocks_the_trim(self):
        tree = self.fixture_worktree("over", 3000)
        holder = self.start("holder", kind="build", hold=True, cwd=tree,
                            SELKA_BUILD_SLOTS="2", SELKA_ZIG_CACHE_CAP_GB="0")
        self.started("holder")
        second = self.start("second", kind="build", cwd=tree,
                            SELKA_BUILD_SLOTS="2", SELKA_ZIG_CACHE_CAP_GB="0.001")
        self.finish(second)
        self.assertNotIn("trimming", (self.root / "second.log").read_text())
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        (self.root / "holder.release").touch()
        self.finish(holder)

    def test_no_cache_is_renamed_while_a_job_of_the_worktree_runs_not_even_by_the_background_walk(self):
        # The walk that an admission starts runs on after the admission, while the job runs, and outside the lock that
        # keeps a rename safe: it must not rename (or delete) anything but what an earlier trim already renamed. Every
        # cache here is over its cap on the record, and a job of the worktree is running throughout.
        tree = self.fixture_worktree("over", 3000)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 2_000_000)
        self.record_size(tree, tier, 1954)
        unit = self.suite_work_directory(tree, "core-tests/a_test", kib=2048)
        caps = dict(SELKA_ZIG_CACHE_CAP_GB="0.001", SELKA_CACHE_TIERS_CAP_GB="0.001", SELKA_TEST_CACHES_CAP_GB="0.001",
                    SELKA_BUILD_SLOTS="2")
        holder = self.start("holder", kind="build", hold=True, cwd=tree, **dict(caps, SELKA_ZIG_CACHE_CAP_GB="0",
                            SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0"))
        self.started("holder")
        for name in ("second", "third"):
            self.finish(self.start(name, kind="build", cwd=tree, **caps))
        self.wait_for_measurements()
        stamp = trim_module().measure_stamp(tree)
        self.assertGreater(stamp.stat().st_size, 0, "the admissions started the walk")
        for path in ((tree / ".zig-cache" / "o" / "junk"), tier / "junk", unit):
            self.assertTrue(path.exists(), path)
        self.assertEqual(sorted(path.name for path in tree.iterdir() if ".trim-" in path.name), [])
        self.assertNotIn("trimming", (self.root / "second.log").read_text() + (self.root / "third.log").read_text())
        # The walk is a measurement: it recorded the test caches' sizes, and still renamed nothing.
        self.assertIn(str(unit), (tree / ".selka-cache" / "test-cache-sizes.tsv").read_text())
        (self.root / "holder.release").touch()
        self.finish(holder)
        # With the worktree idle again, the next admission decides on what the walk recorded and trims.
        last = self.start("last", kind="build", cwd=tree, **caps)
        self.finish(last)
        self.assertIn("trimming", (self.root / "last.log").read_text())
        self.assertFalse((tree / ".zig-cache" / "o" / "junk").exists())
        self.assertFalse(tier.exists())
        self.assertFalse(unit.exists())

    def test_a_measurement_run_by_hand_renames_nothing_either(self):
        tree = self.fixture_worktree("over", 3000)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 2_000_000)
        unit = self.suite_work_directory(tree, "core-tests/a_test", kib=2048)
        sizes = tree / ".git" / "prune-caches.sizes"
        trim = trim_module()
        argv = ["--worktree", str(tree), "--sizes", str(sizes), "--measure-only", "--zig-cap-gb", "0.001",
                "--tiers-cap-gb", "0.001", "--tests-cap-gb", "0.001"]
        self.assertEqual(trim.main(argv), 0)
        for path in ((tree / ".zig-cache" / "o" / "junk"), tier / "junk", unit):
            self.assertTrue(path.exists(), path)
        self.assertEqual(sorted(path.name for path in tree.iterdir() if ".trim-" in path.name), [])
        self.assertIn(str(tier), sizes.read_text())
        self.assertIn(str(unit), (tree / ".selka-cache" / "test-cache-sizes.tsv").read_text())

    def test_the_walk_runs_in_the_background_and_at_most_once_in_ten_minutes(self):
        # What cost seconds at every admission, under the lock every other admission waits for, is now one walk in
        # ten minutes per worktree, in a process of its own that holds no lock. A `du` that waits for the test stands
        # in for a walk over millions of entries: the job must start, run and end while the walk is still blocked.
        trim = trim_module()
        tree = self.fixture_worktree("measured", 10)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 100_000)
        log = self.root / "du.log"
        release = self.root / "du.release"
        tools = self.root / "tools"
        tools.mkdir()
        shim = tools / "du"
        shim.write_text('#!/bin/sh\necho "$PPID" >> "%s"\nwhile [ ! -e "%s" ]; do sleep 0.05; done\nexec "%s" "$@"\n'
                        % (log, release, shutil.which("du")))
        shim.chmod(0o755)
        env = dict(PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   SELKA_ZIG_CACHE_CAP_GB="12", SELKA_CACHE_TIERS_CAP_GB="12")
        self.finish(self.start("first", kind="build", cwd=tree, **env))
        self.wait_for(lambda: log.exists() and log.read_text().split(), "the background walk starts")
        walker = int(log.read_text().split()[0])
        self.assertFalse(release.exists(), "the job ended while the walk was still blocked")
        self.assertFalse(self.admission_locked())
        held = [os.path.realpath(f"/proc/{walker}/fd/{fd}") for fd in os.listdir(f"/proc/{walker}/fd")]
        self.assertNotIn(os.path.realpath(self.slots / "admit.lock"), held)
        # Admissions within the ten minutes start no second walk, while the first still runs and after it.
        for name in ("second", "third"):
            self.finish(self.start(name, kind="build", cwd=tree, **env))
        release.touch()
        self.wait_for_measurements()
        self.finish(self.start("fourth", kind="build", cwd=tree, **env))
        self.wait_for_measurements()
        self.assertEqual(set(log.read_text().split()), {str(walker)})
        # Ten minutes later the next admission starts one.
        stamp = trim.measure_stamp(tree)
        old = time.time() - trim.MEASURE_INTERVAL_SECONDS - 60
        os.utime(stamp, (old, old))
        self.finish(self.start("later", kind="build", cwd=tree, **env))
        self.wait_for_measurements()
        self.assertEqual(len(set(log.read_text().split())), 2)

    def test_an_admission_scans_no_cache_and_the_measurement_does(self):
        trim = trim_module()
        tree = self.fixture_worktree("scan", 10)
        sizes = tree / ".git" / "prune-caches.sizes"
        admission = ["--worktree", str(tree), "--sizes", str(sizes), "--slot-dir", str(self.slots), "--own-slot", "build1",
                     "--zig-cap-gb", "12", "--tiers-cap-gb", "12", "--tests-cap-gb", "12"]
        with mock.patch.object(trim, "stale_asides", return_value=[]) as scan, \
                mock.patch.object(trim, "spawn_measure") as spawn:
            self.assertEqual(trim.main(admission), 0)
            self.assertEqual(trim.main(admission), 0)
        self.assertEqual((scan.call_count, spawn.call_count), (0, 1))
        with mock.patch.object(trim, "stale_asides", return_value=[]) as scan:
            self.assertEqual(trim.main([*admission[:4], "--measure-only"]), 0)
        self.assertEqual(scan.call_count, 1)

    def test_the_asides_scan_skips_work_directories_and_tiers(self):
        # An aside is a sibling of the cache it replaced. Most of a worktree's millions of entries are inside work
        # directories and tiers, which cannot hold one: the scan lists neither.
        trim = trim_module()
        tree = self.root / "asides"
        work = self.suite_work_directory(tree, "core-tests/a_test")
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        inside = (work / "inner.trim-1", tier / "inner.trim-2")
        beside = (tree / ".selka-cache" / "core-tests" / "a_test.trim-3", tree / ".selka-cache" / "core" / "programs-v1.trim-4",
                  tree / ".zig-cache.trim-5")
        for path in (*inside, *beside):
            path.mkdir(parents=True)
        later = time.time() + trim.ASIDE_GRACE_SECONDS + 60
        self.assertEqual(trim.stale_asides(tree, later), sorted(beside))

    def hold_coordinator_lock(self, tree):
        """What `verify_cache.main` does for a whole request: the coordinator lock of this worktree, held exclusively."""
        import worktree_cache_trim as trim
        lock = tree / trim.COORDINATOR_LOCK
        lock.parent.mkdir(parents=True, exist_ok=True)
        stream = lock.open("a")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        return stream

    def test_a_running_coordinator_blocks_the_trim_of_its_worktree_only(self):
        # F48. A coordinator holds no slot while it waits for admitted work, yet it watches the prepared artifacts in
        # `.zig-cache`: a rename of that directory fails its run. Its lock is what proves the worktree busy, for the
        # admissions of its own gate as for anyone else's.
        tree = self.fixture_worktree("over", 3000)
        other = self.fixture_worktree("other", 3000)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 2_000_000)
        self.record_size(tree, tier, 1954)
        stream = self.hold_coordinator_lock(tree)
        blocked = self.start("blocked", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001",
                             SELKA_CACHE_TIERS_CAP_GB="0.001")
        self.finish(blocked)
        log = (self.root / "blocked.log").read_text()
        self.assertNotIn(".zig-cache", log)
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        # What the coordinator does not watch is bounded as before.
        self.assertIn("programs-v1", log)
        self.assertFalse(tier.exists())
        # Another worktree's coordinator does not stop this worktree's trim: the lock is per worktree.
        elsewhere = self.start("elsewhere", kind="build", cwd=other, SELKA_ZIG_CACHE_CAP_GB="0.001")
        self.finish(elsewhere)
        self.assertIn("trimming", (self.root / "elsewhere.log").read_text())
        self.assertFalse((other / ".zig-cache" / "o" / "junk").exists())
        # Once the request ends, the lock is free and the next admission trims as before.
        fcntl.flock(stream, fcntl.LOCK_UN)
        trimmed = self.start("trimmed", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001")
        self.finish(trimmed)
        self.assertIn("trimming", (self.root / "trimmed.log").read_text())
        self.assertFalse((tree / ".zig-cache" / "o" / "junk").exists())

    def wait_for_asides_gone(self, tree):
        self.wait_for(lambda: not [path for path in tree.iterdir() if ".trim-" in path.name],
                      "the background deletion of " + tree.name + " finishes")

    def test_a_coordinator_applies_the_caps_itself_before_it_watches_anything(self):
        # With its lock counting as a busy worktree, a worktree that only runs gates would never be bounded. The
        # coordinator applies the caps once, at the start of its request, as an admission does.
        import worktree_cache_trim as trim
        env = dict(self.env, SELKA_ZIG_CACHE_CAP_GB="0.001")
        tree = self.fixture_worktree("over", 3000)
        self.hold_coordinator_lock(tree)
        self.assertIsNone(trim.bound_for_coordinator(tree, self.slots, env))
        self.assertFalse((tree / ".zig-cache").exists())
        self.wait_for_asides_gone(tree)
        # Under the caps there is nothing to do.
        small = self.fixture_worktree("small", 10)
        self.hold_coordinator_lock(small)
        self.assertIsNone(trim.bound_for_coordinator(small, self.slots, env))
        self.assertTrue((small / ".zig-cache" / "o" / "junk").exists())
        # Only `.zig-cache` is the coordinator's to bound at its start: the other caches are not watched, and a warm
        # request must not pay for walking them.
        tier = small / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 2_000_000)
        self.assertIsNone(trim.bound_for_coordinator(small, self.slots, dict(env, SELKA_CACHE_TIERS_CAP_GB="0.001")))
        self.assertTrue(tier.exists())

    def test_a_coordinator_leaves_a_worktree_with_an_active_job_alone(self):
        import worktree_cache_trim as trim
        env = dict(self.env, SELKA_ZIG_CACHE_CAP_GB="0.001")
        tree = self.fixture_worktree("over", 3000)
        self.hold_coordinator_lock(tree)
        holder = self.start("holder", kind="build", hold=True, cwd=tree, SELKA_BUILD_SLOTS="2")
        self.started("holder")
        self.assertIsNone(trim.bound_for_coordinator(tree, self.slots, env))
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        (self.root / "holder.release").touch()
        self.finish(holder)

    def test_a_coordinator_waits_for_the_admission_lock_then_goes_without_the_caps(self):
        # An admission trims under the admission lock, so no job of the worktree can start between its check and its
        # rename. The coordinator takes the same lock; one that stays busy (a timing window) leaves the caps to the
        # next admission rather than hold up the request.
        import worktree_cache_trim as trim
        env = dict(self.env, SELKA_ZIG_CACHE_CAP_GB="0.001")
        tree = self.fixture_worktree("over", 3000)
        self.hold_coordinator_lock(tree)
        busy = (self.slots / "admit.lock").open("a")
        self.files.append(busy)
        fcntl.flock(busy, fcntl.LOCK_EX)
        # A cache within the cap needs no lock, so a busy one holds nothing up.
        small = self.fixture_worktree("small", 10)
        self.hold_coordinator_lock(small)
        self.assertIsNone(trim.bound_for_coordinator(small, self.slots, env, wait_seconds=0.3))
        reason = trim.bound_for_coordinator(tree, self.slots, env, wait_seconds=0.3)
        self.assertRegex(reason, "admission lock stayed busy")
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        fcntl.flock(busy, fcntl.LOCK_UN)
        self.assertIsNone(trim.bound_for_coordinator(tree, self.slots, env, wait_seconds=0.3))
        self.assertFalse((tree / ".zig-cache").exists())
        self.wait_for_asides_gone(tree)

    def test_a_trim_inside_a_supervised_job_of_its_own_worktree_leaves_nothing_behind(self):
        # A gate action's tests start admissions of their own, with private slot directories, in the checkout the action
        # runs in. Its caches are over the cap and deleting them is slow (a shim `rm`, as on a 30 GiB cache). Started
        # inside the action's supervisor, the deletion is a descendant that outlives the closeout: the action ends 125
        # with every step green, the supervisor kills the deletion half-done, and a cache the action was using is gone.
        # An admission inside a supervised job of its own worktree is that job's own business: it trims nothing.
        tree = self.fixture_worktree("over", 3000)
        shim = self.root / "shim"
        shim.mkdir()
        (shim / "rm").write_text('#!/bin/sh\nsleep 5\nexec /bin/rm "$@"\n')
        (shim / "rm").chmod(0o755)
        environment = dict(self.env, PATH=str(shim) + os.pathsep + os.environ["PATH"], SELKA_ZIG_CACHE_CAP_GB="0.001")
        completed = subprocess.run(
            [sys.executable, "-c", SUPERVISED, str(ROOT / "scripts"), str(SLOT), "build", sys.executable, "-c", "pass"],
            cwd=tree, env=environment, capture_output=True, text=True, timeout=FIXTURE_STARTUP_SECONDS)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertNotIn("trimming", completed.stderr)
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        self.assertEqual(sorted(path.name for path in tree.iterdir() if ".trim-" in path.name), [])

    def test_a_job_that_leaves_a_process_behind_fails_its_test_and_loses_the_process(self):
        # A job whose detached helper outlives it (what a stub that ignores TERM or a settle timer can do).
        code = "import subprocess; subprocess.Popen(['sleep', '31'], start_new_session=True)"
        self.finish(self.start("leaves", command=[sys.executable, "-c", code]))
        with self.assertRaisesRegex(AssertionError, "(?s)sleep 31.*left these processes running"):
            self.assertNoLeftovers(patience=1)
        self.assertNoLeftovers(patience=30)  # the process was killed: once it is gone the check is quiet

    def test_the_fixtures_cannot_trim_the_checkout_they_run_from(self):
        # An admission trims the worktree it runs in. A fixture that kept the caller's directory (the checkout) and the
        # caller's cache bounds would trim, and in a gate delete the caches of, the checkout under test.
        caps = ("SELKA_ZIG_CACHE_CAP_GB", "SELKA_CACHE_TIERS_CAP_GB", "SELKA_TEST_CACHES_CAP_GB")
        self.assertEqual([self.env[name] for name in caps], ["0", "0", "0"])
        seen = self.root / "cwd"
        process = self.start("neutral", kind="build",
                             command=[sys.executable, "-c", f"import os; open({str(seen)!r}, 'w').write(os.getcwd())"])
        self.finish(process)
        self.assertEqual(Path(seen.read_text()).resolve(), self.root.resolve())
        # Even pointed at the checkout, the trimmer under the fixtures' environment bounds nothing and records nothing.
        sizes = self.root / "sizes-of-the-checkout"
        completed = subprocess.run(
            [sys.executable, "-B", str(ROOT / "scripts/worktree_cache_trim.py"), "--worktree", str(ROOT), "--sizes", str(sizes),
             "--slot-dir", str(self.slots), "--own-slot", "build1",
             "--zig-cap-gb", self.env[caps[0]], "--tiers-cap-gb", self.env[caps[1]], "--tests-cap-gb", self.env[caps[2]]],
            env=self.env, capture_output=True, text=True, timeout=FIXTURE_STARTUP_SECONDS)
        self.assertEqual((completed.returncode, completed.stdout, completed.stderr), (0, "", ""))
        self.assertFalse(sizes.exists())

    def test_a_cut_off_deletion_is_found_by_the_scan(self):
        tree = self.root / "cut"
        stale = tree / ".zig-cache.trim-111"
        nested = tree / ".selka-cache" / "core" / "programs-v1.trim-222"
        fresh = tree / ".zig-cache.trim-333"
        others = (tree / "notes.trim-444", tree / ".selka-cache" / "evidence", tree / ".zig-cache")
        for path in (stale, nested, fresh, *others):
            path.mkdir(parents=True)
            (path / "junk").write_text("x")
        (tree / "file.trim-555").write_text("a file, not an aside\n")
        import worktree_cache_trim as trim
        now = time.time()
        self.assertEqual(trim.stale_asides(tree, now), [])
        later = now + trim.ASIDE_GRACE_SECONDS + 60
        self.assertEqual(trim.stale_asides(tree, later), sorted([stale, nested, fresh]))
        # The suffix is a process number only this module writes; the same name under the worktree itself is not its own.
        self.assertNotIn(tree / "notes.trim-444", trim.stale_asides(tree, later))

    def test_the_background_measurement_finishes_a_cut_off_deletion(self):
        # An admission no longer scans for the deletions an earlier trim left half done (that scan is most of what an
        # admission cost); the measurement does, and its deletions are the one thing it removes.
        trim = trim_module()
        tree = self.fixture_worktree("cut", 10)
        stale = tree / ".zig-cache.trim-111"
        (stale / "o").mkdir(parents=True)
        (stale / "o" / "junk").write_text("x")
        live = tree / ".zig-cache" / "o" / "junk"
        with mock.patch.object(trim, "ASIDE_GRACE_SECONDS", -1):
            argv = ["--worktree", str(tree), "--sizes", str(tree / ".git" / "prune-caches.sizes"), "--measure-only"]
            self.assertEqual(trim.main(argv), 0)
        self.wait_for(lambda: not stale.exists(), "the half-done deletion is finished")
        self.assertTrue(live.exists())

    def shim(self, name, log, body="exec", block=None):
        """A tool on a PATH of its own that records each call (its parent's pid and arguments) and then runs the real one.

        BODY "exec" runs the real tool at once; BLOCK is a path the shim waits for before it does; a BODY that is
        "sleep N" sleeps N seconds first, as a slow `du` does."""
        tools = self.root / "shims"
        tools.mkdir(exist_ok=True)
        path = tools / name
        wait = ('while [ ! -e "%s" ]; do sleep 0.05; done\n' % block) if block else ""
        nap = (body + "\n") if body.startswith("sleep") else ""
        path.write_text('#!/bin/sh\necho "$PPID $*" >> "%s"\n%s%sexec "%s" "$@"\n'
                        % (log, wait, nap, shutil.which(name)))
        path.chmod(0o755)
        return str(tools) + os.pathsep + os.environ["PATH"]

    def over_cap_record(self, tree, kib, stamp=0):
        """The sizes record's row for the worktree: KIB at STAMP (a stamp that is not the cache's own)."""
        (tree / ".git" / "prune-caches.sizes").write_text("%s\t%d\t%d\n" % (tree, stamp, kib))

    def admission_arguments(self, tree, zig="0.001", tiers="0", tests="0"):
        return ["--worktree", str(tree), "--sizes", str(tree / ".git" / "prune-caches.sizes"),
                "--slot-dir", str(self.slots), "--own-slot", "build1",
                "--zig-cap-gb", zig, "--tiers-cap-gb", tiers, "--tests-cap-gb", tests]

    def test_a_changed_cache_whose_walk_is_too_slow_is_left_alone_not_renamed_on_the_old_figure(self):
        # The record says 40 GiB for a stamp the cache no longer has, and the cache holds one small file. The bounded
        # walk that would settle it times out (a loaded machine is when it does). The walk this replaced left the cache
        # alone then; keeping the old figure renamed a fresh cache aside.
        trim = trim_module()
        tree = self.fixture_worktree("fresh", 1)
        self.over_cap_record(tree, 40 * 1048576)
        log = self.root / "du.log"
        path = self.shim("du", log, body="sleep 3")
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, PATH=path), mock.patch.object(trim, "spawn_measure"), \
                contextlib.redirect_stderr(stderr):
            self.assertEqual(trim.main(self.admission_arguments(tree)), 0)
        self.assertTrue(log.read_text().split(), "the confirming walk ran")
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        self.assertNotIn("trimming", stderr.getvalue())
        self.assertIn(str(40 * 1048576), (tree / ".git" / "prune-caches.sizes").read_text())

    def test_a_tier_whose_walk_is_too_slow_is_left_alone_too(self):
        trim = trim_module()
        tree = self.fixture_worktree("tiers", 1)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 1000)
        (tree / ".git" / "prune-caches.sizes").write_text("%s\t0\t%d\n" % (tier, 40 * 1048576))
        path = self.shim("du", self.root / "du.log", body="sleep 3")
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, PATH=path), mock.patch.object(trim, "spawn_measure"), \
                contextlib.redirect_stderr(stderr):
            self.assertEqual(trim.main(self.admission_arguments(tree, zig="0", tiers="0.001")), 0)
        self.assertTrue(tier.exists())
        self.assertNotIn("trimming", stderr.getvalue())

    def test_a_walk_that_finds_a_cache_under_its_cap_is_written_back_so_no_admission_repeats_it(self):
        trim = trim_module()
        tree = self.fixture_worktree("settled", 1)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 1000)
        sizes = tree / ".git" / "prune-caches.sizes"
        sizes.write_text("%s\t0\t%d\n%s\t0\t%d\n" % (tree, 40 * 1048576, tier, 40 * 1048576))
        log = self.root / "du.log"
        path = self.shim("du", log)
        arguments = self.admission_arguments(tree, zig="12", tiers="12")
        with mock.patch.dict(os.environ, PATH=path), mock.patch.object(trim, "spawn_measure"):
            self.assertEqual(trim.main(arguments), 0)
            first = len(log.read_text().split("\n")) - 1
            self.assertEqual(trim.main(arguments), 0)
            second = len(log.read_text().split("\n")) - 1
        self.assertEqual((first, second), (2, 2), "one confirming walk per cache, once")
        rows = {line.split("\t")[0]: int(line.split("\t")[2]) for line in sizes.read_text().splitlines()}
        self.assertLess(rows[str(tree)], 1048576)
        self.assertLess(rows[str(tier)], 1048576)
        self.assertTrue((tree / ".zig-cache").exists() and tier.exists())

    def test_a_measurement_merges_into_the_record_as_it_is_when_the_walk_ends(self):
        # The record is shared by every worktree of the repository and a walk takes minutes. A walk that read it first
        # and wrote it back last restored a row another worktree's trim had just removed and dropped the figures that
        # worktree had just written.
        trim = trim_module()
        tree = self.fixture_worktree("walker", 1)
        tier = tree / ".selka-cache" / "core" / "programs-v1"
        tier.mkdir(parents=True)
        (tier / "junk").write_bytes(b"x" * 1000)
        sizes = tree / ".git" / "prune-caches.sizes"
        sizes.write_text("/elsewhere/removed\t5\t99\n")
        log = self.root / "du.log"
        release = self.root / "du.release"
        path = self.shim("du", log, block=release)
        walker = subprocess.Popen(
            [sys.executable, "-B", str(ROOT / "scripts/worktree_cache_trim.py"), "--measure-only", "--worktree", str(tree),
             "--sizes", str(sizes), "--tiers-cap-gb", "10"],
            env=dict(os.environ, PATH=path), start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.jobs.append(walker)
        self.wait_for(lambda: log.exists() and log.read_text().split(), "the walk reaches its first du", walker)
        # While it walks, another worktree's trim removes a row and writes its own.
        trim.update_sizes(sizes, {"/elsewhere/written": (7, 123)}, drop=["/elsewhere/removed"])
        release.touch()
        self.finish(walker)
        record = sizes.read_text()
        self.assertNotIn("/elsewhere/removed", record)
        self.assertIn("/elsewhere/written\t7\t123", record)
        self.assertIn(str(tier), record)

    def test_a_supervised_action_that_admits_from_another_worktree_ends_clean_not_125(self):
        # The supervisor counts every process still running at the end of its action as a leftover and ends the action
        # 125. An admission from a fixture inside an action (verify_cache_test's, in a gate) used to start a background
        # walk that outlived the action's two seconds of grace: here a walk that stays 4 s in `du`.
        tree = self.fixture_worktree("inside", 1)
        (tree / ".selka-cache" / "core" / "programs-v1").mkdir(parents=True)
        ((tree / ".selka-cache" / "core" / "programs-v1") / "junk").write_bytes(b"x" * 1000)
        path = self.shim("du", self.root / "du.log", body="sleep 4")
        environment = dict(self.env, PATH=path, SELKA_ZIG_CACHE_CAP_GB="12", SELKA_CACHE_TIERS_CAP_GB="12")
        completed = subprocess.run(
            [sys.executable, "-c", SUPERVISED, str(ROOT / "scripts"), "sh", "-c",
             "cd '%s' && '%s' build true" % (tree, SLOT)],
            cwd=self.root, env=environment, capture_output=True, text=True, timeout=FIXTURE_STARTUP_SECONDS)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertFalse(self.measurements_running())
        self.assertFalse(trim_module().measure_stamp(tree).exists(), "nothing was requested, so nothing was stamped")

    def test_nothing_is_requested_or_detached_inside_a_supervised_action_but_a_gate_outside_one_still_measures(self):
        # A worktree that only ever runs gates is measured by the admission of the gate itself (it runs before the
        # job, outside the action the job's supervisor wraps) and by `bound_for_coordinator`.
        trim = trim_module()
        tree = self.fixture_worktree("gates", 1)
        with mock.patch.object(trim, "spawn_measure") as spawn:
            self.assertTrue(trim.request_measure(tree, tree / ".git" / "prune-caches.sizes", 10))
        self.assertEqual(spawn.call_count, 1)
        other = self.fixture_worktree("inside-action", 1)
        with mock.patch.dict(os.environ, {trim.SUPERVISED_ROOT: str(self.root)}), \
                mock.patch.object(trim, "spawn_measure") as spawn, mock.patch.object(trim.subprocess, "Popen") as popen:
            self.assertFalse(trim.request_measure(other, other / ".git" / "prune-caches.sizes", 10))
            trim.detach(["sleep", "1"])
            trim.delete_later([other / "nothing"])
        self.assertEqual((spawn.call_count, popen.call_count), (0, 0))

    def test_the_stamp_lives_in_the_worktree_and_a_worktree_without_a_cache_gets_none(self):
        trim = trim_module()
        tree = self.fixture_worktree("stamped", 1)
        sizes = tree / ".git" / "prune-caches.sizes"
        with mock.patch.object(trim, "spawn_measure"):
            self.assertTrue(trim.request_measure(tree, sizes, 10))
            bare = self.root / "bare"
            bare.mkdir()
            subprocess.run(["git", "init", "-q", str(bare)], check=True)
            self.assertFalse(trim.request_measure(bare, bare / ".git" / "prune-caches.sizes", 10))
        self.assertEqual(trim.measure_stamp(tree), tree / ".selka-cache" / "trim-measured")
        self.assertTrue(trim.measure_stamp(tree).read_text().strip())
        self.assertEqual([entry.name for entry in (tree / ".git").iterdir() if "measured" in entry.name], [])
        self.assertFalse((bare / ".selka-cache").exists())

    def test_a_trim_never_touches_another_worktrees_cache(self):
        big = self.fixture_worktree("big", 3000)
        small = self.fixture_worktree("small", 10)
        process = self.start("small-job", kind="build", cwd=small, SELKA_ZIG_CACHE_CAP_GB="0.001")
        self.finish(process)
        self.assertNotIn("trimming", (self.root / "small-job.log").read_text())
        self.assertTrue((big / ".zig-cache" / "o" / "junk").exists())
        self.assertTrue((small / ".zig-cache" / "o" / "junk").exists())

    def test_regenerable_selka_cache_tiers_are_bounded_but_evidence_survives(self):
        tree = self.root / "tiers"
        (tree / ".selka-cache" / "core" / "programs-v1").mkdir(parents=True)
        (tree / ".selka-cache" / "core" / "programs-v1" / "junk").write_bytes(b"x" * 2_000_000)
        (tree / ".selka-cache" / "verification-v3").mkdir(parents=True)
        (tree / ".selka-cache" / "verification-v3" / "evidence.json").write_text("keep\n")
        subprocess.run(["git", "init", "-q", str(tree)], check=True)
        # An admission decides on a recorded size and walks nothing: the record is what a measurement left.
        self.record_size(tree, tree / ".selka-cache" / "core" / "programs-v1", 1954)
        process = self.start("tiers-job", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                             SELKA_CACHE_TIERS_CAP_GB="0.001")
        self.finish(process)
        log = (self.root / "tiers-job.log").read_text()
        self.assertIn("programs-v1", log)
        self.assertFalse((tree / ".selka-cache" / "core" / "programs-v1").exists())
        self.assertTrue((tree / ".selka-cache" / "verification-v3" / "evidence.json").exists())

    def suite_work_directory(self, tree, relative, kib=1024, age_hours=0.0):
        path = tree / ".selka-cache" / relative
        path.mkdir(parents=True)
        (path / ".retention.lock").touch()
        (path / "junk").write_bytes(b"x" * (kib * 1024))
        stamp = time.time() - age_hours * 3600
        for entry in (path / ".retention.lock", path / "junk", path):
            os.utime(entry, (stamp, stamp))
        return path

    def test_test_caches_are_bounded_least_recently_used_first_and_a_held_lease_is_skipped(self):
        tree = self.root / "suites"
        held = self.suite_work_directory(tree, "core-tests/held_test", age_hours=72)
        release = self.suite_work_directory(tree, "lang-tests-release", age_hours=48)
        old = self.suite_work_directory(tree, "core-tests/old_test", age_hours=24)
        program = self.suite_work_directory(tree, "unit-tests/core/build/abc", age_hours=12)
        new = self.suite_work_directory(tree, "core-tests/new_test")
        notes = tree / ".selka-cache" / "core-tests" / "notes"
        notes.mkdir()
        (notes / "kept.txt").write_text("not a work directory\n")
        units = (held, release, old, program, new)
        (tree / ".selka-cache" / "test-cache-sizes.tsv").write_text("".join("%s\t1024\n" % unit for unit in units))
        subprocess.run(["git", "init", "-q", str(tree)], check=True)
        lease = (held / ".retention.lock").open("a")
        self.files.append(lease)
        fcntl.flock(lease, fcntl.LOCK_SH)
        # Five 1 MiB directories against a 2 MiB bound: the three oldest unheld ones go, the held one stays.
        process = self.start("suites-job", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                             SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0.002")
        self.finish(process)
        log = (self.root / "suites-job.log").read_text()
        self.assertEqual(log.count("trimming"), 1, log)
        self.assertIn("test caches 5 MiB to 2 MiB (cap 2 MiB, 3 work directories)", log)
        self.assertEqual([unit.exists() for unit in units], [True, False, False, False, True])
        self.assertTrue((notes / "kept.txt").exists())
        record = (tree / ".selka-cache" / "test-cache-sizes.tsv").read_text()
        self.assertEqual(sorted(record.split()[0::2]), sorted([str(held), str(new)]))

    def seed_variant(self, tree, name, store_hours, seed_hours, with_lease=True):
        """A `runtime_seed` variant as `runtime_seed.zig` leaves it: a store and a work directory that each hold a
        lease, and the variant's own lease, which the seed touches on every use."""
        variant = tree / ".selka-cache" / "core-tests" / "runtime_seed" / name
        for member in ("store", "work"):
            (variant / member).mkdir(parents=True)
            (variant / member / ".retention.lock").touch()
            (variant / member / "junk").write_bytes(b"x" * 512 * 1024)
        (variant / "seed.selka").write_text("func main() -> int:\n    return 0\n")
        if with_lease:
            (variant / ".retention.lock").touch()
        stamp = time.time() - store_hours * 3600
        for entry in (variant / "store" / ".retention.lock", variant / "store" / "junk", variant / "store"):
            os.utime(entry, (stamp, stamp))
        stamp = time.time() - seed_hours * 3600
        for entry in (variant / ".retention.lock", variant / "seed.selka", variant / "work" / ".retention.lock",
                      variant / "work" / "junk", variant / "work", variant):
            if entry.exists():
                os.utime(entry, (stamp, stamp))
        return variant

    def test_a_seed_variant_is_one_unit_ranked_by_its_last_seed_and_a_held_lease_keeps_it_whole(self):
        # The store of a variant is written once and only read afterwards, so it is always the older half. When the
        # trimmer ranked it alone it went first and left a work directory whose replay hid the loss (SeedFailed).
        tree = self.root / "seeds"
        held = self.seed_variant(tree, "held", store_hours=200, seed_hours=100)
        stale = self.seed_variant(tree, "stale", store_hours=200, seed_hours=48)
        current = self.seed_variant(tree, "current", store_hours=200, seed_hours=0)
        other = self.suite_work_directory(tree, "core-tests/other_test", age_hours=24)
        units = (held, stale, current, other)
        (tree / ".selka-cache" / "test-cache-sizes.tsv").write_text("".join("%s\t1024\n" % unit for unit in units))
        subprocess.run(["git", "init", "-q", str(tree)], check=True)
        lease = (held / ".retention.lock").open("a")
        self.files.append(lease)
        fcntl.flock(lease, fcntl.LOCK_SH)
        # Four 1 MiB units against a 2 MiB bound: the stale variant and the older test directory go, whole; the variant a
        # seed holds stays, and so does the one used last even though its store is the oldest thing in the tree.
        process = self.start("seeds-job", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                             SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0.002")
        self.finish(process)
        log = (self.root / "seeds-job.log").read_text()
        self.assertIn("test caches 4 MiB to 2 MiB (cap 2 MiB, 2 work directories)", log)
        self.assertEqual([unit.exists() for unit in units], [True, False, True, False])
        for variant in (held, current):
            self.assertEqual(sorted(entry.name for entry in variant.iterdir()),
                             [".retention.lock", "seed.selka", "store", "work"])

    def test_an_unmeasured_test_cache_is_measured_in_the_background_then_trimmed(self):
        tree = self.root / "unmeasured"
        unit = self.suite_work_directory(tree, "core-tests/a_test", kib=2048)
        subprocess.run(["git", "init", "-q", str(tree)], check=True)
        record = tree / ".selka-cache" / "test-cache-sizes.tsv"
        first = self.start("measure-job", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                           SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0.001")
        self.finish(first)
        self.assertNotIn("trimming", (self.root / "measure-job.log").read_text())
        self.assertTrue(unit.exists())
        self.wait_for(lambda: record.exists() and str(unit) in record.read_text(),
                      "the background measurement records the test cache")
        second = self.start("trim-job", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                            SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0.001")
        self.finish(second)
        self.assertIn("1 work directory)", (self.root / "trim-job.log").read_text())
        self.assertFalse(unit.exists())

    def test_zero_zig_cache_cap_turns_the_trim_off(self):
        tree = self.fixture_worktree("over", 3000)
        process = self.start("no-cap", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0",
                             SELKA_CACHE_TIERS_CAP_GB="0")
        self.finish(process)
        self.assertNotIn("trimming", (self.root / "no-cap.log").read_text())
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())

    def queued(self, name):
        self.wait_for(lambda: "position" in (self.root / (name + ".log")).read_text(),
                      name + " gets a queue ticket", self.named.get(name))

    def started(self, name):
        self.wait_for(lambda: (self.root / (name + ".started")).exists(),
                      name + " starts", self.named.get(name))

    def finish(self, process, status=0):
        self.assertEqual(process.wait(timeout=FIXTURE_STARTUP_SECONDS), status)

    def hold_slot(self, kind="gate", number=1):
        stream = (self.slots / f"{kind}{number}.lock").open("w")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        return stream

    # Compiler watchers (`build-slot.sh watch`, DL-3 part 2). The constants are decision D2's, awaiting the user.
    def status_report(self, **environment):
        return subprocess.check_output([str(SLOT), "status"], env=dict(self.env, **environment), text=True)

    def write_watch_state(self, number, state, rss):
        (self.slots / f"watch{number}.state").write_text("%s %d %d\n" % (state, rss, int(time.time())))

    def start_watcher(self, name, hold=True, mode="job", cwd=None, **environment):
        """Admit a stand-in daemon, `dev_loop.py --daemon`, the only command the watch kind admits. It records its pid;
        mode `job` then runs as JOB does, mode `probe` writes the admission markers it inherited."""
        daemon = self.root / "daemon" / "dev_loop.py"
        if not daemon.exists():
            daemon.parent.mkdir()
            daemon.write_text(WATCH_DAEMON)
        return self.start(name, kind="watch", cwd=cwd, command=[
            sys.executable, "-B", str(daemon), "--daemon", mode, str(self.root), name, str(int(hold)), "0"], **environment)

    def test_the_watch_kind_admits_only_the_daemon_whose_pid_it_records(self):
        # A bare Maker would run its first build outside the build slots, the memory rule and the timing drain.
        for name, command in (("zig", ["zig", "build", "--watch", "-fincremental"]), ("sleep", ["sleep", "5"]),
                              ("script", [sys.executable, "-c", "pass", "--daemon"])):
            with self.subTest(name=name):
                refused = self.start(name, kind="watch", command=command)
                self.finish(refused, 2)
                self.assertIn("admits only a watcher's daemon", (self.root / (name + ".log")).read_text())
        self.assertIn("watch1: free", self.status_report())
        # The daemon is the process the wrapper execs: the owner record names it, alive, for as long as it holds.
        daemon = self.start_watcher("daemon")
        self.started("daemon")
        pid = (self.root / "daemon.pid").read_text()
        self.assertEqual(pid, str(daemon.pid))
        self.assertEqual((self.slots / "watch1.owner").read_text().split()[0], pid)
        self.assertTrue(Path(f"/proc/{pid}").exists())
        self.assertIn(f"watch1: busy; pid {pid}, ", self.status_report())
        (self.root / "daemon.release").touch()
        self.finish(daemon)

    def test_a_watcher_holds_a_watch_slot_and_no_build_slot_one_per_worktree_three_in_all(self):
        trees = [self.fixture_worktree(name, 10) for name in ("a", "b", "c", "d")]
        first = self.start_watcher("first", cwd=trees[0])
        self.started("first")
        # Its only build slot is free: an ordinary build of the same worktree starts at once beside it.
        self.finish(self.start("build", kind="build", cwd=trees[0]))
        report = self.status_report()
        self.assertIn("build1: free", report)
        self.assertIn(f"watch1: busy; pid {first.pid}, worktree {trees[0]}, state unknown", report)
        self.write_watch_state(1, "frozen", 3 << 30)
        self.assertRegex(self.status_report(), rf"watch1: busy; pid {first.pid}, worktree {re.escape(str(trees[0]))}, "
                                               r"frozen, 3\.0 GiB resident \(written \d+s ago\)")
        # One for each worktree, and it never waits.
        again = self.start_watcher("again", hold=False, cwd=trees[0])
        self.finish(again, 3)
        self.assertIn(f"this worktree already has a watcher (watch1, pid {first.pid})", (self.root / "again.log").read_text())
        for name, tree in (("second", trees[1]), ("third", trees[2])):
            self.start_watcher(name, cwd=tree)
            self.started(name)
        fourth = self.start_watcher("fourth", hold=False, cwd=trees[3])
        self.finish(fourth, 4)
        self.assertIn("all 3 watch slot(s) are taken", (self.root / "fourth.log").read_text())
        # A watcher killed in any state, stopped (frozen) included, frees its slot at once; the stale owner and state
        # files it leaves do not count.
        os.killpg(first.pid, signal.SIGSTOP)
        os.killpg(first.pid, signal.SIGKILL)
        first.wait(timeout=FIXTURE_STARTUP_SECONDS)
        self.assertIn("watch1: free", self.status_report())
        (self.root / "first.started").unlink()
        replacement = self.start_watcher("first", cwd=trees[3])
        self.started("first")
        self.assertIn(f"watch1: busy; pid {replacement.pid}, worktree {trees[3]}, state unknown", self.status_report())
        for name in ("first", "second", "third"):
            (self.root / (name + ".release")).touch()
            self.finish(self.named[name])

    def test_a_watcher_needs_its_memory_available_and_gets_no_admission_markers(self):
        short = self.start_watcher("short", hold=False, SELKA_WATCH_MEM="1000000G")
        self.finish(short, 5)
        self.assertIn("a watcher needs", (self.root / "short.log").read_text())
        # Its daemon requests ordinary build admissions, so the watcher must not look like an admitted job.
        self.finish(self.start_watcher("markers", hold=False, mode="probe"))
        self.assertEqual((self.root / "markers.markers").read_text(),
                         repr([None, None, str(self.slots.resolve() / "watch1")]))

    def test_timing_beside_a_frozen_watcher_starts_at_once_and_says_so_and_drains_a_running_one(self):
        watcher = self.start_watcher("watcher")
        self.started("watcher")
        self.write_watch_state(1, "frozen", 3 << 30)
        timing = self.start("timing", kind="timing")
        self.finish(timing)
        self.assertIn("build-slot: 1 watcher(s) beside this measurement: 1 frozen, 3.0 GiB resident",
                      (self.root / "timing.log").read_text())
        # A running watcher is one whose daemon holds an ordinary build admission: the timing request drains it.
        rebuild = self.start("rebuild", kind="build", hold=True)
        self.started("rebuild")
        self.write_watch_state(1, "thawed", 3 << 30)
        (self.root / "timing.started").unlink()
        drained = self.start("timing", kind="timing")
        self.wait_for(lambda: "draining active work (build1.lock)" in (self.root / "timing.log").read_text(),
                      "the timing request waits for the rebuild", drained)
        self.assertFalse((self.root / "timing.started").exists())
        (self.root / "rebuild.release").touch()
        self.finish(rebuild)
        self.finish(drained)
        self.assertIn("1 watcher(s) beside this measurement: 0 frozen", (self.root / "timing.log").read_text())
        (self.root / "watcher.release").touch()
        self.finish(watcher)

    def test_wrappers_that_predate_watchers_share_the_slot_directory_with_one(self):
        # The fixture is `build_slot_legacy.sh` as it was before the watch kind (main 8d09296758). Old wrappers in
        # other worktrees run beside new ones for days: they must neither wait for a watcher nor be overtaken by one.
        old = ["bash", str(ROOT / "test/fixtures/admission/build_slot_legacy_pre_watch.sh")]
        watcher = self.start_watcher("watcher")
        self.started("watcher")
        self.write_watch_state(1, "frozen", 3 << 30)
        for kind in ("build", "gate", "timing"):
            with self.subTest(kind=kind):
                self.finish(self.start("old-" + kind, kind=kind, wrapper=old))
        status = subprocess.check_output([*old, "status"], env=self.env, text=True)
        self.assertNotIn("watch", status)
        # An old wrapper's build and a new wrapper's build still share the build slots.
        held = self.start("old-holder", kind="build", hold=True, wrapper=old)
        self.started("old-holder")
        waiting = self.start("new-build", kind="build")
        self.queued("new-build")
        self.assertFalse((self.root / "new-build.started").exists())
        (self.root / "old-holder.release").touch()
        self.finish(held)
        self.finish(waiting)
        # A new timing request beside an old build drains it, and reports the watcher.
        held = self.start("old-holder2", kind="build", hold=True, wrapper=old)
        self.started("old-holder2")
        timing = self.start("new-timing", kind="timing")
        self.wait_for(lambda: "draining active work" in (self.root / "new-timing.log").read_text(),
                      "the new timing request drains the old build", timing)
        (self.root / "old-holder2.release").touch()
        self.finish(held)
        self.finish(timing)
        self.assertIn("1 watcher(s) beside this measurement", (self.root / "new-timing.log").read_text())
        (self.root / "watcher.release").touch()
        self.finish(watcher)

    def test_a_live_watcher_blocks_every_path_that_renames_or_deletes_its_worktrees_caches(self):
        import worktree_cache_trim as trim
        tree = self.fixture_worktree("over", 3000)
        stale = tree / ".zig-cache.trim-111"
        (stale / "o").mkdir(parents=True)
        caps = dict(SELKA_ZIG_CACHE_CAP_GB="0.001", SELKA_BUILD_SLOTS="2")
        watcher = self.start_watcher("watcher", cwd=tree)
        self.started("watcher")
        # An admission's trim.
        self.finish(self.start("admitted", kind="build", cwd=tree, **caps))
        self.assertNotIn("trimming", (self.root / "admitted.log").read_text())
        # The coordinator's.
        self.hold_coordinator_lock(tree)
        self.assertIsNone(trim.bound_for_coordinator(tree, self.slots, dict(self.env, **caps)))
        # The background measurement's deletion of what an earlier trim renamed aside (detached, so it is mocked: an
        # assertion on the directory would race it).
        argv = ["--worktree", str(tree), "--sizes", str(tree / ".git" / "prune-caches.sizes"), "--measure-only",
                "--slot-dir", str(self.slots)]
        with mock.patch.object(trim, "ASIDE_GRACE_SECONDS", -1), mock.patch.object(trim, "delete_later") as deletion, \
                contextlib.redirect_stderr(io.StringIO()) as printed:
            self.assertEqual(trim.main(argv), 0)
        deletion.assert_not_called()
        self.assertNotIn("finishing", printed.getvalue())
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        self.assertTrue(stale.exists())
        (self.root / "watcher.release").touch()
        self.finish(watcher)
        # Without the watcher the background half finishes the deletion and the coordinator trims.
        with mock.patch.object(trim, "ASIDE_GRACE_SECONDS", -1), mock.patch.object(trim, "delete_later") as deletion:
            self.assertEqual(trim.main(argv), 0)
        deletion.assert_called_once_with([stale])
        with mock.patch.object(trim, "ASIDE_GRACE_SECONDS", -1):
            self.assertEqual(trim.main(argv), 0)
        self.wait_for(lambda: not stale.exists(), "the half-done deletion is finished")
        self.assertIsNone(trim.bound_for_coordinator(tree, self.slots, dict(self.env, **caps)))
        self.assertFalse((tree / ".zig-cache").exists())
        self.wait_for_asides_gone(tree)

    def test_a_watcher_daemons_worktree_lock_blocks_the_trim_through_any_slot_directory(self):
        import worktree_cache_trim as trim
        tree = self.fixture_worktree("over", 3000)
        lock = tree / trim.WATCH_LOCK
        lock.parent.mkdir(parents=True, exist_ok=True)
        stream = lock.open("a")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        self.assertTrue(trim.watcher_running(tree))
        self.finish(self.start("admitted", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001"))
        self.assertNotIn("trimming", (self.root / "admitted.log").read_text())
        self.assertTrue((tree / ".zig-cache" / "o" / "junk").exists())
        fcntl.flock(stream, fcntl.LOCK_UN)
        self.assertFalse(trim.watcher_running(tree))
        self.finish(self.start("trimmed", kind="build", cwd=tree, SELKA_ZIG_CACHE_CAP_GB="0.001"))
        self.assertIn("trimming", (self.root / "trimmed.log").read_text())
        self.wait_for_asides_gone(tree)

    def test_a_zig_build_waits_while_its_worktrees_watcher_runs_and_nothing_else_does(self):
        tree = self.root / "tree"
        thaw = tree / ".selka-cache" / "dev-loop" / "thaw.lock"
        thaw.parent.mkdir(parents=True)
        stream = thaw.open("a")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        tools = self.root / "tools"
        tools.mkdir()
        zig = tools / "zig"
        zig.write_text("#!/bin/sh\ntouch %s/zig-$$.ran\n" % self.root)
        zig.chmod(0o755)
        environment = dict(SELKA_BUILD_SLOTS="3", PATH=str(tools) + os.pathsep + os.environ["PATH"])
        # Neither a watch nor another command waits; a plain `zig build` does, until the watcher is frozen again.
        self.finish(self.start("watch", kind="build", cwd=tree, command=[str(zig), "build", "--watch"], **environment))
        self.finish(self.start("other", kind="build", cwd=tree, command=["true"], **environment))
        self.assertEqual(len(list(self.root.glob("zig-*.ran"))), 1)
        build = self.start("build", kind="build", cwd=tree, command=["zig", "build", "install"], **environment)
        self.wait_for(lambda: "waiting for this worktree's watcher" in (self.root / "build.log").read_text(),
                      "the build waits for the running watcher", build)
        self.assertIsNone(build.poll())
        fcntl.flock(stream, fcntl.LOCK_UN)
        self.finish(build)
        self.assertEqual(len(list(self.root.glob("zig-*.ran"))), 2)

    def test_thaw_comes_before_ticket_before_slot_so_a_rebuild_and_plain_builds_never_deadlock(self):
        # The review's reproduction, with one build slot: the daemon holds the thaw lock exclusively and asks for a
        # slot; a plain `zig build` of the same worktree waits for the thaw lock; a build of another worktree queues.
        # Under the order "thaw before ticket before slot" the plain build waits holding neither a ticket nor a slot.
        tree = self.root / "tree"
        thaw = tree / ".selka-cache" / "dev-loop" / "thaw.lock"
        thaw.parent.mkdir(parents=True)
        stream = thaw.open("a")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        tools = self.root / "tools"
        tools.mkdir()
        zig = tools / "zig"
        zig.write_text("#!/bin/sh\ntouch %s/zig-$$.ran\n" % self.root)
        zig.chmod(0o755)
        environment = dict(SELKA_BUILD_SLOTS="1", PATH=str(tools) + os.pathsep + os.environ["PATH"])
        plain = self.start("plain", kind="build", cwd=tree, command=["zig", "build", "install"], **environment)
        self.wait_for(lambda: "waiting for this worktree's watcher to finish its rebuild (at most 600s)"
                      in (self.root / "plain.log").read_text(), "the plain build waits for the thaw lock", plain)
        self.assertEqual(list((self.slots / "queue-build").glob("*.wait")), [])
        self.finish(self.start("other", kind="build", **environment))
        rebuild = self.start("rebuild", kind="build", hold=True, cwd=tree, **environment)
        self.started("rebuild")
        self.assertIsNone(plain.poll())
        (self.root / "rebuild.release").touch()
        self.finish(rebuild)
        fcntl.flock(stream, fcntl.LOCK_UN)
        self.finish(plain)
        self.assertEqual(len(list(self.root.glob("zig-*.ran"))), 1)
        self.assertEqual((self.root / "plain.log").read_text().count("waiting for this worktree's watcher"), 1)

    def test_locked_shadow_log_does_not_block_admission(self):
        with (self.slots / 'scheduler-shadow.jsonl').open('a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            for kind in ('build', 'gate', 'timing'):
                with self.subTest(kind=kind):
                    process = self.start(kind, kind=kind, SELKA_ADMISSION_BACKEND='shadow')
                    # Both the request and its error report encounter this lock.
                    # The real command must finish while we still hold it.
                    self.finish(process)
                    self.assertTrue((self.root / (kind + '.started')).exists())
                    self.assertIn('shadow observation unavailable: shadow log lock unavailable',
                                  (self.root / (kind + '.log')).read_text())
            self.assertEqual((self.slots / 'scheduler-shadow.jsonl').read_text(), '')

    def waited_seconds(self, name, **environment):
        """Hold the slot for a while, queue `name` behind it, and return what the admitted command read as its wait."""
        lock = self.hold_slot()
        recorded = self.root / (name + ".wait")
        command = [sys.executable, "-c",
                   "import os, sys; open(sys.argv[1], 'w').write(os.environ.get('SELKA_ADMISSION_WAIT_S', 'unset'))",
                   str(recorded)]
        process = self.start(name, command=command, **environment)
        self.queued(name)
        time.sleep(2)
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(process)
        return recorded.read_text()

    def test_admitted_command_reads_the_seconds_it_waited(self):
        # F-S0-6: the wait before admission is invisible to a wrapper whose own clock starts after the queue, so the
        # job's environment names it, in seconds with milliseconds, under both backends.
        for backend in ("shadow", "scheduler"):
            with self.subTest(backend=backend):
                text = self.waited_seconds("waits-" + backend, SELKA_ADMISSION_BACKEND=backend)
                self.assertRegex(text, r"^\d+\.\d{3}$")
                self.assertGreaterEqual(float(text), 1.5)
                self.assertLess(float(text), FIXTURE_STARTUP_SECONDS)

    def test_a_job_admitted_at_once_reads_a_wait_near_zero(self):
        recorded = self.root / "prompt.wait"
        command = [sys.executable, "-c",
                   "import os, sys; open(sys.argv[1], 'w').write(os.environ['SELKA_ADMISSION_WAIT_S'])", str(recorded)]
        self.env["SELKA_ADMISSION_WAIT_S"] = "stale-from-an-outer-job"
        self.finish(self.start("prompt", command=command))
        self.assertRegex(recorded.read_text(), r"^\d+\.\d{3}$")

    def printed_wait(self, name):
        """The seconds the wrapper printed in its `build-slot: KIND slot N, FIFO ticket T after Xs` line, as text."""
        lines = [line for line in (self.root / (name + ".log")).read_text().splitlines()
                 if line.startswith("build-slot:") and " slot " in line and " after " in line]
        self.assertEqual(len(lines), 1, lines)
        return lines[0].rsplit(" after ", 1)[1].removesuffix("s")

    def test_the_printed_wait_is_the_one_the_job_reads_and_counts_the_whole_wait(self):
        # The line used to say `after 0s` for a request that waited seconds for a lock and an interpreter: it counted
        # whole polls from the wrapper's own start. It now prints the time from the request to the job's start.
        text = self.waited_seconds("printed")
        printed = self.printed_wait("printed")
        self.assertRegex(printed, r"^\d+\.\d{3}$")
        self.assertEqual(printed, text)
        self.assertGreaterEqual(float(printed), 1.5)

    def test_the_printed_wait_starts_at_the_request_not_at_the_wrapper(self):
        # build-slot.sh notes the request's start before its interpreter starts and hands it on, so the wait counts the
        # interpreter's start and the shadow observer's registration; a wrapper started without it counts from its own.
        legacy = ROOT / "scripts/build_slot_legacy.sh"
        three_seconds_ago = int((time.time() - 3) * 1_000_000)
        for name, extra, low in (("handed", {"SELKA_ADMISSION_STARTED_US": str(three_seconds_ago)}, 3.0),
                                 ("alone", {}, 0.0)):
            with self.subTest(name):
                environment = dict(self.env, SELKA_ADMISSION_BACKEND="legacy", **extra)
                done = subprocess.run([str(legacy), "gate", sys.executable, "-c", "pass"], env=environment,
                                      capture_output=True, text=True, timeout=FIXTURE_STARTUP_SECONDS)
                self.assertEqual(done.returncode, 0, done.stderr)
                match = re.search(r"slot 1, FIFO ticket \d+ after (\d+\.\d{3})s", done.stderr)
                self.assertIsNotNone(match, done.stderr)
                self.assertGreaterEqual(float(match.group(1)), low)
                self.assertLess(float(match.group(1)), low + FIXTURE_STARTUP_SECONDS)
        # The request's start is not passed on to the job.
        probe = self.root / "started-us"
        command = [sys.executable, "-c", "import os, sys; open(sys.argv[1], 'w').write(os.environ.get('SELKA_ADMISSION_STARTED_US', 'unset'))", str(probe)]
        self.finish(self.start("probe", command=command))
        self.assertEqual(probe.read_text(), "unset")

    def test_a_waiter_starts_when_its_lock_is_released_not_when_a_poll_comes_round(self):
        # The fallback poll is ten minutes: only the release of the lock the waiter is held up by can start it in the
        # time this test allows (a poll would run to the test's own ceiling). Four things hold a waiter up on a lock.
        def released_after(name, hold, **environment):
            holder = hold()
            process = self.start(name, kind=environment.pop("kind", "gate"), SELKA_SLOT_POLL="600", **environment)
            self.queued(name)
            time.sleep(1)
            released = time.monotonic()
            fcntl.flock(holder, fcntl.LOCK_UN)
            self.started(name)
            self.finish(process)
            return float((self.root / (name + ".started")).read_text()) - released
        def admission_lock():
            stream = (self.slots / "admit.lock").open("w")
            self.files.append(stream)
            fcntl.flock(stream, fcntl.LOCK_EX)
            return stream
        cases = {
            "every slot busy": lambda: released_after("slot-busy", self.hold_slot),
            "the settle window or a measurement": lambda: released_after("admit-busy", admission_lock),
            "a measurement queued behind a window": lambda: released_after("timing-admit", admission_lock, kind="timing"),
            "work to drain": lambda: released_after("timing-drain", lambda: self.hold_slot("build", 5), kind="timing"),
        }
        for reason, run in cases.items():
            with self.subTest(reason):
                self.assertLess(run(), 60)

    def test_a_waiter_behind_another_naps_without_leaving_anything_behind_or_passing_it_on(self):
        # A waiter that is not at the front sleeps on a FIFO nobody writes (a `sleep` per poll cost a fork and an exec
        # four times a second). The FIFO is unlinked at once and is not the job's: nothing stays in the slot
        # directory and the job it becomes inherits no descriptor of it.
        sleeps = self.root / "sleeps.log"
        path = self.shim("sleep", sleeps)
        lock = self.hold_slot()
        first = self.start("first", PATH=path)
        self.queued("first")
        listing = self.root / "behind.fds"
        code = ("import os, sys\nlinks = []\nfor fd in os.listdir('/proc/self/fd'):\n    try:\n"
                "        links.append(os.readlink('/proc/self/fd/' + fd))\n    except OSError:\n        pass\n"
                "open(sys.argv[1], 'w').write(chr(10).join(links))")
        behind = self.start("behind", command=[sys.executable, "-c", code, str(listing)], PATH=path)
        self.queued("behind")
        time.sleep(1.5)  # several naps
        self.assertEqual([entry.name for entry in self.slots.iterdir() if entry.name.startswith(".nap")], [])
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(first)
        self.finish(behind)
        self.assertEqual([line for line in listing.read_text().splitlines() if ".nap" in line], [])
        # A nap starts no process: a wrapper that slept instead (a `sleep` per poll) would have called it.
        self.assertFalse(sleeps.exists() and sleeps.read_text().strip(), sleeps.read_text() if sleeps.exists() else "")

    def test_a_waiter_that_cannot_make_a_fifo_sleeps_instead(self):
        tools = self.root / "tools"
        tools.mkdir()
        (tools / "mkfifo").write_text("#!/bin/sh\nexit 1\n")
        (tools / "mkfifo").chmod(0o755)
        sleeps = self.root / "sleeps.log"
        path = self.shim("sleep", sleeps)
        path = str(tools) + os.pathsep + path
        lock = self.hold_slot()
        first = self.start("first", PATH=path)
        self.queued("first")
        behind = self.start("behind", PATH=path)
        self.queued("behind")
        time.sleep(1.5)
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(first)
        self.finish(behind)
        self.assertEqual((self.root / "events").read_text().splitlines(), ["first", "behind"])
        self.assertTrue(sleeps.read_text().strip(), "without a FIFO the waiter sleeps (and the shim sees it)")

    def test_a_waiter_short_of_memory_retries_about_once_a_second_without_starting_awk(self):
        # The front waiter used to retry four times a second, each time starting about six processes (flock four times,
        # awk twice for MemAvailable and for the size in its message): worst exactly when memory is short.
        awks = self.root / "awk.log"
        flocks = self.root / "flock.log"
        path = self.shim("awk", awks)
        path = self.shim("flock", flocks)
        waiter = self.start("short", PATH=path, SELKA_GATE_MEM="1000000G", SELKA_SLOT_POLL="0.25")
        self.queued("short")
        before = len(flocks.read_text().split("\n"))
        time.sleep(3.2)
        flocks_seen = len(flocks.read_text().split("\n")) - before
        waiter.terminate()
        self.finish(waiter, 143)
        # The start-up asks `awk` once (the allowed CPUs); the retries ask it never.
        self.assertLessEqual(len(awks.read_text().split("\n")) - 1, 2, awks.read_text())
        # Four attempts a second would have started well over forty `flock`s in these three seconds.
        self.assertLess(flocks_seen, 25, flocks.read_text())
        self.assertIn("waiting for memory:", (self.root / "short.log").read_text())

    def test_a_dead_ticket_ahead_is_reaped_within_about_a_second_not_a_number_of_polls(self):
        # A waiter behind others looks at the queue without its lock, and properly (the only look that reaps a dead
        # ticket) every fourth poll: with a poll of 5 s that was twenty seconds, where the wrapper before looked every
        # poll. The proper look is now at least once in each second of wall time.
        lock = self.hold_slot()
        front = self.start("front", SELKA_SLOT_POLL="5")
        self.queued("front")
        behind = self.start("behind", SELKA_SLOT_POLL="5")
        self.queued("behind")
        os.kill(front.pid, signal.SIGKILL)
        self.finish(front, -signal.SIGKILL)
        released = time.monotonic()
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.started("behind")
        self.finish(behind)
        delay = float((self.root / "behind.started").read_text()) - released
        # One poll (5 s) and the start: twenty seconds before the fix.
        self.assertLess(delay, 12)

    def test_slot_poll_takes_a_decimal_and_refuses_what_is_not_a_positive_number(self):
        for value, accepted in (("0.25", True), (".5", True), ("2", True), ("0", False), ("0.0", False), ("-1", False),
                                ("abc", False), ("1.2.3", False)):
            with self.subTest(value=value):
                done = subprocess.run([str(SLOT), "gate", sys.executable, "-c", "pass"],
                                      env=dict(self.env, SELKA_SLOT_POLL=value), capture_output=True, text=True,
                                      timeout=FIXTURE_STARTUP_SECONDS)
                self.assertEqual(done.returncode == 0, accepted, done.stderr)
                if not accepted:
                    self.assertIn("SELKA_SLOT_POLL must be a positive number", done.stderr)

    def test_the_files_older_wrappers_read_keep_their_formats(self):
        # Old and new wrappers share one slot directory for days. An older wrapper reads a ticket as `pid start boot
        # enqueued`, an owner record as `pid start boot worktree`, and serializes on admit.lock and KINDn.lock.
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        def start_time(pid):
            return Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        lock = self.hold_slot()
        waiting = self.start("waiting")
        self.queued("waiting")
        ticket = next((self.slots / "queue-gate").glob("*.wait")).read_text().split()
        self.assertEqual(ticket[:3], [str(waiting.pid), start_time(waiting.pid), boot])
        self.assertRegex(ticket[3], r"^\d{10}$")
        self.assertEqual(len(ticket), 4)
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.started("waiting")
        owner = (self.slots / "gate1.owner").read_text().strip().split(None, 3)
        self.assertEqual(owner, [str(waiting.pid), start_time(waiting.pid), boot, str(self.root)])
        self.finish(waiting)

    def test_slow_polling_head_cannot_be_overtaken(self):
        lock = self.hold_slot()
        first = self.start("first", SELKA_SLOT_POLL="3")
        self.queued("first")
        second = self.start("second")
        self.queued("second")
        third = self.start("third")
        self.queued("third")
        report = subprocess.check_output([str(SLOT), "status"], env=self.env, text=True)
        self.assertIn(f"gate queue 1: pid {first.pid}", report)
        self.assertIn(f"gate queue 3: pid {third.pid}", report)
        fcntl.flock(lock, fcntl.LOCK_UN)
        for process in (first, second, third):
            self.finish(process)
        self.assertEqual((self.root / "events").read_text().splitlines(),
                         ["first", "second", "third"])

    def test_sigterm_cleans_up_waiting_ticket(self):
        lock = self.hold_slot()
        first = self.start("cancelled")
        self.queued("cancelled")
        second = self.start("survivor")
        self.queued("survivor")
        first.terminate()
        self.finish(first, 143)
        tickets = list((self.slots / "queue-gate").glob("*.wait"))
        self.assertEqual(len(tickets), 1)
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(second)
        self.assertEqual((self.root / "events").read_text().splitlines(), ["survivor"])

    def test_sigkill_and_unreaped_zombie_do_not_block_successor(self):
        lock = self.hold_slot()
        first = self.start("killed")
        self.queued("killed")
        second = self.start("survivor")
        self.queued("survivor")
        os.kill(first.pid, signal.SIGKILL)
        # Leave the killed process unreaped while the successor checks liveness.
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(second)
        self.finish(first, -signal.SIGKILL)
        self.assertEqual((self.root / "events").read_text().splitlines(), ["survivor"])

    def test_reused_pid_old_boot_and_partial_tickets_are_reaped(self):
        queue = self.slots / "queue-gate"
        queue.mkdir()
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        birth = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        (queue / "00000000000000000001.wait").write_text(f"{os.getpid()} 0 {boot} 0\n")
        (queue / "00000000000000000002.wait").write_text(f"{os.getpid()} {birth} previous-boot 0\n")
        (queue / "00000000000000000003.wait").write_text("")
        (queue / "sequence").write_text("3\n")
        self.finish(self.start("live"))
        self.assertEqual(list(queue.glob("*.wait")), [])

    def test_multiple_slots_retain_parallelism_and_cap(self):
        first = self.start("first", hold=True, SELKA_GATE_SLOTS="2")
        self.started("first")
        second = self.start("second", hold=True, SELKA_GATE_SLOTS="2")
        self.started("second")
        third = self.start("third", SELKA_GATE_SLOTS="2")
        self.queued("third")
        self.assertFalse((self.root / "third.started").exists())
        (self.root / "first.release").touch()
        self.finish(first)
        self.finish(third)
        self.assertIsNone(second.poll())
        (self.root / "second.release").touch()
        self.finish(second)

    def test_memory_blocked_head_is_not_overtaken(self):
        first = self.start("memory", SELKA_GATE_MEM="1000000G")
        self.queued("memory")
        second = self.start("later")
        self.queued("later")
        self.assertFalse((self.root / "later.started").exists())
        first.terminate()
        self.finish(first, 143)
        self.finish(second)

    def test_build_and_gate_queues_are_independent(self):
        lock = self.hold_slot()
        gate = self.start("gate")
        self.queued("gate")
        self.finish(self.start("build", kind="build"))
        self.assertIsNone(gate.poll())
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(gate)

    def test_settle_delay_does_not_keep_queue_locked(self):
        # The first job's settle timer holds the admission lock while a slot is still free. The hold is long and the
        # test ends it itself, so no step of the test (nor a slow start of the second command) can outlast it: the
        # second command is always found waiting on the lock, never admitted after the timer ran out.
        first = self.start("first", hold=True, SELKA_GATE_SLOTS="2", SELKA_SLOT_SETTLE="120")
        self.started("first")
        second = self.start("second", SELKA_GATE_SLOTS="2", SELKA_SLOT_SETTLE="120")
        self.queued("second")
        self.assertTrue(self.admission_locked())
        # A waiting command can still be cancelled during another job's settle.
        second.terminate()
        self.finish(second, 143)
        self.assertFalse((self.root / "second.started").exists())
        self.release_settle_timer(120)
        (self.root / "first.release").touch()
        self.finish(first)

    def admission_locked(self):
        with (self.slots / "admit.lock").open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
        return False

    def test_settle_helper_closes_worker_descriptors_and_output_pipes(self):
        read_fd, write_fd = os.pipe()
        worker_fd = fcntl.fcntl(write_fd, fcntl.F_DUPFD, 32)
        os.close(write_fd)
        try:
            process = subprocess.Popen(
                [str(SLOT), "gate", sys.executable, "-c", JOB, str(self.root), "pipes", "1", "0"],
                env=dict(self.env, SELKA_SLOT_SETTLE="120"),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                pass_fds=(worker_fd,), start_new_session=True)
            self.jobs.append(process)
        finally:
            os.close(worker_fd)
        try:
            # The command runs, so the settle timer is waiting for it (a 120 second hold that ends when the command
            # does). What the timer holds is read from its descriptors, not inferred from how soon the pipes reach
            # EOF: a timer that kept stdout, stderr or the worker's pipe would show it, however slow the machine is.
            self.started("pipes")
            self.assertTrue(self.admission_locked())
            timer = self.settle_timer(120)
            held = [os.readlink(f"/proc/{timer}/fd/{fd}") for fd in os.listdir(f"/proc/{timer}/fd")]
            self.assertEqual([path for path in held if path.startswith(("pipe:", "socket:"))], [], held)
            (self.root / "pipes.release").touch()
            self.wait_for(lambda: process.poll() is not None, "the wrapped command ends", process)
            self.assertEqual(process.returncode, 0)
            # With no other holder, both output pipes and the worker's pipe read EOF at once, and the timer, whose
            # job has exited, lets go of the admission lock without waiting out its 120 seconds.
            output, errors = process.communicate(timeout=FIXTURE_STARTUP_SECONDS)
            self.assertEqual(output, b"")
            self.assertIn(b"FIFO ticket", errors)
            os.set_blocking(read_fd, False)
            self.assertEqual(os.read(read_fd, 1), b"")
            self.wait_for(lambda: not self.admission_locked(), "timer releases admission")
            with (self.slots / "gate1.lock").open("a") as stream:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(read_fd)

    def test_failed_detachment_does_not_start_worker(self):
        tools = self.root / "tools"
        tools.mkdir()
        setsid = tools / "setsid"
        setsid.write_text("#!/bin/sh\nexit 7\n")
        setsid.chmod(0o755)
        process = self.start("failed-detach", SELKA_SLOT_SETTLE="3",
                             PATH=str(tools) + os.pathsep + os.environ["PATH"])
        self.finish(process, 2)
        self.assertFalse((self.root / "failed-detach.started").exists())
        self.assertIn("admission timer failed before detaching",
                      (self.root / "failed-detach.log").read_text())
        self.assertFalse(self.admission_locked())

    def test_detachment_handshake_has_a_finite_failure_boundary(self):
        tools = self.root / "tools"
        tools.mkdir()
        setsid = tools / "setsid"
        setsid.write_text("#!/bin/sh\ntrap '' TERM\nexec sleep 30\n")
        setsid.chmod(0o755)
        process = self.start("stalled-detach", SELKA_SLOT_SETTLE="3",
                             PATH=str(tools) + os.pathsep + os.environ["PATH"])
        self.finish(process, 2)
        self.assertFalse((self.root / "stalled-detach.started").exists())
        self.assertIn("admission timer did not detach",
                      (self.root / "stalled-detach.log").read_text())
        self.assertFalse(self.admission_locked())

    def test_worker_cancellation_preserves_detached_admission_delay(self):
        # A cancelled worker's slot stays held while a process of its job still runs, and so does the admission delay:
        # the detached settle timer waits for the slot lock, which that process holds, not for the wrapper. The hold is
        # long, and the test ends it on a condition (the next worker is queued behind it), so the test's own steps
        # cannot end it early. The sleep is the slow step a loaded machine adds between the cancel and the next worker:
        # the hold must survive it.
        holder = self.root / "descendant.pid"
        # `close_fds=False`: the descendant keeps the slot lock's descriptor, as a build's compiler processes do.
        code = ("import subprocess, sys; p = subprocess.Popen(['sleep', '120'], stdout=subprocess.DEVNULL, "
                "stderr=subprocess.DEVNULL, close_fds=False); open(sys.argv[1], 'w').write(str(p.pid)); "
                "import time; time.sleep(120)")
        first = self.start("cancelled-worker", SELKA_SLOT_SETTLE="120",
                           command=[sys.executable, "-c", code, str(holder)])
        self.wait_for(holder.exists, "the job starts a descendant", first)
        descendant = int(holder.read_text())
        self.addCleanup(self.kill_quietly, descendant)
        os.kill(first.pid, signal.SIGKILL)
        self.finish(first, -signal.SIGKILL)
        self.assertTrue(self.admission_locked())
        time.sleep(5)
        second = self.start("after-cancel", SELKA_SLOT_SETTLE="0")
        self.queued("after-cancel")
        self.assertFalse((self.root / "after-cancel.started").exists())
        self.assertTrue(self.admission_locked())
        # The descendant is the last holder of the slot. Once it is gone the job has exited: the delay ends.
        os.kill(descendant, signal.SIGKILL)
        released = time.monotonic()
        self.finish(second)
        self.assertFalse(self.admission_locked())
        self.assertGreaterEqual(float((self.root / "after-cancel.started").read_text()), released)

    def test_the_settle_delay_ends_when_the_job_has_exited(self):
        # The delay lets the next memory check see an admitted job's footprint. A job that has exited has none, so
        # the delay ends with it instead of running out its seconds: two commands in a row do not wait for each other.
        first = self.start("first", SELKA_SLOT_SETTLE="300", hold=True)
        self.started("first")
        self.assertTrue(self.admission_locked())
        timer = self.settle_timer(300)
        # While the job runs the window is held, as it always was.
        time.sleep(1)
        self.assertTrue(self.admission_locked())
        self.assertTrue(Path(f"/proc/{timer}").exists())
        (self.root / "first.release").touch()
        self.finish(first)
        # The 300 seconds are not waited out: the window closes soon after the job exits.
        self.wait_for(lambda: not self.admission_locked(), "the settle window ends with the job")
        second = self.start("second", SELKA_SLOT_SETTLE="300")
        self.finish(second)
        self.assertEqual((self.root / "events").read_text().splitlines(), ["first", "second"])

    def test_the_settle_delay_waits_for_every_holder_of_the_slot(self):
        # A job that has exited but left a process holding the slot lock has not gone: the delay runs on until that
        # process is gone too (or out its seconds).
        holder = self.root / "left.pid"
        code = ("import subprocess, sys; p = subprocess.Popen(['sleep', '120'], stdout=subprocess.DEVNULL, "
                "stderr=subprocess.DEVNULL, close_fds=False); open(sys.argv[1], 'w').write(str(p.pid))")
        first = self.start("first", SELKA_SLOT_SETTLE="300", command=[sys.executable, "-c", code, str(holder)])
        self.wait_for(holder.exists, "the job leaves a process behind", first)
        self.finish(first)
        left = int(holder.read_text())
        self.addCleanup(self.kill_quietly, left)
        time.sleep(2)
        self.assertTrue(self.admission_locked())
        os.kill(left, signal.SIGKILL)
        self.wait_for(lambda: not self.admission_locked(), "the delay ends with the last holder")

    @staticmethod
    def kill_quietly(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def settle_timer(self, seconds):
        """The pid of the detached settle timer that holds this test's admission lock.

        The timer is `flock -w SECONDS SLOTLOCK true`: it waits for the lock the admitted job holds, so it ends the
        moment the job has exited and otherwise after SECONDS."""
        lock = os.path.realpath(self.slots / "admit.lock")
        # Only this test's own temporary admission lock may be matched: a process with a descriptor elsewhere is never
        # touched, so a mistake here cannot reach a real admission.
        temporary = os.path.realpath(self.root) + os.sep
        self.assertTrue(lock.startswith(temporary), f"{lock} is outside the test's temporary root")
        for pid in filter(str.isdigit, os.listdir("/proc")):
            try:
                argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                if argv[:3] != [b"flock", b"-w", str(seconds).encode()]:
                    continue
                holds = [os.readlink(f"/proc/{pid}/fd/{fd}") for fd in os.listdir(f"/proc/{pid}/fd")]
            except OSError:
                continue
            if any(os.path.realpath(path) == lock for path in holds):
                return int(pid)
        self.fail("no detached settle timer holds the admission lock")

    def release_settle_timer(self, seconds):
        """End the detached settle timer that holds this test's admission lock; return when it was ended."""
        os.kill(self.settle_timer(seconds), signal.SIGTERM)
        return time.monotonic()

    def test_exit_status_cpu_mask_and_lock_lifetime(self):
        cpus = sorted(os.sched_getaffinity(0))
        if len(cpus) < 2:
            self.skipTest("requires two allowed CPUs")
        first = self.start("first", hold=True, status=37, SELKA_TIMING_CPUS=str(cpus[0]))
        self.started("first")
        self.assertNotIn(str(cpus[0]), (self.root / "first.affinity").read_text().split(","))
        second = self.start("second")
        self.queued("second")
        self.assertFalse((self.root / "second.started").exists())
        (self.root / "first.release").touch()
        self.finish(first, 37)
        self.finish(second)

    def test_default_build_uses_all_allowed_cpus(self):
        self.env.pop("SELKA_TIMING_CPUS")
        self.finish(self.start("all", kind="build"))
        self.assertEqual((self.root / "all.affinity").read_text(),
                         ",".join(map(str, sorted(os.sched_getaffinity(0)))))

    def test_timing_drains_both_kinds_and_resumes_queued_work(self):
        build = self.start("build", kind="build", hold=True)
        gate = self.start("gate", hold=True)
        self.started("build")
        self.started("gate")
        timing = self.start("timing", kind="timing", hold=True, status=37)
        self.queued("timing")
        later = self.start("later", kind="build")
        self.queued("later")
        (self.root / "build.release").touch()
        self.finish(build)
        self.assertFalse((self.root / "timing.started").exists())
        self.assertFalse((self.root / "later.started").exists())
        (self.root / "gate.release").touch()
        self.finish(gate)
        self.started("timing")
        self.assertFalse((self.root / "later.started").exists())
        report = subprocess.check_output([str(SLOT), "status"], env=self.env, text=True)
        self.assertIn("timing1: busy", report)
        (self.root / "timing.release").touch()
        self.finish(timing, 37)
        self.finish(later)
        self.assertEqual((self.root / "events").read_text().splitlines()[-2:], ["timing", "later"])

    def test_timing_drains_slots_above_its_configured_count(self):
        lock = self.hold_slot("build", 5)
        timing = self.start("timing", kind="timing")
        self.queued("timing")
        self.assertFalse((self.root / "timing.started").exists())
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(timing)

    def test_queued_timing_has_priority_even_when_it_polls_slowly(self):
        lock = (self.slots / "admit.lock").open("w")
        self.files.append(lock)
        fcntl.flock(lock, fcntl.LOCK_EX)
        timing = self.start("timing", kind="timing", SELKA_SLOT_POLL="3")
        self.queued("timing")
        build = self.start("build", kind="build")
        self.queued("build")
        fcntl.flock(lock, fcntl.LOCK_UN)
        self.finish(timing)
        self.finish(build)
        self.assertEqual((self.root / "events").read_text().splitlines(), ["timing", "build"])

    def test_measurements_are_fifo_and_never_overlap(self):
        first = self.start("first", kind="timing", hold=True)
        self.started("first")
        second = self.start("second", kind="timing", hold=True)
        self.queued("second")
        third = self.start("third", kind="timing")
        self.queued("third")
        build = self.start("build", kind="build")
        self.queued("build")
        self.assertFalse((self.root / "second.started").exists())
        (self.root / "first.release").touch()
        self.finish(first)
        self.started("second")
        self.assertFalse((self.root / "third.started").exists())
        self.assertFalse((self.root / "build.started").exists())
        (self.root / "second.release").touch()
        for process in (second, third, build):
            self.finish(process)
        self.assertEqual((self.root / "events").read_text().splitlines(),
                         ["first", "second", "third", "build"])

    def test_cancelled_drain_resumes_work_without_stopping_active_job(self):
        build = self.start("build", kind="build", hold=True)
        self.started("build")
        timing = self.start("timing", kind="timing")
        self.queued("timing")
        gate = self.start("gate")
        self.queued("gate")
        timing.terminate()
        self.finish(timing, 143)
        self.finish(gate)
        self.assertIsNone(build.poll())
        (self.root / "build.release").touch()
        self.finish(build)

    def test_killed_measurement_releases_admission(self):
        timing = self.start("timing", kind="timing", hold=True)
        self.started("timing")
        build = self.start("build", kind="build")
        self.queued("build")
        os.kill(timing.pid, signal.SIGKILL)
        self.finish(build)
        self.finish(timing, -signal.SIGKILL)

    def test_timing_retains_reserved_cpus(self):
        cpus = sorted(os.sched_getaffinity(0))
        self.finish(self.start("timing", kind="timing", SELKA_TIMING_CPUS=str(cpus[0])))
        if self.env.get('SELKA_ADMISSION_BACKEND') == 'scheduler':
            cpus = cpus[:1]
        self.assertEqual((self.root / "timing.affinity").read_text(), ",".join(map(str, cpus)))

    def test_reserved_scheduler_timing_and_two_builds_run_together(self):
        cpus = sorted(os.sched_getaffinity(0))
        if len(cpus) < 2:
            self.skipTest('requires two allowed CPUs')
        self.env.update(SELKA_ADMISSION_BACKEND='scheduler', SELKA_BUILD_SLOTS='2',
                        SELKA_TIMING_CPUS=str(cpus[0]))
        timing = self.start('reserved-timing', kind='timing', hold=True)
        self.started('reserved-timing')
        first = self.start('parallel-first', kind='build', hold=True)
        second = self.start('parallel-second', kind='build', hold=True)
        self.started('parallel-first')
        self.started('parallel-second')
        self.assertIsNone(timing.poll())
        self.assertEqual((self.root / 'reserved-timing.affinity').read_text(), str(cpus[0]))
        self.assertNotIn(str(cpus[0]), (self.root / 'parallel-first.affinity').read_text().split(','))
        self.assertNotIn(str(cpus[0]), (self.root / 'parallel-second.affinity').read_text().split(','))
        for name in ('reserved-timing', 'parallel-first', 'parallel-second'):
            (self.root / (name + '.release')).touch()
        for process in (timing, first, second):
            self.finish(process)

    def test_a_wait_for_a_command_that_has_exited_fails_at_once(self):
        # A command that exits without writing its marker never will. The wait says so instead of running to its
        # ceiling, so a broken fixture costs seconds, not the minutes a slow machine is allowed to take.
        process = self.start("exits", status=3, command=[sys.executable, "-c", "raise SystemExit(3)"])
        began = time.monotonic()
        with self.assertRaisesRegex(self.failureException, "exited with status 3"):
            self.started("exits")
        self.assertLess(time.monotonic() - began, FIXTURE_STARTUP_SECONDS / 4)
        self.finish(process, 3)

    def test_started_marker_follows_the_affinity_it_announces(self):
        # The marker announces a started job, so the affinity file it promises must already exist when the marker
        # does. The prelude delays the real job between its own two writes, the window a loaded machine opens:
        # the job reads its affinity mask, then writes it, and the test may look as soon as the marker appears.
        prelude = ("import os, time\n"
                   "_real_affinity = os.sched_getaffinity\n"
                   "def _slow_affinity(pid):\n"
                   "    time.sleep(1.0)\n"
                   "    return _real_affinity(pid)\n"
                   "os.sched_getaffinity = _slow_affinity\n")
        command = [sys.executable, "-c", prelude + JOB, str(self.root), "slow-job", "1", "0"]
        process = self.start("slow-job", kind="build", hold=True, command=command)
        self.started("slow-job")
        self.assertTrue((self.root / "slow-job.affinity").exists())
        self.assertTrue((self.root / "slow-job.affinity").read_text())
        (self.root / "slow-job.release").touch()
        self.finish(process)

    def test_scheduler_memory_reservations_share_one_pool(self):
        self.env.update(SELKA_ADMISSION_BACKEND='scheduler', SELKA_BUILD_SLOTS='2',
                        SELKA_ADMISSION_MEMORY='2M', SELKA_BUILD_MEM='2M')
        first = self.start('memory-first', kind='build', hold=True)
        self.started('memory-first')
        second = self.start('memory-second', kind='build')
        self.queued('memory-second')
        self.assertFalse((self.root / 'memory-second.started').exists())
        (self.root / 'memory-first.release').touch()
        self.finish(first)
        self.finish(second)

    def test_shadow_models_reserved_candidate_while_legacy_keeps_control(self):
        import json
        cpus = sorted(os.sched_getaffinity(0))
        if len(cpus) < 2:
            self.skipTest('requires two allowed CPUs')
        self.env.update(SELKA_ADMISSION_BACKEND='shadow', SELKA_TIMING_CPUS=str(cpus[0]))
        timing = self.start('shadow-timing', kind='timing', hold=True)
        self.started('shadow-timing')
        build = self.start('shadow-build', kind='build')
        self.queued('shadow-build')
        log = self.slots / 'scheduler-shadow.jsonl'
        def rows():
            return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        self.wait_for(lambda: any(row['event'] == 'would_admit' and row['kind'] == 'build' for row in rows()),
                      'shadow admits build on disjoint CPUs')
        timing_row = next(row for row in rows() if row['event'] == 'queued' and row['kind'] == 'timing')
        self.assertEqual(timing_row['cpu_set'], cpus[:1])
        self.assertFalse((self.root / 'shadow-build.started').exists())
        (self.root / 'shadow-timing.release').touch()
        self.finish(timing)
        self.finish(build)

    def test_shadow_records_short_command_without_polling_its_environment(self):
        self.env['SELKA_ADMISSION_BACKEND'] = 'shadow'
        self.finish(self.start('short-shadow', kind='build'))
        self.wait_for_observers()
        rows = [json.loads(line) for line in (self.slots / 'scheduler-shadow.jsonl').read_text().splitlines()]
        self.assertEqual([row['event'] for row in rows],
                         ['request', 'queued', 'would_admit', 'legacy_admitted', 'released'])
        self.assertEqual(len({row['key'] for row in rows}), 1)
        self.assertTrue(rows[-1]['legacy_admitted'])
        self.assertTrue(rows[-1]['scheduler_admitted'])
        self.assertFalse(list((self.slots / 'shadow-events').iterdir()))

    def test_nested_wrapper_rejected_without_waiting(self):
        job = self.start("nested", kind="timing", SELKA_ADMISSION_DIR=str(self.slots),
                         SELKA_ADMISSION_KIND="build")
        self.finish(job, 2)
        self.assertIn("nested admission", (self.root / "nested.log").read_text())

    def test_phase_admission_releases_on_exception_and_rejects_upgrade(self):
        original = os.sched_getaffinity(0)
        with mock.patch.dict(os.environ, self.env, clear=True):
            with admission("build"):
                with self.assertRaisesRegex(RuntimeError, "run this harness directly"):
                    with admission("timing"):
                        self.fail("upgraded active build to timing")
            with self.assertRaisesRegex(RuntimeError, "measurement failed"):
                with admission("timing"):
                    with admission("timing"):
                        build = self.start("build", kind="build")
                        self.queued("build")
                        self.assertFalse((self.root / "build.started").exists())
                        raise RuntimeError("measurement failed")
            self.finish(build)
        self.assertEqual(os.sched_getaffinity(0), original)

    def test_parent_death_cancels_phase_holder_even_before_admission(self):
        for waiting in (False, True):
            with self.subTest(waiting=waiting):
                name = "parent-" + str(waiting)
                log = (self.root / (name + ".log")).open("w")
                self.files.append(log)
                code = ("import sys, time\nfrom pathlib import Path\n"
                        "sys.path.insert(0, sys.argv[1])\nfrom build_admission import admission\n"
                        "with admission('timing'):\n"
                        "    Path(sys.argv[2]).touch()\n    time.sleep(60)\n")
                process = subprocess.Popen(
                    [sys.executable, "-B", "-c", code, str(ROOT / "scripts"),
                     str(self.root / (name + ".started"))],
                    env=dict(self.env, SELKA_TIMING_MEM="1000000G" if waiting else "0"),
                    stdout=log, stderr=log, start_new_session=True)
                self.jobs.append(process)
                if waiting:
                    self.queued(name)
                    ticket = next((self.slots / "queue-timing").glob("*.wait"))
                    self.holders.append(int(ticket.read_text().split()[0]))
                else:
                    self.started(name)
                build = self.start("resume-" + str(waiting), kind="build")
                self.queued("resume-" + str(waiting))
                os.kill(process.pid, signal.SIGKILL)
                self.finish(process, -signal.SIGKILL)
                self.finish(build)

    def test_timing_blocks_legacy_admission_lock_users(self):
        timing = self.start("timing", kind="timing", hold=True)
        self.started("timing")
        legacy = subprocess.Popen(
            ["flock", str(self.slots / "admit.lock"), sys.executable, "-c", JOB,
             str(self.root), "legacy", "0", "0"], start_new_session=True)
        self.jobs.append(legacy)
        # A newer build waiter provides synchronization without a fixed sleep.
        build = self.start("build", kind="build")
        self.queued("build")
        self.assertFalse((self.root / "legacy.started").exists())
        (self.root / "timing.release").touch()
        for process in (timing, legacy, build):
            self.finish(process)


if __name__ == "__main__":
    unittest.main()
