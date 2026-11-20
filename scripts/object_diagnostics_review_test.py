#!/usr/bin/env python3
"""Diagnostics observe rejected authority without changing its decision."""
from contextlib import ExitStack
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, os.environ.get("F10_OBJECT_SCRIPTS", str(ROOT / "scripts")))
import verification_git_tree as subject
import verify_cache as coordinator


class ObjectDiagnosticsReview(unittest.TestCase):
    def setUp(self):
        parent = ROOT / ".tmp/f10-object-diagnostic-fixtures"
        parent.mkdir(parents=True, exist_ok=True)
        temp = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.objects = self.root / "objects"
        (self.objects / "56").mkdir(parents=True)
        self.old = self.objects / "56/existing"
        self.old.write_bytes(b"fixed transport")

    def guard(self):
        return subject.ObjectStoreAuthority(self.objects)

    def test_exact_retained_tree_creation_is_additive_and_its_removal_is_not_an_installed_object(self):
        # F21: this tree object appearing in a fan-out directory is what a peer's commit does to a shared
        # store. It was a refusal; objects are written once and named by content, so it is not one now.
        payload = ROOT / "test/fixtures/verification-cache/object.zlib"
        new = self.objects / "56/70b79f2193a30ab8b237c6d18720c374ec939d"
        with self.guard() as guard:
            self.assertTrue(guard.unchanged())
            new.write_bytes(payload.read_bytes())
            self.assertTrue(guard.unchanged())
            new.unlink()
            self.assertTrue(guard.unchanged())
            self.assertEqual([], coordinator.stability_diagnostics([guard])["reasons"])

    def test_removing_an_installed_object_preserves_refusal_and_names_it(self):
        with self.guard() as guard:
            self.assertTrue(guard.unchanged())
            self.old.unlink()
            self.assertFalse(guard.unchanged())
            report = coordinator.stability_diagnostics([guard])
            if os.environ.get("F10_OBJECT_ORIGINAL") == "1":
                self.assertEqual([], report["reasons"])
                self.assertEqual("unknown", report["status"])
            else:
                self.assertEqual("observed", report["status"])
                self.assertTrue(any(row["name"] == str(self.old) and row["reason"] == "inotify:delete"
                                    for row in report["reasons"]), report)
            self.old.write_bytes(b"fixed transport")
            self.assertFalse(guard.unchanged())

    def test_accessor_does_not_drain_pending_events_or_certify_clean(self):
        with self.guard() as guard:
            self.old.write_bytes(b"event")
            before = guard.statistics
            with patch.object(guard.watcher, "drain", side_effect=AssertionError("poll")), patch.object(Path, "lstat", side_effect=AssertionError("stat")):
                self.assertEqual([], guard.stability_diagnostics()["reasons"])
                self.assertEqual("unknown", coordinator.stability_diagnostics([guard])["status"])
            self.assertEqual(before, guard.statistics)
            self.assertFalse(guard.events_unchanged())
            self.assertTrue(guard.stability_diagnostics()["reasons"])

    def test_reports_are_detached_and_cannot_clear_rejection(self):
        with self.guard() as guard:
            self.old.write_bytes(b"new")
            self.assertFalse(guard.unchanged())
            before = guard.stability_diagnostics()
            modified = guard.stability_diagnostics()
            modified["reasons"][0]["reason"] = "forged clean"
            modified["reasons"].clear()
            self.assertEqual(before, guard.stability_diagnostics())
            self.assertFalse(guard.unchanged())

    def test_final_poll_interruption_is_sticky_and_specific(self):
        with self.guard() as guard:
            with patch.object(guard.watcher, "drain", side_effect=[True, KeyboardInterrupt]):
                self.assertRaises(KeyboardInterrupt, guard.unchanged)
            self.assertFalse(guard.events_unchanged())
            self.assertTrue(any("final event validation interrupted" in row["reason"]
                                for row in guard.stability_diagnostics()["reasons"]))

    def test_metadata_fallback_and_bounded_error_name(self):
        with self.guard() as guard:
            self.old.write_bytes(b"changed")
            with patch.object(guard.watcher, "drain", return_value=True):
                self.assertFalse(guard.unchanged())
            self.assertTrue(any(row["name"] == str(self.old) and "metadata changed" in row["reason"]
                                for row in guard.stability_diagnostics()["reasons"]))
        with self.guard() as guard:
            original = Path.lstat
            def unavailable(path):
                if path == self.old:
                    raise PermissionError(13, "denied" * 1000, str(path))
                return original(path)
            with patch.object(Path, "lstat", unavailable):
                self.assertFalse(guard.unchanged())
            report = guard.stability_diagnostics()
            self.assertTrue(report["truncated"])
            self.assertTrue(report["unknown"])
            self.assertTrue(all(len(value) <= 512 for row in report["reasons"] for value in row.values() if isinstance(value, str)))
            self.assertFalse(guard.unchanged())

    def test_closing_one_authority_does_not_revoke_peer(self):
        with self.guard() as first, self.guard() as peer:
            first.close()
            self.assertFalse(first.unchanged())
            self.assertTrue(peer.unchanged())
            first.stability_diagnostics()
            self.assertTrue(peer.events_unchanged())
            self.old.write_bytes(b"new event")
            self.assertFalse(peer.unchanged())
            self.assertTrue(peer.stability_diagnostics()["reasons"])

    def test_bounded_event_flood_and_mixed_unknown_aggregate(self):
        installed = [self.objects / "56" / str(index) for index in range(100)]
        for path in installed:
            path.write_bytes(b"installed")
        with self.guard() as guard:
            for path in installed:
                path.write_bytes(b"x")
            self.assertFalse(guard.unchanged())
            report = coordinator.stability_diagnostics([object(), guard])
            self.assertTrue(report["unknown"])
            self.assertTrue(report["truncated"])
            self.assertEqual(64, len(report["reasons"]))
            self.assertFalse(guard.unchanged())

    def test_output_sibling_remains_clean_and_initial_limits_remain(self):
        with self.guard() as guard:
            (self.root / "output").write_bytes(b"unrelated")
            self.assertTrue(guard.unchanged())
            self.assertEqual([], guard.stability_diagnostics()["reasons"])
        with self.assertRaises(subject.UnsupportedGit):
            with subject.ObjectStoreAuthority(self.objects, max_watches=1):
                self.fail("bound ignored")
        with self.guard() as guard:
            self.assertTrue(guard.unchanged())


if __name__ == "__main__":
    unittest.main()
