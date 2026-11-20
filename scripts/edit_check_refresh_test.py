#!/usr/bin/env python3
"""Unit tests of the edit check's map refresh scheduling (E5): batching, cancellation, refusal, locking, merging, staleness.

    python3 scripts/edit_check_refresh_test.py

Run by `zig build test-edit-check`. No compiler, no build slot and no test binary runs here.
"""
import gzip
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import edit_check_collect  # noqa: E402
import edit_check_map  # noqa: E402
import edit_check_refresh as refresh  # noqa: E402


class BatchSizerTest(unittest.TestCase):
    def test_growth_is_capped_at_double_per_batch(self):
        sizer = refresh.BatchSizer(seconds=60, initial=100, low=10, high=100000)
        sizer.observe(100, 10)
        self.assertEqual(sizer.size(), 200)
        sizer.observe(10000, 10)
        self.assertEqual(sizer.size(), 400)

    def test_a_slow_first_batch_shrinks_to_the_floor_and_sizes_stay_in_bounds(self):
        sizer = refresh.BatchSizer(seconds=60, initial=1000, low=10, high=1000)
        sizer.observe(10, 100)
        self.assertEqual(sizer.size(), 10)
        fast = refresh.BatchSizer(seconds=60, initial=100, low=10, high=1000)
        for _ in range(4):
            fast.observe(10000, 1)
        self.assertEqual(fast.size(), 1000)
        fast.observe(0, 5)
        fast.observe(7, 0)
        self.assertEqual(fast.size(), 1000)


class RunBatchesTest(unittest.TestCase):
    def test_every_name_runs_exactly_once_and_each_root_has_one_first_batch(self):
        names = {"units": ["u%d" % i for i in range(37)], "cli": ["c%d" % i for i in range(5)], "core": []}
        calls = []

        def run_batch(root, batch, first):
            calls.append((root, list(batch), first))
            return 1.0

        sizers = {}
        sizer_for = lambda root: sizers.setdefault(root, refresh.BatchSizer(seconds=60, initial=7, low=1, high=50))  # noqa: E731
        self.assertEqual(refresh.run_batches(names, sizer_for, run_batch, lambda: False), "done")
        for root in names:
            ran = [name for call_root, batch, _ in calls if call_root == root for name in batch]
            self.assertEqual(ran, names[root])
            firsts = [first for call_root, _, first in calls if call_root == root]
            self.assertEqual(firsts[0], True)
            self.assertEqual(firsts.count(True), 1)

    def test_a_cancelled_refresh_stops_before_the_next_batch(self):
        names = {"units": ["u%d" % i for i in range(100)], "cli": [], "core": []}
        calls = []
        flags = iter([False, False, True])
        outcome = refresh.run_batches(names, lambda root: refresh.BatchSizer(initial=10, low=10),
                                      lambda root, batch, first: calls.append(batch) or 1.0, lambda: next(flags))
        self.assertEqual(outcome, "cancelled")
        self.assertEqual(len(calls), 2)


class ConvergeTest(unittest.TestCase):
    def test_a_head_that_moves_during_a_refresh_is_mapped_next(self):
        heads = ["A", "B"]
        maps = set()
        seen = []

        def refresh_once(target):
            seen.append(target)
            if target == "A":
                heads.pop(0)  # main moved while A was being collected
                return "cancelled"
            maps.add(target)
            return "published"

        outcome = refresh.converge(lambda: heads[0], maps.__contains__, refresh_once)
        self.assertEqual(outcome, ("published", "B"))
        self.assertEqual(seen, ["A", "B"])

    def test_a_refused_map_is_not_retried(self):
        seen = []
        outcome = refresh.converge(lambda: "A", lambda commit: False, lambda target: seen.append(target) or "refused")
        self.assertEqual(outcome, ("refused", "A"))
        self.assertEqual(seen, ["A"])

    def test_an_existing_map_needs_no_refresh(self):
        seen = []
        outcome = refresh.converge(lambda: "A", lambda commit: True, lambda target: seen.append(target))
        self.assertEqual(outcome, ("fresh", "A"))
        self.assertEqual(seen, [])


