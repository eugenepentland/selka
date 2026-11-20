#!/usr/bin/env python3
"""Contracts for the language gate's exact unsupported-verdict allowlist."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("test_lang_guard", ROOT / "scripts/test_lang.py")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


def verdict(name="m::test_one", status="unsupported", reason="documented lowering limit"):
    return {"name": name, "status": status, "reason": reason, "at": "3:4"}


def report(*rows):
    counts = {status: sum(row["status"] == status for row in rows) for status in guard.STATUSES}
    return json.dumps({"version": "native-tests-v1", "tests": list(rows), **counts}) + "\n"


def listed(reason="documented lowering limit", suite="tests/lang", name="m::test_one"):
    return {"version": 1, "tests": [{"suite": suite, "name": name, "reason": reason}]}


class GuardTests(unittest.TestCase):
    def run_guard(self, text, entries=None, child_exit=0, suite="tests/lang", extra=()):
        calls, stdout, stderr = [], io.StringIO(), io.StringIO()
        def compiler(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, child_exit, text, "compiler diagnostics\n")
        allowlist = guard.allowlist_entries(entries or {"version": 1, "tests": []})
        with mock.patch.object(guard, "load_allowlist", return_value=allowlist), redirect_stdout(stdout), redirect_stderr(stderr):
            status = guard.main(["--compiler", "pinned-selka", suite, *extra], run=compiler)
        return status, stdout.getvalue(), stderr.getvalue(), calls

    def test_checked_in_list_excludes_both_task_regressions(self):
        entries = guard.load_allowlist(ROOT / "tests/unsupported.json")
        self.assertNotIn(("tests/lang", "parallel_groups::test_lent_borrowed_binding_is_read_after_the_join"), entries)
        self.assertNotIn(("tests/lang", "parallel_groups::test_lent_bound_list_element_is_read_after_the_join"), entries)
        self.assertEqual({}, entries)

    def test_known_unsupported_preserves_real_report_and_runs_every_selected_test(self):
        text = report(verdict(), verdict("m::test_supported", "passed", ""))
        status, stdout, stderr, calls = self.run_guard(text, listed())
        self.assertEqual(0, status)
        self.assertEqual(text, stdout)
        self.assertEqual("compiler diagnostics\n", stderr)
        self.assertEqual(1, len(calls))
        self.assertEqual(["pinned-selka", "test", "tests/lang", "--json"], calls[0][0])

    def test_unknown_unsupported_fails_with_its_actual_reason(self):
        status, _, stderr, _ = self.run_guard(report(verdict()))
        self.assertEqual(1, status)
        self.assertIn("unexpected unsupported test tests/lang/m::test_one: documented lowering limit", stderr)

    def test_matching_name_in_another_suite_does_not_grant_exception(self):
        status, _, stderr, _ = self.run_guard(report(verdict()), listed(suite="tests/ported"))
        self.assertEqual(1, status)
        self.assertIn("unexpected unsupported test tests/lang/m::test_one", stderr)

    def test_changed_reason_fails_instead_of_hiding_a_different_regression(self):
        status, _, stderr, _ = self.run_guard(report(verdict(reason="new unsupported cause")), listed())
        self.assertEqual(1, status)
        self.assertIn("unsupported reason changed", stderr)
        self.assertIn("new unsupported cause", stderr)
        self.assertIn("documented lowering limit", stderr)

    def test_allowlisted_test_failure_remains_a_failure(self):
        status, _, _, _ = self.run_guard(report(verdict(status="failed", reason="returned False")), listed())
        self.assertEqual(1, status)

    def test_nonzero_child_status_is_never_overridden(self):
        status, _, _, _ = self.run_guard(report(verdict()), listed(), child_exit=2)
        self.assertEqual(2, status)

    def test_supported_allowlisted_test_remains_a_normal_pass(self):
        status, stdout, _, _ = self.run_guard(report(verdict(status="passed", reason="")), listed())
        self.assertEqual(0, status)
        self.assertEqual("passed", json.loads(stdout)["tests"][0]["status"])

    def test_empty_or_all_skipped_selection_is_not_green(self):
        self.assertEqual(3, self.run_guard(report())[0])
        self.assertEqual(3, self.run_guard(report(verdict(status="skipped", reason="not selected")))[0])

    def test_summary_cannot_hide_an_unsupported_verdict(self):
        value = json.loads(report(verdict()))
        value["unsupported"] = 0
        status, _, stderr, _ = self.run_guard(json.dumps(value), listed())
        self.assertEqual(1, status)
        self.assertIn("unsupported count does not match", stderr)

    def test_malformed_or_unknown_report_cannot_pass(self):
        self.assertEqual(1, self.run_guard("truncated report")[0])
        self.assertEqual(1, self.run_guard('{"version":"other", "tests":[]}')[0])

    def test_duplicate_verdict_is_refused(self):
        status, _, stderr, _ = self.run_guard(report(verdict(), verdict()), listed())
        self.assertEqual(1, status)
        self.assertIn("duplicate test", stderr)

    def test_release_force_and_cache_arguments_are_forwarded_without_environment_override(self):
        extra = ("--release", "--verify-facts", "--force", "--cache-dir", "private-cache")
        status, _, _, calls = self.run_guard(report(verdict(status="passed", reason="")), extra=extra)
        self.assertEqual(0, status)
        self.assertEqual(["pinned-selka", "test", "tests/lang", *extra, "--json"], calls[0][0])
        self.assertNotIn("env", calls[0][1])

    def test_existing_json_flag_is_not_duplicated(self):
        _, _, _, calls = self.run_guard(report(verdict(status="passed", reason="")), extra=("--json",))
        self.assertEqual(1, calls[0][0].count("--json"))

    def test_allowlist_requires_nonempty_reasons_and_exact_entries(self):
        for value in [listed(reason=""), listed(reason="  "), listed(name="m::*"), listed(suite="tests/other")]:
            with self.subTest(value=value), self.assertRaises(guard.GuardError):
                guard.allowlist_entries(value)

    def test_duplicate_entries_and_duplicate_json_keys_are_refused(self):
        value = listed(); value["tests"].append(dict(value["tests"][0]))
        with self.assertRaisesRegex(guard.GuardError, "duplicate unsupported entry"):
            guard.allowlist_entries(value)
        with self.assertRaisesRegex(guard.GuardError, "duplicate JSON key"):
            json.loads('{"version":1,"version":1,"tests":[]}', object_pairs_hook=guard.unique_object)

    def test_invalid_allowlist_fails_before_running_compiler(self):
        called = mock.Mock()
        with mock.patch.object(guard, "load_allowlist", side_effect=guard.GuardError("missing reason")), redirect_stderr(io.StringIO()):
            status = guard.main(["--compiler", "pinned", "tests/lang"], run=called)
        self.assertEqual(2, status)
        called.assert_not_called()


class StampTests(unittest.TestCase):
    """A run that writes certificates owns its directory's stamp (scripts/ownership_corpus.py)."""

    def setUp(self):
        import tempfile
        self.directory = tempfile.TemporaryDirectory()
        self.certificates = Path(self.directory.name) / "debug"
        self.identity = "a" * 64

    def tearDown(self):
        self.directory.cleanup()

    def run_wrapper(self, child_exit=0, identity=None):
        calls = []
        def compiler(command, **kwargs):
            if command[1:] == ["validate-certificates", "--identity"]:
                return subprocess.CompletedProcess(command, 0, (identity or self.identity) + "\n", "")
            calls.append(command)
            (self.certificates / "module").mkdir(parents=True, exist_ok=True)
            (self.certificates / "module" / "unit.certificate").write_text("written by " + (identity or self.identity))
            return subprocess.CompletedProcess(command, child_exit, report(verdict(status="passed", reason="")), "")
        allowlist = guard.allowlist_entries({"version": 1, "tests": []})
        with mock.patch.object(guard, "load_allowlist", return_value=allowlist), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            status = guard.main(["--compiler", "pinned-selka", "tests/ported", "--emit-certificates", str(self.certificates)], run=compiler)
        return status, calls

    def test_a_run_without_a_stamp_rebuilds_every_program_and_stamps_the_directory(self):
        self.certificates.mkdir(parents=True)
        (self.certificates / "old").mkdir()
        (self.certificates / "old" / "unit.certificate").write_text("left by something else")
        status, calls = self.run_wrapper()
        self.assertEqual(0, status)
        self.assertIn("--force", calls[0])
        self.assertFalse((self.certificates / "old").exists())
        self.assertEqual(self.identity, guard.corpus.read_stamp(self.certificates)["compiler"])

    def test_a_directory_stamped_for_this_compiler_and_these_inputs_is_kept_and_not_forced(self):
        self.run_wrapper()
        (self.certificates / "kept").mkdir()
        (self.certificates / "kept" / "unit.certificate").write_text("kept")
        status, calls = self.run_wrapper()
        self.assertEqual(0, status)
        self.assertNotIn("--force", calls[0])
        self.assertTrue((self.certificates / "kept" / "unit.certificate").exists())

    def test_another_compiler_empties_the_directory_and_forces_a_rebuild(self):
        self.run_wrapper()
        (self.certificates / "stale").mkdir()
        (self.certificates / "stale" / "unit.certificate").write_text("stale")
        status, calls = self.run_wrapper(identity="b" * 64)
        self.assertEqual(0, status)
        self.assertIn("--force", calls[0])
        self.assertFalse((self.certificates / "stale").exists())
        self.assertEqual("b" * 64, guard.corpus.read_stamp(self.certificates)["compiler"])

    def test_a_failed_run_leaves_no_stamp_so_the_next_run_rebuilds(self):
        status, _ = self.run_wrapper(child_exit=1)
        self.assertEqual(1, status)
        self.assertIsNone(guard.corpus.read_stamp(self.certificates))
        _, calls = self.run_wrapper()
        self.assertIn("--force", calls[0])

    def test_a_run_that_writes_no_certificates_touches_no_stamp(self):
        calls = []
        def compiler(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, report(verdict(status="passed", reason="")), "")
        allowlist = guard.allowlist_entries({"version": 1, "tests": []})
        with mock.patch.object(guard, "load_allowlist", return_value=allowlist), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(0, guard.main(["--compiler", "pinned-selka", "tests/ported"], run=compiler))
        self.assertEqual(1, len(calls))  # no identity query


if __name__ == "__main__":
    unittest.main()
