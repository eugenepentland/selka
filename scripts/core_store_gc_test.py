#!/usr/bin/env python3
"""Object-store retention contracts in disposable fixture stores.

The contracts: eviction needs no lease builders wait on (a held shared lease does not stop it); an object used or published
within the grace period is never removed; a candidate that raced the removal comes back; a run reads only the shards that are due.
"""
import fcntl
import json
import os
import re
from pathlib import Path
import tempfile
import subprocess
import sys
import threading
import time
import unittest
from unittest import mock

import core_store_gc as store

HOUR = 3600
DAY = 86400


def aged(path, seconds):
    """Make `path` look unused for `seconds` (its modification and access time)."""
    stamp = time.time() - seconds
    os.utime(path, (stamp, stamp), follow_symlinks=False)


def blocks(*paths):
    """What the file system says `paths` hold on disk, in bytes."""
    return sum(Path(path).stat().st_blocks * 512 for path in paths)


class AllocatedBudget(unittest.TestCase):
    """The budget is disk: a file weighs its allocated blocks, so a store of small files cannot hide behind its payload."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="core-store-gc-blocks-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.units = self.root / "units-v1"
        self.units.mkdir()
        self.count = 0

    def pair(self, size=100, idle=2 * DAY):
        """An object of `size` bytes and a 40-byte checksum record, as the compiler publishes them, idle for `idle` seconds."""
        self.count += 1
        key = f"{self.count:064x}"
        directory = self.units / key[:2]
        directory.mkdir(exist_ok=True)
        path = directory / (key + ".o")
        path.write_bytes(b"o" * size)
        Path(str(path) + ".sum").write_bytes(b"s" * 40)
        for suffix in ("", ".sum"):
            aged(Path(str(path) + suffix), idle)
        return path

    def run_store(self, **options):
        options.setdefault("grace_seconds", HOUR)
        options.setdefault("apply", True)
        options.setdefault("flat_budget", 0.0)
        return store.maintain(self.root, **options)

    def test_the_inventory_is_the_blocks_the_files_hold_not_their_length(self):
        small = [self.pair(size=100) for _ in range(5)]
        report = self.run_store(maximum=1 << 30)
        held = blocks(*small, *[Path(str(path) + ".sum") for path in small])
        self.assertEqual(report["inventory_bytes"], held)
        self.assertEqual(report["retained_bytes"], held)
        self.assertGreater(held, 5 * 140)  # 700 bytes of payload hold ten blocks

    def test_a_store_under_its_cap_in_payload_but_over_it_in_blocks_is_trimmed(self):
        paths = [self.pair(size=100, idle=(20 - number) * HOUR) for number in range(10)]  # oldest first
        payload = 10 * 140
        one = blocks(paths[0], Path(str(paths[0]) + ".sum"))
        self.assertLess(payload, 3 * one)
        report = self.run_store(maximum=5 * one)
        self.assertFalse(report["unmet_budget"])
        self.assertLessEqual(report["retained_bytes"], 5 * one * 9 // 10)
        self.assertEqual([path.exists() for path in paths].count(True), 4)
        self.assertEqual([path.exists() for path in paths], [False] * 6 + [True] * 4)  # the least recently used went

    def test_a_sparse_object_weighs_what_it_holds_and_is_not_trimmed_for_its_length(self):
        sparse = self.pair(size=1)
        with sparse.open("r+b") as stream:
            stream.truncate(1 << 30)
        Path(str(sparse) + ".sum").write_bytes(b"s" * 40)
        aged(sparse, 2 * DAY)
        report = self.run_store(maximum=1 << 20)
        self.assertTrue(sparse.exists())
        self.assertLess(report["retained_bytes"], 1 << 20)

    def test_freed_and_retained_bytes_agree_with_the_disk(self):
        paths = [self.pair(size=3000, idle=(30 - number) * HOUR) for number in range(6)]
        held = blocks(*paths, *[Path(str(path) + ".sum") for path in paths])
        one = held // 6
        report = self.run_store(maximum=held - 2 * one)
        removed = [path for path in paths if not path.exists()]
        self.assertGreater(len(removed), 0)
        self.assertEqual(report["removed_bytes"], len(removed) * one)
        survivors = [path for path in paths if path.exists()]
        self.assertEqual(report["retained_bytes"], blocks(*survivors, *[Path(str(path) + ".sum") for path in survivors]))

    def test_runtime_objects_count_by_blocks_in_the_root(self):
        runtime = self.root / ("core_rt-" + "a" * 8 + ".o")
        runtime.write_bytes(b"r" * 10)
        aged(runtime, 2 * DAY)
        report = self.run_store(maximum=1 << 30)
        self.assertEqual(report["root_bytes"], blocks(runtime))
        self.assertEqual(report["inventory_bytes"], blocks(runtime))


class ObjectRetention(unittest.TestCase):
    """The contracts in a byte model: a file weighs its length, so a fixture of a few bytes can sit on either side of a cap.
    `AllocatedBudget` below runs the real accounting, which weighs a file by its blocks."""

    def setUp(self):
        counting = mock.patch.object(store, "allocated", lambda value: value.st_size)
        counting.start()
        self.addCleanup(counting.stop)
        temporary = tempfile.TemporaryDirectory(prefix="core-store-gc-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.units = self.root / "units-v1"
        self.units.mkdir()
        self.count = 0

    def key(self, digit=None):
        self.count += 1
        return (digit * 64) if digit else f"{self.count:064x}"

    def pair(self, digit=None, idle=2 * DAY, flat=False, sharded=True, size=12):
        """A unit object and its record, idle for `idle` seconds, in the shard layout and (with `flat`) also as flat aliases."""
        key = self.key(digit)
        directory = self.units / key[:2] if sharded else self.units
        directory.mkdir(exist_ok=True)
        path = directory / (key + ".o")
        path.write_bytes(b"o" * size)
        Path(str(path) + ".sum").write_bytes(b"fixture checksum")
        if flat and sharded:
            for suffix in ("", ".sum"):
                (self.units / (key + ".o" + suffix)).hardlink_to(Path(str(path) + suffix))
        for suffix in ("", ".sum"):
            aged(Path(str(path) + suffix), idle)
        return path

    def run_store(self, **options):
        options.setdefault("grace_seconds", HOUR)
        options.setdefault("apply", True)
        # The flat directory is listed only by the tests that ask: it retires the flat names an eviction test wants to find.
        options.setdefault("flat_budget", 0.0)
        return store.maintain(self.root, **options)

    def test_preview_reports_cap_eviction_without_removing_objects(self):
        path = self.pair(size=12)
        report = self.run_store(maximum=0, apply=False)
        self.assertTrue(report["dry_run"])
        self.assertTrue(report["inventory_complete"])
        self.assertEqual(report["inventory_bytes"], 28)
        self.assertEqual(report["removed_bytes"], 28)
        self.assertEqual(report["retained_bytes"], 0)
        self.assertFalse(report["unmet_budget"])
        self.assertTrue(path.exists())
        self.assertFalse((self.root / ".last-maintenance.json").exists())

    def test_real_eviction_removes_the_object_its_record_and_its_flat_aliases(self):
        first = self.pair(flat=True)
        second = self.pair()
        flat_only = self.pair(sharded=False)
        report = self.run_store(maximum=0, flat_budget=300.0)
        self.assertTrue(report["inventory_complete"])
        self.assertFalse(report["unmet_budget"])
        self.assertEqual(report["retained_bytes"], 0)
        self.assertEqual(report["removed_entries"], 3)
        for path in (first, second, flat_only, self.units / first.name):
            self.assertFalse(path.exists())
            self.assertFalse(Path(str(path) + ".sum").exists())
        self.assertEqual([path for path in self.units.rglob("*") if path.is_file() and path.name != ".retention.lock"], [])

    def test_over_cap_removes_the_least_recently_used_down_to_ninety_percent(self):
        paths = [self.pair(idle=(20 - number) * HOUR) for number in range(10)]  # oldest first, 28 bytes each
        report = self.run_store(maximum=260)
        self.assertEqual(report["inventory_bytes"], 280)
        self.assertEqual(report["target_bytes"], 234)
        self.assertEqual(report["retained_bytes"], 224)
        self.assertFalse(report["unmet_target"])
        self.assertEqual([path.exists() for path in paths], [False, False] + [True] * 8)

    def test_under_the_cap_nothing_goes_unless_it_has_been_idle_past_the_age_limit(self):
        young = self.pair(idle=2 * DAY)
        old = self.pair(idle=20 * DAY)
        report = self.run_store(maximum=1 << 20, days=14)
        self.assertTrue(young.exists())
        self.assertFalse(old.exists())
        self.assertEqual(report["removed_entries"], 1)

    def test_an_object_used_within_the_grace_period_is_never_removed_however_far_over_budget(self):
        fresh = self.pair(idle=60)
        recent = self.pair(idle=2 * HOUR)
        stale = self.pair(idle=7 * HOUR)
        report = self.run_store(maximum=0, grace_seconds=6 * HOUR)
        self.assertTrue(fresh.exists() and recent.exists())
        self.assertFalse(stale.exists())
        self.assertTrue(report["unmet_budget"])
        self.assertEqual(report["fresh_bytes"], 56)
        self.assertIn("OVER BUDGET", store.store_status(report))

    def test_eviction_does_not_wait_for_builders_and_needs_no_exclusive_lease(self):
        # A busy machine always has a build, and a build holds a shared lease for as long as it builds. The first version of
        # this program wanted every lease exclusively, so it never ran and then held the builders off while it did.
        stale = self.pair(flat=True)
        with (self.root / ".retention.lock").open("a") as root_lease, (self.units / ".retention.lock").open("a") as unit_lease:
            fcntl.flock(root_lease, fcntl.LOCK_SH)
            fcntl.flock(unit_lease, fcntl.LOCK_SH)
            report = self.run_store(maximum=0)
        self.assertFalse(report["skipped_active"])
        self.assertFalse(stale.exists())
        self.assertEqual(report["removed_entries"], 1)
        self.assertEqual(report["exclusive_seconds"], 0.0)

    def test_a_builder_takes_its_shared_leases_at_once_while_eviction_runs(self):
        for _ in range(40):
            self.pair(flat=True)
        waits = []
        original = store.remove_object

        def builder_arrives(*arguments, **keywords):
            for lock in (self.root / ".retention.lock", self.units / ".retention.lock"):
                with lock.open("a") as lease:
                    started = time.monotonic()
                    fcntl.flock(lease, fcntl.LOCK_SH | fcntl.LOCK_NB)  # a blocking wait would raise here
                    waits.append(time.monotonic() - started)
            return original(*arguments, **keywords)

        with mock.patch.object(store, "remove_object", builder_arrives):
            report = self.run_store(maximum=0)
        self.assertEqual(report["removed_entries"], 40)
        self.assertEqual(len(waits), 80)
        self.assertLess(max(waits), 0.05)

    def test_a_hit_after_the_scan_is_seen_and_the_object_stays(self):
        path = self.pair()
        original = store.scan_shard

        def hit_after_scan(*arguments):
            result = original(*arguments)
            os.utime(path)  # a build's lookup refreshes the modification time
            return result

        with mock.patch.object(store, "scan_shard", hit_after_scan):
            report = self.run_store(maximum=0)
        self.assertTrue(path.exists() and Path(str(path) + ".sum").exists())
        self.assertEqual(report["removed_entries"], 0)
        self.assertTrue(report["unmet_budget"])

    def renaming_hook(self, after_rename):
        """A replacement for os.rename that runs `after_rename(source, destination)` after each tombstone is made."""
        real = os.rename

        def rename(source, destination, *arguments, **keywords):
            real(source, destination, *arguments, **keywords)
            if str(destination).endswith(".partial"):
                after_rename(Path(source), Path(destination))

        return mock.patch.object(os, "rename", rename)

    def test_an_object_touched_between_the_check_and_the_removal_is_put_back(self):
        path = self.pair(flat=True)
        flat = self.units / path.name
        with self.renaming_hook(lambda source, tomb: os.utime(tomb)):
            report = self.run_store(maximum=0)
        self.assertEqual(report["removed_entries"], 0)
        self.assertTrue(path.exists() and flat.exists())
        self.assertTrue(Path(str(path) + ".sum").exists() and Path(str(flat) + ".sum").exists())
        self.assertEqual([entry.name for entry in path.parent.iterdir() if entry.name.endswith(".partial")], [])
        self.assertEqual([entry.name for entry in self.units.iterdir() if entry.name.endswith(".partial")], [])

    def test_a_build_that_republishes_the_name_keeps_its_object_when_the_removal_backs_out(self):
        path = self.pair()

        def republish(source, tomb):
            if source == path:
                source.write_bytes(b"new object from a build")  # the miss's rename into place
                os.utime(tomb)

        with self.renaming_hook(republish):
            self.run_store(maximum=0)
        self.assertEqual(path.read_bytes(), b"new object from a build")
        self.assertEqual([entry.name for entry in path.parent.iterdir() if entry.name.endswith(".partial")], [])

    def test_an_object_published_while_a_shard_is_read_is_unseen_and_untouched(self):
        old = self.pair("a" * 1)
        published = self.units / old.parent.name / (old.parent.name * 31 + "b" * 33 + ".o")
        original = store.scan_shard

        def publish_after_scan(root, database, shard, *rest):
            result = original(root, database, shard, *rest)
            if shard == old.parent.name:
                published.write_bytes(b"new object")
                Path(str(published) + ".sum").write_bytes(b"new checksum")
            return result

        with mock.patch.object(store, "scan_shard", publish_after_scan):
            report = self.run_store(maximum=0, grace_seconds=0)
        self.assertFalse(old.exists())
        self.assertTrue(published.exists() and Path(str(published) + ".sum").exists())
        self.assertEqual(report["removed_entries"], 1)
        again = self.run_store(maximum=0, grace_seconds=HOUR)
        self.assertTrue(published.exists())  # seen now, but used within the grace period
        self.assertEqual(again["removed_entries"], 0)

    def test_foreign_paths_and_symlinks_survive(self):
        kept = self.pair("a", flat=False)
        foreign = self.root / "valuable.o"
        foreign.write_bytes(b"keep")
        linked = self.units / (kept.name)
        linked.symlink_to(foreign)
        stray = self.units / "notes.txt"
        stray.write_bytes(b"mine")
        aged(stray, 30 * DAY)
        report = self.run_store(maximum=0)
        self.assertFalse(report["unmet_budget"])
        self.assertFalse(kept.exists())
        self.assertEqual(foreign.read_bytes(), b"keep")
        self.assertTrue(linked.is_symlink())
        self.assertTrue(stray.exists())

    def test_a_run_reads_only_the_shards_that_are_due(self):
        self.pair("a")
        first = self.run_store(maximum=1 << 20, rescan_seconds=HOUR)
        self.assertEqual((first["shards_scanned"], first["unscanned_shards"]), (256, 0))
        late = self.pair("b")
        second = self.run_store(maximum=0, rescan_seconds=HOUR)
        self.assertEqual(second["shards_scanned"], 0)
        self.assertTrue(late.exists())  # not in the ledger yet: neither counted nor evicted
        third = self.run_store(maximum=0, rescan_seconds=0)
        self.assertEqual(third["shards_scanned"], 256)
        self.assertFalse(late.exists())

    def test_the_scan_budget_bounds_a_run_and_budget_eviction_waits_for_every_shard(self):
        paths = [self.pair() for _ in range(8)]
        primed = self.run_store(maximum=1 << 20, scan_seconds=0)
        self.assertEqual((primed["shards_scanned"], primed["unscanned_shards"]), (0, 256))
        self.assertFalse(primed["inventory_complete"])
        self.assertIn("priming", store.store_status(primed))
        partial = self.run_store(maximum=0, scan_seconds=0)
        self.assertTrue(all(path.exists() for path in paths))  # an unread store is not evicted by budget
        self.assertEqual(partial["removed_entries"], 0)
        done = self.run_store(maximum=0)
        self.assertTrue(done["inventory_complete"])
        self.assertFalse(any(path.exists() for path in paths))

    def test_the_age_batch_bounds_how_many_idle_objects_one_run_removes(self):
        paths = [self.pair(idle=30 * DAY) for _ in range(3)]
        report = self.run_store(maximum=1 << 20, batch=1)
        self.assertEqual(report["removed_entries"], 1)
        self.assertTrue(report["more"])
        self.assertEqual(sum(path.exists() for path in paths), 2)

    def test_the_eviction_budget_bounds_a_run_and_says_more_remains(self):
        paths = [self.pair() for _ in range(8)]
        original = store.remove_object

        def slow(*arguments, **keywords):
            time.sleep(0.05)
            return original(*arguments, **keywords)

        with mock.patch.object(store, "remove_object", slow):
            report = self.run_store(maximum=0, evict_seconds=0.12, workers=1)
        self.assertTrue(report["more"])
        self.assertTrue(report["unmet_target"])
        self.assertTrue(0 < report["removed_entries"] < 8)
        self.assertEqual(sum(path.exists() for path in paths), 8 - report["removed_entries"])

    def test_a_run_that_ran_out_of_time_with_candidates_left_says_more_and_not_stalled(self):
        paths = [self.pair() for _ in range(4)]
        original = store.remove_object
        calls = []

        def removing_then_time_runs_out(*arguments, **keywords):
            calls.append(1)
            result = original(*arguments, **keywords)
            if len(calls) == 2:
                time.sleep(0.2)
            return result

        with mock.patch.object(store, "remove_object", removing_then_time_runs_out):
            report = self.run_store(maximum=0, evict_seconds=0.1, workers=1)
        self.assertTrue(report["more"])
        self.assertFalse(report["stalled"])
        self.assertEqual(report["removed_entries"], 2)
        self.assertEqual(sum(path.exists() for path in paths), 2)

    def test_eviction_on_many_threads_removes_every_candidate_once_and_counts_every_byte(self):
        paths = [self.pair(idle=(100 + number) * HOUR, flat=number % 2 == 0) for number in range(300)]  # 28 bytes each
        report = self.run_store(maximum=300 * 28 - 100 * 28, workers=8)  # 8400 bytes held; keep 90% of 5600
        self.assertEqual(report["errors"], 0)
        self.assertLessEqual(report["retained_bytes"], 5040)
        self.assertGreater(report["retained_bytes"], 5040 - 28)
        survivors = [path for path in paths if path.exists()]
        self.assertEqual(len(survivors), report["retained_bytes"] // 28)
        self.assertEqual(survivors, paths[:len(survivors)])  # the least recently used went, nothing else
        self.assertEqual([entry for entry in self.units.rglob("*.partial")], [])
        for path in survivors:
            self.assertTrue(Path(str(path) + ".sum").exists())

    def test_a_flat_only_object_is_given_a_shard_name_and_is_then_evicted_like_any_other(self):
        old = self.pair(sharded=False, idle=30 * DAY)
        young = self.pair(sharded=False, idle=2 * DAY)
        report = self.run_store(maximum=1 << 20, flat_seconds=0, flat_budget=300.0)
        self.assertTrue(report["flat_listed"])
        self.assertFalse(old.exists())
        shard_name = self.units / young.name[:2] / young.name
        self.assertTrue(shard_name.exists() and Path(str(shard_name) + ".sum").exists())
        self.assertEqual(report["retained_bytes"], 28)

    def test_the_flat_names_of_an_object_that_has_a_shard_name_are_retired_and_the_object_stays(self):
        both = self.pair(flat=True, idle=2 * DAY)
        flat_only = self.pair(sharded=False, idle=2 * DAY)
        shard_inode = both.stat().st_ino
        report = self.run_store(maximum=1 << 20, flat_seconds=0, flat_budget=300.0)
        self.assertTrue(report["flat_listed"])
        self.assertEqual(report["flat_names_retired"], 4)
        for name in (both.name, flat_only.name):
            self.assertFalse((self.units / name).exists() or (self.units / (name + ".sum")).exists())
            shard_name = self.units / name[:2] / name
            self.assertTrue(shard_name.exists() and Path(str(shard_name) + ".sum").exists())
        self.assertEqual(both.stat().st_ino, shard_inode)
        self.assertEqual(report["retained_bytes"], 56)
        again = self.run_store(maximum=1 << 20, flat_seconds=0, flat_budget=300.0)
        self.assertEqual(again["flat_names_retired"], 0)

    def test_a_flat_name_is_kept_while_its_object_has_no_regular_shard_name(self):
        key = self.key()
        (self.units / key[:2]).mkdir()
        (self.units / key[:2] / (key + ".o")).symlink_to("elsewhere")
        flat = self.units / (key + ".o")
        flat.write_bytes(b"o" * 12)
        aged(flat, 2 * DAY)
        report = self.run_store(maximum=1 << 20, flat_seconds=0, flat_budget=300.0)
        self.assertEqual(report["flat_names_retired"], 0)
        self.assertTrue(flat.exists())

    def test_an_orphan_record_and_a_stale_staging_file_are_collected_and_a_fresh_one_is_kept(self):
        key = self.key()
        shard = self.units / key[:2]
        shard.mkdir()
        orphan = shard / (key + ".o.sum")
        orphan.write_bytes(b"record")
        aged(orphan, 7 * HOUR)
        stale = shard / (key + ".o." + "b" * 32 + ".partial")
        stale.write_bytes(b"half")
        aged(stale, 2 * DAY)
        fresh = shard / (key + ".o." + "c" * 32 + ".partial")
        fresh.write_bytes(b"half")
        aged(fresh, HOUR)
        self.run_store(maximum=1 << 20, grace_seconds=6 * HOUR)
        self.assertFalse(orphan.exists() or stale.exists())
        self.assertTrue(fresh.exists())

    def test_runtime_objects_go_only_when_idle_and_only_when_no_build_holds_the_root(self):
        old = self.root / ("core_rt-" + "a" * 8 + ".o")
        old.write_bytes(b"runtime")
        aged(old, 20 * DAY)
        young = self.root / ("core_rt-" + "b" * 8 + ".o")
        young.write_bytes(b"runtime")
        aged(young, DAY)
        with (self.root / ".retention.lock").open("a") as lease:
            fcntl.flock(lease, fcntl.LOCK_SH)
            busy = self.run_store(maximum=1 << 20)
        self.assertTrue(busy["root_busy"])
        self.assertTrue(old.exists())
        free = self.run_store(maximum=1 << 20)
        self.assertFalse(free["root_busy"])
        self.assertFalse(old.exists())
        self.assertTrue(young.exists())
        self.assertLess(free["exclusive_seconds"], 5.0)
        self.assertEqual(free["retained_bytes"], 7)

    def test_the_exclusive_window_on_the_root_lease_is_bounded_by_seconds_not_by_what_there_is_to_remove(self):
        for number in range(3000):
            path = self.root / (f"core_rt-{number:08x}.o")
            path.write_bytes(b"runtime")
            aged(path, 20 * DAY)
        original = store.drop
        slowed = {"drops": 0}

        def slow_drop(path):
            slowed["drops"] += 1
            time.sleep(0.01)
            return original(path)

        with mock.patch.object(store, "drop", slow_drop):
            report = self.run_store(maximum=1 << 20, window_seconds=0.3)
        self.assertGreater(report["root_removed"], 0)
        self.assertLess(report["root_removed"], 3000)
        self.assertLess(report["exclusive_seconds"], 1.5)
        again = self.run_store(maximum=1 << 20, window_seconds=60.0)
        self.assertEqual(report["root_removed"] + again["root_removed"], 3000)

    def test_the_previous_ledgers_are_dropped_once_every_shard_is_read(self):
        old = self.root / ".size-ledger-v2.sqlite3"
        old.write_bytes(b"x" * 1000)
        self.run_store(apply=False)
        self.assertTrue(old.exists())
        self.run_store()
        self.assertFalse(old.exists())
        self.assertTrue((self.root / store.LEDGER).exists())

    def test_a_damaged_ledger_is_made_again_from_the_store(self):
        stale = self.pair(idle=7 * HOUR)
        (self.root / store.LEDGER).write_bytes(b"this is not a database" * 100)
        report = self.run_store(maximum=0, grace_seconds=6 * HOUR)
        self.assertFalse(stale.exists())
        self.assertTrue(report["inventory_complete"])

    def test_the_ledger_can_live_outside_the_store(self):
        self.pair()
        outside = self.root.parent / (self.root.name + "-ledger.sqlite3")
        self.addCleanup(lambda: [Path(str(outside) + suffix).unlink(missing_ok=True) for suffix in ("", "-wal", "-shm")])
        report = self.run_store(maximum=1 << 20, ledger=str(outside), apply=False)
        self.assertTrue(outside.exists())
        self.assertFalse((self.root / store.LEDGER).exists())
        self.assertGreater(report["ledger_bytes"], 0)

    def test_scheduled_status_line_and_last_record_explain_priming_and_over_budget(self):
        report = self.run_store()
        recorded = json.loads((self.root / ".last-maintenance.json").read_text())
        self.assertTrue(recorded["inventory_complete"])
        self.assertIn("complete", store.store_status(recorded))
        self.assertIn("INCOMPLETE", store.store_status({"skipped_incomplete": True, "incomplete_attempts": 3}))
        self.assertIn("OVER BUDGET", store.store_status({"inventory_complete": True, "unmet_budget": True,
                                                         "retained_bytes": 2 << 30, "maximum_bytes": 1 << 30}))
        self.assertIn("priming", store.store_status({"inventory_complete": False, "unscanned_shards": 100}))
        self.assertIn("skipped", store.store_status({"skipped_active": True}))
        self.assertTrue(report["inventory_complete"])

    def test_a_second_maintenance_run_is_reported_skipped_not_waited_for(self):
        with (self.root / ".store-maintenance.lock").open("a") as running:
            fcntl.flock(running, fcntl.LOCK_EX)
            report = self.run_store()
        self.assertTrue(report["skipped_active"])

    def test_over_budget_shrinks_to_target_in_one_run_while_builders_publish(self):
        # 400 objects across shards, the older half far past the grace period. A "builder" publishes new objects the way the
        # compiler does (object renamed into place, then its record) for the whole run, and keeps hitting a few old ones.
        olds = [self.pair(idle=(2 + number % 20) * DAY, flat=True) for number in range(200)]
        newer = [self.pair(idle=(8 + number % 10) * HOUR, flat=True) for number in range(200)]
        used = olds[:5]
        published = []
        stop = threading.Event()

        def builder():
            number = 0
            while not stop.is_set() and number < 300:
                key = f"f{number:063x}"
                directory = self.units / key[:2]
                directory.mkdir(exist_ok=True)
                partial = directory / (key + ".o.0123456789abcdef0123456789abcdef.partial")
                partial.write_bytes(b"o" * 12)
                os.rename(partial, directory / (key + ".o"))
                (directory / (key + ".o.sum")).write_bytes(b"fixture checksum")
                published.append(directory / (key + ".o"))
                for path in used:
                    try:
                        os.utime(path)
                    except FileNotFoundError:
                        pass
                number += 1

        thread = threading.Thread(target=builder)
        thread.start()
        report = self.run_store(maximum=400 * 28, rescan_seconds=0)
        stop.set()
        thread.join()
        self.assertLessEqual(report["retained_bytes"], report["target_bytes"])
        self.assertFalse(report["unmet_budget"])
        for path in published:
            self.assertTrue(path.exists() and Path(str(path) + ".sum").exists(), path)
        for path in used:
            self.assertTrue(path.exists(), "an object a build kept using was evicted")
        survivors = sum(path.exists() for path in olds + newer)
        self.assertLess(survivors, 400)


class DeniedStores(unittest.TestCase):
    def test_a_store_named_by_the_deny_list_is_refused_and_a_private_one_is_not(self):
        with tempfile.TemporaryDirectory(prefix="core-store-deny-") as temporary:
            real = Path(temporary) / "real"
            private = Path(temporary) / "private"
            real.mkdir()
            private.mkdir()
            link = Path(temporary) / "link"
            link.symlink_to(real)
            with mock.patch.dict(os.environ, {store.DENY_ENVIRONMENT: os.pathsep.join([str(real), "/nowhere"])}):
                self.assertTrue(store.denied(real) and store.denied(link))
                self.assertFalse(store.denied(private))
                output = subprocess.run([sys.executable, str(Path(store.__file__)), "--store", str(link), "--apply"],
                                        capture_output=True, text=True)
                self.assertEqual(output.returncode, 2)
                self.assertTrue(json.loads(output.stdout)["refused"])
                self.assertEqual(list(real.iterdir()), [])
            self.assertFalse(store.denied(real))

    def test_the_user_store_is_where_an_unset_runtime_cache_variable_lands(self):
        self.assertEqual(store.user_store_roots({"XDG_CACHE_HOME": "/x", "HOME": "/h"}),
                         ["/x/selka/core-runtime", "/h/.cache/selka/core-runtime"])
        self.assertEqual(store.user_store_roots({"XDG_CACHE_HOME": "relative", "HOME": "/h"}), ["/h/.cache/selka/core-runtime"])
        self.assertEqual(store.user_store_roots({}), [])


class ClaimAndTimerContracts(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="core-store-claims-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_idle_claim_clearing_scales_linearly(self):
        # The subject is that clearing scales and does not stall. An absolute wall-clock
        # bound fails on a loaded machine (a gate run measured 61 s for this work), so the
        # check is a ratio in one run, on processor time: a stall is not work, and wall time
        # swings by 2x or more for the same clearing under load. Clearing 500,000 idle claims
        # (the default cap) must cost less than twice the linear ratio of 5 against 100,000.
        cost = {}
        for count in (100_000, 500_000):
            root = self.root / str(count)
            work = root / "units-v1" / "work"
            work.mkdir(parents=True)
            for index in range(count):
                (work / (f"{index:064x}" + ".lock")).touch()
            started = store.time.process_time()
            report = store.maintain(root, apply=True, claim_seconds=3600)  # the default 60 s bound would cut a loaded machine's run short
            cost[count] = store.time.process_time() - started
            self.assertEqual(report["idle_claims_removed"], count)
            self.assertEqual(list(work.iterdir()), [])
        self.assertLess(cost[500_000] / cost[100_000], 10.0)

    def test_a_held_claim_stays_and_an_idle_one_goes(self):
        work = self.root / "units-v1" / "work"
        work.mkdir(parents=True)
        held = work / ("a" * 64 + ".lock")
        idle = work / ("b" * 64 + ".lock")
        foreign = work / "notes.lock"
        for path in (held, idle, foreign):
            path.touch()
        with held.open("a") as lease:
            fcntl.flock(lease, fcntl.LOCK_EX)
            report = store.maintain(self.root, apply=True)
        self.assertEqual(report["idle_claims_removed"], 1)
        self.assertTrue(held.exists() and foreign.exists())
        self.assertFalse(idle.exists())

    def test_a_preview_counts_idle_claims_without_locking_or_removing_them(self):
        work = self.root / "work"
        work.mkdir()
        (work / ("a" * 64 + ".lock")).touch()
        report = store.maintain(self.root)
        self.assertEqual(report["idle_claims_removed"], 1)
        self.assertEqual(len(list(work.iterdir())), 1)

    def test_every_timer_has_an_activation_or_calendar_trigger(self):
        directory = Path(__file__).resolve().parents[1] / "scripts" / "systemd"
        timers = sorted(directory.glob("*.timer"))
        self.assertGreaterEqual(len(timers), 2)
        for timer in timers:
            triggers = [line.strip() for line in timer.read_text().splitlines()
                        if line.startswith(("OnBootSec=", "OnUnitInactiveSec=", "OnActiveSec=", "OnCalendar="))]
            self.assertTrue(triggers, timer.name + " has no trigger")
            self.assertTrue(any(line.startswith(("OnActiveSec=", "OnCalendar=")) for line in triggers),
                            timer.name + " only triggers relative to a prior run")
        core = (directory / "selka-core-store.timer").read_text()
        self.assertIn("OnCalendar=*:0/15", core)



DAY = 86400


class ToolMemoRetention(unittest.TestCase):
    """The toolchain identity memos (`core-tools-v1/`) are bounded by age and by bytes, and nothing else there is touched."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="core-tools-gc-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in store.TOOL_DIRECTORIES:
            (self.root / name).mkdir()

    def memo(self, digit, age_days, directory="tool-identity", kind="memo", size=10, touched_days=None):
        """A memo `age_days` old (read `touched_days` ago when it was read since)."""
        path = self.root / directory / (digit * 64 + "." + kind)
        path.write_bytes(b"x" * size)
        modified = os.stat(path).st_mtime - age_days * DAY
        accessed = os.stat(path).st_mtime - (age_days if touched_days is None else touched_days) * DAY
        os.utime(path, (accessed, modified))
        return path

    def test_a_memo_idle_past_the_age_bound_goes_and_a_young_or_recently_read_one_stays(self):
        old = self.memo("a", 20)
        young = self.memo("b", 2)
        read = self.memo("c", 20, directory="approval-v3", touched_days=1)
        report = store.collect_tools(self.root, apply=True, maximum=1 << 20, days=14)
        self.assertFalse(old.exists())
        self.assertTrue(young.exists() and read.exists())
        self.assertEqual((report["tools_entries"], report["tools_removed_files"], report["tools_removed_bytes"]), (3, 1, 10))
        self.assertEqual(report["tools_retained_bytes"], 20)

    def test_the_verdict_namespace_the_compiler_writes_is_collected(self):
        # GH-3b review, R8: `tool_identity.zig` writes `approval-v4/`; a namespace the list lacks is never collected.
        source = (Path(__file__).resolve().parents[1] / "src/core/tool_identity.zig").read_text()
        written = re.findall(r'"\{s\}/(approval-v[0-9]+)/', source)
        self.assertEqual(written, ["approval-v4"])
        self.assertIn(written[0], store.TOOL_DIRECTORIES)
        old = self.memo("d", 20, directory=written[0])
        store.collect_tools(self.root, apply=True, maximum=1 << 20, days=14)
        self.assertFalse(old.exists())

    def test_a_preview_removes_nothing(self):
        old = self.memo("a", 20)
        report = store.collect_tools(self.root, apply=False, maximum=1 << 20, days=14)
        self.assertTrue(old.exists())
        self.assertEqual(report["tools_removed_files"], 1)

    def test_over_the_byte_bound_the_least_recently_used_go_first_down_to_ninety_percent(self):
        paths = [self.memo(str(index), 10 - index, size=100) for index in range(1, 8)]
        report = store.collect_tools(self.root, apply=True, maximum=500, days=14)
        # 700 bytes held; 90% of the bound is 450: three go (700 -> 400), the oldest three.
        self.assertEqual([path.exists() for path in paths], [False, False, False, True, True, True, True])
        self.assertEqual(report["tools_retained_bytes"], 400)

    def test_a_staged_publication_expires_after_a_day_and_foreign_names_and_links_stay(self):
        stale = self.root / "tool-identity" / ("a" * 64 + ".memo." + "b" * 32 + ".pending")
        stale.write_bytes(b"half")
        os.utime(stale, (time.time() - 2 * DAY,) * 2)
        fresh = self.root / "tool-identity" / ("c" * 64 + ".inventory." + "d" * 32 + ".pending")
        fresh.write_bytes(b"half")
        foreign = self.root / "tool-identity" / "notes.txt"
        foreign.write_bytes(b"mine")
        os.utime(foreign, (0, 0))
        linked = self.root / "tool-identity" / ("e" * 64 + ".memo")
        linked.symlink_to(foreign)
        store.collect_tools(self.root, apply=True, maximum=1 << 20, days=14)
        self.assertFalse(stale.exists())
        self.assertTrue(fresh.exists() and foreign.exists() and linked.is_symlink())

    def test_a_missing_store_or_a_symlinked_namespace_is_left_alone(self):
        self.assertEqual(store.collect_tools(self.root / "absent", apply=True)["tools_entries"], 0)
        outside = self.root / "outside"
        outside.mkdir()
        victim = outside / ("a" * 64 + ".memo")
        victim.write_bytes(b"x")
        os.utime(victim, (0, 0))
        (self.root / "approval-v3").rmdir()
        (self.root / "approval-v3").symlink_to(outside)
        store.collect_tools(self.root, apply=True, days=1)
        self.assertTrue(victim.exists())

    def test_main_bounds_the_memos_beside_the_store_and_reports_them(self):
        runtime = self.root / "core-runtime"
        runtime.mkdir()
        tools = self.root / "core-tools-v1"
        tools.mkdir()
        (tools / "tool-identity").mkdir()
        old = tools / "tool-identity" / ("a" * 64 + ".memo")
        old.write_bytes(b"x")
        os.utime(old, (0, 0))
        output = subprocess.run([sys.executable, str(Path(store.__file__)), "--store", str(runtime), "--apply"],
                                check=True, capture_output=True, text=True).stdout
        report = json.loads(output.splitlines()[0])
        self.assertEqual(report["tools_removed_files"], 1)
        self.assertFalse(old.exists())


if __name__ == "__main__":
    unittest.main()
