#!/usr/bin/env python3
"""The watch loop (`scripts/dev_loop.py`) with real admission in a private slot directory and a stand-in Maker.

The stand-in watches its tree with fanotify, as Zig's Maker does, and waits for an event in `poll` with no timeout on
the fanotify descriptor, so the daemon's idle signature is exercised for real. Its "build" sleeps, then writes the
sources it read to `zig-out/built.txt` (or prints a compile error) and a `Build Summary` line.
"""
import ctypes
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
import dev_loop  # noqa: E402
import focused_test  # noqa: E402

DEV_LOOP = SCRIPTS / "dev_loop.py"
PATIENCE = 240

FAKE_MAKER = r'''
import ctypes, os, select, subprocess, sys, time
from pathlib import Path
build_seconds = float(os.environ.get("FAKE_BUILD_SECONDS", "0.2"))
lib = ctypes.CDLL(None, use_errno=True)
lib.fanotify_mark.argtypes = [ctypes.c_int, ctypes.c_uint, ctypes.c_uint64, ctypes.c_int, ctypes.c_char_p]
fan = lib.fanotify_init(0x1 | 0x2 | 0x400 | 0x800, os.O_RDONLY)
Path(".zig-cache").mkdir(exist_ok=True)
for directory in ["src", ".zig-cache"] + [str(p) for p in Path("src").rglob("*") if p.is_dir()]:
    assert lib.fanotify_mark(fan, 0x1, 0x8 | 0x2 | 0x80 | 0x100 | 0x200 | 0x08000000 | 0x40000000, -100,
                             directory.encode()) == 0
if os.environ.get("FAKE_SERVER"):
    server = subprocess.Popen([sys.executable, "-c", "import select; select.poll().poll()"])
    Path("server.pid").write_text(str(server.pid))
builds = [0]
def build(cause):
    builds[0] += 1
    contents = "".join(p.read_text() for p in sorted(Path("src").rglob("*.zig")))
    # Each build announces its start after it has read the sources, so a test can edit during a build by events.
    Path("build-starts").write_text(str(builds[0]))
    time.sleep(build_seconds)
    if "STALL" in contents:
        # A Maker that waits for its compilers for ever, using no CPU.
        while True:
            time.sleep(1)
    if "WEDGE" in contents:
        # A compile server that exits and is never reaped: the Maker waits for it for ever.
        subprocess.Popen(["true"])
        while True:
            time.sleep(1)
    if "ERROR" in contents:
        print("src/a.zig:1:1: error: bad thing", flush=True)
        print("    ERROR", flush=True)
        print("Build Summary: 2/3 steps succeeded (1 failed)", flush=True)
        return
    Path("zig-out").mkdir(exist_ok=True)
    Path("zig-out/built.txt").write_text(contents)
    print("Build Summary: 3/3 steps succeeded", flush=True)
    if builds[0] > 1 and os.environ.get("FAKE_BUSY_AFTER"):
        # A Maker that never comes back to its watch poll after a build (stuck on FileBusy, say): it cannot be frozen.
        while True:
            time.sleep(0.05)
    # Lingering after a build, before the watch poll, leaves the daemon unable to freeze for that long.
    time.sleep(float(os.environ.get("FAKE_LINGER", "0")))
    if os.environ.get("FAKE_SELF") and cause == "src":
        # The live identity run rewrites a generated file the compile steps watch: one more build follows.
        Path(".zig-cache/identity.zig").write_text(str(time.time()))
def drain():
    names = set()
    while True:
        try:
            data = os.read(fan, 65536)
        except BlockingIOError:
            return names
        names.add("identity" if b"identity.zig" in data else "src")
poller = select.poll()
poller.register(fan, select.POLLIN)
cause = "src"
while True:
    build(cause)
    if os.environ.get("FAKE_NEVER_IDLE"):
        while not poller.poll(100):
            pass
    else:
        poller.poll()
    causes = drain()
    while poller.poll(50):
        causes |= drain()
    cause = "src" if "src" in causes else "identity"
'''


def adopt_orphans():
    ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER


def live_children():
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
                    os.waitpid(int(pid), os.WNOHANG)
                    continue
                found[int(pid)] = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            except (OSError, ChildProcessError):
                continue
    return found


def lock_held(path):
    try:
        with open(path) as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
    except BlockingIOError:
        return True
    except FileNotFoundError:
        return False


