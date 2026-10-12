"""Failure-injection fixtures for the proposed port timing admission migration."""
import fcntl
import os
from pathlib import Path
import tempfile
import unittest
import timing_bridge


class TimingBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.files = [open(self.directory / name, "w") for name in ("admit.lock", "timing1.lock")]
        for handle in self.files:
            self.addCleanup(handle.close)
            fcntl.flock(handle, fcntl.LOCK_EX)
        self.descriptors = tuple(handle.fileno() for handle in self.files)
        self.environment = {"MYLANG_ADMISSION_KIND": "timing", "MYLANG_ADMISSION_DIR": str(self.directory)}
        self.cpus = sorted(os.sched_getaffinity(0))

    def verify(self):
        return timing_bridge.verify(self.environment, self.cpus, descriptors=self.descriptors)

    def test_authenticated_locks_record_provenance(self):
        receipt = self.verify()
        self.assertEqual(receipt["contract"], "direct-exclusive-admission-v1")
        self.assertEqual(receipt["affinity"], self.cpus)
        self.assertEqual(len(receipt["locks"]), 2)

    def test_forged_markers_with_unlocked_files_fail(self):
        fcntl.flock(self.files[0], fcntl.LOCK_UN)
        with self.assertRaisesRegex(ValueError, "exclusive lock"):
            self.verify()

    def test_gate_admission_cannot_measure(self):
        self.environment["MYLANG_ADMISSION_KIND"] = "gate"
        with self.assertRaisesRegex(ValueError, "timing admission"):
            self.verify()

    def test_missing_descriptor_fails(self):
        self.descriptors = (999999, self.descriptors[1])
        with self.assertRaisesRegex(ValueError, "descriptor unavailable"):
            self.verify()

    def test_replaced_live_lock_path_fails(self):
        (self.directory / "admit.lock").unlink()
        (self.directory / "admit.lock").touch()
        with self.assertRaisesRegex(ValueError, "another file"):
            self.verify()

    def test_changed_affinity_fails(self):
        self.cpus = self.cpus + [max(self.cpus) + 1]
        with self.assertRaisesRegex(ValueError, "affinity differs"):
            self.verify()

    def test_unqualified_directory_fails(self):
        self.environment["MYLANG_ADMISSION_DIR"] = "."
        with self.assertRaisesRegex(ValueError, "canonical"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
