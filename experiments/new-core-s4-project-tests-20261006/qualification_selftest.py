#!/usr/bin/env python3
"""Retained false-qualification and timeout regressions; never runs a compiler."""
import argparse
import copy
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import conformance_checked as conformance
import fuzz_matrix as fuzz
import project_matrix as projects
import qualification_support as support
import qualification_provenance as provenance

AREA = None


def report(statuses):
    result = {"version": "native-tests-v1", "tests": [
        {"name": name, "status": status} for name, status in statuses]}
    result.update({status: sum(test["status"] == status for test in result["tests"])
                   for status in ("passed", "cached", "failed", "skipped", "unsupported")})
    return result


def row(name, tests):
    return {"file": name, "tests": tests, "problems": [],
            "modes": {mode: {"match": tests, "mismatch": 0, "unsupported": 0}
                      for mode in ("debug", "release")}}


class QualificationTests(unittest.TestCase):
    def retained(self, name, value):
        (AREA / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n")

    def test_requested_core_and_source_revision_survive_historical_forwarding(self):
        receipt = ["--evidence", "/owned/evidence", "--old-source", "a" * 40,
                   "--core-source", "b" * 40, "--old-origin", "/origins/old.json",
                   "--core-origin", "/origins/core.json"]
        records = []
        for supplied in (["--core", "/oracles/core"], ["--core=/oracles/core"]):
            historical = ["--mylang", "/oracles/old", *supplied, "--set", "all",
                          "--modes", "debug,release", "--leakcheck", "--verify"]
            for argv in (receipt + historical, historical + receipt):
                _, options, forwarded = conformance.arguments(argv)
                self.assertEqual(options.core_source, "b" * 40)
                self.assertEqual(forwarded, historical)
                records.append({"argv": argv, "core_source": options.core_source,
                                "forwarded": forwarded})
        self.retained("historical-core-forwarding", records)

    def test_force_cannot_normalize_cached_to_passed(self):
        value = report([("app::test_dependency", "cached")])
        self.retained("forced-cached-report", value)
        done = subprocess.CompletedProcess(["core", "test", "--force"], 0, json.dumps(value))
        self.assertEqual(projects.verdicts(done)[0], [("app::test_dependency", "passed")])
        with self.assertRaisesRegex(ValueError, "did not execute"):
            projects.verdicts(done, forced=True)

    def test_report_duplicates_counts_status_and_unsupported_fail_closed(self):
        good = report([("app::test_one", "passed")])
        mutations = []
        duplicate = copy.deepcopy(good)
        duplicate["tests"] *= 2
        duplicate["passed"] = 2
        mutations.append(("duplicate", duplicate, 0))
        wrong_total = copy.deepcopy(good)
        wrong_total["passed"] = True
        mutations.append(("boolean-total", wrong_total, 0))
        mutations.append(("unsupported", report([("app::test_one", "unsupported")]), 0))
        mutations.append(("wrong-status", report([("app::test_one", "failed")]), 0))
        for field, values in (("executed", (0, 2, True)), ("dropped", (1, True, -1)),
                              ("unloaded", (1, True, -1))):
            mutations.extend((field + "-" + str(value), {**good, field: value}, 0)
                             for value in values)
        for name, value, status in mutations:
            self.retained(name + "-report", value)
            with self.subTest(name=name), self.assertRaises(ValueError):
                conformance.validate_report(value, status)

    def test_empty_test_selection_cannot_qualify(self):
        empty = report([])
        self.retained("empty-report", empty)
        # Empty JSON is valid for a support file. It cannot erase a baseline test row.
        conformance.validate_report(empty, 3)
        with self.assertRaisesRegex(ValueError, "count differs"):
            conformance.coverage([row("test_file", 0)], {"test_file": 3}, ["debug", "release"], 3)
        with self.assertRaisesRegex(ValueError, "aggregate empty"):
            conformance.coverage([row("support", 0)], {"support": 0}, ["debug", "release"], 0)
        with self.assertRaisesRegex(ValueError, "retained baseline"):
            conformance.coverage([row("custom", 0), row("real", 3)], {"custom": None, "real": 3}, ["debug", "release"], 3)

    def test_legitimate_support_rows_and_exact_file_coverage(self):
        expected = {"real": 3, **{f"support-{i}": 0 for i in range(9)}}
        rows = [row(name, count) for name, count in expected.items()]
        conformance.coverage(rows, expected, ["debug", "release"], 3)
        with self.assertRaisesRegex(ValueError, "coverage differs"):
            conformance.coverage(rows[:-1], expected, ["debug", "release"], 3)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            conformance.coverage(rows + [rows[0]], expected, ["debug", "release"], 3)

    def test_authoritative_baselines_and_discovery_agree(self):
        baseline = conformance.baseline_table(conformance.BASELINE.read_text())
        other = conformance.baseline_table(conformance.CROSSCHECK.read_text())
        self.assertEqual(baseline["counts"], other["counts"])
        self.assertEqual(sum(baseline["counts"].values()), 1518)
        # The full table also includes generated *_case support modules and an
        # arena-filtered row: 95 selected-zero rows, all pinned individually.
        self.assertEqual(sum(count == 0 for count in baseline["counts"].values()), 95)
        self.assertEqual(baseline["counts"]["migrated/propagation"], 9)
        sweep = conformance.imported("selftest_s1", conformance.ROOT / "experiments/new-core-s1-20261005/conformance.py")
        args = argparse.Namespace(set="all", include_arena=False, files=[], modes="debug,release",
                                  leakcheck=True, verify=True)
        expected, total = conformance.selection(sweep, args, baseline["counts"], None)
        self.assertEqual(expected, baseline["counts"])
        self.assertEqual(total, 1518)
        args.set = None
        subset, selected_total = conformance.selection(sweep, args, baseline["counts"], None)
        self.assertEqual(set(subset), set(sweep.S1))
        self.assertEqual(selected_total, sum(baseline["counts"][name] for name in sweep.S1))
        self.assertGreater(selected_total, 0)
        inputs = conformance.baseline_inputs(conformance.ROOT, baseline["source_commit"])
        self.assertTrue(inputs)
        self.retained("authoritative-input-identities", inputs)
        self.retained("authoritative-counts", baseline)

    def test_full_conformance_requires_leak_and_fact_checks(self):
        baseline = conformance.baseline_table(conformance.BASELINE.read_text())
        sweep = conformance.imported("selftest_full_flags", conformance.ROOT / "experiments/new-core-s1-20261005/conformance.py")
        for leak, verify in ((False, False), (False, True), (True, False)):
            args = argparse.Namespace(set="all", include_arena=False, files=[], modes="debug,release",
                                      leakcheck=leak, verify=verify)
            with self.subTest(leak=leak, verify=verify), self.assertRaisesRegex(ValueError, "leakcheck and verify"):
                conformance.selection(sweep, args, baseline["counts"], None)
        self.assertEqual(provenance.scope(1), "diagnostic")
        self.assertEqual(provenance.scope(50), "package")
        self.assertEqual(provenance.scope(200, final=True), "final")
        with self.assertRaisesRegex(ValueError, "200"):
            provenance.scope(50, final=True)

    def test_live_phase_rejects_edits_additions_removals_and_alias_retargets(self):
        folder = AREA / "live-phase"
        folder.mkdir()
        leaf, dependency = folder / "leaf.my", folder / "dep.my"
        leaf.write_text("module leaf\n\ndef value() -> int:\n    return 7\n")
        dependency.write_text("module dep\nimport leaf\n")
        phase = provenance.InputPhase(folder)
        phase.check()
        before = leaf.stat()
        leaf.write_text(leaf.read_text().replace("return 7", "return 8"))
        os.utime(leaf, ns=(before.st_atime_ns, before.st_mtime_ns))
        with self.assertRaisesRegex(ValueError, "live qualification inputs changed"):
            phase.check()
        phase = provenance.InputPhase(folder)
        added = folder / "app.cases.json"
        added.write_text('{"providers": {"dep.my": "changed"}}\n')
        with self.assertRaises(ValueError):
            phase.check()
        phase = provenance.InputPhase(folder)
        dependency.unlink()
        with self.assertRaises(ValueError):
            phase.check()
        alias = folder / "selected.api"
        alias.symlink_to("leaf.my")
        dependency.write_bytes(leaf.read_bytes())
        phase = provenance.InputPhase(folder)
        alias.unlink()
        alias.symlink_to("dep.my")
        with self.assertRaises(ValueError):
            phase.check()
        self.retained("live-phase-generations", phase.record())

    def test_live_phase_guards_config_absence_and_registered_outputs_only(self):
        folder = AREA / "live-phase-outputs"
        folder.mkdir()
        (folder / "app.my").write_text("def main() -> int:\n    return 0\n")
        config = AREA / "outside-mylang.json"
        output, cache = folder / "generated-executable", folder / "owned-cache"
        phase = provenance.InputPhase(folder, (config,), (output, cache))
        output.write_bytes(b"owned generated output")
        cache.mkdir()
        (cache / "object").write_bytes(b"owned generated object")
        phase.check()
        config.write_text('{"version":1}\n')
        with self.assertRaises(ValueError):
            phase.check()
        config.unlink()
        phase = provenance.InputPhase(folder, (config,), (output, cache))
        (folder / "unexpected-output").write_bytes(b"not registered to any producer")
        with self.assertRaises(ValueError):
            phase.check()

    def test_deliberate_phase_mutation_rejects_unrelated_edits(self):
        folder = AREA / "deliberate-phase"
        folder.mkdir()
        leaf, config = folder / "leaf.my", folder / "mylang.json"
        leaf.write_text("return 7\n")
        config.write_text('{"version":1}\n')
        phase = provenance.InputPhase(folder)
        phase.check()
        leaf.write_text("return 8\n")
        phase.advance((leaf,))
        phase.check()
        leaf.write_text("return 9\n")
        config.write_text('{"version":2}\n')
        with self.assertRaisesRegex(ValueError, "unrelated input changed"):
            phase.advance((leaf,))

    def test_actual_old_source_origin_rejects_false_label_and_wrong_artifact(self):
        root = conformance.ROOT
        receipt = root / "experiments/new-core-s3-20261006/wave-b/s3-c/resume-context-corrected-oracle.json"
        old = root.parent / "codex-new-core-s4-emission/.mylang-cache/s4-emission/oracle/mylang"
        good = provenance.origin(root, receipt, old, provenance.LEGACY_SOURCE, "old")
        self.assertEqual(good["production_source_commit"], provenance.LEGACY_SOURCE)
        self.assertIsNone(good["build_source_commit"])
        self.assertEqual(good["codec"], "reviewed-s3-c-legacy-v1")
        with self.assertRaisesRegex(ValueError, "asserted source differs"):
            provenance.origin(root, receipt, old, "a16a324e", "old")
        wrong = AREA / "wrong-origin-artifact"
        wrong.write_bytes(b"pure fixture, never executed\n")
        wrong.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "compiler bytes differ"):
            provenance.origin(root, receipt, wrong, provenance.LEGACY_SOURCE, "old")
        with self.assertRaisesRegex(ValueError, "legacy"):
            provenance.origin(root, receipt, old, provenance.LEGACY_SOURCE, "core")
        self.retained("actual-legacy-origin-binding", good)

    def test_canonical_compiler_execution_survives_supplied_alias_retarget(self):
        first, second = AREA / "canonical-old-fixture", AREA / "canonical-core-fixture"
        first.write_text("old fixture, never executed")
        second.write_text("core fixture, never executed")
        for path in (first, second):
            path.chmod(0o755)
        alias = AREA / "supplied-core-fixture"
        alias.symlink_to(second)
        tool = argparse.Namespace(mylang=str(first), core=str(alias))
        receipt = {"oracles": support.distinct_oracles(first, alias)}
        provenance.bind_compilers(tool, receipt)
        alias.unlink()
        alias.symlink_to(first)
        self.assertEqual(tool.core, str(second))
        self.assertEqual(support.identity(tool.core), receipt["oracles"]["core"])
        self.assertNotEqual(support.identity(alias), receipt["oracles"]["core"])

    def test_package_scope_rejects_genuine_historical_core_source_differences(self):
        receipt = {"core_source_diff": ["src/core/driver.zig"]}
        provenance.bind_scope(receipt, "diagnostic")
        self.assertEqual(receipt["scope"], "diagnostic")
        for selected_scope in ("package", "final"):
            with self.subTest(scope=selected_scope), self.assertRaisesRegex(ValueError, "active package compiler source"):
                provenance.bind_scope(receipt, selected_scope)
        receipt["core_source_diff"] = []
        provenance.bind_scope(receipt, "package")
        self.assertEqual(receipt["scope"], "package")
        with self.assertRaisesRegex(ValueError, "invalid qualification scope"):
            provenance.bind_scope(receipt, "historical")

    def test_actual_fresh_core_origin_and_incomplete_generation_refusal(self):
        receipt = conformance.ROOT.parent / "codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/site-control-core-origin-02/summary.json"
        value = json.loads(receipt.read_text())
        good = provenance.origin(conformance.ROOT, receipt, value["compiler"]["path"], value["source_commit"], "core")
        self.assertNotEqual(good["production_source_commit"], good["build_source_commit"])
        self.retained("actual-fresh-core-origin-binding", good)
        broken = {**value, "inputs_after": []}
        with self.assertRaisesRegex(ValueError, "generations changed"):
            provenance.control_origin(conformance.ROOT, broken, "core")
        broken = {**value, "source_files": value["source_files"][:-1]}
        with self.assertRaisesRegex(ValueError, "inventory is incomplete"):
            provenance.control_origin(conformance.ROOT, broken, "core")
        broken = {**value, "helpers": {**value["helpers"], "origin": {"path": "unreviewed", "sha256": "0" * 64}}}
        with self.assertRaisesRegex(ValueError, "not reviewed"):
            provenance.control_origin(conformance.ROOT, broken, "core")

    def fuzz_fixture(self, name):
        area = AREA / name
        area.mkdir()
        evidence, cache = area / "evidence", area / "cache"
        (evidence / "sources").mkdir(parents=True)
        cache.mkdir()
        old, core = area / "old-fixture", area / "core-fixture"
        for path in (old, core):
            path.write_text("fixture only, never executed: " + path.name)
            path.chmod(0o755)
        args = argparse.Namespace(kind="s0", cases=1, seed=1, old=old, new=core,
                                  evidence=evidence, cache_root=cache)
        return area, args

    def test_guarded_strict_fuzz_rejects_mode_change_and_during_build_mutation(self):
        # Real inherited monitor and actual S4 subclass, with synthetic process
        # results injected only in this unit test; no compiler/guest is launched.
        for during in (False, True):
            area, args = self.fuzz_fixture("strict-guard-" + str(during))
            work = area / "inputs"
            work.mkdir()
            source = work / "case.my"
            source.write_text("def main() -> int:\n    for i in range(3):\n        pass\n    return 0\n")
            monitor = fuzz.guarded_monitor(fuzz.strict_wrapper().Monitor)(args, None)
            calls = []

            def simulated(argv, *positional, **options):
                calls.append(argv)
                if during:
                    source.write_text("def main() -> int:\n    return 0\n")
                return subprocess.CompletedProcess(argv, 0, b"0\n", b"")

            monitor.original_run = simulated
            try:
                old = [str(args.old), "build", str(source), "-o", str(area / "old-output")]
                if during:
                    with self.assertRaisesRegex(ValueError, "changed"):
                        monitor.run(old)
                else:
                    monitor.run(old)
                    source.write_text("def main() -> int:\n    return 0\n")
                    with self.assertRaisesRegex(ValueError, "changed"):
                        monitor.run([str(args.new), "build", str(source), "-o", str(area / "core-output")])
                self.assertEqual(len(calls), 1)
            finally:
                monitor.journal.close()
            self.retained("strict-guard-result-" + str(during), {"synthetic_process_results": True,
                "compiler_processes": 0, "calls": calls, "inventory": support.identity(monitor.inputs.directory / "inventory.json")})

    def test_fuzz_closure_guards_import_provider_policy_embed_and_membership(self):
        for changed in ("dep.my", "case.cases.json", "case.api", "asset.bin", "policy", "new.my", "mylang.json"):
            area, args = self.fuzz_fixture("closure-" + changed.replace(".", "-"))
            work = area / "inputs"
            work.mkdir()
            source = work / "case.my"
            source.write_text("import dep\ndef main() -> int:\n    return dep.value()\n")
            for name in ("dep.my", "case.cases.json", "case.api", "asset.bin", "policy"):
                (work / name).write_text("retained input bytes")
            (work / "mylang.json").write_text('{"version":1,"import_policy":"policy"}\n')
            inputs = provenance.FuzzInputs(args)
            inputs.before([str(args.old), "build", str(source), "-o", str(work / "old-output")])
            inputs.check()
            (work / changed).write_text("changed input bytes")
            with self.subTest(changed=changed), self.assertRaises((ValueError, json.JSONDecodeError)):
                inputs.check()

    def test_fuzz_next_case_requires_completed_previous_phase(self):
        area, args = self.fuzz_fixture("next-case-phase")
        work = area / "inputs"
        work.mkdir()
        first, second = work / "case0.my", work / "case1.my"
        first.write_text("def main() -> int:\n    return 0\n")
        monitor = fuzz.guarded_monitor(fuzz.strict_wrapper().Monitor)(args, None)
        monitor.original_run = lambda argv, *a, **kw: subprocess.CompletedProcess(argv, 0, b"0\n", b"")
        try:
            monitor.run([str(args.old), "build", str(first), "-o", str(work / "case0-old")])
            second.write_text("def main() -> int:\n    return 1\n")
            with self.assertRaisesRegex(ValueError, "prior case completed"):
                monitor.run([str(args.old), "build", str(second), "-o", str(work / "case1-old")])
            second.unlink()
            for mode, executable, flags in (("debug", args.new, []), ("release", args.new, ["--release"]),
                                             ("verify", args.new, ["--release", "--verify-facts"])):
                output = work / ("case0-" + mode)
                monitor.run([str(executable), "build", str(first), "-o", str(output), *flags])
                for number in range(5):
                    monitor.run([str(work / "case0-old"), str(number)])
                    monitor.run([str(output), str(number)])
            second.write_text("def main() -> int:\n    return 1\n")
            monitor.run([str(args.old), "build", str(second), "-o", str(work / "case1-old")])
            self.assertEqual(len(monitor.inputs.sources), 2)
        finally:
            monitor.journal.close()

    def test_fuzz_cleanup_preserves_paths_and_validates_before_removal(self):
        for style in ("mkdtemp", "temporary"):
            area, args = self.fuzz_fixture("cleanup-" + style)
            inputs = provenance.FuzzInputs(args)
            with provenance.GeneratorCleanup(inputs, [Path(__file__)]):
                if style == "mkdtemp":
                    work = Path(tempfile.mkdtemp(dir=area))
                    source = work / "case.my"
                    source.write_text("def main() -> int:\n    return 0\n")
                    argv = [str(args.old), "build", str(source), "-o", str(work / "old-output")]
                    retained = list(argv)
                    inputs.before(argv)
                    self.assertEqual(argv, retained)
                    shutil.rmtree(work)
                else:
                    with tempfile.TemporaryDirectory(dir=area) as temporary:
                        work = Path(temporary)
                        source = work / "case.my"
                        source.write_text("def main() -> int:\n    return 0\n")
                        inputs.before([str(args.old), "build", str(source), "-o", str(work / "old-output")])
                inputs.finish()
            self.assertFalse(work.exists())
            self.assertEqual(len(inputs.cleanup_proofs), 1)
            self.assertTrue(inputs.cleanup_proofs[0]["cleanup_complete"])
            self.retained("proved-cleanup-" + style, inputs.cleanup_proofs)

    def test_fuzz_cleanup_rejects_last_minute_edit_and_unproved_removal(self):
        area, args = self.fuzz_fixture("cleanup-invalid")
        inputs = provenance.FuzzInputs(args)
        with provenance.GeneratorCleanup(inputs, [Path(__file__)]):
            work = Path(tempfile.mkdtemp(dir=area))
            source = work / "case.my"
            source.write_text("def main() -> int:\n    return 0\n")
            inputs.before([str(args.old), "build", str(source), "-o", str(work / "old-output")])
            source.write_text("def main() -> int:\n    return 1\n")
            with self.assertRaisesRegex(ValueError, "changed"):
                shutil.rmtree(work)
            self.assertTrue(source.exists())
        # Removal through a function that was not the scoped owned cleanup hook
        # cannot be mistaken for successful intentional generator cleanup.
        shutil.rmtree(work)
        with self.assertRaisesRegex(ValueError, "changed"):
            inputs.finish()

    def test_final_matrix_rechecks_completed_worker_inputs(self):
        area, args = self.fuzz_fixture("completed-worker")
        work = area / "inputs"
        work.mkdir()
        source = work / "case.my"
        source.write_text("def main() -> int:\n    return 0\n")
        inputs = provenance.FuzzInputs(args)
        inputs.before([str(args.old), "build", str(source), "-o", str(work / "old-output")])
        inputs.finish()
        summary = {"input_inventory": support.identity(inputs.directory / "inventory.json"),
                   "intentional_cleanups": inputs.cleanup_proofs}
        self.assertTrue(provenance.fuzz_unchanged(summary))
        source.write_text("def main() -> int:\n    return 1\n")
        with self.assertRaisesRegex(ValueError, "before final aggregate"):
            provenance.fuzz_unchanged(summary)

    def test_identical_oracles_and_before_after_snapshots(self):
        folder = AREA / "snapshot-project"
        folder.mkdir()
        leaf = folder / "leaf.my"
        leaf.write_bytes(b"module leaf\n\ndef value() -> int:\n    return 1\n")
        before = support.snapshot(folder, AREA / "snapshot-before")
        leaf.write_bytes(b"module leaf\n\ndef value() -> int:\n    return 2\n")
        after = support.snapshot(folder, AREA / "snapshot-after")
        self.assertNotEqual(before["files"]["leaf.my"]["sha256"], after["files"]["leaf.my"]["sha256"])
        self.assertIn(b"return 1", Path(before["files"]["leaf.my"]["path"]).read_bytes())
        first, second = AREA / "oracle-one", AREA / "oracle-copy"
        first.write_bytes(b"#!/bin/sh\nexit 0\n")
        second.write_bytes(first.read_bytes())
        first.chmod(0o755)
        second.chmod(0o755)
        for other in (first, second):
            with self.subTest(other=other.name), self.assertRaisesRegex(ValueError, "distinct"):
                support.distinct_oracles(first, other)

    def test_timeout_kills_reaps_descendants_and_retains_partial_raw_output(self):
        # Both descendants create new sessions, like a nested local fuzz worker.
        child = ("import subprocess,sys,time,os\n"
                 "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'],start_new_session=True)\n"
                 "os.write(2,('grandchild=%d\\n'%p.pid).encode())\n"
                 "time.sleep(30)\n")
        parent = ("import subprocess,sys,time,os\n"
                  f"p=subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True)\n"
                  "os.write(1,b'partial\\xff\\n')\n"
                  "os.write(2,('child=%d\\n'%p.pid).encode())\n"
                  "time.sleep(30)\n")
        fixture = AREA / "timeout-parent.py"
        fixture.write_text(parent)
        capture = support.Capture(AREA / "timeout-processes", AREA)
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            capture.run([sys.executable, str(fixture)], capture_output=True, text=True, timeout=0.5)
        error = caught.exception
        self.assertEqual(error.stdout, b"partial\xff\n")
        pids = [int(line.split(b"=")[1]) for line in error.stderr.splitlines()]
        self.assertEqual(len(pids), 2)
        for pid in pids:
            try:
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
                with self.assertRaises(ChildProcessError):
                    os.waitpid(pid, os.WNOHANG)
            finally:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        saved = json.loads((AREA / "timeout-processes/command-00001.json").read_text())
        self.assertTrue(saved["timed_out"])
        self.assertEqual(Path(saved["stdout"]["path"]).read_bytes(), error.stdout)
        self.assertEqual(Path(saved["stderr"]["path"]).read_bytes(), error.stderr)
        self.assertEqual(support.identity(saved["stdout"]["path"]), saved["stdout"])

    def test_source_tool_manifest_binds_paths_and_exact_bytes(self):
        names = ("old-fixture", "core-fixture", "zig-fixture", "qbe-fixture")
        for name in names:
            path = AREA / name
            path.write_bytes(("fixture " + name + "\n").encode())
            path.chmod(0o755)
        arguments = argparse.Namespace(old_source="HEAD", core_source="HEAD",
            zig=AREA / "zig-fixture", qbe=AREA / "qbe-fixture")
        environment = {key: os.environ.get(key) for key in ("MYLANG_ZIG", "MYLANG_QBE")}
        try:
            receipt = support.manifest(conformance.ROOT, AREA / "old-fixture", AREA / "core-fixture",
                arguments, [Path(__file__)])
            self.assertEqual(receipt["tools"]["zig"], support.identity(arguments.zig))
            self.assertEqual(receipt["tools"]["qbe"], support.identity(arguments.qbe))
            self.assertEqual(os.environ["MYLANG_ZIG"], str(arguments.zig))
            self.assertEqual(os.environ["MYLANG_QBE"], str(arguments.qbe))
            self.assertEqual(receipt["compiler_sources"]["old"], receipt["source_commit"])
            self.retained("fixture-manifest", {"test_fixtures_only": True, **receipt})
            arguments.qbe.write_bytes(b"changed fixture bytes\n")
            self.assertNotEqual(support.identity(arguments.qbe), receipt["tools"]["qbe"])
        finally:
            for key, value in environment.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    def orphan_fixture(self, folder):
        folder.mkdir()
        child = ("import os,time\nfrom pathlib import Path\n"
                 f"Path({str(folder / 'orphan.pid')!r}).write_text(str(os.getpid()))\n"
                 "os.write(1,b'orphan-partial\\xff\\n')\ntime.sleep(30)\n")
        parent = ("import os,sys,subprocess\n"
                  f"subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True)\n"
                  "os._exit(0)\n")
        fixture = folder / "original-command.py"
        fixture.write_text(parent)
        return fixture

    def test_exited_original_command_orphan_timeout_is_bounded_and_reaped(self):
        folder = AREA / "exited-original"
        fixture = self.orphan_fixture(folder)
        capture = support.Capture(folder / "processes", AREA)
        began = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            capture.run([sys.executable, str(fixture)], capture_output=True, timeout=0.3)
        self.assertLess(time.monotonic() - began, 2)
        self.assertEqual(caught.exception.stdout, b"orphan-partial\xff\n")
        pid = int((folder / "orphan.pid").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        saved = json.loads((folder / "processes/command-00001.json").read_text())
        self.assertTrue(saved["timed_out"])
        self.assertEqual(saved["supervisor_result"]["status"], 0)
        self.assertEqual(saved["supervisor_result"]["remaining_children"], [])

    def test_orphan_cleanup_preserves_concurrent_commands(self):
        folder = AREA / "concurrent-isolation"
        fixture = self.orphan_fixture(folder)
        capture = support.Capture(folder / "processes", AREA)

        def command(label):
            if label == "orphan":
                with self.assertRaises(subprocess.TimeoutExpired) as caught:
                    capture.run([sys.executable, str(fixture)], capture_output=True, timeout=0.3)
                return caught.exception.stdout
            script = "import time,os;time.sleep(0.8);os.write(1," + repr(label.encode()) + ")"
            result = capture.run([sys.executable, "-c", script], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0)
            return result.stdout

        with ThreadPoolExecutor(max_workers=3) as workers:
            actual = list(workers.map(command, ("survivor-A", "orphan", "survivor-B")))
        self.assertEqual(actual, [b"survivor-A", b"orphan-partial\xff\n", b"survivor-B"])
        self.assertFalse(Path(f"/proc/{int((folder / 'orphan.pid').read_text())}").exists())

    def test_final_fuzz_requires_200_cases_for_each_of_nine_kinds(self):
        oracles = {"old": {"path": "old", "sha256": "old-hash"},
                   "new": {"path": "core", "sha256": "core-hash"}}
        total = 0
        for kind in fuzz.KINDS:
            comparisons = 200 * (9 if kind == "rc" else 15)
            summary = {"kind": kind, "qualified": True, "complete": True,
                "native_complete": True, "oracle_unchanged": True, "inputs_unchanged": True,
                "cases_requested": 200, "cases_seen": 200, "accepted": 200,
                "comparisons_expected": comparisons, "native_comparisons": comparisons,
                "old_rejected": 0, "core_refused": 0, "core_build_failed": 0,
                "harness_status": 0, "failures": [], "error": None, "oracles": oracles}
            self.assertTrue(fuzz.qualified_kind(0, summary, kind, 200, oracles))
            self.assertFalse(fuzz.qualified_kind(0, summary, kind, 50, oracles))
            for key, value in (("accepted", 200.0), ("native_comparisons", comparisons - 1),
                               ("native_complete", False), ("old_rejected", 1)):
                wrong = {**summary, key: value}
                with self.subTest(kind=kind, key=key):
                    self.assertFalse(fuzz.qualified_kind(0, wrong, kind, 200, oracles))
            total += comparisons
        self.assertEqual(len(fuzz.KINDS), 9)
        self.assertEqual(total, 25800)


def main():
    global AREA
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    AREA = args.evidence.resolve()
    AREA.mkdir(parents=True, exist_ok=False)
    sources = [Path(__file__), Path(conformance.__file__), Path(projects.__file__), Path(support.__file__),
               Path(provenance.__file__), Path(__file__).with_name("fuzz_matrix.py")]
    before = [support.identity(path) for path in sources]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(QualificationTests))
    after = [support.identity(path) for path in sources]
    passed = result.wasSuccessful() and before == after
    (AREA / "summary.json").write_text(json.dumps({"sources": before, "source_unchanged": before == after,
        "tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "qualified": passed}, indent=2) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