class WatchLoop(unittest.TestCase):
    def setUp(self):
        adopt_orphans()
        patched = mock.patch.dict(os.environ)
        patched.start()
        self.addCleanup(patched.stop)
        os.environ.pop("SELKA_ADMISSION_SUPERVISED", None)
        for key in [key for key in os.environ if key.startswith("SELKA_ADMISSION_")]:
            os.environ.pop(key)
        self.before = set(live_children())
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="dev-loop-test-", dir=scratch)
        self.root = Path(self.temp.name)
        self.slots = self.root / "slots"
        self.slots.mkdir()
        self.tree = self.root / "tree"
        (self.tree / "src").mkdir(parents=True)
        (self.tree / "src" / "a.zig").write_text("pub const a = 1;\n")
        (self.tree / "build.zig").write_text("// configure input\n")
        subprocess.run(["git", "init", "-q", str(self.tree)], check=True)
        maker = self.root / "fake_maker.py"
        maker.write_text(FAKE_MAKER)
        self.env = dict(os.environ, SELKA_SLOT_DIR=str(self.slots),
                        SELKA_ZIG_CACHE_CAP_GB="0", SELKA_CACHE_TIERS_CAP_GB="0", SELKA_TEST_CACHES_CAP_GB="0",
                        SELKA_BUILD_MEM="0", SELKA_GATE_MEM="0", SELKA_TIMING_MEM="0", SELKA_WATCH_MEM="0",
                        SELKA_BUILD_SLOTS="1", SELKA_SLOT_SETTLE="0", SELKA_SLOT_POLL="0.25",
                        SELKA_ADMISSION_BACKEND="legacy", SELKA_TIMING_CPUS="",
                        SELKA_DEV_LOOP_MAKER=json.dumps([sys.executable, "-B", str(maker)]),
                        SELKA_DEV_LOOP_SELF_CHECK_SECONDS="20")

    def tearDown(self):
        if dev_loop.daemon_alive(self.tree):
            self.run_loop("stop", check=False)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            left = {pid: command for pid, command in live_children().items() if pid not in self.before}
            if not left:
                break
            time.sleep(0.05)
        for pid in left:
            try:
                os.killpg(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                os.kill(pid, signal.SIGKILL)
        self.temp.cleanup()
        self.assertEqual(left, {}, "the test left these processes running")

    def run_loop(self, *arguments, check=True, status=0, **environment):
        completed = subprocess.run([sys.executable, "-B", str(DEV_LOOP), *arguments], cwd=self.tree,
                                   env=dict(self.env, **environment), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, timeout=PATIENCE)
        if check:
            self.assertEqual(completed.returncode, status, completed.stdout)
        return completed

    def start_loop(self, **environment):
        return self.run_loop("start", **environment)

    def edit(self, text):
        (self.tree / "src" / "a.zig").write_text(text)

    def built(self):
        return (self.tree / "zig-out" / "built.txt").read_text()

    def state(self):
        return json.loads((self.tree / dev_loop.STATE / "state.json").read_text())

    def events(self):
        path = self.tree / dev_loop.STATE / "events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()]

    def wait_for(self, predicate, description, patience=PATIENCE):
        deadline = time.monotonic() + patience
        while not predicate():
            if time.monotonic() > deadline:
                self.fail("timed out: " + description)
            time.sleep(0.02)

    def build_starts(self):
        try:
            return int((self.tree / "build-starts").read_text())
        except (OSError, ValueError):
            return 0

    def daemon_pid(self):
        return int((self.slots / "watch1.owner").read_text().split()[0])

    def slot_free(self, kind="build1"):
        return not lock_held(self.slots / (kind + ".lock"))

    def test_start_builds_once_then_freezes_holding_a_watch_slot_and_no_build_slot(self):
        started = self.start_loop()
        self.assertIn("build 1 passed", started.stdout)
        self.assertEqual(self.built(), "pub const a = 1;\n")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        self.assertTrue(lock_held(self.slots / "watch1.lock"))
        self.wait_for(self.slot_free, "the build slot is released")
        self.assertFalse(lock_held(self.tree / dev_loop.STATE / "thaw.lock"))
        self.assertEqual((self.slots / "watch1.state").read_text().split()[0], "frozen")
        # The owner record names the daemon, alive, and the daemon is the process the wrapper exec'd.
        self.assertIn("--daemon", Path(f"/proc/{self.daemon_pid()}/cmdline").read_text())
        # Frozen means stopped: an edit starts no build until a wait thaws it.
        self.edit("pub const a = 2;\n")
        time.sleep(0.5)
        self.assertEqual(self.built(), "pub const a = 1;\n")
        waited = self.run_loop("wait")
        self.assertRegex(waited.stdout, r"build 2 passed \([\d.]+ s, slot wait [\d.]+ s\)")
        self.assertEqual(self.built(), "pub const a = 2;\n")
        # Nothing changed: the last result, at once, with no thaw.
        again = self.run_loop("wait")
        self.assertIn("nothing changed since build 2", again.stdout)

    def test_wait_returns_the_build_that_holds_the_newest_edit_not_the_self_triggered_one(self):
        self.start_loop(FAKE_SELF="1", FAKE_BUILD_SECONDS="0.6")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        for value in range(2, 5):
            self.edit("pub const a = %d;\n" % value)
            waiter = subprocess.Popen([sys.executable, "-B", str(DEV_LOOP), "wait"], cwd=self.tree, env=self.env,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            # A second edit lands while that build runs (after it read the sources): the build that answers must hold it.
            started = self.build_starts()
            self.wait_for(lambda: self.build_starts() > started, "the build starts")
            self.edit("pub const a = %d0;\n" % value)
            output = waiter.communicate(timeout=PATIENCE)[0]
            self.assertEqual(waiter.returncode, 0, output)
            self.assertEqual(self.built(), "pub const a = %d0;\n" % value, output)
            self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes after its own build")
        summaries = [e for e in self.events() if e["kind"] == "summary"]
        self.assertTrue(any(not e["same"] for e in summaries), "an edit landed during a build")

    def test_an_edit_made_at_once_after_a_wait_is_built_and_the_next_wait_answers_with_that_build(self):
        # The watch builds such an edit by itself before the daemon freezes it; the next wait takes that build.
        self.start_loop(FAKE_SELF="1", FAKE_BUILD_SECONDS="0.4")
        answers = []
        for value in range(20, 26):
            self.edit("pub const a = %d;\n" % value)
            waited = self.run_loop("wait")
            self.assertEqual(self.built(), "pub const a = %d;\n" % value, waited.stdout)
            self.assertRegex(waited.stdout, r"build \d+ passed")
            answers.append(waited.stdout)
        self.assertTrue(any("nothing changed since build" in answer for answer in answers),
                        "no wait was answered by a build made before the freeze")
        self.assertFalse(any(e["kind"] == "stalled" for e in self.events()))

    def test_an_edit_made_while_wait_queues_for_its_slot_is_answered_by_its_own_build(self):
        # Review item 1: the snapshot was taken before the admission, so this build's failure was reported as the
        # previous build's pass.
        self.start_loop()
        self.wait_for(self.slot_free, "the build slot is released")
        other = open(self.slots / "build1.lock", "w")
        fcntl.flock(other, fcntl.LOCK_EX)
        waiter = subprocess.Popen([sys.executable, "-B", str(DEV_LOOP), "wait"], cwd=self.tree, env=self.env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.edit("pub const a = 30;\n")
        self.wait_for(lambda: any(e["kind"] == "thaw-locked" for e in self.events()[-2:]), "the wait queues for a slot")
        self.edit("ERROR\n")
        fcntl.flock(other, fcntl.LOCK_UN)
        other.close()
        output = waiter.communicate(timeout=PATIENCE)[0]
        self.assertEqual(waiter.returncode, 1, output)
        self.assertIn("src/a.zig:1:1: error: bad thing", output)

    def test_an_edit_made_between_an_answer_and_the_freeze_is_answered_with_its_own_build(self):
        # Review item 2: a build an edit started after the answer, with no build after it, was never taken.
        self.start_loop(FAKE_LINGER="0.8")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        self.edit("pub const a = 31;\n")
        self.assertIn("passed", self.run_loop("wait").stdout)
        self.edit("ERROR\n")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes after building the edit")
        failed = self.run_loop("wait", status=1)
        self.assertIn("src/a.zig:1:1: error: bad thing", failed.stdout)

    def test_a_long_freeze_does_not_count_against_the_next_wait_as_a_stall(self):
        # Review item 3: the stall clock carried over from the previous wait.
        self.start_loop(SELKA_DEV_LOOP_STALL_SECONDS="2", FAKE_BUILD_SECONDS="0.5")
        self.edit("pub const a = 32;\n")
        self.assertIn("passed", self.run_loop("wait").stdout)
        time.sleep(3)
        self.edit("pub const a = 33;\n")
        self.assertIn("passed", self.run_loop("wait").stdout)
        self.assertEqual(self.built(), "pub const a = 33;\n")

    def test_a_maker_killed_while_frozen_is_not_reaped_until_it_is_stopped(self):
        # Review item 4: reaping it at once freed its process group id for reuse while the daemon would still signal it.
        self.start_loop()
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        maker = self.state()["maker"]
        os.kill(maker, signal.SIGKILL)
        time.sleep(1)
        self.assertTrue(Path(f"/proc/{maker}").exists(), "the killed Maker was reaped before it was stopped")
        self.assertEqual(Path(f"/proc/{maker}/stat").read_text().rsplit(")", 1)[1].split()[0], "Z")
        self.edit("pub const a = 34;\n")
        restarted = self.run_loop("wait")
        self.assertIn("the watcher ended", restarted.stdout)
        self.assertFalse(Path(f"/proc/{maker}").exists())

    def test_a_maker_that_cannot_be_frozen_is_stopped_and_gives_its_locks_back(self):
        # Review item 5: the slot and the exclusive thaw lock were held until the idle stop.
        self.start_loop(FAKE_BUSY_AFTER="1", SELKA_DEV_LOOP_FREEZE_SECONDS="2")
        self.edit("pub const a = 35;\n")
        self.assertIn("passed", self.run_loop("wait").stdout)
        # The daemon writes its state after it has released (`Daemon.release`), so the state is what to wait for: waiting
        # for the locks and then reading the state read "thawed" in a loaded gate (13 November).
        self.wait_for(lambda: self.state()["state"] == "stopped", "the watcher that could not be frozen is stopped",
                      patience=30)
        self.assertTrue(self.slot_free(), "the build slot is given back")
        self.assertFalse(lock_held(self.tree / dev_loop.STATE / "thaw.lock"), "the thaw lock is given back")
        self.assertIn("could not be frozen", self.state()["stopped_for"])

    def test_a_compile_error_is_reported_with_its_file_and_line(self):
        self.start_loop()
        self.edit("ERROR\n")
        failed = self.run_loop("wait", status=1)
        self.assertIn("build 2 failed (1 steps", failed.stdout)
        self.assertIn("src/a.zig:1:1: error: bad thing", failed.stdout)
        self.assertIn("    ERROR", failed.stdout)
        self.assertLessEqual(len(failed.stdout.splitlines()), dev_loop.MAX_LINES)
        self.edit("pub const a = 3;\n")
        self.assertIn("build 3 passed", self.run_loop("wait").stdout)

    def test_without_the_idle_signature_the_daemon_runs_without_freezing_and_keeps_its_slot(self):
        started = self.start_loop(FAKE_NEVER_IDLE="1", SELKA_DEV_LOOP_SELF_CHECK_SECONDS="2")
        self.assertIn("idle signature was not seen", started.stdout)
        self.assertEqual(self.state()["mode"], "no-freeze")
        self.assertFalse(self.slot_free(), "a watcher that cannot freeze keeps its build slot")
        self.assertFalse(lock_held(self.tree / dev_loop.STATE / "thaw.lock"))
        self.edit("pub const a = 5;\n")
        self.assertIn("passed", self.run_loop("wait").stdout)
        self.assertEqual(self.built(), "pub const a = 5;\n")
        # Review item 6: unfrozen, the watch relinks on every edit, so `test` refuses rather than run a binary it may
        # rewrite.
        refused = self.run_loop("test", "units", "x", status=2)
        self.assertIn("cannot be frozen", refused.stdout)
        # Unfrozen, the watch builds an edit before any wait asks (as under load in a gate): the wait takes that build.
        self.edit("pub const a = 6;\n")
        self.wait_for(lambda: self.built() == "pub const a = 6;\n", "the unfrozen watch builds the edit by itself")
        time.sleep(0.5)
        self.assertIn("passed", self.run_loop("wait").stdout)

    def test_the_daemon_stops_itself_after_its_idle_time(self):
        self.start_loop(SELKA_DEV_LOOP_IDLE_SECONDS="2")
        self.wait_for(lambda: not dev_loop.daemon_alive(self.tree), "the idle daemon stops", patience=60)
        self.wait_for(lambda: not lock_held(self.slots / "watch1.lock"), "its watch slot is free")
        self.assertTrue(any(e["kind"] == "idle-stop" for e in self.events()))
        self.assertIn("no watcher running", self.run_loop("status").stdout)

    def test_a_frozen_watcher_short_of_gate_memory_is_stopped_and_the_next_wait_restarts_it(self):
        memory = dict(SELKA_GATE_MEM="1000000G", SELKA_DEV_LOOP_MEMORY_CHECK_SECONDS="0.2",
                      SELKA_DEV_LOOP_MEMORY_GRACE_SECONDS="0.5")
        self.start_loop(**memory)
        self.wait_for(lambda: self.state()["state"] == "stopped", "the watcher is stopped for memory", patience=60)
        self.assertIn("SELKA_GATE_MEM", self.state()["stopped_for"])
        self.assertTrue(lock_held(self.slots / "watch1.lock"), "the daemon stays")
        self.edit("pub const a = 6;\n")
        restarted = self.run_loop("wait")
        self.assertIn("restarting the watcher, which was stopped: MemAvailable stayed below", restarted.stdout)
        self.assertEqual(self.built(), "pub const a = 6;\n")

    def test_killing_the_daemon_frees_the_watch_slot_build_slot_and_thaw_lock_in_any_state(self):
        # Frozen, with the daemon itself stopped too: the Maker and its stopped compile server go with it.
        self.start_loop(FAKE_SERVER="1")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        server = int((self.tree / "server.pid").read_text())
        maker = self.state()["maker"]
        daemon = self.daemon_pid()
        os.kill(daemon, signal.SIGSTOP)
        os.kill(daemon, signal.SIGKILL)
        self.wait_for(lambda: not lock_held(self.slots / "watch1.lock"), "the watch slot is free")
        for pid in (maker, server):
            self.wait_for(lambda: not Path(f"/proc/{pid}").exists() or
                          Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] == "Z",
                          "process %d ends" % pid)
        self.assertIn("no watcher running", self.run_loop("status").stdout)
        # Thawed, mid-build, holding a build slot and the thaw lock.
        self.start_loop(FAKE_BUILD_SECONDS="3")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        self.edit("pub const a = 7;\n")
        waiter = subprocess.Popen([sys.executable, "-B", str(DEV_LOOP), "wait"], cwd=self.tree, env=self.env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.wait_for(lambda: not self.slot_free(), "the rebuild holds a build slot")
        self.assertTrue(lock_held(self.tree / dev_loop.STATE / "thaw.lock"))
        os.kill(self.daemon_pid(), signal.SIGKILL)
        self.wait_for(self.slot_free, "the build slot is freed")
        self.wait_for(lambda: not lock_held(self.tree / dev_loop.STATE / "thaw.lock"), "the thaw lock is freed")
        self.wait_for(lambda: not lock_held(self.slots / "watch1.lock"), "the watch slot is freed")
        waiter.communicate(timeout=PATIENCE)
        self.assertNotEqual(waiter.returncode, 0)

    def test_killing_the_slot_holder_while_thawed_stops_the_watcher_and_frees_the_slot(self):
        self.start_loop(FAKE_BUILD_SECONDS="3")
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        self.edit("pub const a = 8;\n")
        waiter = subprocess.Popen([sys.executable, "-B", str(DEV_LOOP), "wait"], cwd=self.tree, env=self.env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.wait_for(lambda: any(e["kind"] == "continued" for e in self.events()[-2:]), "the watcher is thawed")
        holder = int((self.slots / "build1.owner").read_text().split()[0])
        self.assertIn("--hold", Path(f"/proc/{holder}/cmdline").read_text())
        os.kill(holder, signal.SIGKILL)
        output = waiter.communicate(timeout=PATIENCE)[0]
        self.assertEqual(waiter.returncode, 2, output)
        self.assertIn("the process holding the build slot ended", output)
        self.wait_for(self.slot_free, "the build slot is free")
        self.assertFalse(lock_held(self.tree / dev_loop.STATE / "thaw.lock"))
        self.assertEqual(self.state()["state"], "stopped")

    def test_the_daemon_takes_thaw_then_ticket_then_slot(self):
        self.start_loop()
        self.wait_for(lambda: self.state()["state"] == "frozen", "the watcher freezes")
        self.wait_for(self.slot_free, "the build slot is released")
        # Someone else holds the one build slot: the daemon waits for it holding the thaw lock, and a plain
        # `zig build` of the same worktree waits for the thaw lock without a ticket.
        other = open(self.slots / "build1.lock", "w")
        fcntl.flock(other, fcntl.LOCK_EX)
        self.edit("pub const a = 9;\n")
        waiter = subprocess.Popen([sys.executable, "-B", str(DEV_LOOP), "wait"], cwd=self.tree, env=self.env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.wait_for(lambda: lock_held(self.tree / dev_loop.STATE / "thaw.lock"), "the daemon takes the thaw lock")
        tools = self.root / "tools"
        tools.mkdir()
        (tools / "zig").write_text("#!/bin/sh\ntouch %s/zig.ran\n" % self.root)
        (tools / "zig").chmod(0o755)
        plain = subprocess.Popen([str(SCRIPTS / "build-slot.sh"), "build", "zig", "build", "install"], cwd=self.tree,
                                 env=dict(self.env, PATH=str(tools) + os.pathsep + os.environ["PATH"]),
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(1.0)
        tickets = sorted((self.slots / "queue-build").glob("*.wait"))
        self.assertEqual(len(tickets), 1, "only the daemon's slot holder has a ticket")
        self.assertIsNone(plain.poll())
        fcntl.flock(other, fcntl.LOCK_UN)
        other.close()
        output = waiter.communicate(timeout=PATIENCE)[0]
        self.assertEqual(waiter.returncode, 0, output)
        self.assertIn("waiting for this worktree's watcher", plain.communicate(timeout=PATIENCE)[0])
        self.assertTrue((self.root / "zig.ran").exists())
        kinds = [e["kind"] for e in self.events()]
        last = len(kinds) - 1 - kinds[::-1].index("thaw-locked")
        self.assertEqual(kinds[last:last + 3], ["thaw-locked", "admitted", "continued"])

    def test_wait_refuses_to_rebuild_while_a_process_runs_a_product(self):
        self.start_loop(SELKA_DEV_LOOP_BUSY_SECONDS="1")
        product = self.tree / "zig-out" / "bin" / "selka"
        product.parent.mkdir(parents=True, exist_ok=True)
        # A copy of the interpreter stands in for the compiler (coreutils here is one program that reads its name).
        shutil.copy2(os.path.realpath(sys.executable), product)
        running = subprocess.Popen([str(product), "-c", "import time; time.sleep(60)"])
        try:
            self.wait_for(lambda: dev_loop.running_products(self.tree.resolve()), "the product runs")
            self.edit("pub const a = 11;\n")
            refused = self.run_loop("wait", status=2)
            self.assertIn("process %d runs zig-out/bin/selka" % running.pid, refused.stdout)
            self.assertNotEqual(self.built(), "pub const a = 11;\n", "nothing was rebuilt under the running product")
        finally:
            running.kill()
            running.wait()
        self.assertIn("passed", self.run_loop("wait").stdout)
        self.assertEqual(self.built(), "pub const a = 11;\n")

    def test_a_maker_whose_compiler_ended_is_stopped_and_the_next_wait_restarts_it(self):
        self.start_loop(SELKA_DEV_LOOP_WEDGE_SECONDS="1")
        self.edit("WEDGE\n")
        stuck = self.run_loop("wait", status=2, SELKA_DEV_LOOP_WEDGE_SECONDS="1")
        self.assertIn("the watch stopped making progress", stuck.stdout)
        self.assertEqual(self.state()["state"], "stopped")
        self.wait_for(self.slot_free, "the build slot is free")
        self.edit("pub const a = 12;\n")
        restarted = self.run_loop("wait")
        self.assertIn("restarting the watcher, which was stopped: the watch stopped making progress", restarted.stdout)
        self.assertEqual(self.built(), "pub const a = 12;\n")

    def test_a_maker_that_uses_no_cpu_while_a_build_is_awaited_is_stopped(self):
        self.start_loop(SELKA_DEV_LOOP_STALL_SECONDS="2")
        self.edit("STALL\n")
        stuck = self.run_loop("wait", status=2)
        self.assertIn("no process of the Maker used CPU for 2 s", stuck.stdout)
        self.wait_for(self.slot_free, "the build slot is free")
        self.edit("pub const a = 13;\n")
        self.assertIn("restarting the watcher, which was stopped", self.run_loop("wait").stdout)
        self.assertEqual(self.built(), "pub const a = 13;\n")

    def test_a_worktree_path_too_long_for_the_socket_is_refused_with_a_message(self):
        deep = self.root / ("d" * 60) / ("e" * 60)
        deep.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", str(deep)], check=True)
        completed = subprocess.run([sys.executable, "-B", str(DEV_LOOP), "start"], cwd=deep, env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=PATIENCE)
        self.assertEqual(completed.returncode, 2, completed.stdout)
        self.assertIn("too long for the daemon's Unix socket", completed.stdout)
        self.assertNotIn("Traceback", completed.stdout)

    def test_wait_refuses_while_a_gate_runs(self):
        self.start_loop()
        lock = self.tree / ".selka-cache" / "verification-v3" / "coordinator.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        with lock.open("a") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            self.edit("pub const a = 10;\n")
            refused = self.run_loop("wait", status=2)
            self.assertIn("a gate is running in this worktree", refused.stdout)
        self.assertIn("build 2 passed", self.run_loop("wait").stdout)

    def test_start_twice_reports_the_running_watcher_and_a_stale_state_is_reported(self):
        self.start_loop()
        pid = self.daemon_pid()
        again = self.run_loop("start")
        self.assertIn("already has a watcher", again.stdout)
        self.assertIn("daemon pid %d" % pid, again.stdout)
        os.kill(pid, signal.SIGKILL)
        self.wait_for(lambda: not dev_loop.daemon_alive(self.tree), "the daemon is gone")
        self.assertIn("no watcher running (the last daemon, pid %d" % pid, self.run_loop("status").stdout)
        self.assertIn("no watcher in this worktree", self.run_loop("wait", status=2).stdout)
        self.assertIn("build 1 passed", self.start_loop().stdout)

    def test_a_configure_input_change_or_a_moved_head_restarts_the_watcher(self):
        self.start_loop()
        first = self.state()["maker"]
        (self.tree / "build.zig").write_text("// changed\n")
        restarted = self.run_loop("wait")
        self.assertIn("a configure input changed; restarting the watcher", restarted.stdout)
        self.assertNotEqual(self.state()["maker"], first)

    def test_the_idle_signature_is_qualified_for_the_pinned_zig(self):
        # The signature (`maker_state`) reads the pinned Maker's internals. A new pin must be re-qualified: run a real
        # watch session, check the first build's self-check, then update QUALIFIED_ZIG.
        self.assertEqual((ROOT / ".zigversion").read_text().strip(), dev_loop.QUALIFIED_ZIG)

    def test_test_runs_the_installed_binary_with_the_runtime_filter_and_compiles_nothing(self):
        self.start_loop()
        focus = self.tree / "zig-out" / "focus"
        focus.mkdir(parents=True)
        (focus / "unit-tests").write_text("#!/bin/sh\necho \"$@\" > %s/args\necho '3 x.test.b...FAIL (E)'\n"
                                          "echo 'test: FAIL — 1 failed of 2'\nexit 1\n" % self.root)
        (focus / "unit-tests").chmod(0o755)
        ran = self.run_loop("test", "units", "x.test", status=1)
        self.assertEqual((self.root / "args").read_text().strip(), "--test-filter=x.test")
        self.assertIn("FAILED x.test.b", ran.stdout)
        self.assertIn("exit status 1; log ", ran.stdout)
        # The focused-test wrapper uses a live watcher's binaries for the roots it has.
        printed = []
        with mock.patch.dict(os.environ, self.env):
            code = focused_test.watch_run("units", "x.test", self.tree, out=printed.append)
        self.assertEqual(code, 1)
        self.assertTrue(any("watch binaries" in line for line in printed), printed)
        self.assertIsNone(focused_test.watch_run("golden", "x", self.tree, out=printed.append))

    def test_test_prints_each_failing_test_with_its_message_and_place_and_keeps_the_exit_status(self):
        # A real failing run of a Guardian test binary (scripts/run-report-fixtures/terminal-fail.log): three failures
        # among four tests. Each prints its full name, what it expected and found, and the file:line of the test; the
        # last line has the exit status and the log; the status is the binary's, 1.
        self.start_loop()
        fixtures = ROOT / "scripts" / "run-report-fixtures"
        focus = self.tree / "zig-out" / "focus"
        focus.mkdir(parents=True)
        (focus / "unit-tests").write_text("#!/bin/sh\ncat '%s'\nexit 1\n" % (fixtures / "terminal-fail.log"))
        (focus / "unit-tests").chmod(0o755)
        ran = self.run_loop("test", "units", "fail.test", status=1)
        lines = ran.stdout.splitlines()
        self.assertIn("FAILED fail.test.equal ints", lines)
        self.assertIn("  expected 1, found 3", lines)
        self.assertTrue(any(line.startswith("  at ") and "fail.zig:3" in line for line in lines), lines)
        self.assertIn("FAILED fail.test.equal strings", lines)
        self.assertIn("  expected: b", lines)
        self.assertLessEqual(len(lines), 40)
        self.assertTrue(lines[-1].startswith("dev-loop: exit status 1; log "), lines[-1])
        # A passing run is one verdict line and the closing line, exit status 0.
        (focus / "unit-tests").write_text("#!/bin/sh\ncat '%s'\n" % (fixtures / "terminal-pass.log"))
        passed = self.run_loop("test", "units", "poller", status=0)
        self.assertIn("PASS filter poller: 19 passed", passed.stdout)
        self.assertNotIn("FAILED", passed.stdout)



def elf(path, segments):
    """A minimal 64-bit ELF file whose program headers are SEGMENTS, (type, filesz, memsz) each."""
    import struct
    header = bytearray(64)
    header[:5] = b"\x7fELF\x02"
    struct.pack_into("<Q", header, 32, 64)
    struct.pack_into("<HH", header, 54, 56, len(segments))
    table = b"".join(struct.pack("<IIQQQQQQ", kind, 5, 0, 0, 0, filesz, memsz, 4096) for kind, filesz, memsz in segments)
    Path(path).write_bytes(bytes(header) + table)


class JudgingAStall(unittest.TestCase):
    """How the Maker's stall and wedge are judged: scripted looks at its process tree under a scripted clock, so what a
    loaded machine does to the timing is part of the input and no test waits for a time."""

    def setUp(self):
        patched = mock.patch.dict(os.environ, SELKA_DEV_LOOP_STALL_SECONDS="2", SELKA_DEV_LOOP_WEDGE_SECONDS="1")
        patched.start()
        self.addCleanup(patched.stop)
        self.clock = 0.0
        self.sample = (0, False)
        for patch in (mock.patch.object(dev_loop, "now", lambda: self.clock),
                      mock.patch.object(dev_loop.Maker, "sample_tree", lambda maker: self.sample)):
            patch.start()
            self.addCleanup(patch.stop)
        self.maker = object.__new__(dev_loop.Maker)
        self.maker.pid = os.getpid()

    def look(self, gap, ticks=0, awake=False, counting=True):
        """Advance the clock by GAP and look once: the verdict of `stalled`."""
        self.clock += gap
        self.sample = (ticks, awake)
        return self.maker.stalled(counting=counting)

    def quiet_until_stalled(self, step=0.1, limit=100):
        """Seconds of quiet looks (STEP apart, no CPU, all asleep) until the verdict turns true."""
        began = self.clock
        while not self.look(step):
            self.assertLess(self.clock - began, limit, "never stalled")
        return self.clock - began

    def test_a_tree_that_is_quiet_for_the_window_is_stalled(self):
        self.assertFalse(self.look(0))
        self.assertAlmostEqual(self.quiet_until_stalled(), 2.0, delta=0.15)

    def test_a_thread_the_machine_holds_up_starts_the_clock_again(self):
        # Runnable, in disk wait or stopped: the Maker used no CPU for the window, as it does while its pages come in from
        # swap, and nothing is wrong with it. The clock counts from the last time it could not run.
        self.assertFalse(self.look(0))
        for _ in range(19):
            self.assertFalse(self.look(0.1))
        self.assertFalse(self.look(0.1, awake=True))
        self.assertAlmostEqual(self.quiet_until_stalled(), 2.0, delta=0.15)

    def test_cpu_used_starts_the_clock_again(self):
        self.assertFalse(self.look(0))
        for _ in range(19):
            self.assertFalse(self.look(0.1))
        self.assertFalse(self.look(0.1, ticks=1))
        self.assertAlmostEqual(self.quiet_until_stalled(), 2.0, delta=0.15)

    def test_a_look_the_daemon_could_not_take_in_time_counts_at_most_half_a_second(self):
        # The daemon starved for a minute saw nothing of the Maker in that minute.
        self.assertFalse(self.look(0))
        for _ in range(10):
            self.assertFalse(self.look(0.1))
        self.assertFalse(self.look(60.0))
        self.assertFalse(self.look(0.1))
        # 1.0 s of looks, 0.5 s for the minute, 0.1 s: 1.6 s counted, 0.4 s short of the window.
        self.assertAlmostEqual(self.quiet_until_stalled(), 0.4, delta=0.15)

    def test_looks_while_no_build_is_awaited_count_for_nothing(self):
        self.assertFalse(self.look(0))
        for _ in range(60):
            self.assertFalse(self.look(0.1, counting=False))
        self.assertAlmostEqual(self.quiet_until_stalled(), 2.0, delta=0.15)

    def zombie_maker(self):
        """A real process with a zombie child it never reaps, standing in for a Maker whose compile server exited."""
        code = ("import subprocess, sys, time; subprocess.Popen(['true']); print('R', flush=True); time.sleep(60)")
        child = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        self.assertEqual(child.stdout.readline().strip(), "R")
        self.addCleanup(child.stdout.close)
        deadline = time.monotonic() + PATIENCE
        while not any(Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] == "Z"
                      for pid in map(int, Path(f"/proc/{child.pid}/task/{child.pid}/children").read_text().split())):
            self.assertLess(time.monotonic(), deadline, "the child never became a zombie")
            time.sleep(0.01)
        self.maker.pid = child.pid
        return child

    def test_a_zombie_the_maker_leaves_while_it_sleeps_is_a_wedge_after_the_limit(self):
        self.zombie_maker()
        self.assertEqual(self.maker.wedged(), 0)
        seen = 0
        while not seen:
            self.clock += 0.1
            seen = self.maker.wedged()
            self.assertLess(self.clock, 100, "never wedged")
        self.assertAlmostEqual(self.clock, 1.0, delta=0.15)

    def test_a_zombie_the_maker_has_not_had_the_chance_to_reap_is_no_wedge(self):
        # The Maker is runnable or in disk wait: it reaps the zombie when it next runs. A wall-clock age called it
        # wedged after the limit however slow the machine was.
        self.zombie_maker()
        self.assertEqual(self.maker.wedged(), 0)
        self.sample = (0, True)
        for _ in range(100):
            self.clock += 0.1
            self.assertEqual(self.maker.wedged(), 0)
        self.sample = (0, False)
        self.clock += 0.1
        self.assertEqual(self.maker.wedged(), 0)

    def test_the_tree_is_awake_when_a_thread_is_stopped_and_asleep_otherwise(self):
        mock.patch.stopall()
        self.addCleanup(lambda: None)
        child = subprocess.Popen([sys.executable, "-c", "import time; print('R', flush=True); time.sleep(60)"],
                                 stdout=subprocess.PIPE, text=True)
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        self.addCleanup(child.stdout.close)
        self.assertEqual(child.stdout.readline().strip(), "R")
        maker = object.__new__(dev_loop.Maker)
        maker.pid = child.pid
        deadline = time.monotonic() + PATIENCE
        while maker.sample_tree()[1]:
            self.assertLess(time.monotonic(), deadline, "the sleeping child never slept")
            maker.tree_looked = None
            time.sleep(0.01)
        os.kill(child.pid, signal.SIGSTOP)
        deadline = time.monotonic() + PATIENCE
        while True:
            maker.tree_looked = None
            if maker.sample_tree()[1]:
                break
            self.assertLess(time.monotonic(), deadline, "the stopped child never showed as awake")
            time.sleep(0.01)
        self.assertIsInstance(maker.sample_tree()[0], int)


class AnsweringARequest(unittest.TestCase):
    def test_the_state_file_is_written_before_the_answer_is_sent(self):
        # A client that reads state.json the moment its wait returns must find the state the answer describes. The
        # answer used to go first, and the file said "thawed" after "the watcher was stopped" whenever the daemon was
        # slow to write it (15 November, at load 27).
        order = []

        class Connection:
            def sendall(self, data):
                order.append(("sent", json.loads(data)["code"]))

        daemon = object.__new__(dev_loop.Daemon)
        with mock.patch.object(dev_loop.Daemon, "wait", lambda self: (2, ["dev-loop: the watcher was stopped"])), \
                mock.patch.object(dev_loop.Daemon, "write_state", lambda self, force=False: order.append(("written",))), \
                mock.patch.object(dev_loop.Daemon, "public_accepted", lambda self: None):
            self.assertTrue(daemon.answer(Connection(), "wait"))
        self.assertEqual(order, [("written",), ("sent", 2)])


class WatchOnly(unittest.TestCase):
    """The one known watch-only case is recognised exactly: a padded executable, exit 2, the ceiling message."""

    def setUp(self):
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="dev-loop-watch-only-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_load_segments_tell_a_padded_incremental_executable_from_a_normal_one(self):
        mib = 1 << 20
        elf(self.root / "watch", [(1, 162 * mib, 434 * mib), (7, 1, 1)])
        elf(self.root / "normal", [(1, 77 * mib, 78 * mib)])
        self.assertEqual(dev_loop.load_segments(self.root / "watch"), (162 * mib, 434 * mib)[::-1])
        self.assertTrue(dev_loop.padded(self.root / "watch"))
        self.assertFalse(dev_loop.padded(self.root / "normal"))
        self.assertFalse(dev_loop.padded(sys.executable))
        self.assertFalse(dev_loop.padded(self.root / "missing"))
        line = dev_loop.watch_only_line("x.test.a", self.root / "watch", self.root / "normal")
        self.assertIn("maps 434.0 MiB of executable against 78.0 MiB for the normal build", line)

    def run_refusal(self, status, message):
        compiler = self.root / ("compiler-%d" % status)
        compiler.write_text("#!/bin/sh\necho '%s' >&2\nexit %d\n" % (message, status))
        compiler.chmod(0o755)
        binary = self.root / "tests"
        binary.write_text("#!/bin/sh\n\"$SELKA_TEST_COMPILER\" check main.selka\nstatus=$?\n[ $status = 1 ] && exit 0\n"
                          "echo \"expected 1, found $status\"\necho '1 x.test.a...FAIL (TestExpectedEqual)'\nexit 1\n")
        binary.chmod(0o755)
        with mock.patch.object(dev_loop, "padded", return_value=True):
            return dev_loop.ceiling_refusal(binary, self.root, compiler, self.root / ("scratch-%d" % status), "x.test.a")

    def test_only_an_exit_2_with_the_ceiling_message_from_a_padded_compiler_is_watch_only(self):
        ceiling = "selka: out of memory: the compiler reached its own memory ceiling of 192 MiB"
        self.assertTrue(self.run_refusal(2, ceiling))
        self.assertFalse(self.run_refusal(2, "selka: host failure: something else"))
        self.assertFalse(self.run_refusal(3, ceiling))
        self.assertFalse(self.run_refusal(1, ceiling), "a passing test is no refusal")
        # Review item 7: a test that expects the refusal and fails for another reason is no watch-only case.
        compiler = self.root / "compiler-expected"
        compiler.write_text("#!/bin/sh\necho '%s' >&2\nexit 2\n" % ceiling)
        compiler.chmod(0o755)
        expects = self.root / "expects-refusal"
        expects.write_text("#!/bin/sh\n\"$SELKA_TEST_COMPILER\" check main.selka\n"
                           "echo 'error: TestUnexpectedResult'\necho '1 x.test.a...FAIL (TestUnexpectedResult)'\nexit 1\n")
        expects.chmod(0o755)
        with mock.patch.object(dev_loop, "padded", return_value=True):
            self.assertFalse(dev_loop.ceiling_refusal(expects, self.root, compiler, self.root / "scratch-expected",
                                                      "x.test.a"))
        with mock.patch.object(dev_loop, "padded", return_value=False):
            self.assertFalse(dev_loop.ceiling_refusal(self.root / "tests", self.root, self.root / "compiler-2",
                                                      self.root / "scratch", "x.test.a"))

    def test_compare_reads_the_newest_edit_check_selection(self):
        older = self.root / "edit-check" / "1" / "selection.tsv"
        newer = self.root / "edit-check" / "2" / "selection.tsv"
        for path in (older, newer):
            path.parent.mkdir(parents=True)
        older.write_text("units\tnamed\told\treason\n")
        newer.write_text("units\tnamed\ta.test.x\tr\ncore\tunnamed\t\tr\ncli\tnamed\tb.test.y\tr\n"
                         "guests\tnamed\ttests/lang/a.selka\tr\n")
        os.utime(older, (1, 1))
        with mock.patch.dict(os.environ, TMPDIR=str(self.root)):
            selected, guests, path = dev_loop.edit_check_selection(self.root / "nowhere")
        self.assertEqual(path, newer)
        self.assertEqual(selected, {"units": ["a.test.x"], "core": [], "cli": ["b.test.y"]})
        self.assertTrue(guests)


class InstallOverALink(unittest.TestCase):
    """A watch build installs symbolic links (`build.zig`'s `installBinary`); a later ordinary build must put a regular
    file back, which Zig's install (`Dir.updateFile`, an atomic rename onto the path) does."""

    def test_an_ordinary_install_replaces_a_symbolic_link_with_a_file(self):
        zig = os.environ.get("ZIG") or os.environ.get("SELKA_ZIG") or shutil.which("zig")
        if not zig:
            self.skipTest("no Zig on PATH")
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="dev-loop-install-", dir=scratch) as name:
            tree = Path(name)
            (tree / "build.zig").write_text(
                "const std = @import(\"std\");\n"
                "pub fn build(b: *std.Build) void {\n"
                "    const files = b.addWriteFiles();\n"
                "    const made = files.add(\"made\", \"the ordinary build's bytes\\n\");\n"
                "    b.getInstallStep().dependOn(&b.addInstallFileWithDir(made, .{ .custom = \"focus\" }, \"x\").step);\n"
                "}\n")
            target = tree / "artifact"
            target.write_text("the watch build's artifact\n")
            link = tree / "zig-out" / "focus" / "x"
            link.parent.mkdir(parents=True)
            link.symlink_to(os.path.relpath(target, link.parent))
            subprocess.run([zig, "build", "--cache-dir", str(tree / ".zig-cache")], cwd=tree, check=True,
                           capture_output=True, timeout=PATIENCE)
            self.assertFalse(link.is_symlink())
            self.assertTrue(link.is_file())
            self.assertEqual(link.read_text(), "the ordinary build's bytes\n")
            self.assertEqual(target.read_text(), "the watch build's artifact\n", "the link's target was written through")


if __name__ == "__main__":
    unittest.main()
