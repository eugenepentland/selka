#!/usr/bin/env python3
"""Unit tests for the acceptance matrix's judging logic. No builds run.

Recorded fixtures (fixtures/*.json) are real reports: `tests-*.json` from
`mylang test tests/lang/frontend_numbers.my --json` at f6971a623 (cold, warm,
and `--release --verify-facts` with MYL_CORE_LEAKCHECK=1), `last-run-warm.json`
a trimmed unchanged complete verification from the 12 October closeout tree.
Reports for features that do not exist yet (execution receipts, mismatch
counters) are derived from them in the tests and say so.

Run: python3 -B experiments/output-keyed-receipts-20261012/matrix_test.py
"""

import copy
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import matrix  # noqa: E402


def fixture(name):
    return json.loads((HERE / "fixtures" / name).read_text())


ALL_FEATURES = {name: True for name in matrix.FEATURE_NOTES}
NO_FEATURES = {name: False for name in matrix.FEATURE_NOTES}


def with_reason(report, status, reason, **top):
    """A derived report: every test given STATUS and cache REASON."""
    derived = copy.deepcopy(report)
    for test in derived["tests"]:
        test["status"] = status
        test["cache"]["reason"] = reason
        test["cache"]["action"] = "reuse" if status == "cached" else "execute"
    counts = {"passed": 0, "failed": 0, "skipped": 0, "cached": 0, "unsupported": 0}
    counts[status] = len(derived["tests"])
    derived.update(counts)
    derived.update(top)
    return derived


class Blake3Test(unittest.TestCase):
    # Official BLAKE3 vectors (input byte i is i % 251); the larger lengths were
    # cross-checked against core-unit-sum-v1 records written by the compiler.
    VECTORS = {
        0: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
        1023: "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11",
        1024: "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
        1025: "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444",
        2049: "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030",
        17411: "7181fb0b502806e4c2d4728170bb6226ff376eb993f39bff87d82bf4c82af73c",
    }

    def test_vectors(self):
        for length, digest in self.VECTORS.items():
            self.assertEqual(matrix.blake3(bytes(i % 251 for i in range(length))).hex(), digest, length)
        self.assertEqual(matrix.blake3(b"abc").hex(),
                         "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")

    def record(self, payload):
        header = matrix.BLOB_MAGIC + bytes([3]) + b"\x11" * 32 + struct.pack("<Q", len(payload)) + matrix.blake3(payload)
        return header + payload

    def test_forge_keeps_key_and_size_and_recomputes_digest(self):
        payload = bytes(range(256)) * 9
        forged = matrix.forge_blob(self.record(payload))
        self.assertEqual(len(forged), len(self.record(payload)))
        self.assertEqual(forged[:len(matrix.BLOB_MAGIC) + 41], self.record(payload)[:len(matrix.BLOB_MAGIC) + 41])
        body = forged[matrix.BLOB_HEADER:]
        self.assertNotEqual(body, payload)
        self.assertEqual(forged[len(matrix.BLOB_MAGIC) + 41:matrix.BLOB_HEADER], matrix.blake3(body))

    def test_forge_refuses_a_record_whose_digest_it_cannot_reproduce(self):
        damaged = bytearray(self.record(b"payload bytes"))
        damaged[-1] ^= 1
        with self.assertRaises(ValueError):
            matrix.forge_blob(bytes(damaged))
        with self.assertRaises(ValueError):
            matrix.forge_blob(b"not a record")


