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
                        MYLANG_BUILD_MEM="0", MYLANG_GATE_MEM="0",
                        MYLANG_BUILD_SLOTS="1", MYLANG_GATE_SLOTS="1",
                        MYLANG_SLOT_SETTLE="0", MYLANG_SLOT_POLL="1",
                        MYLANG_TIMING_CPUS="")
        self.jobs = []
        self.files = []

    def tearDown(self):
        for process in self.jobs:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
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
                [str(SLOT), "gate", sys.executable, "-c", "pass"],
                env=dict(self.env, MYLANG_SLOT_SETTLE="3"),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                pass_fds=(worker_fd,), start_new_session=True)
            self.jobs.append(process)
        finally:
            os.close(worker_fd)
        try:
            # communicate waits for pipe EOF as well as worker exit. A timer
            # retaining stdout/stderr would make this wait for all three seconds.
            output, errors = process.communicate(timeout=2)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(output, b"")
            self.assertTrue(self.admission_locked())
            os.set_blocking(read_fd, False)
            self.assertEqual(os.read(read_fd, 1), b"")
            with (self.slots / "gate1.lock").open("a") as stream:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.wait_for(lambda: not self.admission_locked(), "timer releases admission")
        finally:
            os.close(read_fd)

    def test_failed_detachment_does_not_start_worker(self):
        tools = self.root / "tools"
        tools.mkdir()
        setsid = tools / "setsid"
        setsid.write_text("#!/bin/sh\nexit 7\n")
        setsid.chmod(0o755)
        process = self.start("failed-detach", MYLANG_SLOT_SETTLE="3",
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
        process = self.start("stalled-detach", MYLANG_SLOT_SETTLE="3",
                             PATH=str(tools) + os.pathsep + os.environ["PATH"])
        self.finish(process, 2)
        self.assertFalse((self.root / "stalled-detach.started").exists())
        self.assertIn("admission timer did not detach",
                      (self.root / "stalled-detach.log").read_text())
        self.assertFalse(self.admission_locked())

    def test_worker_cancellation_preserves_detached_admission_delay(self):
        first = self.start("cancelled-worker", hold=True, MYLANG_SLOT_SETTLE="3")
        self.started("cancelled-worker")
        os.killpg(first.pid, signal.SIGTERM)
        self.finish(first, -signal.SIGTERM)
        self.assertTrue(self.admission_locked())
        second = self.start("after-cancel", MYLANG_SLOT_SETTLE="0")
        self.queued("after-cancel")
        self.assertFalse((self.root / "after-cancel.started").exists())
        self.assertTrue(self.admission_locked())
        self.finish(second)
        self.assertFalse(self.admission_locked())
        self.assertGreaterEqual(
            float((self.root / "after-cancel.started").read_text())
            - float((self.root / "cancelled-worker.started").read_text()), 2.5)

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


if __name__ == "__main__":
    unittest.main()
