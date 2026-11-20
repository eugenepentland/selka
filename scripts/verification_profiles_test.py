#!/usr/bin/env python3
"""Fail-closed coverage and scheduling tests for supported feedback profiles."""
import copy
import hashlib
import json
from pathlib import Path
import unittest

import verification_profiles as profiles


class Profiles(unittest.TestCase):
    def setUp(self):
        self.plan = {"groups": [{"id": name} for name in ("units", "language", "docs", "fmt")],
                     "configuration": {"filtered": False, "proofs": True}}
        self.rows = [{"id": group["id"], "state": "execute", "action_key": str(index) * 64,
                      "invalidation": {"changes": []}} for index, group in enumerate(self.plan["groups"])]

    def result(self, profile="complete", **kwargs):
        selected = profiles.schedule(self.plan, self.rows, profile)["selected"]
        return profiles.coverage(self.plan, self.rows, selected, profile, status=0, inputs_stable=True, **kwargs)

    def test_complete_cold_and_warm_account_for_same_current_inventory(self):
        cold = self.result()
        for row in self.rows:
            row["state"] = "reused"
        warm = self.result()
        self.assertTrue(cold["complete_verification"])
        self.assertTrue(warm["complete_verification"])
        self.assertEqual(cold["required"], warm["required"])
        self.assertEqual(4, cold["counts"]["executed"])
        self.assertEqual(4, warm["counts"]["reused"])

    def test_proofs_selects_and_certifies_exactly_what_complete_does(self):
        complete = self.result("complete")
        proofs = self.result("proofs")
        self.assertEqual(profiles.schedule(self.plan, self.rows, "complete")["selected"], profiles.schedule(self.plan, self.rows, "proofs")["selected"])
        self.assertTrue(proofs["complete_verification"])
        self.assertEqual((complete["status"], complete["counts"]), (proofs["status"], proofs["counts"]))
        self.assertEqual("proofs", proofs["profile"])

    def test_quick_cannot_issue_complete_verification_even_when_all_reused(self):
        for row in self.rows:
            row["state"] = "reused"
        report = self.result("quick")
        self.assertEqual("partial", report["status"])
        self.assertEqual([], report["outstanding"])
        self.assertFalse(report["complete_verification"])

    def test_quick_prioritizes_relevant_inexpensive_work_and_names_deferred(self):
        self.rows[1]["invalidation"]["changes"] = [{"kind": "file_content_changed", "name": "src/check.zig"}]
        self.rows[2]["invalidation"]["changes"] = [{"kind": "file_content_changed", "name": "docs/example.md"}]
        plan = profiles.schedule(self.plan, self.rows, "quick", quick_actions=1, costs={"language": 10, "docs": 1})
        report = profiles.coverage(self.plan, self.rows, plan["selected"], "quick", status=0, inputs_stable=True)
        self.assertEqual(["docs"], plan["selected"])
        self.assertEqual(["units", "language", "fmt"], report["outstanding"])
        self.assertTrue(plan["heuristic"])

    def test_broad_edit_keeps_larger_visible_pending_inventory(self):
        self.rows[0]["state"] = "reused"
        narrow = profiles.schedule(self.plan, self.rows, "quick")
        self.rows[0]["state"] = "execute"
        for row in self.rows:
            row["invalidation"]["changes"] = [{"name": "src/check.zig"}]
        broad = profiles.schedule(self.plan, self.rows, "quick")
        self.assertEqual(3, len(narrow["pending"]))
        self.assertEqual(4, len(broad["pending"]))
        self.assertEqual(4, len(broad["affected_actions"]))

    def test_edited_session_and_one_shot_use_same_receipt_decisions(self):
        self.rows[0]["state"] = "reused"
        self.rows[2]["state"] = "reused"
        session = profiles.schedule(self.plan, self.rows)
        one_shot = profiles.schedule(copy.deepcopy(self.plan), copy.deepcopy(self.rows))
        self.assertEqual(session, one_shot)
        self.assertEqual(["language", "fmt"], session["selected"])

    def test_shared_gate_failure_does_not_certify_selected_actions(self):
        report = profiles.coverage(self.plan, self.rows, ["units", "language"], status=1, inputs_stable=True)
        self.assertEqual(4, report["counts"]["outstanding"])
        self.assertEqual(0, report["counts"]["executed"])
        self.assertFalse(report["complete_verification"])

    def test_lost_input_authority_revokes_reused_coverage(self):
        for row in self.rows:
            row["state"] = "reused"
        report = profiles.coverage(self.plan, self.rows, [], status=0, inputs_stable=False)
        self.assertEqual(4, len(report["outstanding"]))
        self.assertEqual("failed", report["status"])

    def test_missing_duplicate_unknown_and_corrupt_decisions_are_rejected(self):
        for rows in (self.rows[:-1], self.rows + self.rows[:1], [self.rows[0]] * 4):
            with self.assertRaises(ValueError):
                profiles.schedule(self.plan, rows)
        self.rows[0]["action_key"] = "corrupt"
        with self.assertRaises(ValueError):
            self.result()

    def test_filtered_inventory_never_completes_gate(self):
        self.plan["configuration"]["filtered"] = True
        self.assertFalse(self.result()["complete_verification"])

    def test_a_build_without_the_proofs_flag_never_completes_the_gate(self):
        # -Dproofs off makes the four Lean proof actions print "skipped" and exit 0: a green run that proved nothing about them.
        for configuration in ({"filtered": False, "proofs": False}, {"filtered": False}):
            for profile in ("complete", "proofs"):
                self.plan["configuration"] = configuration
                report = self.result(profile)
                self.assertFalse(report["complete_verification"])
                self.assertFalse(report["proofs_enabled"])
                self.assertEqual("partial", report["status"])
        self.plan["configuration"] = {"filtered": False, "proofs": True}
        self.assertTrue(self.result()["complete_verification"])

    def test_skipped_or_explicit_failed_work_cannot_complete_a_successful_command(self):
        self.rows[0].update(state="skipped")
        self.rows[1].update(success=False)
        report = profiles.coverage(self.plan, self.rows, [row["id"] for row in self.rows], status=0, inputs_stable=True)
        self.assertEqual(["units", "language"], report["outstanding"])
        self.assertFalse(report["complete_verification"])

    def test_exported_C0_inventory_is_used_without_a_parallel_test_list(self):
        fixture = Path(__file__).resolve().parents[1] / "test/fixtures/verification-profiles/C0-inventory.json"
        raw = fixture.read_bytes()
        self.assertEqual("a0fe8ff69c900552da9bf6b8ba662c9478915044e6d7c5f68a7d7cc7664b185c", hashlib.sha256(raw).hexdigest())
        self.plan = json.loads(raw)
        self.rows = [{"id": group["id"], "state": "fresh", "action_key": hashlib.sha256(group["id"].encode()).hexdigest()}
                     for group in self.plan["groups"]]
        self.assertEqual(43, self.result()["counts"]["executed"])
        self.assertEqual(["juice", "juice-runtime"], self.result()["qualification_owed"])
        self.assertEqual(40, self.result("quick")["counts"]["outstanding"])

    def test_preparation_and_qualification_are_reported_without_gate_admission(self):
        names = ["input-discovery", "environment-discovery", "component-preparation", "juice", "juice-runtime"]
        self.plan["groups"] = [{"id": name} for name in names]
        self.rows = [{"id": name, "state": "owed" if name.startswith("juice") else "prepared", "action_key": "a" * 64}
                     for name in names]
        schedule = profiles.schedule(self.plan, self.rows)
        report = self.result()
        self.assertEqual([], schedule["selected"])
        self.assertEqual([], report["outstanding"])
        self.assertEqual(3, report["counts"]["prepared"])
        self.assertEqual(0, report["counts"]["executed"])
        self.assertEqual(["juice", "juice-runtime"], report["qualification_owed"])
        self.assertTrue(report["complete_verification"])
        self.assertFalse(report["complete_qualification"])

    def test_unrelated_group_cannot_claim_preparation_or_qualification(self):
        self.rows[0]["state"] = "prepared"
        with self.assertRaises(ValueError):
            self.result()
        self.rows[0]["state"] = "owed"
        with self.assertRaises(ValueError):
            self.result()

    def test_long_requires_gate_and_qualified_additional_work(self):
        required = ["fuzz", "wall-clock"]
        partial = self.result("long-qualification", qualification_required=required)
        with self.assertRaisesRegex(ValueError, "serialized qualification"):
            self.result("long-qualification", qualification_required=required,
                        qualification_results=[{"id": name, "complete": True, "success": True, "qualified": True}
                                               for name in required])
        self.assertTrue(partial["complete_verification"])
        self.assertFalse(partial["complete_qualification"])
        self.assertEqual(required, partial["qualification_outstanding"])
        self.assertFalse(self.result("long-qualification")["complete_qualification"])

    def test_insufficient_qualification_and_invalid_costs_are_rejected(self):
        with self.assertRaises(ValueError):
            self.result("long-qualification", qualification_required=["wall-clock"],
                        qualification_results=[{"id": "wall-clock", "complete": True, "success": True, "qualified": False}])
        for costs in ({"units": float("nan")}, {"units": -1}, {"unknown": 1}):
            with self.assertRaises(ValueError):
                profiles.schedule(self.plan, self.rows, costs=costs)


if __name__ == "__main__":
    unittest.main()