class TestReportTest(unittest.TestCase):
    def test_parse_takes_the_last_report_line(self):
        text = "build-slot: noise\n" + json.dumps(fixture("tests-cold.json")) + "\n" + json.dumps(fixture("tests-warm.json")) + "\n"
        self.assertEqual(matrix.parse_test_report(text)["cached"], 3)
        self.assertIsNone(matrix.parse_test_report("no json here\n{broken"))

    def test_summary_of_cold_and_warm(self):
        cold = matrix.summarize_tests(fixture("tests-cold.json"))
        warm = matrix.summarize_tests(fixture("tests-warm.json"))
        self.assertEqual((cold["eligible"], cold["eligible_executed"], cold["eligible_cached"]), (3, 3, 0))
        self.assertEqual((warm["eligible"], warm["eligible_executed"], warm["eligible_cached"], warm["ir_hits"]), (3, 0, 3, 3))
        self.assertEqual(warm["by_reason"], {"whole-report-hit": 3})
        self.assertFalse(matrix.summarize_tests(None)["available"])

    def test_ineligible_reasons_do_not_count_as_misses(self):
        report = with_reason(fixture("tests-cold.json"), "passed", "live-effects")
        summary = matrix.summarize_tests(report)
        self.assertEqual((summary["eligible"], summary["eligible_executed"]), (0, 0))

    def test_row1_warm_repeat_passes_and_cold_repeat_fails(self):
        warm = matrix.judge_all_hit("repeat", matrix.summarize_tests(fixture("tests-warm.json")))
        cold = matrix.judge_all_hit("repeat", matrix.summarize_tests(fixture("tests-cold.json")))
        self.assertEqual(matrix.decide(warm), matrix.PASS)
        self.assertEqual(matrix.decide(cold), matrix.FAIL)

    def test_fact_leak_repeat_is_not_judged_without_the_feature(self):
        refused = matrix.summarize_tests(fixture("tests-facts-leak-refused.json"))
        self.assertEqual(refused["by_reason"], {"verify-facts": 3})
        unready = matrix.judge_all_hit("repeat", refused, feature="fact_leak_receipts", features=NO_FEATURES)
        ready = matrix.judge_all_hit("repeat", refused, feature="fact_leak_receipts", features=ALL_FEATURES)
        self.assertEqual(matrix.decide(unready), matrix.NOT_JUDGED)
        self.assertIn("fact_leak_receipts", unready[0]["note"])
        self.assertEqual(matrix.decide(ready), matrix.FAIL)

    def test_row2_exec_tier(self):
        # Derived: a post-edit report in which every test is an execution-receipt hit.
        exec_hit = with_reason(fixture("tests-warm.json"), "cached", "exec-receipt-hit", exec_receipts={"hits": 3, "saves": 0})
        checks = matrix.judge_exec_tier("after-edit", matrix.summarize_tests(exec_hit), ALL_FEATURES)
        by_name = {c["check"].split(": ", 1)[1]: c["result"] for c in checks}
        self.assertEqual(by_name["IR keys miss"], matrix.PASS)
        self.assertEqual(by_name["100% exec-receipt-hit"], matrix.PASS)
        self.assertEqual(by_name["zero trials"], matrix.PASS)
        self.assertEqual(by_name["exec_receipts.hits equals eligible"], matrix.PASS)
        self.assertEqual(by_name["zero zig cc"], matrix.NOT_JUDGED)
        self.assertEqual(matrix.decide(checks), "partial")
        # Today's tree after a compiler edit: everything executes, exec tier absent.
        today = matrix.judge_exec_tier("after-edit", matrix.summarize_tests(fixture("tests-cold.json")), NO_FEATURES)
        today_by_name = {c["check"].split(": ", 1)[1]: c["result"] for c in today}
        self.assertEqual(today_by_name["IR keys miss"], matrix.PASS)
        self.assertEqual(today_by_name["100% exec-receipt-hit"], matrix.NOT_JUDGED)
        # An IR hit after a compiler edit would be a stale-key bug.
        stale = matrix.judge_exec_tier("after-edit", matrix.summarize_tests(fixture("tests-warm.json")), ALL_FEATURES)
        self.assertEqual(stale[0]["result"], matrix.FAIL)

    def test_verdict_map_equates_cached_and_passed(self):
        self.assertEqual(matrix.verdict_map(fixture("tests-warm.json")), matrix.verdict_map(fixture("tests-cold.json")))
        failed = with_reason(fixture("tests-cold.json"), "failed", "no-success-receipt")
        self.assertNotEqual(matrix.verdict_map(failed), matrix.verdict_map(fixture("tests-cold.json")))

    def test_none_hit_for_negative_controls(self):
        self.assertEqual(matrix.decide(matrix.judge_none_hit("x", matrix.summarize_tests(fixture("tests-cold.json")))), matrix.PASS)
        self.assertEqual(matrix.decide(matrix.judge_none_hit("x", matrix.summarize_tests(fixture("tests-warm.json")))), matrix.FAIL)


class CoordinatorTest(unittest.TestCase):
    def test_unchanged_repeat(self):
        report = fixture("last-run-warm.json")
        checks = matrix.judge_coordinator_warm("repeat", report, report)
        self.assertEqual(matrix.decide(checks), matrix.PASS)
        fresh = next(c for c in checks if "always-fresh" in c["check"])
        self.assertEqual(len(fresh["observed"]), 11)
        executed = copy.deepcopy(report)
        executed["actions"][0]["state"] = "execute"
        self.assertEqual(matrix.decide(matrix.judge_coordinator_warm("repeat", executed)), matrix.FAIL)

    def test_language_zero_is_not_judged_without_telemetry(self):
        report = fixture("last-run-warm.json")
        self.assertIsNone(matrix.language_executed(report))
        self.assertEqual(matrix.judge_language_zero("repeat", report)[0]["result"], matrix.NOT_JUDGED)
        known = copy.deepcopy(report)
        for row in known["actions"]:
            if row["id"] == "language":
                row["test_telemetry"] = [{"executed": 0}, {"executed": 0}]
        self.assertEqual(matrix.judge_language_zero("repeat", known)[0]["result"], matrix.PASS)
        for row in known["actions"]:
            if row["id"] == "language":
                row["test_telemetry"][1]["executed"] = 1790
        self.assertEqual(matrix.judge_language_zero("repeat", known)[0]["result"], matrix.FAIL)

    def test_two_worktrees(self):
        a = fixture("last-run-warm.json")
        b = copy.deepcopy(a)
        checks = matrix.judge_two_worktrees(a, b)
        by_name = {c["check"]: c["result"] for c in checks}
        self.assertEqual(by_name["all action keys identical across worktrees"], matrix.PASS)
        self.assertEqual(by_name["every action identity path-free"], matrix.NOT_JUDGED)
        b["actions"][3]["action_key"] = "0" * 64
        b["actions"][4]["state"] = "execute"
        by_name = {c["check"]: c for c in matrix.judge_two_worktrees(a, b)}
        self.assertEqual(by_name["all action keys identical across worktrees"]["result"], matrix.FAIL)
        self.assertEqual(by_name["all action keys identical across worktrees"]["observed"]["differing"], [a["actions"][3]["id"]])
        self.assertEqual(by_name["worktree B reuses every group except always-fresh"]["result"], matrix.FAIL)
        for row in b["actions"]:
            row["path_free"] = True
        self.assertEqual({c["check"]: c["result"] for c in matrix.judge_two_worktrees(a, b)}["every action identity path-free"], matrix.PASS)


