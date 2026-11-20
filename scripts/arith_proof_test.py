#!/usr/bin/env python3
"""Tests for scripts/arith_proof.py: the tool lookup, the failure reading of `lake build` and the template check, with a stand-in `lake`."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import arith_proof as proof  # noqa: E402


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
        proof.lake_build("lake", lambda *a, **k: result(0, "Build completed successfully (37 jobs).\n"))

    def test_a_sorry_fails_even_though_lake_exits_zero(self):
        with self.assertRaises(proof.ProofError) as caught:
            proof.lake_build("lake", lambda *a, **k: result(0, "warning: Arith/X.lean:3:8: declaration uses `sorry`\n"))
        self.assertIn("failed", str(caught.exception))

    def test_an_error_or_a_nonzero_exit_fails(self):
        for outcome in (result(1, "", "boom"), result(0, "error: Arith/X.lean:1:1: nope\n")):
            with self.assertRaises(proof.ProofError):
                proof.lake_build("lake", lambda *a, outcome=outcome, **k: outcome)

    def test_an_axiom_violation_is_an_error_line_of_the_build(self):
        with self.assertRaises(proof.ProofError):
            proof.lake_build("lake", lambda *a, **k: result(1, "error: Arith/Check.lean:30:2: divU_correct depends on the axioms [sorryAx]\n"))


class Rendering(unittest.TestCase):
    def test_both_checks_run_and_the_cases_are_counted(self):
        calls = []

        def run(command, **kwargs):
            calls.append(command)
            return result(0)

        count = proof.check_rendering("lake", run)
        self.assertEqual([c[1:4] for c in calls], [["exe", "arith-templates", "--check"], ["exe", "arith-templates", "--md"]])
        self.assertGreaterEqual(count, 400)

    def test_a_stale_file_fails_and_says_which(self):
        def run(command, **kwargs):
            return result(1, "", "templates.txt is not what Arith.Formulas renders") if "--check" in command else result(0)

        with self.assertRaises(proof.ProofError) as caught:
            proof.check_rendering("lake", run)
        self.assertIn("not what Arith.Formulas renders", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
