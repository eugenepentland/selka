#!/usr/bin/env python3
"""Installed native Juice parity and lifecycle checks; no PMU or Valgrind required."""
from __future__ import annotations
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_juice import sample_record, MANIFEST
import test_juice as reference
from juice_tool.report import compare_records

COMPILER = Path(sys.argv.pop(1)).resolve()

class NativeJuice(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="juice-native-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value))
        return path

    def command(self, *args, code=0, env=None, compiler=COMPILER):
        result = subprocess.run([str(compiler), "juice", *map(str, args)], text=True,
                                capture_output=True, timeout=60, env=env, cwd=self.root)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def records(self, a=None, b=None):
        a = a or sample_record(1000)
        b = b or sample_record(800)
        for row, name in ((a, "base"), (b, "candidate")):
            row.update(version="juice-v1", status="complete", name=name)
        return a, b, self.write("base.json", a), self.write("candidate.json", b)

    def compare(self, a=None, b=None, **kwargs):
        a, b, first, second = self.records(a, b)
        output = self.root / "comparison.json"
        self.command("compare", first, second, "--output", output, **kwargs)
        return json.loads(output.read_text()), compare_records(a, b)

    def test_installed_binary_works_without_checkout_or_python(self):
        moved = self.root / "selka"
        shutil.copy2(COMPILER, moved)
        environment = dict(os.environ, PATH="")
        self.command("--help", env=environment, compiler=moved)
        _, _, a, b = self.records()
        output = self.root / "report.json"
        self.command("compare", a, b, "--output", output, env=environment, compiler=moved)
        self.assertEqual(json.loads(output.read_text())["suite_juice"], 80)
        self.assertIn("not proportionally less time", output.with_suffix(".md").read_text())

    def test_native_report_matches_reference_for_instructions_and_risks(self):
        a, b = sample_record(1000), sample_record(700)
        b["build"]["code"]["functions"]["work"] = {"bytes": 25, "atomic_sites": 1}
        native, reference = self.compare(a, b)
        for key in ("juice", "instruction_ratio", "ratio_envelope", "direction", "assessment", "repeatable"):
            self.assertEqual(native["workloads"]["w"][key], reference["workloads"]["w"][key])
        self.assertEqual(native["workloads"]["w"]["assessment"], "mixed")

    def test_incompatible_inputs_modes_and_outputs_fail(self):
        a, b, first, second = self.records()
        output = self.root / "report.json"
        b["contract"]["input"] = "changed"
        self.write("candidate.json", b)
        self.command("compare", first, second, "--output", output, code=2)
        b["contract"] = a["contract"]
        b["sources"] = {"main": "changed"}
        self.write("candidate.json", b)
        self.command("compare", first, second, "--mode", "backend", "--output", output, code=2)
        b["workloads"]["w"]["correctness"] = {"stdout": "wrong"}
        self.write("candidate.json", b)
        self.command("compare", first, second, "--output", output, code=2)
        self.assertFalse(output.exists())

    def test_malformed_records_never_crash_or_pass(self):
        _, _, a, b = self.records()
        for corrupt in ({}, [], {"version": "juice-v1", "status": "incomplete"}):
            self.write("candidate.json", corrupt)
            self.command("compare", a, b, "--output", self.root / "bad.json", code=2)
        self.command("compare", a, a, "--output", a, code=2)
        self.command("compare", a, a, "--output", self.root / "bad.json", "--max-spread", "nan", code=2)

    def test_quick_and_larger_validation_uses_same_change(self):
        a, b, first, second = self.records()
        quick = self.root / "quick.json"
        self.command("compare", first, second, "--output", quick)
        a["workloads"]["w"]["tier"] = b["workloads"]["w"]["tier"] = "validation"
        self.write("base.json", a)
        self.write("candidate.json", b)
        large = self.root / "large.json"
        self.command("compare", first, second, "--output", large)
        result = self.root / "validation.json"
        self.command("validate", quick, large, "--output", result)
        self.assertTrue(json.loads(result.read_text())["passed"])
        bad = json.loads(large.read_text())
        bad["change_id"] = "different"
        self.write("large.json", bad)
        self.command("validate", quick, large, "--output", result, code=2)

    def test_native_calibration_matches_reference_evidence(self):
        fixture = reference.Calibration("test_validated_model_and_out_of_domain_abstention")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        dataset = fixture.dataset()
        output = self.root / "model.json"
        self.command("calibrate", dataset, "--output", output)
        model = json.loads(output.read_text())
        self.assertAlmostEqual(model["exponent"], 0.8)
        points = json.loads(dataset.read_text())
        points["points"][-1]["split"] = "train"
        dataset.write_text(json.dumps(points))
        self.command("calibrate", dataset, "--output", output, code=2)

    def project(self):
        if not shutil.which("cc"):
            self.skipTest("C compiler unavailable")
        (self.root / "program.c").write_text('#include <stdio.h>\nint main(void){puts("ok");return 0;}\n')
        (self.root / "data.txt").write_text("fixed input\n")
        manifest = self.root / "juice.toml"
        manifest.write_text(MANIFEST)
        perf = self.root / "fixture-perf"
        perf.write_text('''#!/bin/sh
if [ "$1" = --version ]; then printf 'Juice test collector 1\n'; exit 0; fi
while [ "$#" -gt 0 ]; do
 case "$1" in
  -o) output=$2; shift 2;;
  -e) event=$2; shift 2;;
  --) shift; break;;
  *) shift;;
 esac
done
printf '1000;;%s;1;100.00\n' "$event" > "$output"
"$@"
''')
        perf.chmod(0o755)
        return manifest, perf

    def capture(self, manifest, perf, name, code=0):
        self.command("record", manifest, "--name", name, "--repeats", 2,
                     "--perf", perf, "--cache-dir", self.root / "cache", code=code)
        return self.root / "cache/test-project/records" / name / "record.json"

    def test_capture_build_cache_immutability_and_evidence_integrity(self):
        manifest, perf = self.project()
        first = self.capture(manifest, perf, "first")
        second = self.capture(manifest, perf, "second")
        a, b = json.loads(first.read_text()), json.loads(second.read_text())
        self.assertFalse(a["build"]["cached"])
        self.assertTrue(b["build"]["cached"])
        self.assertEqual(a["status"], "complete")
        self.assertEqual(a["sources"]["program.c"], hashlib.sha256((self.root / "program.c").read_bytes()).hexdigest())
        for name, digest in a["evidence"].items():
            self.assertEqual(digest, hashlib.sha256((first.parent / name).read_bytes()).hexdigest())
        output = self.root / "same.json"
        self.command("compare", first, second, "--output", output)
        self.assertEqual(json.loads(output.read_text())["suite_juice"], 100)
        self.capture(manifest, perf, "second", code=2)
        artifact = second.parent / next(iter(b["evidence"]))
        artifact.write_text("tampered")
        self.command("compare", first, second, "--output", output, code=2)

    def test_changed_source_invalidates_build_even_when_first_byte_matches(self):
        manifest, perf = self.project()
        first = json.loads(self.capture(manifest, perf, "before").read_text())
        source = self.root / "program.c"
        source.write_text(source.read_text().replace('puts("ok")', 'puts("new")'))
        manifest.write_text(MANIFEST.replace('expected_stdout = "ok\\n"', 'expected_stdout = "new\\n"'))
        second = json.loads(self.capture(manifest, perf, "after").read_text())
        self.assertFalse(second["build"]["cached"])
        self.assertNotEqual(first["sources"], second["sources"])
        self.assertNotEqual(first["build"]["key"], second["build"]["key"])

    def test_wrong_output_and_partial_counts_retain_incomplete_records(self):
        manifest, perf = self.project()
        manifest.write_text(MANIFEST.replace('expected_stdout = "ok\\n"', 'expected_stdout = "wrong\\n"'))
        record = self.capture(manifest, perf, "wrong", code=2)
        self.assertEqual(json.loads(record.read_text())["status"], "incomplete")
        manifest.write_text(MANIFEST)
        perf.write_text(perf.read_text().replace("100.00", "99.00"))
        record = self.capture(manifest, perf, "partial", code=2)
        self.assertEqual(json.loads(record.read_text())["status"], "incomplete")

    def test_analyze_builds_without_executing_application(self):
        manifest, _ = self.project()
        (self.root / "program.c").write_text('int main(void){return 77;}\n')
        output = self.root / "analysis.json"
        self.command("analyze", manifest, "--output", output, "--cache-dir", self.root / "cache")
        self.assertEqual(json.loads(output.read_text())["version"], "juice-analysis-v1")
        self.assertNotIn("juice", json.loads(output.read_text()))

    def test_unknown_manifest_field_cannot_disable_oracle(self):
        manifest, perf = self.project()
        manifest.write_text(MANIFEST.replace("expected_stdout", "expected_stdut"))
        self.capture(manifest, perf, "invalid", code=2)
        self.assertFalse((self.root / "cache").exists())

if __name__ == "__main__":
    unittest.main()
