#!/usr/bin/env python3
"""Tests for scripts/cache_proof.py: the tool lookup, the failure reading of `lake build`, the fixture check and the sample, with a stand-in `lake`."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import cache_proof as proof  # noqa: E402


def result(code=0, out="", err=""):
    return subprocess.CompletedProcess([], code, out, err)


class Lake(unittest.TestCase):
    def test_a_missing_lake_fails_with_the_path_it_looked_at(self):
        with self.assertRaises(proof.ProofError) as caught:
            proof.find_lake({"HOME": "/nonexistent-home", "SELKA_LAKE": ""})
        self.assertIn("/nonexistent-home/.elan/bin/lake", str(caught.exception))
        self.assertIn("never skips", str(caught.exception))

    def test_selka_lake_wins_over_home(self):
        with tempfile.TemporaryDirectory() as directory:
            lake = Path(directory) / "lake"
            lake.write_text("#!/bin/sh\n")
            lake.chmod(0o755)
            self.assertEqual(proof.find_lake({"HOME": "/nonexistent-home", "SELKA_LAKE": str(lake)}), str(lake))

    def test_the_tool_directory_comes_first_on_path(self):
        self.assertTrue(proof.tool_env("/opt/elan/bin/lake")["PATH"].startswith("/opt/elan/bin" + os.pathsep))


class Build(unittest.TestCase):
    def test_a_clean_build_passes(self):
        proof.lake_build("lake", lambda *a, **k: result(0, "Build completed successfully (31 jobs).\n"))

    def test_a_sorry_fails_even_though_lake_exits_zero(self):
        with self.assertRaises(proof.ProofError):
            proof.lake_build("lake", lambda *a, **k: result(0, "warning: Cache/X.lean:3:8: declaration uses `sorry`\n"))

    def test_an_error_or_a_nonzero_exit_fails(self):
        for outcome in (result(1, "", "boom"), result(0, "error: Cache/X.lean:1:1: nope\n")):
            with self.assertRaises(proof.ProofError):
                proof.lake_build("lake", lambda *a, outcome=outcome, **k: outcome)

    def test_an_axiom_violation_is_an_error_line_of_the_build(self):
        with self.assertRaises(proof.ProofError):
            proof.lake_build("lake", lambda *a, **k: result(1, "error: Cache/Check.lean:30:2: warm_eq_clean depends on the axioms [sorryAx]\n"))


class Fixtures(unittest.TestCase):
    def test_the_script_must_say_fixtures_ok(self):
        proof.run_fixtures(lambda *a, **k: result(0, "ok   something\nfixtures ok\n"))
        for outcome in (result(1, "FAIL stale\n"), result(0, "ok   something\n")):
            with self.assertRaises(proof.ProofError):
                proof.run_fixtures(lambda *a, outcome=outcome, **k: outcome)


class Sample(unittest.TestCase):
    def test_every_nth_entry_starting_with_the_first_and_the_same_every_time(self):
        entries = [Path(f"e{i:02d}.selka") for i in range(30)]
        picked = proof.sample(list(reversed(entries)), 12)
        self.assertEqual([p.name for p in picked], ["e00.selka", "e12.selka", "e24.selka"])
        self.assertEqual(picked, proof.sample(entries, 12))

    def test_an_interval_below_one_takes_everything(self):
        entries = [Path(f"e{i}.selka") for i in range(5)]
        self.assertEqual(len(proof.sample(entries, 0)), 5)


class CaseEnvironment(unittest.TestCase):
    """F36: the captured runs of one entry must not read the test tier that other runs of the same entry write."""

    def environment(self, base, case, shared=None):
        import cache_plan_diff as diff
        saved = dict(os.environ)
        try:
            os.environ.pop("SELKA_TEST_SHARED_CACHE", None)
            if shared is not None:
                os.environ["SELKA_TEST_SHARED_CACHE"] = shared
            return diff.case_environment(Path(base) / "cases" / case / "capture", Path(base) / "components")
        finally:
            os.environ.clear()
            os.environ.update(saved)

    def test_each_case_gets_a_test_tier_of_its_own_whatever_the_caller_set(self):
        with tempfile.TemporaryDirectory() as base:
            first = self.environment(base, "a.selka", shared="/home/user/.cache/selka/native-tests")
            second = self.environment(base, "b.selka")
            self.assertEqual(first["SELKA_TEST_SHARED_CACHE"], str(Path(base) / "cases" / "a.selka" / "shared-tests"))
            self.assertEqual(second["SELKA_TEST_SHARED_CACHE"], str(Path(base) / "cases" / "b.selka" / "shared-tests"))
            self.assertNotEqual(first["SELKA_TEST_SHARED_CACHE"], second["SELKA_TEST_SHARED_CACHE"])
            self.assertFalse(Path(first["SELKA_TEST_SHARED_CACHE"]).exists())

    def test_the_recording_planner_is_still_named_and_the_mode_override_is_dropped(self):
        with tempfile.TemporaryDirectory() as base:
            os.environ["SELKA_CACHE_PLAN_MODE"] = "shadow"
            try:
                env = self.environment(base, "a.selka")
            finally:
                os.environ.pop("SELKA_CACHE_PLAN_MODE", None)
            self.assertEqual(env["CACHE_PLAN_CAPTURE"], str(Path(base) / "cases" / "a.selka" / "capture"))
            self.assertEqual(env["SELKA_COMPONENT_DIR"], str(Path(base) / "components"))
            self.assertNotIn("SELKA_CACHE_PLAN_MODE", env)


if __name__ == "__main__":
    unittest.main()
