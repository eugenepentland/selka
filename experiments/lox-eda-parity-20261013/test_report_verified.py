#!/usr/bin/env python3
"""Guard the optimized report's identity and publication boundaries."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ReportValidation(unittest.TestCase):
    def run_case(self, body, reference=None, command="report"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copyfile(Path(__file__).with_name("report_verified.py"), root / "report_verified.py")
            (root / "artifact").write_text("original")
            (root / "pipeline.py").write_text(
                "from pathlib import Path\nimport hashlib\n"
                "ROOT=Path(__file__).parent\n"
                "def main():\n"
                " p=ROOT/'artifact'\n"
                " digest=hashlib.sha256(p.read_bytes()).hexdigest()\n"
                + "\n".join(" " + line for line in body.splitlines()) + "\n"
            )
            args = [sys.executable, "-B", str(root / "report_verified.py"), "--output", str(root / "output")]
            if reference is not None:
                (root / "reference.json").write_text(reference)
                args += ["--compare", str(root / "reference.json")]
            result = subprocess.run([*args, "--", command], capture_output=True, text=True)
            output = root / "output/parity-report.json"
            receipt = root / "output/validation.json"
            return result, output.exists(), json.loads(receipt.read_text()) if receipt.exists() else None

    valid = "assert_pins({str(p):digest})\nassert_pins({str(p):digest})\nsave(ROOT/'parity-report.json', {'scope':60,'cells':{str(i):{} for i in range(60)}})"

    def test_repeated_pins_and_identical_reference(self):
        reference = json.dumps({"scope": 60, "cells": {str(i): {} for i in range(60)}}, indent=2) + "\n"
        result, published, receipt = self.run_case(self.valid, reference)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(published)
        self.assertEqual(receipt["expected_identity_checks"], 2)
        self.assertEqual(receipt["distinct_hashed_artifacts"], 2)

    def test_conflicting_receipt_identity(self):
        result, published, _ = self.run_case(self.valid.replace("assert_pins({str(p):digest})\nsave", "assert_pins({str(p):'0'*64})\nsave"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inconsistent receipt identity", result.stderr)
        self.assertFalse(published)

    def test_change_during_report(self):
        result, published, _ = self.run_case(self.valid + "\np.write_text('changed')")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity changed during report", result.stderr)
        self.assertFalse(published)

    def test_wrong_initial_identity(self):
        result, published, _ = self.run_case(self.valid.replace("{str(p):digest}", "{str(p):'0'*64}"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity changed", result.stderr)
        self.assertFalse(published)

    def test_wrapper_change_during_report(self):
        result, published, _ = self.run_case(self.valid + "\n(ROOT/'report_verified.py').write_text('changed')")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Report wrapper changed", result.stderr)
        self.assertFalse(published)

    def test_incomplete_denominator(self):
        result, published, _ = self.run_case(self.valid.replace("'scope':60", "'scope':59"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(published)

    def test_different_reference(self):
        result, published, _ = self.run_case(self.valid, "{}")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reports differ", result.stderr)
        self.assertFalse(published)

    def test_no_other_pipeline_command(self):
        result, published, _ = self.run_case(self.valid, command="count")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Only report validation", result.stderr)
        self.assertFalse(published)


if __name__ == "__main__":
    unittest.main()