class AggregationTest(unittest.TestCase):
    def test_decide(self):
        p, f, n = (matrix.check("x", 1, 1, ok) for ok in (True, False, None))
        self.assertEqual(matrix.decide([p, p]), matrix.PASS)
        self.assertEqual(matrix.decide([p, n]), "partial")
        self.assertEqual(matrix.decide([n]), matrix.NOT_JUDGED)
        self.assertEqual(matrix.decide([p, n, f]), matrix.FAIL)
        self.assertEqual(matrix.decide([]), matrix.NOT_JUDGED)

    def test_aggregate(self):
        self.assertEqual(matrix.aggregate([matrix.PASS, "skipped"]), matrix.PASS)
        self.assertEqual(matrix.aggregate([matrix.PASS, matrix.NOT_JUDGED]), "partial")
        self.assertEqual(matrix.aggregate(["error", matrix.FAIL]), "error")
        self.assertEqual(matrix.aggregate(["skipped"]), "skipped")

    def test_find_keys_and_integration_check(self):
        report = {"program": "reused", "shared": {"determinism_mismatches": 1}}
        self.assertEqual(matrix.find_keys(report, "mismatch"), [("shared.determinism_mismatches", 1)])
        with tempfile.TemporaryDirectory() as root:
            store = Path(root)
            self.assertTrue(matrix.integration_mismatch_check(store)["passes"])
            (store / "compiler-artifacts-v3").mkdir()
            (store / "compiler-artifacts-v3" / "mismatches.log").write_text("program 00ff... size 10 != 11\n")
            result = matrix.integration_mismatch_check(store)
            self.assertEqual((result["lines"], result["passes"]), (1, False))


class PlanTest(unittest.TestCase):
    def test_thirteen_rows_with_plan_text(self):
        self.assertEqual([row.number for row in matrix.ROWS], list(range(1, 14)))
        plan = (HERE.parents[1] / matrix.PLAN)
        if plan.exists():
            text = plan.read_text()
            for row in matrix.ROWS:
                self.assertIn(row.expected, text, row.id)

    def test_selection(self):
        self.assertEqual(len(matrix.select(None)), 13)
        chosen = matrix.select("1:lang-debug,8")
        self.assertEqual([(row.number, [s.name for s in subs]) for row, subs in chosen],
                         [(1, ["lang-debug"]), (8, ["memory-limit", "ld-preload", "projection"])])
        with self.assertRaises(SystemExit):
            matrix.select("14")
        with self.assertRaises(SystemExit):
            matrix.select("1:nope")

    def test_edit_anchors_resolve_on_this_tree(self):
        root = HERE.parents[1]
        for row_id, (relative, old, _new, _description) in matrix.EDITS.items():
            path = root / relative
            self.assertTrue(path.exists(), relative)
            if old is not None:
                self.assertEqual(path.read_text().count(old), 1, row_id)
        self.assertEqual((root / matrix.ROW9_HELPER).read_text().count("    items[8] = 8\n"), 1)

    def test_every_plan_builds_without_side_effects(self):
        class Args:
            tree = str(HERE.parents[1])
            work = tempfile.mkdtemp()
            evidence = tempfile.mkdtemp()
            dry_run = True
            keep_work = False
            lang_entry = None
            small_entry = "tests/lang/frontend_numbers.my"
            old_ref = "f6971a623"
            build_env = None
        ctx = matrix.Context(Args())
        for row in matrix.ROWS:
            for sub in row.subcases:
                steps = sub.plan(ctx)
                self.assertTrue(steps, (row.id, sub.name))
                names = [step.name for step in steps]
                self.assertEqual(len(names), len(set(names)), (row.id, sub.name, names))
        self.assertEqual(list(Path(Args.work).iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
