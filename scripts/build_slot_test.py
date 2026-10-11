#!/usr/bin/env python3
"""Exercise shared admission with real processes and private, on-disk locks."""
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from build_admission import admission

ROOT = Path(__file__).resolve().parents[1]
SLOT = ROOT / "scripts/build-slot.sh"
JOB = """
import os, sys, time
from pathlib import Path
root, name, hold, status = sys.argv[1:]
root = Path(root)
with (root / 'events').open('a') as f:
    f.write(name + '\\n')
(root / (name + '.started')).write_text(str(time.monotonic()))
(root / (name + '.affinity')).write_text(','.join(map(str, sorted(os.sched_getaffinity(0)))))
while hold == '1' and not (root / (name + '.release')).exists():
    time.sleep(.02)
sys.exit(int(status))
"""


class Admission(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="slot-test-", dir=scratch)
        self.root = Path(self.temp.name)
        self.slots = self.root / "slots"
        self.slots.mkdir()
        self.env = dict(os.environ, MYLANG_SLOT_DIR=str(self.slots),
                        MYLANG_BUILD_MEM="0", MYLANG_GATE_MEM="0", MYLANG_TIMING_MEM="0",
                        MYLANG_BUILD_SLOTS="1", MYLANG_GATE_SLOTS="1",
                        MYLANG_SLOT_SETTLE="0", MYLANG_SLOT_POLL="1",
                        MYLANG_TIMING_CPUS="")
        self.jobs = []
        self.holders = []
        self.files = []

    def tearDown(self):
        for process in self.jobs:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        for pid in self.holders:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for stream in self.files:
            stream.close()
        self.temp.cleanup()

    def wait_for(self, predicate, description):
        deadline = time.monotonic() + 12
        while not predicate():
            if time.monotonic() > deadline:
                logs = {p.name: p.read_text() for p in self.root.glob("*.log")}
                self.fail(f"Timed out: {description}; {logs}")
            time.sleep(.02)

    def start(self, name, kind="gate", hold=False, status=0, **environment):
        log = (self.root / (name + ".log")).open("w")
        self.files.append(log)
        process = subprocess.Popen(
            [str(SLOT), kind, sys.executable, "-c", JOB, str(self.root), name,
             str(int(hold)), str(status)], env=dict(self.env, **environment),
            stdout=log, stderr=log, start_new_session=True)
        self.jobs.append(process)
        return process

    def queued(self, name):
        self.wait_for(lambda: "position" in (self.root / (name + ".log")).read_text(),
                      name + " gets a queue ticket")

    def started(self, name):
        self.wait_for(lambda: (self.root / (name + ".started")).exists(),
                      name + " starts")

    def finish(self, process, status=0):
        self.assertEqual(process.wait(timeout=12), status)

    def hold_slot(self, kind="gate", number=1):
        stream = (self.slots / f"{kind}{number}.lock").open("w")
        fcntl.flock(stream, fcntl.LOCK_EX)
        self.files.append(stream)
        return stream

    def test_slow_polling_head_cannot_be_overtaken(self):
        lock = self.hold_slot()
        first = self.start("first", MYLANG_SLOT_POLL="3")
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
        first = self.start("first", hold=True, MYLANG_GATE_SLOTS="2")
        self.started("first")
        second = self.start("second", hold=True, MYLANG_GATE_SLOTS="2")
        self.started("second")
        third = self.start("third", MYLANG_GATE_SLOTS="2")
        self.queued("third")
        self.assertFalse((self.root / "third.started").exists())
        (self.root / "first.release").touch()
        self.finish(first)
        self.finish(third)
        self.assertIsNone(second.poll())
        (self.root / "second.release").touch()
        self.finish(second)

    def test_memory_blocked_head_is_not_overtaken(self):
        first = self.start("memory", MYLANG_GATE_MEM="1000000G")
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
        first = self.start("first", hold=True, MYLANG_GATE_SLOTS="2", MYLANG_SLOT_SETTLE="3")
        self.started("first")
        second = self.start("second", MYLANG_GATE_SLOTS="2", MYLANG_SLOT_SETTLE="3")
        self.queued("second")
        # A waiting command can still be cancelled during another job's settle.
        second.terminate()
        self.finish(second, 143)
        self.assertFalse((self.root / "second.started").exists())
        (self.root / "first.release").touch()
        self.finish(first)

    def test_exit_status_cpu_mask_and_lock_lifetime(self):
        cpus = sorted(os.sched_getaffinity(0))
        if len(cpus) < 2:
            self.skipTest("requires two allowed CPUs")
        first = self.start("first", hold=True, status=37, MYLANG_TIMING_CPUS=str(cpus[0]))
        self.started("first")
        self.assertNotIn(str(cpus[0]), (self.root / "first.affinity").read_text().split(","))
        second = self.start("second")
        self.queued("second")
        self.assertFalse((self.root / "second.started").exists())
        (self.root / "first.release").touch()
        self.finish(first, 37)
        self.finish(second)

    def test_default_build_uses_all_allowed_cpus(self):
        self.env.pop("MYLANG_TIMING_CPUS")
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
        timing = self.start("timing", kind="timing", MYLANG_SLOT_POLL="3")
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
        self.finish(self.start("timing", kind="timing", MYLANG_TIMING_CPUS=str(cpus[0])))
        self.assertEqual((self.root / "timing.affinity").read_text(), ",".join(map(str, cpus)))

    def test_nested_wrapper_rejected_without_waiting(self):
        job = self.start("nested", kind="timing", MYLANG_ADMISSION_DIR=str(self.slots),
                         MYLANG_ADMISSION_KIND="build")
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
                    env=dict(self.env, MYLANG_TIMING_MEM="1000000G" if waiting else "0"),
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
