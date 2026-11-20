#!/usr/bin/env python3
"""Pins the edit check's guest plan and guest file list (E2) on synthetic inputs.

Run: python3 tests/test_edit_check.py  (also run by `zig build test-affected-selection`).
"""
import contextlib
import gzip
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import edit_check  # noqa: E402
import edit_check_collect  # noqa: E402
import edit_check_refresh  # noqa: E402

EVERY = ["tests/lang/a.selka", "tests/lang/b.selka", "tests/lang/sub/c.selka"]


class GuestPlanTest(unittest.TestCase):
    def test_no_guest_file_selected_runs_nothing(self):
        self.assertEqual([], edit_check.guest_plan([], EVERY, "selka"))

    def test_every_guest_file_selected_is_one_directory_run(self):
        self.assertEqual([("guests", "guests", None, ["selka", "test", "tests/lang"])],
                         edit_check.guest_plan(list(EVERY), EVERY, "selka"))

    def test_some_guest_files_selected_are_one_process_each(self):
        self.assertEqual([("guests", "guests-0", None, ["selka", "test", "tests/lang/b.selka"]),
                          ("guests", "guests-1", None, ["selka", "test", "tests/lang/sub/c.selka"])],
                         edit_check.guest_plan(["tests/lang/b.selka", "tests/lang/sub/c.selka"], EVERY, "selka"))


class GuestFilesTest(unittest.TestCase):
    def test_every_my_file_under_tests_lang_is_a_guest_file(self):
        with tempfile.TemporaryDirectory() as root:
            for name in ["tests/lang/a.selka", "tests/lang/sub/c.selka", "tests/lang/README.md", "tests/other.selka"]:
                path = os.path.join(root, name)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "w").close()
            self.assertEqual(["tests/lang/a.selka", "tests/lang/sub/c.selka"], edit_check_collect.guest_files(root))


class DriverStepsTest(unittest.TestCase):
    """An edit of the goals register's page or of a pinned example selects the goals check (W24's open item)."""

    def test_an_edit_of_the_goals_page_or_a_pin_selects_the_goals_check(self):
        self.assertEqual([("test-goals", ["docs/goals.md"])], edit_check.driver_steps(["docs/goals.md", "src/lexer.zig"]))
        pins = ["test/fixtures/goals/docs/G09-nothing-implicit.md", "test/fixtures/goals/README.md"]
        self.assertEqual([("test-goals", pins)], edit_check.driver_steps(["src/lexer.zig"] + pins))
        self.assertEqual([("test-goals", ["tests/goals_register.py"])], edit_check.driver_steps(["tests/goals_register.py"]))

    def test_an_edit_of_the_compiler_map_or_its_driver_selects_the_goals_check(self):
        # The same step runs the compiler map's check (`--map`), so its page and its driver select it too (DL-7).
        both = ["docs/tooling/compiler-map.md", "tests/compiler_map.py"]
        self.assertEqual([("test-goals", both)], edit_check.driver_steps(["src/lexer.zig"] + both))

    def test_a_page_or_fixture_beside_them_selects_no_step(self):
        self.assertEqual([], edit_check.driver_steps(["docs/goals-notes.md", "docs/io.md", "test/fixtures/fix-migration/a.selka"]))
        self.assertEqual([], edit_check.driver_steps([]))

    def test_the_selection_line_names_the_step_and_the_first_path(self):
        self.assertEqual("steps: test-goals (docs/goals.md)", edit_check.step_line([("test-goals", ["docs/goals.md"])]))
        self.assertEqual("steps: test-goals (a.md and 1 more)", edit_check.step_line([("test-goals", ["a.md", "b.md"])]))

    def test_the_paths_since_the_maps_commit_are_committed_staged_unstaged_and_untracked_edits(self):
        with tempfile.TemporaryDirectory() as root:
            def git(*arguments):
                subprocess.run(["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t", *arguments], check=True,
                               capture_output=True)
            for name in ("docs", "test/fixtures/goals/docs"):
                os.makedirs(os.path.join(root, name))
            for name in ("docs/goals.md", "docs/io.md", "test/fixtures/goals/docs/G1.md", "a.txt"):
                with open(os.path.join(root, name), "w") as handle:
                    handle.write("one\n")
            git("init", "-q")
            git("add", ".")
            git("commit", "-q", "-m", "base")
            base = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip()
            with open(os.path.join(root, "docs/io.md"), "w") as handle:
                handle.write("two\n")
            git("commit", "-q", "-am", "committed edit")
            with open(os.path.join(root, "docs/goals.md"), "w") as handle:
                handle.write("two\n")
            with open(os.path.join(root, "test/fixtures/goals/docs/G2.md"), "w") as handle:
                handle.write("new pin\n")
            self.assertEqual(["docs/goals.md", "docs/io.md", "test/fixtures/goals/docs/G2.md"], edit_check.changed_paths(base, root))
            self.assertEqual(["docs/goals.md", "test/fixtures/goals/docs/G2.md"], [p for p in edit_check.changed_paths("HEAD", root)])

    def test_a_map_file_name_gives_its_commit(self):
        self.assertEqual("0123abc", edit_check.map_commit("/store/coverage-0123abc.json.gz"))
        self.assertIsNone(edit_check.map_commit("/store/other.json.gz"))


