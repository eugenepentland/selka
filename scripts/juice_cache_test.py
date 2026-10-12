#!/usr/bin/env python3
"""Coordinator qualification with simulated native captures and real evidence/watches."""
from contextlib import ExitStack, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import juice_cache as cache
import juice_evidence as evidence


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Host:
    identity = {"host": "fixture"}

    def unchanged(self):
        return True


class Coordinator(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="juice-coordinator-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.binary = self.root / "compiler"
        self.binary.write_text("#!/bin/sh\nexit 0\n")
        self.binary.chmod(0o755)
        (self.root / "shared").write_bytes(b"shared helper")
        self.contract = self.root / "suite.json"
        rows = []
        for name in ("alpha", "beta", "gamma"):
            (self.root / name).mkdir()
            (self.root / name / "input").write_bytes(name.encode())
            (self.root / name / "manifest.json").write_text(json.dumps({"name": name}))
            rows.append({"id": name, "manifest": name + "/manifest.json", "workload": "tiny",
                         "dependencies": ["shared"] if name != "gamma" else [],
                         "reuse": "historical", "complete": True})
        self.contract.write_text(json.dumps({"version": "juice-suite-v1", "workloads": rows}))
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.root)}
        self.calls = []
        self.limits = []
        self.before = self.after = None
        self.fail = False
        self.interrupt = None
        self.providers = {"plain": {}}
        self.search_scopes = []
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(cache, "ROOT", self.root))
        self.stack.enter_context(patch.object(cache, "IMPLEMENTATION_INPUTS", []))
        self.stack.enter_context(patch.object(cache, "plan", side_effect=self.plan))
        self.stack.enter_context(patch.object(cache, "tool_paths", return_value=[]))
        self.stack.enter_context(patch.object(cache, "provider_tools", return_value=cache.juice_provider.Tools(
            self.binary, self.binary, self.binary, self.binary)))
        self.stack.enter_context(patch.object(cache.juice_provider, "search_scopes", side_effect=lambda *_: self.search_scopes))
        self.stack.enter_context(patch.object(cache.juice_provider, "resolve", side_effect=lambda *_: self.providers))
        self.stack.enter_context(patch.object(cache.identity, "tools", side_effect=lambda _env, binaries, _zig: ([], binaries)))
        self.stack.enter_context(patch.object(cache.verification, "normalized_environment", side_effect=lambda _root: dict(self.env)))
        self.stack.enter_context(patch.object(cache.verification, "HostContext", Host))
        self.stack.enter_context(patch.object(cache.verification, "run_admitted", side_effect=self.admitted))

    def plan(self, args, spec, env):
        manifest = Path(spec["manifest"])
        root = manifest.parent
        name = json.loads(manifest.read_text())["name"]
        work = {"name": "tiny", "units": 1, "unit": "item", "outputs": [],
                "expected_stdout": "ok\n", "expected_stderr": "", "check": []}
        collector = {"kind": args.collector, "profile": args.profile,
                     "cpu": args.cpu or 0, "event": "instructions:u", "tool": {"path": str(self.binary)}}
        native_cache = args.cache_dir / "native" / name
        configuration = {"compiler": {"path": str(self.binary)}, "tools": {}, "spec": {}}
        return {"version": "juice-plan-v1", "manifest_path": str(manifest), "root": str(root),
                "manifest": {"name": name, "adapter": "native", "build": {}, "environment": {}},
                "sources": {"input": digest((root / "input").read_bytes())}, "inputs": {},
                "selected_workloads": [work], "build_config": configuration,
                "implementation": {"embedded_identity": "a" * 64},
                "measurement": {"repeats": args.repeats, "collector": collector,
                                "context": {"collector": collector, "libraries": {},
                                            "system": "Linux", "kernel": "fixture", "machine": "x86_64",
                                            "cpu": {"model": "fixture"}, "execution_path": str(native_cache / "workspace/run")}},
                "paths": {"cache": str(native_cache), "run": str(native_cache / "workspace/run")},
                "input_scopes": {"files": [str(manifest), str(root / "input")], "directories": []}}

    def admitted(self, _root, kind, argv, env, unchanged, timings, limits=None):
        self.assertEqual(kind, "gate")
        self.limits.append(limits)
        self.assertEqual(Path(argv[1]).name, "juice_worker.py")
        argv = argv[2:]
        manifest = Path(argv[3])
        name = manifest.parent.name
        if self.before:
            self.before(name)
        self.assertTrue(unchanged())
        self.calls.append(name)
        if self.interrupt == len(self.calls):
            raise KeyboardInterrupt
        label = argv[argv.index("--name") + 1]
        native_root = Path(argv[argv.index("--cache-dir") + 1]) / name
        record_path = native_root / "records" / label / "record.json"
        record_path.parent.mkdir(parents=True)
        args = self.args("--target", name)
        args.repeats = int(argv[argv.index("--repeats") + 1])
        args.cpu = int(argv[argv.index("--cpu") + 1])
        args.collector = argv[argv.index("--collector") + 1]
        native = self.plan(args, {"manifest": str(manifest)}, env)
        want = cache.expected(native, args)
        record = {"version": "juice-v1", "identity_scheme": "mylang-juice-native-v1",
                  "name": label, "status": "complete", "tool_id": "a" * 64,
                  "source_root": str(manifest.parent), "sources": native["sources"],
                  "manifest": native["manifest"], "contract": want["contract"],
                  "build_config": native["build_config"], "collector": want["collector"],
                  "context": native["measurement"]["context"]}
        body = (manifest.parent / "input").read_bytes()
        plain = native_root / "builds" / digest(body) / "plain"
        plain.parent.mkdir(parents=True, exist_ok=True)
        plain.write_bytes(body)
        record["build"] = {"key": digest(body), "artifacts": {"plain": digest(body)}}
        raw, samples = {}, []
        for index in range(args.repeats):
            prefix = f"tiny-{index}-sample"
            files = {prefix + ".stdout": b"ok\n", prefix + ".stderr": b"",
                     prefix + ".perf": b"100;;instructions:u;1000;100.00;;\n"}
            for filename, data in files.items():
                (record_path.parent / filename).write_bytes(data)
                raw[filename] = digest(data)
            samples.append({"exit_code": 0, "wall_seconds": 0.001, "stdout_sha256": digest(b"ok\n"),
                            "stderr_sha256": digest(b""), "metrics": {"instructions": 100}, "functions": [], "lines": []})
        record["evidence"] = raw
        record["context"]["libraries"] = dict((self.providers or {}).get("plain", {}))
        record["workloads"] = {"tiny": {"units": 1, "unit": "item", "samples": samples,
            "correctness": {"stdout": digest(b"ok\n"), "stderr": digest(b""), "files": {}},
            "metrics": {"instructions": {"samples": [100] * args.repeats, "median": 100,
                                          "min": 100, "max": 100, "spread": 0}}, "functions": [], "lines": []}}
        record_path.write_text(json.dumps(record))
        timings.append({"kind": kind, "observed_held_seconds": 0.01})
        if self.after:
            self.after(name)
        return int(self.fail), 0.01

    def args(self, *extra):
        return cache.options(["capture", str(self.contract), "--compiler", str(self.binary),
                              "--cache-dir", str(self.root / "cache"), *extra])

    def capture(self, *extra):
        with redirect_stdout(io.StringIO()):
            status = cache.execute(self.args(*extra))
        return status, cache.document(self.root / "cache/last-run.json")

    def test_shared_measurements_reuse_without_admission_and_outputs_stay_private(self):
        shared = self.root / "shared-evidence"
        args = ("--target", "alpha", "--shared-cache-dir", str(shared))
        _, cold = self.capture(*args)
        self.calls.clear()
        _, warm = self.capture(*args)
        self.assertEqual((self.calls, warm["counts"]), ([], {"executed": 0, "reused": 1, "admissions": 0}))
        self.assertEqual(cold["actions"][0]["key"], warm["actions"][0]["key"])
        self.assertTrue(Path(warm["actions"][0]["record"]).is_relative_to(self.root / "cache/runs"))
        self.assertFalse((shared / "runs").exists())
        self.assertTrue(warm["evidence_store"]["shared"])
        self.assertGreater(warm["snapshot_statistics"]["files_hashed"], 0)

    def test_shared_workload_path_change_remains_an_exact_identity_miss(self):
        shared = self.root / "shared-evidence"
        _, cold = self.capture("--target", "alpha", "--shared-cache-dir", str(shared))
        other = self.root / "compiler-at-other-path"
        other.write_bytes(self.binary.read_bytes())
        other.chmod(0o755)
        self.calls.clear()
        _, moved = self.capture("--target", "alpha", "--shared-cache-dir", str(shared), "--compiler", str(other))
        self.assertEqual(self.calls, ["alpha"])
        self.assertNotEqual(cold["actions"][0]["key"], moved["actions"][0]["key"])

    def test_shared_gc_cannot_remove_lazy_evidence_during_materialization(self):
        shared = self.root / "shared-evidence"
        args = ("--target", "alpha", "--shared-cache-dir", str(shared))
        self.capture(*args)
        materialize = evidence.EvidenceStore.materialize
        observed = []
        def protected(retained, destination):
            observed.append(cache.fuzz_campaign_store.Store(shared).gc(dry_run=False))
            return materialize(retained, destination)
        with patch.object(evidence.EvidenceStore, "materialize", side_effect=protected):
            _, warm = self.capture(*args)
        self.assertEqual(warm["counts"]["reused"], 1)
        self.assertTrue(observed[0]["skipped_active"])

    def test_shared_store_cannot_overlap_declared_source_scope(self):
        source = self.root / "alpha"
        original = self.plan
        def scoped(*arguments):
            value = original(*arguments)
            value["input_scopes"]["directories"] = [str(source)]
            return value
        with patch.object(cache, "plan", side_effect=scoped), self.assertRaisesRegex(ValueError, "overlap"):
            self.capture("--target", "alpha", "--shared-cache-dir", str(source / "shared-evidence"))
        self.assertEqual(self.calls, [])

    def policies(self, **fields):
        value = cache.document(self.contract)
        for row in value["workloads"]:
            row.update(fields)
        self.contract.write_text(json.dumps(value))

    def test_invalid_work_controls_are_rejected_before_admission(self):
        for flag, value in (("--max-actions", "0"), ("--action-timeout", "nan"), ("--action-timeout", "-1")):
            with self.assertRaises(SystemExit) as failure, patch("sys.stderr", io.StringIO()):
                self.capture(flag, value)
            self.assertEqual(2, failure.exception.code)
        self.assertEqual([], self.calls)

    def test_work_cap_reports_partial_resumes_and_does_not_charge_reuse(self):
        status, partial = self.capture("--max-actions", "1")
        self.assertEqual(3, status)
        self.assertFalse(partial["complete"])
        self.assertTrue(partial["work_budget"]["exhausted"])
        self.assertEqual(["beta", "gamma"], partial["outstanding"])
        self.calls.clear()
        status, resumed = self.capture()
        self.assertEqual((0, ["beta", "gamma"]), (status, self.calls))
        self.assertEqual(1, resumed["counts"]["reused"])
        self.calls.clear()
        status, warm = self.capture("--max-actions", "1")
        self.assertEqual((0, []), (status, self.calls))
        self.assertTrue(warm["complete"])
        self.assertEqual([], warm["outstanding"])

    def test_action_deadline_is_explicit_and_identity_bound(self):
        self.capture("--target", "alpha", "--action-timeout", "7")
        self.assertEqual(7, self.limits[-1].timeout_seconds)
        self.calls.clear()
        self.capture("--target", "alpha", "--action-timeout", "8")
        self.assertEqual(["alpha"], self.calls)
        self.assertEqual(8, self.limits[-1].timeout_seconds)

    def test_warm_reuses_before_admission_and_labels_historical_evidence(self):
        status, cold = self.capture()
        self.assertEqual((0, 3), (status, cold["counts"]["executed"]))
        self.calls.clear()
        status, warm = self.capture()
        self.assertEqual((0, []), (status, self.calls))
        self.assertEqual({"executed": 0, "reused": 3, "admissions": 0}, warm["counts"])
        self.assertTrue(all(not row["fresh"] and row["policy"] == "historical" for row in warm["actions"]))

    def test_private_edit_runs_only_its_workload_and_revert_reuses(self):
        self.capture()
        source = self.root / "alpha/input"
        source.write_bytes(b"edited alpha")
        self.calls.clear()
        _, edited = self.capture()
        self.assertEqual(["alpha"], self.calls)
        self.assertEqual(2, edited["counts"]["reused"])
        source.write_bytes(b"alpha")
        self.calls.clear()
        self.capture()
        self.assertEqual([], self.calls)

    def test_shared_helper_runs_all_consumers_only(self):
        self.capture()
        (self.root / "shared").write_bytes(b"changed shared helper")
        self.calls.clear()
        self.capture()
        self.assertEqual(["alpha", "beta"], self.calls)

    def test_unknown_and_physical_deterministic_contracts_always_run(self):
        self.policies(complete=False)
        self.capture("--target", "alpha")
        self.capture("--target", "alpha")
        self.assertEqual(["alpha", "alpha"], self.calls)
        self.calls.clear()
        self.policies(complete=True, reuse="deterministic")
        self.capture("--target", "alpha")
        self.capture("--target", "alpha")
        self.assertEqual(["alpha", "alpha"], self.calls)

    def test_fresh_failed_capture_does_not_revive_previous_success(self):
        self.capture("--target", "alpha")
        self.fail = True
        status, failed = self.capture("--target", "alpha", "--fresh")
        self.assertEqual(1, status)
        self.assertFalse(failed["complete"])
        self.fail = False
        self.calls.clear()
        self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)

    def test_collector_context_and_repetition_changes_invalidate(self):
        self.capture("--target", "alpha")
        self.calls.clear()
        self.capture("--target", "alpha", "--cpu", "1")
        self.capture("--target", "alpha", "--repeats", "2")
        self.assertEqual(["alpha", "alpha"], self.calls)

    def test_corrupt_retained_raw_bytes_remeasure_only_affected_workloads(self):
        _, cold = self.capture("--target", "alpha")
        store = evidence.EvidenceStore(self.root / "cache/evidence-v2")
        receipt = store.lookup(cold["actions"][0]["key"], cold["actions"][0]["expected"])
        store.backend._path("blobs", receipt.record_digest).write_bytes(b"damaged")
        self.calls.clear()
        _, repaired = self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)
        self.assertTrue(repaired["success"])

    def test_queued_aba_prevents_execution(self):
        def change(_name):
            source = self.root / "alpha/input"
            original = source.read_bytes()
            source.write_bytes(b"temporary")
            source.write_bytes(original)
        self.before = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture("--target", "alpha")
        self.assertEqual([], self.calls)
        self.assertFalse(cache.document(self.root / "cache/last-run.json")["success"])

    def test_runtime_aba_never_publishes_a_receipt(self):
        def change(_name):
            path = self.root / "shared"
            original = path.read_bytes()
            path.write_bytes(b"temporary")
            path.write_bytes(original)
        self.after = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture("--target", "alpha")
        self.after = None
        self.calls.clear()
        self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)

    def test_cancellation_preserves_only_completed_actions(self):
        self.interrupt = 2
        with self.assertRaises(KeyboardInterrupt):
            self.capture()
        self.assertFalse(cache.document(self.root / "cache/last-run.json")["complete"])
        self.interrupt = None
        self.calls.clear()
        _, resumed = self.capture()
        self.assertEqual(["beta", "gamma"], self.calls)
        self.assertEqual(1, resumed["counts"]["reused"])

    def test_guard_of_previously_reused_workload_remains_live(self):
        self.capture()
        (self.root / "beta/input").write_bytes(b"changed beta")
        def change(_name):
            path = self.root / "alpha/input"
            path.write_bytes(b"changed alpha")
        self.after = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture()
        self.assertFalse(cache.document(self.root / "cache/last-run.json")["complete"])

    def test_injection_environment_and_loaded_validator_changes_miss(self):
        self.capture("--target", "alpha")
        self.calls.clear()
        with patch.object(evidence, "LOADED_CODE_SHA256", "different"):
            self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)
        self.env["LD_PRELOAD"] = "unsupported"
        self.calls.clear()
        self.capture("--target", "alpha")
        self.capture("--target", "alpha")
        self.assertEqual(["alpha", "alpha"], self.calls)

    def test_threshold_only_comparison_never_admits_measurements(self):
        _, capture = self.capture("--target", "alpha")
        report = self.root / "saved-run.json"
        report.write_text(json.dumps(capture))
        self.calls.clear()
        commands = []
        def decision(argv, **_kwargs):
            commands.append(argv)
            return type("Result", (), {"returncode": 1 if argv[-1] == "99.0" else 0})()
        with patch.object(cache.subprocess, "run", side_effect=decision):
            for threshold, expected_status in ((101, 0), (99, 1)):
                args = cache.options(["compare", str(report), str(report), "--compiler", str(self.binary),
                                      "--output", str(self.root / ("decision-" + str(threshold))),
                                      "--fail-above", str(threshold)])
                self.assertEqual(expected_status, cache.compare(args))
        self.assertEqual([], self.calls)
        self.assertEqual(2, len(commands))
        self.assertTrue(all(argv[1:3] == ["juice", "compare"] for argv in commands))

    def test_uncovered_library_cannot_borrow_another_workloads_contract(self):
        self.capture("--target", "alpha")
        with cache.Snapshot(self.root, ["shared"]) as one, cache.Snapshot(self.root, ["gamma/input"]) as other:
            record = {"context": {"libraries": {str(self.root / "gamma/input"): digest(b"gamma")}}}
            self.assertFalse(cache.covered_libraries(record, [one]))
            self.assertTrue(cache.covered_libraries(record, [other]))

    def test_killed_comparator_cannot_publish_a_success(self):
        _, captured = self.capture("--target", "alpha")
        report = self.root / "saved-run.json"
        report.write_text(json.dumps(captured))
        output = self.root / "comparison"
        args = cache.options(["compare", str(report), str(report), "--output", str(output),
                              "--compiler", str(self.binary)])
        with patch.object(cache.subprocess, "run", return_value=type("Result", (), {"returncode": -15})()):
            self.assertEqual(143, cache.compare(args))
        decisions = cache.document(output / "decisions.json")
        self.assertFalse(decisions["complete"])
        self.assertFalse(decisions["success"])

    def test_capture_report_cannot_overwrite_suite_manifest_or_dependency(self):
        for path in (self.contract, self.root / "alpha/manifest.json", self.root / "alpha/input", self.root / "shared"):
            with self.subTest(path=path):
                original = path.read_bytes()
                with self.assertRaisesRegex(ValueError, "overlaps"):
                    self.capture("--report", str(path))
                self.assertEqual(original, path.read_bytes())
        self.assertEqual([], self.calls)

    def test_comparison_output_cannot_overwrite_its_declaration(self):
        output = self.root / "comparison"
        output.mkdir()
        report = output / "decisions.json"
        report.write_bytes(b"preserve input")
        args = cache.options(["compare", str(report), str(report), "--output", str(output),
                              "--compiler", str(self.binary)])
        with self.assertRaisesRegex(ValueError, "overlaps"):
            cache.compare(args)
        self.assertEqual(b"preserve input", report.read_bytes())

    def test_comparison_rejects_path_traversal_ids(self):
        _, captured = self.capture("--target", "alpha")
        captured["actions"][0]["id"] = "../escape"
        path = self.root / "bad-run.json"
        path.write_text(json.dumps(captured))
        with self.assertRaisesRegex(ValueError, "invalid comparison workload"):
            cache.comparison_rows(path)

    def test_artifact_aba_during_provider_inspection_cannot_publish(self):
        def inspect(artifacts, *_args):
            artifact = artifacts["plain"]
            original = artifact.read_bytes()
            artifact.write_bytes(b"different ELF provider contract")
            artifact.write_bytes(original)
            return self.providers
        with patch.object(cache.juice_provider, "resolve", side_effect=inspect):
            with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
                self.capture("--target", "alpha")
        self.calls.clear()
        _, result = self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)
        self.assertTrue(result["actions"][0]["qualified"])

    def test_source_mutation_during_final_capture_report_revokes_success(self):
        original = cache.verification.atomic_record
        def publish(path, state):
            original(path, state)
            if state.get("version") == "juice-run-v1" and state.get("complete"):
                source = self.root / "alpha/input"
                source.write_bytes(b"changed during publication")
        with patch.object(cache.verification, "atomic_record", side_effect=publish):
            with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
                self.capture("--target", "alpha")
        state = cache.document(self.root / "cache/last-run.json")
        self.assertFalse(state["complete"])
        self.assertFalse(state["success"])

    def test_previous_retained_outputs_remain_guarded_until_final_report(self):
        self.capture()
        (self.root / "beta/input").write_bytes(b"edit beta")
        def change(_name):
            candidates = list((self.root / "cache/runs").glob("*/retained/build/plain"))
            self.assertTrue(candidates)
            candidates[0].write_bytes(b"changed retained alpha")
        self.after = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture()

    def test_dynamic_providers_require_watched_files_and_current_resolution(self):
        library = self.root / "shared"
        self.providers = {"plain": {str(library): digest(library.read_bytes())}}
        _, cold = self.capture("--target", "alpha")
        self.assertTrue(cold["actions"][0]["qualified"])
        self.calls.clear()
        _, warm = self.capture("--target", "alpha")
        self.assertEqual(1, warm["counts"]["reused"])
        self.providers = {"plain": {}}
        _, changed = self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)
        self.assertEqual(1, changed["counts"]["executed"])

    def test_unbound_runtime_provider_stays_fresh(self):
        library = self.root / "gamma/input"
        self.providers = {"plain": {str(library): digest(library.read_bytes())}}
        for _ in range(2):
            _, result = self.capture("--target", "alpha")
            self.assertFalse(result["actions"][0]["qualified"])
        self.assertEqual(["alpha", "alpha"], self.calls)

    def test_unknown_provider_resolution_stays_fresh(self):
        self.providers = None
        for _ in range(2):
            _, result = self.capture("--target", "alpha")
            self.assertFalse(result["actions"][0]["qualified"])
        self.assertEqual(["alpha", "alpha"], self.calls)

    def test_dynamic_resolution_requires_supported_search_scopes(self):
        self.search_scopes = None
        library = self.root / "shared"
        self.providers = {"plain": {str(library): digest(library.read_bytes())}}
        _, result = self.capture("--target", "alpha")
        self.assertFalse(result["actions"][0]["qualified"])

    def test_provider_search_candidate_aba_blocks_publication(self):
        search = self.root / "providers"
        search.mkdir()
        self.search_scopes = [search]
        def change(_name):
            candidate = search / "libcandidate.so"
            candidate.write_bytes(b"temporary candidate")
            candidate.unlink()
        self.after = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture("--target", "alpha")
        self.after = None
        self.calls.clear()
        _, result = self.capture("--target", "alpha")
        self.assertEqual(["alpha"], self.calls)
        self.assertTrue(result["actions"][0]["qualified"])

    def test_absent_provider_directory_aba_blocks_execution(self):
        search = self.root / "providers"
        self.search_scopes = [search / "glibc-hwcaps/x86-64-v3"]
        def change(_name):
            search.mkdir()
            search.rmdir()
        self.before = change
        with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
            self.capture("--target", "alpha")
        self.assertEqual([], self.calls)

    def test_suite_validation_rejects_unknown_fields_duplicate_ids_and_output_overlap(self):
        value = cache.document(self.contract)
        value["workloads"][0]["unknown"] = True
        self.contract.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "invalid workload"):
            cache.suite(self.contract, [])
        with self.assertRaisesRegex(ValueError, "outside every watched"):
            cache.target_inputs({"dependencies": [str(self.root) + "/"]},
                                {"manifest": {"adapter": "native"}, "input_scopes": {"directories": [], "files": []}},
                                self.root / "cache", self.root / "report.json")


    def comparison_fixture(self, output):
        _, captured = self.capture("--target", "alpha")
        report = self.root / "comparison-source.json"
        report.write_text(json.dumps(captured))
        args = cache.options(["compare", str(report), str(report), "--output", str(output),
                              "--compiler", str(self.binary)])
        return args, report, captured

    def test_comparison_workload_outputs_cannot_overwrite_reports_model_or_compiler(self):
        for field, suffix in (("baseline", ".json"), ("candidate", ".md"),
                              ("model", ".json"), ("compiler", ".md")):
            with self.subTest(field=field):
                output = self.root / ("overlap-" + field)
                output.mkdir()
                args, report, captured = self.comparison_fixture(output)
                destination = output / ("alpha" + suffix)
                destination.write_bytes(report.read_bytes() if field in ("baseline", "candidate") else b"preserve input")
                if field == "compiler":
                    destination.chmod(0o755)
                setattr(args, field, destination)
                original = destination.read_bytes()
                with self.assertRaisesRegex(ValueError, "overlaps"):
                    cache.compare(args)
                self.assertEqual(original, destination.read_bytes())
                self.assertFalse((output / "decisions.json").exists())

    def test_comparison_preserves_retained_raw_and_artifact_inputs(self):
        output = self.root / "retain-overlap"
        args, _report, captured = self.comparison_fixture(output)
        row = captured["actions"][0]
        record = Path(row["record"])
        for directory in (record.parent, record.parent / "nested", record.parent.parent):
            with self.subTest(directory=directory):
                args.output = directory
                original = record.read_bytes()
                with self.assertRaisesRegex(ValueError, "overlaps"):
                    cache.compare(args)
                self.assertEqual(original, record.read_bytes())
        output.mkdir()
        args.output = output
        artifact = Path(next(iter(row["artifacts"].values())))
        os.link(artifact, output / "alpha.md")
        original = artifact.read_bytes()
        with self.assertRaisesRegex(ValueError, "overlaps"):
            cache.compare(args)
        self.assertEqual(original, artifact.read_bytes())
        self.assertFalse((output / "decisions.json").exists())

    def test_comparison_rejects_reserved_coordinator_report_id(self):
        output = self.root / "reserved"
        args, report, captured = self.comparison_fixture(output)
        captured["actions"][0]["id"] = "decisions"
        report.write_text(json.dumps(captured))
        with self.assertRaisesRegex(ValueError, "reserved"):
            cache.compare(args)
        self.assertFalse(output.exists())

    def test_comparison_runtime_library_and_loaded_source_changes_cannot_publish_success(self):
        for kind in ("library", "implementation"):
            with self.subTest(kind=kind):
                output = self.root / ("runtime-" + kind)
                args, _report, _captured = self.comparison_fixture(output)
                provider = self.root / (kind + ".input")
                provider.write_bytes(b"original runtime bytes")
                def change(_argv, **_kwargs):
                    provider.write_bytes(b"changed runtime bytes")
                    return type("Result", (), {"returncode": 0})()
                with patch.object(cache.identity, "tools", return_value=([], [self.binary, provider] if kind == "library" else [self.binary])), \
                        patch.object(cache, "IMPLEMENTATION_INPUTS", [str(provider)] if kind == "implementation" else []), \
                        patch.object(cache.subprocess, "run", side_effect=change):
                    with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
                        cache.compare(args)
                state = cache.document(output / "decisions.json")
                self.assertFalse(state["complete"])
                self.assertFalse(state["success"])

    def test_comparison_rejects_runtime_loader_injection_before_outputs(self):
        output = self.root / "injected"
        args, _report, _captured = self.comparison_fixture(output)
        self.env["LD_PRELOAD"] = "injected.so"
        with self.assertRaisesRegex(ValueError, "unsupported injection"):
            cache.compare(args)
        self.assertFalse(output.exists())


    def test_comparison_runtime_change_during_publication_revokes_completed_decision(self):
        output = self.root / "publication-race"
        args, _report, _captured = self.comparison_fixture(output)
        library = self.root / "runtime-library"
        library.write_bytes(b"before publication")
        original = cache.verification.atomic_record
        def publish(path, state):
            original(path, state)
            if state.get("version") == "juice-decisions-v1" and state["complete"]:
                library.write_bytes(b"changed during publication")
        with patch.object(cache.identity, "tools", return_value=([], [self.binary, library])), \
                patch.object(cache.subprocess, "run", return_value=type("Result", (), {"returncode": 0})()), \
                patch.object(cache.verification, "atomic_record", side_effect=publish):
            with self.assertRaises(cache.fuzz_campaign_store.InputsChanged):
                cache.compare(args)
        state = cache.document(output / "decisions.json")
        self.assertFalse(state["complete"])
        self.assertFalse(state["success"])


    def test_comparison_runtime_identity_records_environment_digest_without_secrets(self):
        output = self.root / "environment-identity"
        args, _report, _captured = self.comparison_fixture(output)
        self.env["PRIVATE_API_TOKEN"] = "fixture-secret-must-not-be-recorded"
        with patch.object(cache.subprocess, "run", return_value=type("Result", (), {"returncode": 0})()):
            self.assertEqual(0, cache.compare(args))
        state = cache.document(output / "decisions.json")
        self.assertEqual(cache.verification.key(self.env), state["runtime"]["environment_sha256"])
        self.assertNotIn(self.env["PRIVATE_API_TOKEN"], (output / "decisions.json").read_text())


if __name__ == "__main__":
    unittest.main()
