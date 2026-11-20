#!/usr/bin/env python3
"""Tests for scripts/ownership_verdict_store.py: keys, damage, conflicts, leases, retention and where the store lives."""
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import ownership_verdict_store as store  # noqa: E402

CHECKER = "c" * 64
OTHER_CHECKER = "d" * 64


def digest(n: int) -> str:
    return f"{n:064x}"


class Verdicts(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.parent = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_a_verdict_is_found_by_its_certificate_and_its_checker_only(self):
        verdicts = store.VerdictStore(self.parent)
        self.assertEqual(verdicts.put_many("zig", CHECKER, {digest(1): "accept", digest(2): "reject J2 b0 1"}), 2)
        self.assertEqual(verdicts.get_many("zig", CHECKER, [digest(1), digest(2), digest(3)]), {digest(1): "accept", digest(2): "reject J2 b0 1"})
        self.assertEqual(verdicts.get_many("zig", OTHER_CHECKER, [digest(1)]), {})
        self.assertEqual(verdicts.get_many("lean", CHECKER, [digest(1)]), {})

    def test_a_second_store_on_the_same_directory_reads_what_the_first_published(self):
        store.VerdictStore(self.parent).put_many("lean", CHECKER, {digest(7): "accept"})
        self.assertEqual(store.VerdictStore(self.parent).get_many("lean", CHECKER, [digest(7)]), {digest(7): "accept"})

    def test_a_damaged_record_is_a_miss_and_republishing_repairs_it(self):
        verdicts = store.VerdictStore(self.parent)
        verdicts.put_many("zig", CHECKER, {digest(1): "accept"})
        record = verdicts._path("zig", CHECKER, digest(1))
        record.write_bytes(b"reject J2 b0 1\n" + b"0" * 64 + b"\n")
        self.assertEqual(verdicts.get_many("zig", CHECKER, [digest(1)]), {})
        record.unlink()
        verdicts.put_many("zig", CHECKER, {digest(1): "accept"})
        self.assertEqual(verdicts.get_many("zig", CHECKER, [digest(1)]), {digest(1): "accept"})

    def test_a_different_verdict_for_a_stored_key_is_logged_and_the_stored_one_kept(self):
        verdicts = store.VerdictStore(self.parent)
        verdicts.put_many("zig", CHECKER, {digest(1): "accept"})
        self.assertEqual(verdicts.put_many("zig", CHECKER, {digest(1): "reject J2 b0 1"}), 0)
        self.assertEqual(verdicts.get_many("zig", CHECKER, [digest(1)]), {digest(1): "accept"})
        log = (verdicts.directory / "mismatches.log").read_text()
        self.assertIn("mismatch zig", log)
        self.assertIn(digest(1), log)

    def test_a_checker_is_established_by_a_completed_run_only(self):
        verdicts = store.VerdictStore(self.parent)
        verdicts.put_many("lean", CHECKER, {digest(1): "accept"})
        self.assertFalse(verdicts.established("lean", CHECKER))
        verdicts.establish("lean", CHECKER)
        self.assertTrue(verdicts.established("lean", CHECKER))
        self.assertFalse(verdicts.established("lean", OTHER_CHECKER))
        self.assertFalse(verdicts.established("zig", CHECKER))

    def test_an_unknown_format_is_an_error_not_a_store_to_overwrite(self):
        store.VerdictStore(self.parent)
        (self.parent / store.NAMESPACE / "format.json").write_text(json.dumps({"namespace": store.NAMESPACE, "version": 99}))
        with self.assertRaises(store.StoreError):
            store.VerdictStore(self.parent)


class Retention(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.parent = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def fill(self, verdicts, count):
        now = time.time()
        for n in range(count):
            verdicts.put_many("zig", CHECKER, {digest(n): "accept"})
            os.utime(verdicts._path("zig", CHECKER, digest(n)), (now - 20000 + n, now - 20000 + n))

    def test_collection_evicts_the_least_recently_used_beyond_the_bound(self):
        verdicts = store.VerdictStore(self.parent, max_entries=3)
        self.fill(verdicts, 6)
        verdicts.establish("zig", CHECKER)
        report = verdicts.collect()
        self.assertEqual((report["scanned"], report["removed"], report["retained"]), (6, 3, 3))
        self.assertEqual(sorted(verdicts.get_many("zig", CHECKER, [digest(n) for n in range(6)])), [digest(3), digest(4), digest(5)])
        self.assertTrue(verdicts.established("zig", CHECKER))  # markers are never collected

    def test_a_hit_keeps_a_record_among_the_recently_used(self):
        verdicts = store.VerdictStore(self.parent, max_entries=3)
        self.fill(verdicts, 6)
        self.assertEqual(verdicts.get("zig", CHECKER, digest(0)), "accept")  # the oldest, used now
        self.assertTrue(verdicts._path("zig", CHECKER, digest(0)).stat().st_mtime > time.time() - 100)
        verdicts.collect()
        self.assertIn(digest(0), verdicts.get_many("zig", CHECKER, [digest(0)]))

    def test_a_store_a_process_holds_is_skipped_not_waited_for(self):
        verdicts = store.VerdictStore(self.parent, max_entries=1)
        self.fill(verdicts, 3)
        with verdicts.lease():
            other = store.VerdictStore.__new__(store.VerdictStore)
            other.directory, other.max_entries = verdicts.directory, 1
            self.assertEqual(other.collect(), {"skipped": "in use"})
            self.assertEqual(len(verdicts.get_many("zig", CHECKER, [digest(n) for n in range(3)])), 3)
        self.assertEqual(verdicts.collect()["removed"], 2)

    def test_opening_collects_at_most_once_an_interval(self):
        first = store.VerdictStore(self.parent, max_entries=2, interval=3600)
        self.fill(first, 5)
        store.VerdictStore(self.parent, max_entries=2, interval=3600)  # inside the hour of the first collection: nothing removed
        self.assertEqual(len(first.get_many("zig", CHECKER, [digest(n) for n in range(5)])), 5)
        (first.directory / "last-collection").write_text("0")
        os.utime(first.directory / "last-collection", (0, 0))
        store.VerdictStore(self.parent, max_entries=2, interval=3600)  # the hour has passed
        self.assertEqual(len(first.get_many("zig", CHECKER, [digest(n) for n in range(5)])), 2)


class Location(unittest.TestCase):
    def test_the_shared_root_follows_the_coordinator_s_order(self):
        self.assertEqual(store.shared_root({"SELKA_VERIFICATION_SHARED_CACHE": "/named", "HOME": "/home/x"}), Path("/named"))
        self.assertIsNone(store.shared_root({"SELKA_VERIFICATION_SHARED_CACHE": "", "HOME": "/home/x"}))
        self.assertEqual(store.shared_root({"XDG_CACHE_HOME": "/xdg", "HOME": "/home/x"}), Path("/xdg/selka/verification-shared"))
        self.assertEqual(store.shared_root({"XDG_CACHE_HOME": "relative", "HOME": "/home/x"}), Path("/home/x/.cache/selka/verification-shared"))
        self.assertEqual(store.shared_root({"HOME": "/home/x"}), Path("/home/x/.cache/selka/verification-shared"))
        self.assertIsNone(store.shared_root({}))

    def test_a_namespace_in_a_fresh_root_leaves_the_coordinators_store_usable(self):
        import fuzz_campaign_store
        with tempfile.TemporaryDirectory() as root:
            store.initialize_host(Path(root))
            store.VerdictStore(Path(root)).put_many("zig", CHECKER, {digest(1): "accept"})
            fuzz_campaign_store.Store(Path(root))  # still opens: the namespace is a foreign entry, not a damaged store
            self.assertEqual(store.VerdictStore(Path(root)).get_many("zig", CHECKER, [digest(1)]), {digest(1): "accept"})


if __name__ == "__main__":
    unittest.main()