def write_map(path, document):
    """A map file as `edit-check-tool map` writes it: gzip-compressed JSON."""
    with gzip.open(path, "wt") as handle:
        json.dump(document, handle)


class RefusedMapTest(unittest.TestCase):
    def test_a_map_without_the_unrecorded_list_is_refused_and_one_with_it_is_not(self):
        with tempfile.TemporaryDirectory() as directory:
            old = os.path.join(directory, "coverage-old.json.gz")
            new = os.path.join(directory, "coverage-new.json.gz")
            write_map(old, {"format": "edit-check-coverage-map-v2", "commit": "a", "tests": []})
            write_map(new, {"format": "edit-check-coverage-map-v2", "commit": "b", "unrecorded": []})
            self.assertTrue(edit_check.map_refused(old))
            self.assertFalse(edit_check.map_refused(new))
            self.assertTrue(edit_check.map_refused(os.path.join(directory, "missing.json.gz")))

    def test_a_refused_map_is_one_line_a_refresh_and_the_no_map_fallback(self):
        with tempfile.TemporaryDirectory() as store:
            output = io.StringIO()
            with mock.patch.object(edit_check_refresh, "lock_held", return_value=False), \
                    mock.patch.object(edit_check_refresh, "refresh_allowed", return_value=True), \
                    mock.patch.object(edit_check_refresh, "start_detached", return_value="/log/worker.log") as start, \
                    mock.patch.object(edit_check.subprocess, "call", return_value=0) as fallback, \
                    contextlib.redirect_stdout(output):
                status = edit_check.refused_map(store, "/maps/coverage-abc.json.gz", False)
            self.assertEqual(status, 0)
            self.assertEqual(start.call_count, 1)
            self.assertEqual(fallback.call_args.args[0][-1], os.path.join(ROOT, "scripts", "affected_tests.py"))
            lines = output.getvalue().splitlines()
            self.assertEqual(len(lines), 1)
            self.assertIn("coverage-abc.json.gz predates the unrecorded list", lines[0])
            self.assertIn("started a refresh of main (log /log/worker.log)", lines[0])

    def test_a_select_only_run_refuses_the_map_without_starting_a_refresh(self):
        with tempfile.TemporaryDirectory() as store:
            output = io.StringIO()
            # The real refresh_allowed: a select-only run never starts a refresh.
            with mock.patch.object(edit_check_refresh, "lock_held", return_value=False), \
                    mock.patch.object(edit_check_refresh, "start_detached") as start, \
                    mock.patch.object(edit_check.subprocess, "call") as fallback, \
                    contextlib.redirect_stdout(output):
                status = edit_check.refused_map(store, "/maps/coverage-abc.json.gz", True)
            self.assertEqual(status, 0)
            start.assert_not_called()
            fallback.assert_not_called()
            self.assertIn("no refresh is running", output.getvalue())


if __name__ == "__main__":
    unittest.main()
