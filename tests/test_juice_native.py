#!/usr/bin/env python3
"""Installed native Juice parity and lifecycle checks; no PMU or Valgrind required."""
from __future__ import annotations
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
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
        moved = self.root / "mylang"
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
events=${event#"{"}; events=${events%"}"}
: > "$output"
IFS=,
for item in $events; do printf '1000;;%s;1;100.00\n' "$item" >> "$output"; done
unset IFS
"$@"
''')
        perf.chmod(0o755)
        return manifest, perf

    def capture(self, manifest, perf, name, code=0):
        self.command("record", manifest, "--name", name, "--repeats", 2,
                     "--perf", perf, "--cache-dir", self.root / "cache", code=code)
        return self.root / "cache/test-project/records" / name / "record.json"

    def plan(self, manifest, perf, *args, env=None):
        result = self.command("plan", manifest, "--perf", perf,
                              "--cache-dir", self.root / "cache", *args, env=env)
        return json.loads(result.stdout)

    def test_plan_inspects_exact_contract_without_building_or_creating_cache(self):
        manifest, perf = self.project()
        launcher = self.root / "version-only-compiler"
        marker = self.root / "unexpected-build"
        launcher.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo fixture-compiler; '
                            'else touch "' + str(marker) + '"; exit 79; fi\n')
        launcher.chmod(0o755)
        manifest.write_text(MANIFEST.replace('compiler = "cc"',
                                            'compiler = "' + str(launcher) + '"'))
        before = sorted(p.name for p in self.root.iterdir())
        planned = self.plan(manifest, perf, "--repeats", 2, "--workload", "quick")
        self.assertEqual(planned["version"], "juice-plan-v1")
        self.assertEqual(planned["root"], str(self.root))
        self.assertEqual(planned["manifest_path"], str(manifest))
        self.assertEqual(planned["sources"]["program.c"],
                         hashlib.sha256((self.root / "program.c").read_bytes()).hexdigest())
        self.assertEqual(planned["inputs"]["data.txt"],
                         hashlib.sha256((self.root / "data.txt").read_bytes()).hexdigest())
        self.assertEqual(planned["selected_workloads"][0]["name"], "quick")
        self.assertEqual(planned["selected_workloads"][0]["exit_code"], 0)
        self.assertEqual(planned["measurement"]["repeats"], 2)
        self.assertEqual(planned["measurement"]["context"]["libraries"], {})
        self.assertEqual(planned["implementation"]["running_elf"]["sha256"],
                         hashlib.sha256(COMPILER.read_bytes()).hexdigest())
        self.assertEqual(planned["build_config"]["compiler"]["path"], str(launcher))
        self.assertIn(str(launcher), planned["input_scopes"]["files"])
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), before)
        self.assertFalse(marker.exists())
        self.assertFalse((self.root / "cache").exists())

    def test_plan_never_acquires_capture_workspace_lock(self):
        manifest, perf = self.project()
        cache = self.root / "cache/test-project"
        cache.mkdir(parents=True)
        with (cache / ".lock").open("wb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # Use the suite's normal deadline: Debug plan also hashes the full
            # compiler ELF. The lock stays held for the entire bounded request.
            result = self.command("plan", manifest, "--perf", perf,
                                  "--cache-dir", self.root / "cache")
            self.assertEqual(json.loads(result.stdout)["paths"]["cache"], str(cache))
        self.assertFalse((cache / "workspace").exists())

    def test_plan_is_stable_and_declares_glob_membership_for_new_sources(self):
        manifest, perf = self.project()
        manifest.write_text(MANIFEST.replace('["program.c"]', '["*.c"]'))
        first = self.plan(manifest, perf)
        self.assertEqual(first, self.plan(manifest, perf))
        self.assertIn(str(self.root), first["input_scopes"]["directories"])
        (self.root / "new.c").write_text("/* newly matching transitive source */\n")
        second = self.plan(manifest, perf)
        self.assertIn("new.c", second["sources"])
        self.assertIn(str(self.root / "new.c"), second["input_scopes"]["files"])
        (self.root / "program.c").write_text("/* changed source, same declared path */\n")
        self.assertNotEqual(first["sources"]["program.c"],
                            self.plan(manifest, perf)["sources"]["program.c"])
        self.assertFalse((self.root / "cache").exists())

    def test_plan_dependency_resources_and_default_valgrind_scope_are_explicit(self):
        manifest, perf = self.project()
        resources = self.root / "provider"
        resources.mkdir()
        header = resources / "header.h"
        header.write_text("#define VALUE 1\n")
        manifest.write_text(MANIFEST.replace('[build]', '[build]\ndependencies = ["provider"]\ntools = ["sh"]'))
        first = self.plan(manifest, perf)
        self.assertIn(str(resources), first["input_scopes"]["directories"])
        self.assertEqual(first["build_config"]["dependencies"][str(header)],
                         hashlib.sha256(header.read_bytes()).hexdigest())
        self.assertIn(first["build_config"]["tools"]["sh"]["path"],
                      first["input_scopes"]["files"])
        header.write_text("#define VALUE 2\n")
        self.assertNotEqual(first["build_config"]["dependencies"],
                            self.plan(manifest, perf)["build_config"]["dependencies"])
        environment = dict(os.environ)
        environment.pop("VALGRIND_LIB", None)
        unscoped = self.plan(manifest, perf, "--collector", "callgrind", "--valgrind", perf,
                             env=environment)
        self.assertEqual(unscoped["collector_runtime"]["provider_scope"], "incomplete")
        self.assertFalse(unscoped["collector_runtime"]["closure_complete"])
        engine = resources / "callgrind-fixture"
        engine.write_text("collector engine contents\n")
        environment["VALGRIND_LIB"] = str(resources)
        scoped = self.plan(manifest, perf, "--collector", "callgrind", "--valgrind", perf,
                           env=environment)
        self.assertEqual(scoped["collector_runtime"]["provider_scope"], "explicit")
        self.assertFalse(scoped["collector_runtime"]["closure_complete"])
        self.assertEqual(scoped["collector_runtime"]["environment"]["VALGRIND_LIB"], str(resources))
        self.assertEqual(scoped["measurement"]["collector"]["engines"][engine.name],
                         hashlib.sha256(engine.read_bytes()).hexdigest())

    def test_plan_native_toml_json_selection_and_profile_semantics_match(self):
        manifest, perf = self.project()
        first = self.plan(manifest, perf, "--profile", "runtime", "--repeats", 5)
        equivalent = self.write("juice.json", first["manifest"])
        second = self.plan(equivalent, perf, "--profile", "runtime", "--repeats", 5)
        for field in ("manifest", "sources", "inputs", "selected_workloads", "build_config", "measurement"):
            self.assertEqual(first[field], second[field])
        self.assertIn("event_group", first["measurement"]["collector"])
        self.assertIn("scheduling_policy", first["measurement"]["context"])
        self.command("plan", manifest, "--perf", perf, "--workload", "absent", code=2)
        self.command("plan", manifest, "--name", "not-allowed", code=2)
        self.command("plan", manifest, "--output", self.root / "not-allowed.json", code=2)
        self.assertFalse((self.root / "cache").exists())

    def test_plan_preserves_provider_symlink_paths_for_mutation_watches(self):
        manifest, perf = self.project()
        resource = self.root / "sdk"
        resource.mkdir()
        header = resource / "header.h"
        header.write_text("/* external provider */\n")
        alias = self.root / "sdk-alias"
        alias.symlink_to(resource, target_is_directory=True)
        file_alias = self.root / "header-alias.h"
        file_alias.symlink_to(header)
        manifest.write_text(MANIFEST.replace('[build]',
                            '[build]\ndependencies = ["sdk-alias", "header-alias.h"]'))
        planned = self.plan(manifest, perf)
        self.assertIn(str(alias), planned["input_scopes"]["directories"])
        self.assertIn(str(resource), planned["input_scopes"]["directories"])
        self.assertIn(str(file_alias), planned["input_scopes"]["files"])
        self.assertIn(str(header), planned["input_scopes"]["files"])
        self.assertEqual(planned["build_config"]["dependencies"][str(header)],
                         hashlib.sha256(header.read_bytes()).hexdigest())
        self.assertFalse((self.root / "cache").exists())

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

    def runtime_records(self, refs=(1000, 1100)):
        a, b = sample_record(1000), sample_record(800)
        for record, count in zip((a, b), refs):
            metrics = record["workloads"]["w"]["metrics"]
            for key in ("cycles", "reference_cycles"):
                metrics[key] = dict(median=count, min=count, max=count, spread=0,
                                    samples=[count] * 3)
        return self.records(a, b)

    def test_runtime_cost_detects_regression_despite_fewer_instructions(self):
        _, _, a, b = self.runtime_records()
        output = self.root / "runtime.json"
        self.command("compare", a, b, "--output", output)
        cell = json.loads(output.read_text())["workloads"]["w"]
        self.assertEqual(cell["juice"], 80)
        self.assertAlmostEqual(cell["runtime_proxy"]["estimated_ratio"], 1.1)
        self.assertFalse(cell["runtime_proxy"]["accuracy_validated"])
        self.assertIn("5% accuracy target is unvalidated", output.with_suffix(".md").read_text())

    def test_runtime_spread_abstains_and_forged_summary_fails(self):
        _, b, first, second = self.runtime_records()
        ref = b["workloads"]["w"]["metrics"]["reference_cycles"]
        ref.update(min=1000, max=1200, spread=200 / 1100, samples=[1000, 1100, 1200])
        self.write("candidate.json", b)
        output = self.root / "runtime.json"
        self.command("compare", first, second, "--output", output)
        proxy = json.loads(output.read_text())["workloads"]["w"]["runtime_proxy"]
        self.assertEqual(proxy["status"], "uncertain")
        self.assertIsNone(proxy["estimated_ratio"])
        ref["spread"] = 0
        self.write("candidate.json", b)
        self.command("compare", first, second, "--output", output, code=2)

    def test_alternating_counter_pairs_cancel_shared_drift_and_require_matching_identity(self):
        a, b, first, second = self.runtime_records()
        baseline = [1000, 1000, 1100, 1100, 1200, 1200, 1300, 1300, 1400, 1400]
        for record, scale in ((a, 1), (b, 1.1)):
            cell = record["workloads"]["w"]
            cell["pairing"] = dict(method="alternating-captures-v1", id="same-session", samples_per_pair=2)
            for key in cell["metrics"]:
                values = [value * scale for value in baseline]
                median = statistics.median(values)
                cell["metrics"][key] = dict(samples=values, median=median, min=min(values), max=max(values),
                                             spread=(max(values) - min(values)) / median)
        self.write("base.json", a)
        self.write("candidate.json", b)
        output = self.root / "paired.json"
        self.command("compare", first, second, "--output", output)
        proxy = json.loads(output.read_text())["workloads"]["w"]["runtime_proxy"]
        self.assertEqual(proxy["status"], "estimated")
        self.assertAlmostEqual(proxy["estimated_ratio"], 1.1)
        self.assertEqual(len(proxy["reference_cycles"]["pair_ratios"]), 5)
        b["workloads"]["w"]["pairing"]["id"] = "different-session"
        self.write("candidate.json", b)
        self.command("compare", first, second, "--output", output, code=2)
        b["workloads"]["w"]["pairing"] = dict(a["workloads"]["w"]["pairing"], samples_per_pair=3)
        a["workloads"]["w"]["pairing"] = b["workloads"]["w"]["pairing"]
        self.write("base.json", a)
        self.write("candidate.json", b)
        self.command("compare", first, second, "--output", output, code=2)

    def test_runtime_validation_requires_matching_independent_stable_timings(self):
        _, _, a, b = self.runtime_records()
        comparison = self.root / "comparison.json"
        self.command("compare", a, b, "--output", comparison)
        report = json.loads(comparison.read_text())
        evidence = {key: report[key] for key in ("base_id", "candidate_id", "context_id")}
        evidence.update(version="juice-timing-evidence-v1", workload="w",
                        method="independent alternating processes", pairs=[[1, 1.1]] * 5)
        timing = self.write("timing.json", evidence)
        output = self.root / "validation.json"
        self.command("validate-runtime", comparison, timing, "--output", output)
        self.assertTrue(json.loads(output.read_text())["passed"])
        evidence["pairs"] = [[1, 1.3]] * 5
        self.write("timing.json", evidence)
        self.command("validate-runtime", comparison, timing, "--output", output, code=1)
        self.assertEqual(json.loads(output.read_text())["status"], "outside-target")
        evidence["pairs"][0] = [1, 2]
        self.write("timing.json", evidence)
        self.command("validate-runtime", comparison, timing, "--output", output, code=1)
        self.assertEqual(json.loads(output.read_text())["status"], "uncertain")
        evidence["candidate_id"] = "wrong build"
        self.write("timing.json", evidence)
        self.command("validate-runtime", comparison, timing, "--output", output, code=2)

    def test_runtime_capture_preserves_three_events_and_rejects_partial_group(self):
        manifest, perf = self.project()
        self.command("record", manifest, "--name", "runtime", "--repeats", 2,
                     "--profile", "runtime", "--perf", perf, "--cache-dir", self.root / "cache")
        path = self.root / "cache/test-project/records/runtime/record.json"
        record = json.loads(path.read_text())
        self.assertEqual(record["collector"]["profile"], "runtime")
        self.assertIn("reference_cycles", record["workloads"]["quick"]["metrics"])
        perf.write_text(perf.read_text().replace('for item in $events; do',
                       'for item in $events; do case "$item" in *ref-cycles*) continue;; esac;'))
        self.command("record", manifest, "--name", "missing", "--repeats", 2,
                     "--profile", "runtime", "--perf", perf, "--cache-dir", self.root / "cache", code=2)
        self.assertEqual(json.loads((path.parent.parent / "missing/record.json").read_text())["status"], "incomplete")

    def test_unknown_manifest_field_cannot_disable_oracle(self):
        manifest, perf = self.project()
        manifest.write_text(MANIFEST.replace("expected_stdout", "expected_stdut"))
        self.capture(manifest, perf, "invalid", code=2)
        self.assertFalse((self.root / "cache").exists())

if __name__ == "__main__":
    unittest.main()
