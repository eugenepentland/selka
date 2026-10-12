#!/usr/bin/env python3
"""Authentication, bounded coverage and supported counter-parser adversarial cases."""
from contextlib import ExitStack
import json
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import verification_profiles as profiles
import verification_qualification as q
from verification_snapshot import Snapshot


def scaling():
    return ("".join(f"duplicate header index: {size} functions, work={size * 3}, one distant pair, deterministic; two-run elapsed=1.000s\n"
                    for size in (128, 512, 1024)) +
            "".join(f"duplicate banded distance: {size} repeated statements, work={size * 3}, literal drift retained\n"
                    for size in (50, 100, 200))).encode()


class Qualification(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tool/lib").mkdir(parents=True)
        self.zig = self.root / "tool/zig"
        self.zig.write_text("#!/bin/sh\nexit 0\n")
        self.zig.chmod(0o755)
        self.input = self.root / "source"
        self.input.write_text("original")
        self.context = {"inventory": "a" * 64, "producer": "b" * 64}
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.snapshot = self.stack.enter_context(Snapshot(self.root, ["source"]))
        self.stack.enter_context(patch.object(q, "INPUTS", []))
        self.stack.enter_context(patch.object(q.verification, "normalized_environment", return_value={"PATH": "/usr/bin:/bin"}))
        self.stack.enter_context(patch.object(q, "_admitted", side_effect=self.admitted))
        self.calls = []

    def admitted(self, run, root, env, argv, directory, deadline):
        self.calls.append(argv)
        directory.mkdir()
        (directory / "stdout.log").write_bytes(scaling())
        run._observed_files[directory / "stdout.log"] = hashlib.sha256(scaling()).hexdigest()
        (directory / "stderr.log").write_bytes(b"")
        return scaling(), b""

    def execute(self, **kwargs):
        return self.stack.enter_context(q.qualify(self.root, self.root / "cache", self.zig, self.zig,
            self.context, [self.snapshot], targets=["scaling"], **kwargs))

    def test_actual_handle_authenticates_exact_context_and_declared_inventory(self):
        run = self.execute()
        self.assertEqual({"scaling"}, q.qualified_names(run, self.context, q.OBLIGATIONS))
        self.assertEqual(1, len(self.calls))
        self.assertEqual(6, run.rows[1]["observed"]["cases_completed"])
        with self.assertRaises(ValueError):
            q.qualified_names(run, {"producer": "changed"}, q.OBLIGATIONS)
        with self.assertRaises(ValueError):
            q.qualified_names(run, self.context, ["scaling"])

    def test_serialized_success_booleans_cannot_supply_authority(self):
        run = self.execute()
        for row in run.rows:
            row.update(complete=True, success=True, qualified=True)
        self.assertEqual({"scaling"}, q.qualified_names(run, self.context, q.OBLIGATIONS))
        with self.assertRaises(ValueError):
            q.qualified_names(run.report(), self.context, q.OBLIGATIONS)

    def test_evidence_mutation_and_closed_handle_reject_stale_success(self):
        run = self.execute()
        (run.area / "scaling/stdout.log").write_bytes(scaling() + b"corrupt")
        with self.assertRaises(ValueError):
            q.qualified_names(run, self.context, q.OBLIGATIONS)
        run.__exit__()
        with self.assertRaises(ValueError):
            q.qualified_names(run, self.context, q.OBLIGATIONS)

    def test_output_changed_after_parse_before_guard_cannot_authorize(self):
        original = q.QualificationRun._freeze
        def changed(run, directory):
            (directory / "stdout.log").write_bytes(scaling() + b"edited")
            return original(run, directory)
        with patch.object(q.QualificationRun, "_freeze", changed):
            run = self.execute()
        self.assertEqual(set(), q.qualified_names(run, self.context, q.OBLIGATIONS))
        self.assertIn("between parsing", run.rows[1]["reason"])

    def test_source_aba_revokes_authority(self):
        run = self.execute()
        self.input.write_text("changed")
        self.input.write_text("original")
        with self.assertRaises(ValueError):
            q.qualified_names(run, self.context, q.OBLIGATIONS)

    def test_full_gate_remains_required_despite_authenticated_scaling(self):
        run = self.execute()
        plan = {"groups": [{"id": "gate"}], "configuration": {"filtered": False}}
        rows = [{"id": "gate", "state": "execute", "action_key": "a" * 64}]
        failed = profiles.coverage(plan, rows, ["gate"], "long-qualification", status=1, inputs_stable=True,
            qualification_required=q.OBLIGATIONS, qualification_run=run, qualification_context=self.context)
        passed = profiles.coverage(plan, rows, ["gate"], "long-qualification", status=0, inputs_stable=True,
            qualification_required=q.OBLIGATIONS, qualification_run=run, qualification_context=self.context)
        self.assertFalse(failed["complete_verification"])
        self.assertTrue(passed["complete_verification"])
        self.assertFalse(passed["complete_qualification"])
        self.assertNotIn("scaling", passed["qualification_outstanding"])

    def test_partial_execution_cannot_authorize_and_unsupported_work_is_named(self):
        with patch.object(q, "_admitted", side_effect=ValueError("timeout")):
            run = self.execute()
        self.assertEqual(set(), q.qualified_names(run, self.context, q.OBLIGATIONS))
        self.assertIn("timeout", run.rows[1]["reason"])
        self.assertIn("wall-clock-performance", run.report()["outstanding"])
        self.assertIn("bootstrap", run.report()["outstanding"])

    def test_arbitrary_commands_and_invalid_limits_are_rejected_before_execution(self):
        for targets, maximum, timeout, steps in ((["shell command"], 1, 3, 1), (["fuzz"] * 2, 1, 3, 1),
                                                (["fuzz"], 0, 3, 1), (["fuzz"], 1, float("nan"), 1), (["fuzz"], 1, None, 1)):
            with self.assertRaises(ValueError):
                q.validate_options(targets, maximum, timeout, steps)
        self.assertEqual([], self.calls)

    def test_work_cap_does_not_hide_required_obligations(self):
        with patch.object(q, "_fuzz", return_value={"counts": {}}):
            run = self.stack.enter_context(q.qualify(self.root, self.root / "cap-cache", self.zig, self.zig,
                self.context, [self.snapshot], targets=["fuzz", "scaling"], max_actions=1))
        # The mocked first adapter provides no directory to freeze, so cannot
        # authorize success; it still consumes its attempted work allowance.
        self.assertEqual("partial", run.rows[1]["state"])
        self.assertIn("scaling", run.report()["outstanding"])
        self.assertEqual([], self.calls)

    def test_scaling_missing_wrong_or_zero_work_is_rejected(self):
        self.assertEqual(9, q.scaling_work(scaling())["compiler_invocations"])
        for bad in (scaling().splitlines()[0], scaling().replace(b"128 functions", b"127 functions"),
                    scaling().replace(b"work=384", b"work=0")):
            with self.assertRaises(ValueError):
                q.scaling_work(bad)

    def test_compiler_work_checks_actual_counts_not_equal_fingerprints(self):
        value = {"version": "work-report-v1", "command": "check", "fingerprint_unchanged": True,
                 "parsed_modules": {"performed": 1, "reused": 0}, "checked_bodies": {"performed": 2, "reused": 0}}
        self.assertEqual({"parsed_modules": 1, "checked_bodies": 2}, q.compiler_work(json.dumps(value).encode()))
        value["checked_bodies"]["performed"] = 0
        with self.assertRaises(ValueError):
            q.compiler_work(json.dumps(value).encode())


if __name__ == "__main__":
    unittest.main()
