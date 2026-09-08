#!/usr/bin/env python3
"""Actual compiler, immutable execution, stale evidence and requirement history."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import trace as intent_trace
from intent import model
from intent.report import snapshot, attach, query

COMPILER = None
EXAMPLE = Path(__file__).resolve().parents[1] / "examples/intent"


class IntentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "project"
        shutil.copytree(EXAMPLE, self.root)
        self.entry = self.root / "main.my"
        self.cache = self.base / "cache"
        manifest = model.read(self.root / "verify.json")
        manifest["steps"][0]["commands"][0][0] = str(COMPILER)
        self.write("verify.json", manifest)

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def report(self, evidence=None, previous=None):
        report, _ = snapshot(COMPILER, self.entry, "intent.json", "verify.json", previous)
        return attach(report, evidence)

    def verify(self):
        return intent_trace.verify(COMPILER, self.entry, "intent.json", "verify.json", self.cache)

    def test_declared_links_and_transitive_impact_are_not_proofs(self):
        report = self.report()
        self.assertEqual(report["diagnostics"], [])
        self.assertEqual(report["requirements"][0]["evidence"], "declared")
        self.assertFalse(report["requirements"][0]["formally_proven"])
        self.assertFalse(report["acceptance_authenticated"])
        impacted = query(report, symbol="main::configured_limit")
        self.assertEqual(set(impacted["records"]), {"LIMIT-001", "DEC-LIMIT"})
        self.assertTrue(impacted["partial"])
        with self.assertRaisesRegex(ValueError, "complete previous"):
            self.report(previous=impacted)

    def test_real_execution_cache_and_source_change_invalidate_evidence(self):
        first = self.verify()
        self.assertTrue(first["receipt"]["verification"]["full_manifest_passed"])
        self.assertEqual(self.report(first)["requirements"][0]["evidence"], "linked-tests-passed")
        self.assertEqual(self.verify()["receipt"]["verification"]["steps"][0]["status"], "cached")
        self.entry.write_text(self.entry.read_text().replace("return 7", "return 8"))
        self.assertEqual(self.report(first)["requirements"][0]["evidence"], "stale")
        failed = self.verify()
        self.assertFalse(failed["receipt"]["verification"]["full_manifest_passed"])
        self.assertEqual(self.report(failed)["requirements"][0]["evidence"], "failed")

    def test_revision_changes_and_retirement_preserve_history(self):
        old = self.report()
        data = model.read(self.root / "intent.json")
        data["requirements"][0]["statement"] += " Updated interpretation."
        self.write("intent.json", data)
        with self.assertRaisesRegex(ValueError, "higher revision"):
            self.report(previous=old)
        data["requirements"][0]["revision"] += 1
        self.write("intent.json", data)
        self.assertEqual(self.report(previous=old)["changes"], [{"id":"LIMIT-001","change":"revised"}])
        data["requirements"] = []
        data["decisions"] = []
        self.write("intent.json", data)
        with self.assertRaisesRegex(ValueError, "retired"):
            self.report(previous=old)

    def test_broken_symbols_tests_and_source_snapshots_are_diagnostics(self):
        data = model.read(self.root / "intent.json")
        data["requirements"][0]["implements"] = ["main::missing"]
        data["requirements"][0]["tests"] = ["missing"]
        self.write("intent.json", data)
        codes = {d["code"] for d in self.report()["diagnostics"]}
        self.assertEqual(codes, {"I_UNKNOWN_SYMBOL", "I_UNKNOWN_TEST"})
        with self.assertRaisesRegex(ValueError, "diagnostics"):
            self.verify()
        (self.root / "request.md").write_text("Changed request")
        with self.assertRaisesRegex(ValueError, "snapshot hash"):
            self.report()

    def test_intent_edit_stales_results_without_running_code_and_corruption_rejects(self):
        evidence = self.verify()
        data = model.read(self.root / "intent.json")
        data["requirements"][0]["rationale"] += " More context."
        data["requirements"][0]["revision"] += 1
        self.write("intent.json", data)
        self.assertEqual(self.report(evidence)["requirements"][0]["evidence"], "stale")
        evidence["receipt"]["basis_sha256"] = "forged"
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.report(evidence)

    def test_unbuilt_proposals_remain_visible_but_accepted_gaps_block_verification(self):
        data = model.read(self.root / "intent.json")
        data["requirements"][0]["implements"] = []
        data["requirements"][0]["tests"] = []
        self.write("intent.json", data)
        self.assertEqual({d["severity"] for d in self.report()["diagnostics"]}, {"warning"})
        self.assertTrue(self.verify()["receipt"]["verification"]["full_manifest_passed"])
        data["requirements"][0]["status"] = "accepted"
        self.write("intent.json", data)
        with self.assertRaisesRegex(ValueError, "diagnostics"):
            self.verify()

    def test_changed_acceptance_test_invalidates_passing_evidence(self):
        first = self.verify()
        data = model.read(self.root / "verify.json")
        data["steps"][0]["expect_stdout"] = "8\n"
        self.write("verify.json", data)
        self.assertEqual(self.report(first)["requirements"][0]["evidence"], "stale")

    def test_untracked_jobs_are_labelled_as_observations(self):
        data = model.read(self.root / "verify.json")
        data["steps"][0]["complete"] = False
        self.write("verify.json", data)
        report = self.report(self.verify())
        self.assertEqual(report["requirements"][0]["evidence"], "observed-pass-untracked-inputs")

    def test_existing_scheduler_executes_intent_jobs_and_malformed_receipts_reject(self):
        from verification.scheduler import Scheduler
        from verification.core import digest
        scheduler = Scheduler(self.base / "queue.db")
        result = intent_trace.verify(COMPILER, self.entry, "intent.json", "verify.json",
                                     self.cache, executor=scheduler.execute)
        self.assertEqual(self.report(result)["requirements"][0]["evidence"], "linked-tests-passed")
        bad = {"version": "intent-evidence-v1", "verification": []}
        with self.assertRaisesRegex(ValueError, "verification report"):
            self.report({"receipt": bad, "sha256": digest(bad)})

    def test_duplicate_keys_and_external_paths_reject(self):
        (self.root / "intent.json").write_text('{"version":1,"version":2}')
        with self.assertRaisesRegex(ValueError, "duplicate JSON"):
            self.report()
        with self.assertRaisesRegex(ValueError, "inside"):
            model.local(self.root, "../outside")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    args = parser.parse_args()
    COMPILER = args.compiler.resolve()
    unittest.main(argv=[sys.argv[0]])