class PublishTest(unittest.TestCase):
    def test_a_refused_map_leaves_the_last_good_map_in_place(self):
        with tempfile.TemporaryDirectory() as directory:
            final = os.path.join(directory, "coverage-A.json.gz")
            partial = os.path.join(directory, "partial-A.json.gz")
            with open(final, "wb") as handle:
                handle.write(b"good")
            with open(partial, "wb") as handle:
                handle.write(b"bad")
            self.assertFalse(refresh.publish_map(partial, final, ["units-00001 failed"]))
            self.assertFalse(os.path.exists(partial))
            with open(final, "rb") as handle:
                self.assertEqual(handle.read(), b"good")

    def test_an_accepted_map_replaces_the_old_one_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            final = os.path.join(directory, "coverage-B.json.gz")
            partial = os.path.join(directory, "partial-B.json.gz")
            with open(partial, "wb") as handle:
                handle.write(b"new")
            self.assertTrue(refresh.publish_map(partial, final, []))
            self.assertFalse(os.path.exists(partial))
            with open(final, "rb") as handle:
                self.assertEqual(handle.read(), b"new")

    def test_failed_tests_reads_the_refusal_list(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "map.json.gz")
            with gzip.open(path, "wt") as handle:
                json.dump({"failed": ["core.test.x"]}, handle)
            self.assertEqual(edit_check_map.failed_tests(path), ["core.test.x"])


