#!/usr/bin/env python3
"""Exercise comparison integrity, collectors, isolation and held-out calibration.

No PMU permissions or Valgrind installation are needed by the gate. Real native
collector qualification lives in scripts/juice_validate.py and its saved report.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from juice_tool.calibration import fit, predict
from juice_tool.cli import main as cli
from juice_tool.collectors import parse_grind, parse_perf, summarize
from juice_tool.common import JuiceError, read_json, run, write_json
from juice_tool.engine import analyze, capture
from juice_tool.manifest import Manifest
from juice_tool.report import compare_records, load_record, semantic_delta, validate_scenarios


MANIFEST = '''version = 1
name = "test-project"
sources = ["program.c"]
inputs = ["data.txt"]
[build]
compiler = "cc"
command = ["{compiler}", "-O2", "-g", "{root}/program.c", "-o", "{binary}"]
[[workloads]]
name = "quick"
family = "test"
unit = "record"
units = 8
args = []
expected_stdout = "ok\\n"
'''


class Directory(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="juice-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "program.c").write_text('#include <stdio.h>\nint main(void) {puts("ok"); return 0;}\n')
        (self.root / "data.txt").write_text("fixed input\n")
        self.manifest = self.root / "juice.toml"
        self.manifest.write_text(MANIFEST)

    def change_manifest(self, old, new):
        self.manifest.write_text(self.manifest.read_text().replace(old, new))


class Contracts(Directory):
    def test_explicit_source_and_fixed_input_identities(self):
        m = Manifest(self.manifest)
        self.assertEqual(set(m.sources), {"program.c"})
        self.assertEqual(set(m.inputs), {"data.txt"})
        self.assertEqual(m.select("quick", None)[0]["units"], 8)

    def test_unknown_fields_do_not_silently_disable_a_check(self):
        self.change_manifest("expected_stdout", "expected_stdut")
        with self.assertRaisesRegex(JuiceError, "unknown workload"):
            Manifest(self.manifest)

    def test_requires_a_correctness_oracle(self):
        self.change_manifest('expected_stdout = "ok\\n"', '')
        with self.assertRaisesRegex(JuiceError, "every workload needs"):
            Manifest(self.manifest)

    def test_rejects_invalid_units_and_empty_selections(self):
        for value in ("0", "-1", "nan", "inf", "true"):
            self.manifest.write_text(MANIFEST.replace("units = 8", "units = " + value))
            with self.assertRaisesRegex(JuiceError, "finite and positive"):
                Manifest(self.manifest)
        self.manifest.write_text(MANIFEST)
        with self.assertRaisesRegex(JuiceError, "selection"):
            Manifest(self.manifest).select("validation", None)

    def test_fixed_inputs_cannot_escape_or_overlap_source(self):
        self.change_manifest('inputs = ["data.txt"]', 'inputs = ["../outside"]')
        with self.assertRaisesRegex(JuiceError, "inside"):
            Manifest(self.manifest)
        self.manifest.write_text(MANIFEST.replace('inputs = ["data.txt"]', 'inputs = ["program.c"]'))
        with self.assertRaisesRegex(JuiceError, "disjoint"):
            Manifest(self.manifest)

    def test_source_symlink_escape_rejected(self):
        (self.root / "program.c").unlink()
        (self.root / "program.c").symlink_to("/etc/hosts")
        with self.assertRaisesRegex(JuiceError, "symlink escapes"):
            Manifest(self.manifest)

    def test_regex_has_exactly_one_capture(self):
        self.manifest.write_text(MANIFEST + 'stdout_regex = "ok"\n')
        with self.assertRaisesRegex(JuiceError, "one capture"):
            Manifest(self.manifest)

    def test_incorrect_oracle_type_is_a_manifest_error(self):
        self.change_manifest('expected_stdout = "ok\\n"', 'expected_stdout = 12')
        with self.assertRaisesRegex(JuiceError, "must be a string"):
            Manifest(self.manifest)

    def test_cli_rejects_non_json_output_and_nan_gate(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(cli(["compare", "a", "b", "--output", "report.md"]), 2)
            self.assertEqual(cli(["compare", "a", "b", "--output", "report.json", "--fail-above", "nan"]), 2)


class Parsers(unittest.TestCase):
    def test_hybrid_perf_requires_exact_event_and_full_running(self):
        event = "cpu_core/instructions/u"
        self.assertEqual(parse_perf("1000;;cpu_core/instructions/u;2000;100.00;;\n", event), {"instructions": 1000})
        for text in ("<not counted>;;cpu_core/instructions/u;0;0.00;;\n",
                     "1000;;cpu_core/instructions/u;1000;50.00;;\n",
                     "1000;;cpu_atom/instructions/u;2000;100.00;;\n",
                     "-1;;cpu_core/instructions/u;2000;100.00;;\n",
                     "1000;;cpu_core/instructions/u;nan;100.00;;\n"):
            with self.assertRaises(JuiceError):
                parse_perf(text, event)

    def test_compressed_callgrind_self_costs_exclude_call_arcs(self):
        profile = '''positions: instr line
events: Ir Ge
summary: 0 0
ob=(1) program
fl=(1) kernel.c
fn=(1) outer
0x100 10 3
cfn=(2) inner
calls=1 0x200 20
* * 7 1
0x104 +1 2
fn=(2)
0x200 20 7 1
totals: 12 1
'''
        result = parse_grind(profile)
        self.assertEqual(result["metrics"], {"instructions": 12, "atomics": 1})
        self.assertEqual({f["function"]: f["instructions"] for f in result["functions"]}, {"outer": 5, "inner": 7})
        self.assertEqual(sum(row["instructions"] for row in result["lines"]), 12)

    def test_cachegrind_summary_and_trailing_zero_events(self):
        result = parse_grind("events: Ir Dr Dw\nfl=a.c\nfn=main\n10 2 1\n11 3 2 1\nsummary: 5 3 1\n")
        self.assertEqual(result["metrics"], {"instructions": 5, "data_reads": 3, "data_writes": 1})

    def test_callgrind_region_can_omit_trailing_zero_summary_events(self):
        result = parse_grind("events: Ir Ge\nfl=a.c\nfn=phase\n1 12\nsummary: 12\ntotals: 12\n")
        self.assertEqual(result["metrics"], {"instructions": 12, "atomics": 0})

    def test_truncated_or_inconsistent_profiles_fail(self):
        for profile in ("events: Ir\nfl=a\nfn=main\n1 5\nsummary: 100\n",
                        "events: Ir\nfn=(9)\n1 5\nsummary: 5\n", ""):
            with self.assertRaises(JuiceError):
                parse_grind(profile)


def sample_record(value=100):
    metrics = summarize([{"metrics": {"instructions": value}}] * 3)
    cell = {"metrics": metrics, "units": 10, "unit": "record", "family": "f", "tier": "quick",
            "scope": "complete scenario", "weight": 1, "correctness": {"stdout": "same"},
            "functions": [], "lines": []}
    return {"name": "sample", "contract": {"input": "fixed"}, "context": {"cpu": 0},
            "collector": {"kind": "perf"}, "sources": {"main": "abc"}, "build_config": {"compiler": "same"},
            "build": {"code": {"available": True, "sections": {}, "functions": {}}}, "workloads": {"w": cell}}


class Reports(unittest.TestCase):
    def test_work_index_and_application_unit_normalization(self):
        a, b = sample_record(), sample_record(80)
        report = compare_records(a, b)
        self.assertEqual(report["workloads"]["w"]["juice"], 80)
        self.assertEqual(report["workloads"]["w"]["assessment"], "less-work")
        self.assertEqual(report["runtime_prediction"]["status"], "uncalibrated")

    def test_higher_atomic_cost_cannot_be_a_clean_improvement(self):
        a, b = sample_record(), sample_record(80)
        a["workloads"]["w"]["metrics"]["atomics"] = {"median": 1}
        b["workloads"]["w"]["metrics"]["atomics"] = {"median": 2}
        self.assertEqual(compare_records(a, b)["workloads"]["w"]["assessment"], "mixed")

    def test_missing_code_analysis_is_unknown_not_zero_expensive_operations(self):
        a, b = sample_record(), sample_record(80)
        b["build"]["code"]["available"] = False
        self.assertEqual(compare_records(a, b)["workloads"]["w"]["assessment"], "mixed")

    def test_input_context_and_output_changes_refuse_comparison(self):
        for key, value in (("contract", {}), ("context", {})):
            b = sample_record()
            b[key] = value
            with self.assertRaises(JuiceError):
                compare_records(sample_record(), b)
        b = sample_record()
        b["workloads"]["w"]["correctness"] = {"stdout": "wrong"}
        with self.assertRaisesRegex(JuiceError, "outputs differ"):
            compare_records(sample_record(), b)

    def test_mode_enforces_what_is_held_fixed(self):
        b = sample_record()
        b["sources"] = {"main": "new"}
        with self.assertRaisesRegex(JuiceError, "application sources"):
            compare_records(sample_record(), b, "backend")
        b["build_config"] = {"compiler": "new"}
        with self.assertRaisesRegex(JuiceError, "identical compiler"):
            compare_records(sample_record(), b, "application")

    def test_new_link_dependency_is_reported_but_changed_installed_library_is_rejected(self):
        a, b = sample_record(), sample_record(80)
        a["context"]["libraries"] = {"libc": "same"}
        b["context"]["libraries"] = {"libc": "same", "libpthread": "added"}
        report = compare_records(a, b)
        self.assertIn("libpthread", report["library_changes"])
        self.assertEqual(report["workloads"]["w"]["assessment"], "mixed")
        b["context"]["libraries"]["libc"] = "changed"
        with self.assertRaisesRegex(JuiceError, "contexts differ"):
            compare_records(a, b)

    def test_variable_counts_are_uncertain(self):
        b = sample_record(80)
        b["workloads"]["w"]["metrics"] = summarize([{"metrics": {"instructions": v}} for v in (50, 80, 100)])
        self.assertEqual(compare_records(sample_record(), b)["workloads"]["w"]["assessment"], "uncertain")

    def test_counter_hook_changes_are_not_treated_as_less_work(self):
        a = {"semantic": {"version": "v1", "totals": {"runtime_retains": 100}}, "counter_semantics": "old"}
        b = {"semantic": {"version": "v1", "totals": {"runtime_retains": 50}}, "counter_semantics": "new"}
        self.assertEqual(semantic_delta(a, b)["status"], "incompatible")

    def test_semantic_sites_keep_inlined_origin_and_source_location(self):
        site = {"function": "caller", "origin": "inlined_helper", "path": "main.selka", "line": 12,
                "column": 4, "kind": "list_copy", "detail": "copy", "count": 3, "bytes": 24, "extra": 0}
        a = {"semantic": {"version": "v1", "totals": {}, "sites": [site]}, "counter_semantics": "same"}
        b = {"semantic": {"version": "v1", "totals": {}, "sites": []}, "counter_semantics": "same"}
        result = semantic_delta(a, b)
        self.assertEqual(result["sites"][0]["origin"], "inlined_helper")
        self.assertEqual(result["sites"][0]["candidate"]["count"], 0)
        self.assertEqual(result["requested_allocation_bytes"]["status"], "unavailable")

    def test_larger_scenarios_must_compare_the_same_change(self):
        quick = compare_records(sample_record(), sample_record(80))
        larger = copy.deepcopy(quick)
        larger["workloads"]["w"]["tier"] = "validation"
        self.assertTrue(validate_scenarios(quick, larger)["passed"])
        larger["change_id"] = "different"
        with self.assertRaisesRegex(JuiceError, "different source"):
            validate_scenarios(quick, larger)

    def test_startup_dominated_short_scenario_is_rejected(self):
        quick = compare_records(sample_record(1000), sample_record(151))
        larger = copy.deepcopy(quick)
        larger["workloads"]["w"]["tier"] = "validation"
        larger["workloads"]["w"]["instruction_ratio"] = 0.143
        self.assertFalse(validate_scenarios(quick, larger)["passed"])


class FakeCollector:
    kind = "perf"
    cpu = min(os.sched_getaffinity(0))
    identity = {"kind": "test-only", "cpu": cpu}

    def __init__(self, instructions=1000):
        self.instructions = instructions
        self.paths = []

    def collect(self, argv, work, env, prefix, workload):
        self.paths.append((argv, str(work), env))
        result = run(argv, work, env, prefix, workload["timeout_seconds"])
        return {**result, "metrics": {"instructions": self.instructions}, "functions": [], "lines": []}


@unittest.skipUnless(shutil.which("cc"), "native build integration requires a C compiler")
class Runner(Directory):
    def record(self, name, collector=None):
        args = argparse.Namespace(name=name, repeats=2, tier="quick", workload=None,
                                  cache_dir=self.root / "cache", compiler=None, static=False)
        return capture(Manifest(self.manifest), collector or FakeCollector(), args)

    def test_round_trip_paths_cache_identity_and_immutability(self):
        collector = FakeCollector()
        first = self.record("base", collector)
        second = self.record("candidate", collector)
        a, b = load_record(first), load_record(second)
        self.assertEqual(collector.paths[0], collector.paths[-1])
        self.assertTrue(b["build"]["cached"])
        self.assertEqual(compare_records(a, b)["suite_juice"], 100)
        with self.assertRaisesRegex(JuiceError, "immutable"):
            self.record("base")

    def test_static_analysis_does_not_execute_the_application(self):
        (self.root / "program.c").write_text("int main(void) {for (;;) {} return 1;}")
        options = argparse.Namespace(cache_dir=self.root / "cache", compiler=None)
        analysis = analyze(Manifest(self.manifest), options)
        self.assertEqual(analysis["version"], "juice-analysis-v1")
        self.assertEqual(set(analysis["build"]["artifacts"]), {"plain"})
        self.assertNotIn("workloads", analysis)

    def test_changed_source_invalidates_cached_build(self):
        first = load_record(self.record("base"))
        with (self.root / "program.c").open("a") as stream:
            stream.write("\n/* source edit */\n")
        second = load_record(self.record("edit"))
        self.assertFalse(second["build"]["cached"])
        self.assertNotEqual(first["build"]["key"], second["build"]["key"])

    def test_corrupt_build_cache_is_not_reused(self):
        record = load_record(self.record("base"))
        binary = self.root / "cache/test-project/builds" / record["build"]["key"] / "plain"
        binary.write_text("corrupted")
        with self.assertRaisesRegex(JuiceError, "corrupt build cache"):
            self.record("candidate")

    def test_native_build_prefix_is_executed(self):
        self.change_manifest('compiler = "cc"', 'compiler = "cc"\nprefix = ["/usr/bin/false"]')
        with self.assertRaisesRegex(JuiceError, "plain build failed"):
            self.record("failed-wrapper")

    def test_wrong_output_retains_an_incomplete_record(self):
        self.change_manifest('expected_stdout = "ok\\n"', 'expected_stdout = "wrong\\n"')
        with self.assertRaisesRegex(JuiceError, "incorrect stdout"):
            self.record("bad")
        path = self.root / "cache/test-project/records/bad/record.json"
        self.assertEqual(read_json(path)["status"], "incomplete")
        with self.assertRaisesRegex(JuiceError, "not a complete"):
            load_record(path)

    def test_raw_evidence_tampering_is_detected(self):
        path = self.record("base")
        next(path.parent.glob("*.stdout")).write_text("changed")
        with self.assertRaisesRegex(JuiceError, "modified raw evidence"):
            load_record(path)

    def test_timeout_does_not_produce_a_score(self):
        (self.root / "program.c").write_text("#include <unistd.h>\nint main(void) {sleep(10);return 0;}")
        self.manifest.write_text(MANIFEST + "timeout_seconds = 0.03\n")
        with self.assertRaisesRegex(JuiceError, "incomplete run"):
            self.record("timeout")

    def test_program_output_artifact_is_checked_across_versions(self):
        (self.root / "program.c").write_text('#include <stdio.h>\nint main(void) {FILE *f=fopen("result.txt","w");fputs("one",f);fclose(f);puts("ok");return 0;}')
        self.manifest.write_text(MANIFEST + 'outputs = ["result.txt"]\n')
        first = load_record(self.record("base"))
        (self.root / "program.c").write_text((self.root / "program.c").read_text().replace('"one"', '"two"'))
        second = load_record(self.record("candidate"))
        with self.assertRaisesRegex(JuiceError, "outputs differ"):
            compare_records(first, second)


class Calibration(Directory):
    def dataset(self):
        points = []
        for i, ratio in enumerate((0.6, 0.8, 1.2, 1.4, 0.7, 1.3, 0.65, 0.9, 1.25)):
            report = compare_records(sample_record(1000), sample_record(round(1000 * ratio)))
            report["base_id"], report["candidate_id"] = "base", str(i)
            report["workloads"]["w"]["family"] = "a" if i < 3 else "b" if i < 6 else "heldout"
            write_json(self.root / f"report-{i}.json", report)
            evidence = {"version": "juice-timing-evidence-v1", "method": "synthetic test only",
                        "base_id": "base", "candidate_id": str(i), "context_id": report["context_id"],
                        "workload": "w", "pairs": [[1, ratio ** 0.8]] * 5}
            write_json(self.root / f"timing-{i}.json", evidence)
            points.append({"comparison": f"report-{i}.json", "workload": "w", "timing_evidence": f"timing-{i}.json",
                           "split": "train" if i < 6 else "validation"})
        path = self.root / "dataset.json"
        write_json(path, {"version": "juice-calibration-data-v1", "points": points})
        return path

    def test_validated_model_and_out_of_domain_abstention(self):
        path = self.dataset()
        model = fit(path)
        self.assertAlmostEqual(model["exponent"], 0.8)
        report = read_json(self.root / "report-6.json")
        predict(report, model)
        self.assertAlmostEqual(report["runtime_prediction"]["workloads"]["w"]["ratio"], 0.65 ** 0.8)
        report["workloads"]["w"]["family"] = "unseen"
        predict(report, model)
        self.assertIn("reason", report["runtime_prediction"]["workloads"]["w"])

    def test_training_validation_leakage_is_rejected(self):
        path = self.dataset()
        report = read_json(self.root / "report-6.json")
        report["workloads"]["w"]["family"] = "a"
        write_json(self.root / "report-6.json", report)
        with self.assertRaisesRegex(JuiceError, "disjoint"):
            fit(path)

    def test_wrong_build_or_noisy_timings_cannot_calibrate(self):
        path = self.dataset()
        evidence = read_json(self.root / "timing-0.json")
        evidence["candidate_id"] = "other"
        write_json(self.root / "timing-0.json", evidence)
        with self.assertRaisesRegex(JuiceError, "does not match"):
            fit(path)
        path = self.dataset()
        evidence = read_json(self.root / "timing-0.json")
        evidence["pairs"][0][1] *= 2
        write_json(self.root / "timing-0.json", evidence)
        with self.assertRaisesRegex(JuiceError, "vary"):
            fit(path)

    def test_model_with_bad_held_out_predictions_is_rejected(self):
        path = self.dataset()
        evidence = read_json(self.root / "timing-6.json")
        evidence["pairs"] = [[1, 2]] * 5
        write_json(self.root / "timing-6.json", evidence)
        with self.assertRaisesRegex(JuiceError, "failed held-out"):
            fit(path)


if __name__ == "__main__":
    unittest.main()
