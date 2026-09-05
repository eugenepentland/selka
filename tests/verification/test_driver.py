import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

DRIVER = Path(__file__).resolve().parents[2] / "scripts" / "verify.py"
spec = importlib.util.spec_from_file_location("verify", DRIVER)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def step(name, code="print(7)", **fields):
    return {"id": name, "kind": "test", "commands": [[sys.executable, "-c", code]], **fields}


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = self.root / "verify.json"

    def run_steps(self, steps, only=()):
        self.manifest.write_text(json.dumps({"version": 1, "steps": steps}))
        with contextlib.redirect_stderr(io.StringIO()):
            return verify.run(self.manifest, only)

    def test_selection_reports_dependencies_and_never_claims_full_suite(self):
        report = self.run_steps([step("build"), step("first", depends_on=["build"]), step("unchecked", "raise Exception()")], ["first"])
        self.assertEqual(report["requested"], ["first"])
        self.assertEqual(report["selected"], ["build", "first"])
        self.assertTrue(report["selected_passed"])
        self.assertFalse(report["full_manifest_passed"])
        self.assertEqual(report["steps"][2]["status"], "unselected")
        self.assertFalse(report["steps"][2]["executed"])

    def test_failure_blocks_dependents_but_runs_independent_steps(self):
        report = self.run_steps([step("bad", "raise SystemExit(3)"), step("blocked", depends_on=["bad"]), step("independent")])
        self.assertEqual([s["status"] for s in report["steps"]], ["failed", "blocked", "passed"])
        self.assertFalse(report["full_manifest_passed"])
        self.assertFalse(report["steps"][1]["executed"])

    def test_parity_uses_executed_byte_outputs_and_expected_result(self):
        parity = step("parity", kind="parity", expect_stdout="7\n")
        parity["commands"].append([sys.executable, "-c", "print(7)"])
        self.assertTrue(self.run_steps([parity])["full_manifest_passed"])
        parity["commands"][1][-1] = "print(8)"
        self.assertFalse(self.run_steps([parity])["selected_passed"])
        del parity["expect_stdout"]
        parity["commands"] = [[sys.executable, "-c", f"import sys; sys.stdout.buffer.write(bytes([{byte}]))"] for byte in (254, 255)]
        self.assertFalse(self.run_steps([parity])["selected_passed"])

    def test_mutation_requires_expected_diagnostic_not_any_failure(self):
        mutation = step("mutation", "import sys; print('E_TYPE', file=sys.stderr); sys.exit(1)", kind="mutation", expect_exit=1, expect_stderr_contains="E_TYPE")
        self.assertTrue(self.run_steps([mutation])["selected_passed"])
        mutation["expect_stderr_contains"] = "E_IMMUTABLE"
        self.assertFalse(self.run_steps([mutation])["selected_passed"])

    def test_timeout_output_limit_and_launch_failure_are_reported(self):
        report = self.run_steps([step("timeout", "import time; time.sleep(10)", timeout=0.05), step("output", "print('x'*1000)", max_output_bytes=10), {"id": "missing", "kind": "test", "commands": [[str(self.root / "absent")]]}])
        self.assertTrue(report["steps"][0]["commands"][0]["timed_out"])
        self.assertTrue(report["steps"][1]["commands"][0]["output_truncated"])
        self.assertFalse(report["steps"][2]["executed"])
        self.assertFalse(report["selected_passed"])

    def test_spec_markers_and_benchmarks_are_separate_evidence(self):
        (self.root / "spec.md").write_text("# Contract\nexpected behavior")
        rows = [{"id": "spec", "kind": "spec", "path": "spec.md", "contains": "# Contract"}, step("samples", kind="benchmark", repeats=3)]
        report = self.run_steps(rows)
        self.assertTrue(report["full_manifest_passed"])
        self.assertEqual(len(report["steps"][1]["commands"]), 3)
        self.assertIn("no elapsed-time pass/fail", report["steps"][1]["timing_policy"])
        self.assertEqual(report["runtime_coverage"], "not measured")
        rows[0]["contains"] = "missing"
        self.assertFalse(self.run_steps(rows)["selected_passed"])

    def test_manifest_validation_and_unmatched_filters_precede_execution(self):
        invalid = [step("bad", timeout=float('nan')), step("bad", timeout=True), step("bad", expect_exit=True), step("bad", commands="echo 7"), step("bad", depends_on=["future"]), step("bad", kind="mutation"), step("bad", kind="parity"), step("bad", unknown=True)]
        for row in invalid:
            with self.subTest(row=row), self.assertRaises(ValueError):
                verify.validate({"version": 1, "steps": [row]})
        with self.assertRaises(ValueError):
            self.run_steps([step("actual")], ["absent"])
        with self.assertRaises(ValueError):
            self.run_steps([step("same"), step("same")])
        self.manifest.write_text('{"version": 1, "version": 1, "steps": []}')
        with self.assertRaises(ValueError):
            verify.run(self.manifest)

    def test_cli_reports_filtered_success_failure_and_usage_distinctly(self):
        self.run_steps([step("good", expect_stdout="7\n"), step("bad", "raise SystemExit(1)")], ["good"])
        report = self.root / "report.json"
        result = subprocess.run([sys.executable, str(DRIVER), str(self.manifest), "--only", "good", "--report", str(report)], capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(json.loads(report.read_text())["full_manifest_passed"])
        failed = subprocess.run([sys.executable, str(DRIVER), str(self.manifest)], capture_output=True)
        self.assertEqual(failed.returncode, 1)
        invalid = subprocess.run([sys.executable, str(DRIVER), str(self.manifest), "--only", "absent"], capture_output=True)
        self.assertEqual(invalid.returncode, 2)


if __name__ == "__main__":
    unittest.main()