class PruneTest(unittest.TestCase):
    def store_with(self, directory, commits):
        """A map store holding one map per commit (name -> its commit time), the refresh's own files and durations."""
        for commit in commits:
            with open(os.path.join(directory, "coverage-%s.json.gz" % commit), "w") as handle:
                handle.write("map")
        for name in ("durations.json", "shadow.jsonl", "coverage-%s-run1.json.gz" % ("e" * 40)):
            with open(os.path.join(directory, name), "w") as handle:
                handle.write("not a finished map")
        os.makedirs(os.path.join(directory, "refresh"))

    def remaining(self, directory):
        return sorted(name for name in os.listdir(directory) if refresh.MAP_NAME.fullmatch(name))

    def test_the_store_keeps_the_newest_maps_by_commit_time_and_never_touches_other_files(self):
        commits = {("%d" % index) * 40: 1000 + index for index in range(1, 9)}
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(refresh, "commit_time", lambda commit, fallback: commits[commit]):
            self.store_with(directory, commits)
            removed = refresh.prune_maps(directory, keep=5)
            self.assertEqual(removed, ["3" * 40, "2" * 40, "1" * 40])
            self.assertEqual(self.remaining(directory), ["coverage-%s.json.gz" % ("%d" % index * 40) for index in range(4, 9)])
            for name in ("durations.json", "shadow.jsonl", "refresh", "coverage-%s-run1.json.gz" % ("e" * 40)):
                self.assertTrue(os.path.exists(os.path.join(directory, name)), name)
            self.assertEqual(refresh.prune_maps(directory, keep=5), [])

    def test_a_protected_commit_and_a_map_a_running_edit_check_holds_stay(self):
        commits = {("%d" % index) * 40: 1000 + index for index in range(1, 8)}
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(refresh, "commit_time", lambda commit, fallback: commits[commit]):
            self.store_with(directory, commits)
            held = refresh.hold_map(os.path.join(directory, "coverage-%s.json.gz" % ("1" * 40)))
            self.assertIsNotNone(held)
            removed = refresh.prune_maps(directory, keep=3, protect={"2" * 40})
            held.close()
            self.assertEqual(removed, ["4" * 40, "3" * 40])
            self.assertEqual(self.remaining(directory), ["coverage-%s.json.gz" % ("%d" % index * 40) for index in (1, 2, 5, 6, 7)])
            self.assertEqual(refresh.prune_maps(directory, keep=3), ["2" * 40, "1" * 40])
            self.assertEqual(self.remaining(directory), ["coverage-%s.json.gz" % ("%d" % index * 40) for index in (5, 6, 7)])

    def test_a_commit_this_checkout_does_not_know_is_ordered_by_its_files_time(self):
        with tempfile.TemporaryDirectory() as directory:
            self.store_with(directory, ["a" * 40, "b" * 40, "c" * 40])
            for age, commit in enumerate(("a" * 40, "b" * 40, "c" * 40)):
                os.utime(os.path.join(directory, "coverage-%s.json.gz" % commit), (5000 - age * 10, 5000 - age * 10))
            self.assertEqual(refresh.prune_maps(directory, keep=2), ["c" * 40])
            self.assertEqual(self.remaining(directory), ["coverage-%s.json.gz" % ("a" * 40), "coverage-%s.json.gz" % ("b" * 40)])

    def test_a_missing_store_has_nothing_to_prune(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(refresh.prune_maps(os.path.join(directory, "absent"), keep=1), [])


class LockTest(unittest.TestCase):
    def test_the_lock_admits_one_refresher(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "refresh", "refresh.lock")
            first = refresh.try_lock(path)
            self.assertIsNotNone(first)
            self.assertIsNone(refresh.try_lock(path))
            first.close()
            second = refresh.try_lock(path)
            self.assertIsNotNone(second)
            second.close()


def write_batch(directory, root, names, hits):
    """A batch directory as the collector writes it: tests, results and one hit set per name in HITS."""
    os.makedirs(os.path.join(directory, "cov"))
    with open(os.path.join(directory, "tests-%s.json" % root), "w") as handle:
        json.dump(["%s.test.%d" % (root, i) for i in range(names)], handle)
    with open(os.path.join(directory, "results-%s.jsonl" % root), "w") as handle:
        for token in hits:
            handle.write(json.dumps({"token": token, "status": 0}) + "\n")
            os.makedirs(os.path.join(directory, "cov", token))
            with open(os.path.join(directory, "cov", token, "1.cov"), "w") as cov:
                cov.write("hits " + token + "\n")


class KeepResultsTest(unittest.TestCase):
    def test_a_refused_runs_result_files_survive_the_work_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            work = os.path.join(directory, "work")
            os.makedirs(os.path.join(work, "run-1", "cov"))
            with open(os.path.join(work, "run-1", "results-core.jsonl"), "w") as handle:
                handle.write('{"token": "core-00001", "status": 1}\n')
            logs = os.path.join(directory, "logs")
            refresh.keep_results(work, logs)
            with open(os.path.join(logs, "run-1-results-core.jsonl")) as handle:
                self.assertIn("core-00001", handle.read())


class MergeTest(unittest.TestCase):
    def test_merge_moves_every_hit_set_once_and_keeps_the_result_order(self):
        with tempfile.TemporaryDirectory() as directory:
            first = os.path.join(directory, "batch-1")
            second = os.path.join(directory, "batch-2")
            write_batch(first, "units", 3, ["units-00000", "units-00001"])
            write_batch(second, "units", 3, ["units-00002"])
            run = os.path.join(directory, "run-1")
            refresh.merge_batches(run, [("units", first), ("units", second)])
            self.assertEqual(sorted(os.listdir(os.path.join(run, "cov"))), ["units-00000", "units-00001", "units-00002"])
            with open(os.path.join(run, "results-units.jsonl")) as handle:
                tokens = [json.loads(line)["token"] for line in handle]
            self.assertEqual(tokens, ["units-00000", "units-00001", "units-00002"])
            with open(os.path.join(run, "tests-units.json")) as handle:
                self.assertEqual(len(json.load(handle)), 3)

    def test_merge_refuses_batches_with_different_test_lists(self):
        with tempfile.TemporaryDirectory() as directory:
            first = os.path.join(directory, "batch-1")
            second = os.path.join(directory, "batch-2")
            write_batch(first, "cli", 2, ["cli-00000"])
            write_batch(second, "cli", 3, ["cli-00001"])
            with self.assertRaises(refresh.MergeError):
                refresh.merge_batches(os.path.join(directory, "run-1"), [("cli", first), ("cli", second)])


def write_unrecorded_list(directory, value):
    """A batch's unrecorded.json as the collector writes it: a list of tokens, or {"traced": false}."""
    with open(os.path.join(directory, "unrecorded.json"), "w") as handle:
        json.dump(value, handle)


def write_trace(out, token, number, pids):
    """A trace of TOKEN's attempt NUMBER that executed an instrumented `selka` at each of PIDS."""
    os.makedirs(os.path.join(out, "exec"), exist_ok=True)
    with open(os.path.join(out, "exec", "%s-%d.strace" % (token, number)), "w") as handle:
        for pid in pids:
            handle.write('%d execve("/x/zig-out/coverage/bin/selka", ["selka"], 0x0) = 0\n' % pid)


class UnrecordedMergeTest(unittest.TestCase):
    def test_the_traced_batches_unite_their_unrecorded_lists(self):
        with tempfile.TemporaryDirectory() as directory:
            first = os.path.join(directory, "batch-1")
            second = os.path.join(directory, "batch-2")
            write_batch(first, "cli", 2, ["cli-00000"])
            write_batch(second, "cli", 2, ["cli-00001"])
            write_unrecorded_list(first, ["cli-00000"])
            write_unrecorded_list(second, ["cli-00001"])
            run = os.path.join(directory, "run-1")
            refresh.merge_batches(run, [("cli", first), ("cli", second)])
            with open(os.path.join(run, "unrecorded.json")) as handle:
                self.assertEqual(json.load(handle), ["cli-00000", "cli-00001"])

    def test_untraced_batches_mark_the_run_untraced(self):
        with tempfile.TemporaryDirectory() as directory:
            first = os.path.join(directory, "batch-1")
            write_batch(first, "units", 1, ["units-00000"])
            write_unrecorded_list(first, {"traced": False})
            run = os.path.join(directory, "run-2")
            refresh.merge_batches(run, [("units", first)])
            with open(os.path.join(run, "unrecorded.json")) as handle:
                self.assertEqual(json.load(handle), {"traced": False})

    def test_a_mix_of_traced_and_untraced_batches_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            first = os.path.join(directory, "batch-1")
            second = os.path.join(directory, "batch-2")
            write_batch(first, "core", 2, ["core-00000"])
            write_batch(second, "core", 2, ["core-00001"])
            write_unrecorded_list(first, ["core-00000"])
            write_unrecorded_list(second, {"traced": False})
            with self.assertRaises(refresh.MergeError):
                refresh.merge_batches(os.path.join(directory, "run-1"), [("core", first), ("core", second)])


class GuestUnrecordedTest(unittest.TestCase):
    def test_a_guest_file_whose_phase_left_a_process_without_a_hit_set_is_unrecorded(self):
        with tempfile.TemporaryDirectory() as directory:
            os.makedirs(os.path.join(directory, "cov", "guests-00000"))
            os.makedirs(os.path.join(directory, "cov", "guests-00001"))
            with open(os.path.join(directory, "results-guests.jsonl"), "w") as handle:
                handle.write(json.dumps({"root": "guests", "token": "guests-00000", "attempts": [0, 0]}) + "\n")
                handle.write(json.dumps({"root": "guests", "token": "guests-00001", "attempts": [0, 0]}) + "\n")
            # guests-00000: the warm phase ran selka (pid 22) and left no hit set for it.
            write_trace(directory, "guests-00000", 0, [11])
            write_trace(directory, "guests-00000", 1, [22])
            open(os.path.join(directory, "cov", "guests-00000", "11.cov"), "w").close()
            # guests-00001: both phases ran selka and both left a hit set.
            write_trace(directory, "guests-00001", 0, [33])
            write_trace(directory, "guests-00001", 1, [44])
            open(os.path.join(directory, "cov", "guests-00001", "33.cov"), "w").close()
            open(os.path.join(directory, "cov", "guests-00001", "44.cov"), "w").close()
            self.assertEqual(edit_check_collect.unrecorded_tokens(directory, root="guests"), ["guests-00000"])

    def test_the_guest_phase_adds_its_tokens_to_the_first_runs_list(self):
        with tempfile.TemporaryDirectory() as directory:
            run = os.path.join(directory, "run-1")
            os.makedirs(run)
            write_unrecorded_list(run, ["cli-00169"])
            edit_check_collect.write_unrecorded(run, ["guests-00003"])
            with open(os.path.join(run, "unrecorded.json")) as handle:
                self.assertEqual(json.load(handle), ["cli-00169", "guests-00003"])

    def test_a_guest_file_with_no_trace_for_a_phase_is_unrecorded(self):
        with tempfile.TemporaryDirectory() as directory:
            os.makedirs(os.path.join(directory, "cov", "guests-00000"))
            with open(os.path.join(directory, "results-guests.jsonl"), "w") as handle:
                handle.write(json.dumps({"root": "guests", "token": "guests-00000", "attempts": [0, 0]}) + "\n")
            write_trace(directory, "guests-00000", 0, [])
            self.assertEqual(edit_check_collect.unrecorded_tokens(directory, root="guests"), ["guests-00000"])


def git_repo(commits):
    """A repository with COMMITS commits on main; returns its path and the commit ids, oldest first."""
    directory = tempfile.mkdtemp(prefix="e5-repo-")
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    subprocess.run(["git", "init", "-q", "-b", "main", directory], check=True)
    ids = []
    for number in range(commits):
        with open(os.path.join(directory, "f.txt"), "w") as handle:
            handle.write(str(number))
        subprocess.run(["git", "-C", directory, "add", "f.txt"], check=True)
        subprocess.run(["git", "-C", directory, "commit", "-q", "-m", "c%d" % number], check=True, env=env)
        ids.append(subprocess.check_output(["git", "-C", directory, "rev-parse", "HEAD"], text=True).strip())
    return directory, ids


class StalenessTest(unittest.TestCase):
    def test_commits_behind_counts_commits_after_the_map(self):
        directory, ids = git_repo(4)
        with mock.patch.object(refresh, "ROOT", directory):
            self.assertEqual(refresh.commits_behind(ids[0], "main"), 3)
            self.assertEqual(refresh.commits_behind(ids[3], "main"), 0)

    def test_the_staleness_line_appears_past_the_threshold_and_only_a_real_run_starts_a_refresh(self):
        directory, ids = git_repo(refresh.STALE_COMMITS + 3)
        store = tempfile.mkdtemp(prefix="e5-store-")
        behind = refresh.STALE_COMMITS + 2
        with mock.patch.object(refresh, "ROOT", directory), mock.patch.object(refresh, "start_detached") as start:
            self.assertIsNone(refresh.staleness_note(store, ids[-2], select_only=True))
            note = refresh.staleness_note(store, ids[0], select_only=True)
            self.assertIn("%d commits behind main" % behind, note)
            self.assertIn("no refresh is running", note)
            start.assert_not_called()
        with mock.patch.object(refresh, "ROOT", directory), mock.patch.object(refresh, "start_detached") as start:
            start.return_value = "log"
            note = refresh.staleness_note(store, ids[0], select_only=False)
            start.assert_called_once_with(store, "main")
            self.assertIn("started a refresh of main", note)


class CheckoutTest(unittest.TestCase):
    def test_checkout_creates_a_locked_worktree_at_the_target(self):
        directory, ids = git_repo(2)
        worktree = os.path.join(tempfile.mkdtemp(prefix="e5-wt-"), "refresh")
        with mock.patch.object(refresh, "ROOT", directory):
            refresh.checkout(worktree, ids[0])
            self.assertTrue(refresh.worktree_locked(worktree))
            head = subprocess.check_output(["git", "-C", worktree, "rev-parse", "HEAD"], text=True).strip()
            self.assertEqual(head, ids[0])
            refresh.checkout(worktree, ids[1])
            head = subprocess.check_output(["git", "-C", worktree, "rev-parse", "HEAD"], text=True).strip()
            self.assertEqual(head, ids[1])


class GuestPhaseTest(unittest.TestCase):
    def worker(self, directory):
        worker = refresh.Worker.__new__(refresh.Worker)
        worker.store, worker.ref, worker.repo, worker.env = directory, "main", directory, {}
        return worker

    def test_the_guest_phase_collects_into_the_first_runs_directory_in_one_admission(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(refresh, "admitted", return_value=(0, 0.0, 1.0)) as admitted, \
                mock.patch.object(refresh, "wait_while_queued", return_value=0.0), mock.patch.object(refresh, "record"):
            self.worker(directory).collect_guests("c0", os.path.join(directory, "run-1"), directory)
        command = admitted.call_args.args[1]
        self.assertEqual(admitted.call_count, 1)
        self.assertIn("--guests", command)
        self.assertEqual(command[command.index("--out") + 1], os.path.join(directory, "run-1"))

    def test_a_failed_guest_phase_fails_the_refresh(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(refresh, "admitted", return_value=(1, 0.0, 1.0)), \
                mock.patch.object(refresh, "wait_while_queued", return_value=0.0), mock.patch.object(refresh, "record"):
            with self.assertRaises(refresh.BatchFailed):
                self.worker(directory).collect_guests("c0", os.path.join(directory, "run-1"), directory)


class OutputWrappedTest(unittest.TestCase):
    def test_the_command_writes_its_own_output_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = os.path.join(directory, "command.out")
            subprocess.run(refresh.output_wrapped(["sh", "-c", "printf first; printf second >&2"], output), check=True)
            with open(output) as handle:
                self.assertEqual(handle.read(), "firstsecond")


class SlotParsingTest(unittest.TestCase):
    def test_busy_lines_keep_only_gate_and_timing_requests(self):
        status = "slot dir: x\nbuild1: free\ngate queue 1: pid 12, waiting 5s\ntiming queue 2: pid 9, waiting 1s\nbuild queue 1: pid 3, waiting 0s\n"
        self.assertEqual(refresh.busy_lines(status), ["gate queue 1: pid 12, waiting 5s", "timing queue 2: pid 9, waiting 1s"])

    def test_admission_wait_is_read_from_the_first_admission_line(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "log")
            with open(path, "w") as handle:
                handle.write("build-slot: build slot 2, FIFO ticket 14 after 12.250s\nzig output\n")
            self.assertEqual(refresh.admission_wait(path), 12.25)


if __name__ == "__main__":
    unittest.main()
