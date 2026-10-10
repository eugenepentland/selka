#!/usr/bin/env python3
"""Concrete differential replay and strict campaign qualification regressions."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import differential_corpus as corpus
import incremental_diff
import interface_diff


class DifferentialCorpusTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="differential-corpus-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / "project"
        self.project.mkdir()
        (self.project / "main.my").write_text("func main() -> int:\n    return 0\n")
        (self.project / "mylang.json").write_text('{"version":2}\n')
        (self.project / "policy.bin").write_bytes(b"\x00\xff\x80\n")
        (self.project / ".config").write_bytes(b"hidden input\n")
        self.output = self.root / "corpus.json"
        self.calls = []

    def invoke(self, module, arguments, worker, **overrides):
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(sys, "argv", [module.__file__, *map(str, arguments)]))
            stack.enter_context(patch.object(module.subprocess, "run", side_effect=worker))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            for name, value in overrides.items():
                stack.enter_context(patch.object(module, name, value))
            return module.main()

    def incremental_worker(self, command, **kwargs):
        data = (Path(kwargs["cwd"]) / "main.my").read_bytes()
        self.calls.append((command[0], data, "--no-cache" in command))
        return subprocess.CompletedProcess(command, 0, b"", b"")

    def interface_worker(self, command, **kwargs):
        action = command[2]
        if action == "emit":
            source = Path(command[3]).read_bytes()
            self.calls.append((command[0], source, action))
            if b"REJECT" in source:
                return subprocess.CompletedProcess(command, 1, "", "rejected")
            output = Path(command[4].removeprefix("--out="))
            output.mkdir(parents=True, exist_ok=True)
            (output / "main.myi").write_bytes(b"stable artifact")
            value = {"modules": [{"module": "main", "interface_hash": "public contract",
                                    "implementation_hash": hashlib.sha256(source).hexdigest()}]}
            return subprocess.CompletedProcess(command, 0, json.dumps(value), "")
        if action == "show":
            return subprocess.CompletedProcess(command, 0, "functions\n  main::main declared exported effects={}\nshapes\n", "")
        if action == "oracle":
            self.calls.append((command[0], Path(command[3]).read_bytes(), action))
            return subprocess.CompletedProcess(command, 0, "", "")
        raise AssertionError(command)

    def test_binary_config_and_hidden_baseline_roundtrip_is_deterministic(self):
        saved = corpus.Corpus.capture(self.project, "incremental-v1")
        saved.append({"main.my": b"changed\n"}, ["literal"])
        saved.save(self.output)
        first = self.output.read_bytes()
        saved.save(self.output)
        self.assertEqual(first, self.output.read_bytes())
        loaded = corpus.Corpus.load(self.output, "incremental-v1")
        destination = self.root / "restored"
        loaded.restore(destination, loaded.cases[0])
        self.assertEqual(b"\x00\xff\x80\n", (destination / "policy.bin").read_bytes())
        self.assertEqual(b"hidden input\n", (destination / ".config").read_bytes())
        self.assertEqual(b"changed\n", (destination / "main.my").read_bytes())
        self.assertEqual(4, len(corpus.load(self.output, "incremental-v1")["base_files"]))

    def test_schema_paths_checksums_counts_and_duplicate_members_fail_closed(self):
        valid = corpus.Corpus.capture(self.project, "incremental-v1")
        valid.append({"main.my": b"changed"}, ["mutation"])
        document = valid.document
        mutations = [
            lambda value: value.update(version="unknown"),
            lambda value: value.update(adapter="interfaces-v1"),
            lambda value: value["base_files"][0].update(path="../escape"),
            lambda value: value["base_files"][0].update(path="/absolute"),
            lambda value: value["base_files"][0].update(data="%%%"),
            lambda value: value["base_files"][0].update(sha256="0" * 64),
            lambda value: value["cases"][0].update(ordinal=1),
            lambda value: value["cases"][0].update(ordinal=False),
            lambda value: value["cases"][0]["changes"][0].update(path="unknown.my"),
            lambda value: value["base_files"].append(value["base_files"][0]),
            lambda value: value["cases"][0].update(unexpected=True),
        ]
        for mutation in mutations:
            value = copy.deepcopy(document)
            mutation(value)
            with self.subTest(value=value), self.assertRaises(corpus.CorpusError):
                corpus.validate(value, "incremental-v1")
        self.output.write_text('{"version":1,"version":2}')
        with self.assertRaises(corpus.CorpusError):
            corpus.load(self.output, "incremental-v1")

    def test_file_parent_collision_and_payload_limits_are_rejected(self):
        saved = corpus.Corpus.capture(self.project, "incremental-v1")
        bad = copy.deepcopy(saved.document)
        bad["base_files"] = [corpus.file_record("a", b"one"), corpus.file_record("a/b", b"two")]
        with self.assertRaises(corpus.CorpusError):
            corpus.validate(bad, "incremental-v1")
        with patch.object(corpus, "MAX_PAYLOAD", 1), self.assertRaises(corpus.CorpusError):
            corpus.validate(saved.document, "incremental-v1")
        with patch.object(corpus, "MAX_CASES", 0), self.assertRaises(corpus.CorpusError):
            saved.append({}, [])
        self.assertEqual([], saved.cases)
        with patch.object(corpus, "MAX_FILE", 1), self.assertRaises(corpus.CorpusError):
            corpus.Corpus.capture(self.project, "incremental-v1")

    def test_strict_baseline_matches_visible_recipe_scope_and_rejects_symlinks(self):
        (self.project / "__pycache__").mkdir()
        (self.project / "__pycache__" / "ignored").write_bytes(b"ignored")
        (self.project / "ignored.pyc").write_bytes(b"ignored")
        copied = self.root / "visible"
        corpus.copy_baseline(self.project, copied, strict=True)
        self.assertEqual(["main.my", "mylang.json", "policy.bin"], sorted(path.name for path in copied.iterdir()))
        (self.project / "alias").symlink_to(copied, target_is_directory=True)
        with self.assertRaises(corpus.CorpusError):
            corpus.copy_baseline(self.project, self.root / "refused", strict=True)
        (self.project / "alias").unlink()
        (self.project / "alias.my").symlink_to(self.project / "main.my")
        with self.assertRaises(corpus.CorpusError):
            corpus.copy_baseline(self.project, self.root / "file-refused", strict=True)

    def test_strict_isolation_binds_default_config_and_preserves_declared_policy(self):
        (self.project / "mylang.json").unlink()
        (self.root / "mylang.json").write_text('{"version":2,"import_policy":"outside.json"}')
        (self.root / "outside.json").write_bytes(b"unbound ambient policy")
        corpus.isolate_baseline(self.project)
        self.assertEqual(b'{"version":2}\n', (self.project / "mylang.json").read_bytes())
        saved = corpus.Corpus.capture(self.project, "incremental-v1")
        self.assertIn("mylang.json", [row["path"] for row in saved.document["base_files"]])
        configuration = b'{"version":2,"import_policy":"policy.bin"}'
        (self.project / "mylang.json").write_bytes(configuration)
        corpus.isolate_baseline(self.project)
        self.assertEqual(configuration, (self.project / "mylang.json").read_bytes())
        for policy in ("../outside.json", str(self.root / "outside.json"), "missing.json"):
            (self.project / "mylang.json").write_text(json.dumps({"version": 2, "import_policy": policy}))
            with self.subTest(policy=policy), self.assertRaises(corpus.CorpusError):
                corpus.isolate_baseline(self.project)

    def test_strict_replay_adds_default_config_for_old_bundle_before_worker(self):
        (self.project / "mylang.json").unlink()
        saved = corpus.Corpus.capture(self.project, "incremental-v1")
        saved.append({}, ["retained no-op"])
        saved.save(self.output)
        observed = []
        def worker(command, **kwargs):
            observed.append((Path(kwargs["cwd"]) / "mylang.json").read_bytes())
            return subprocess.CompletedProcess(command, 0, b"", b"")
        args = ["candidate", "--steps", 0, "--strict-campaign", "--replay-corpus", self.output]
        self.assertEqual(0, self.invoke(incremental_diff, args, worker))
        self.assertEqual([b'{"version":2}\n'] * 4, observed)

    def test_incremental_replay_uses_retained_bytes_after_generator_project_and_candidate_change(self):
        mutation = lambda text, rng: [("literal", text.replace("return 0", "return 7"))]
        args = ["candidate-a", "--steps", 3, "--seed", 3, "--project", self.project,
                "--strict-campaign", "--corpus-out", self.output]
        self.assertEqual(0, self.invoke(incremental_diff, args, self.incremental_worker, mutations=mutation))
        loaded = corpus.load(self.output, "incremental-v1")
        self.assertEqual(3, len(loaded["cases"]))
        self.assertTrue(all(case["labels"] for case in loaded["cases"]))
        (self.project / "main.my").write_text("changed original input")
        self.calls.clear()
        replay = ["candidate-b", "--steps", 0, "--seed", 999, "--project", self.root / "missing",
                  "--strict-campaign", "--replay-corpus", self.output]
        def forbidden(*unused):
            raise AssertionError("generator invoked during replay")
        self.assertEqual(0, self.invoke(incremental_diff, replay, self.incremental_worker, mutations=forbidden))
        mutated = [data for _, data, cold in self.calls if cold and b"return 7" in data]
        self.assertEqual(3, len(mutated))
        self.assertTrue(all(Path(name).name == "candidate-b" for name, _, _ in self.calls))
        self.assertTrue(any(b"return 0" in data for _, data, _ in self.calls))

    def test_incremental_identical_crashes_keep_legacy_verdict_but_strict_rejects(self):
        def crashing(command, **kwargs):
            self.calls.append(command)
            # The initial pristine check and each warmup succeed; both mutated
            # cached/cold checks crash identically.
            status = 0 if len(self.calls) <= 2 else -11
            return subprocess.CompletedProcess(command, status, b"", b"crash")
        args = ["candidate", "--steps", 1, "--project", self.project]
        self.assertEqual(0, self.invoke(incremental_diff, args, crashing))
        self.calls.clear()
        strict = [*args, "--strict-campaign", "--corpus-out", self.output]
        self.assertEqual(2, self.invoke(incremental_diff, strict, crashing))
        self.assertEqual(1, len(corpus.load(self.output, "incremental-v1")["cases"]))

    def test_incremental_replay_restores_config_before_every_cache_warmup(self):
        saved = corpus.Corpus.capture(self.project, "incremental-v1")
        saved.append({"mylang.json": b"changed config"}, ["config edit"])
        saved.append({"mylang.json": b"another config"}, ["config edit"])
        saved.save(self.output)
        observed = []
        def worker(command, **kwargs):
            observed.append((Path(kwargs["cwd"]) / "mylang.json").read_bytes())
            return subprocess.CompletedProcess(command, 0, b"", b"")
        args = ["candidate", "--steps", 0, "--strict-campaign", "--replay-corpus", self.output]
        self.assertEqual(0, self.invoke(incremental_diff, args, worker))
        self.assertEqual([b'{"version":2}\n', b'{"version":2}\n', b"changed config", b"changed config",
                          b'{"version":2}\n', b"another config", b"another config"], observed)

    def test_incremental_export_retains_implicit_newline_changes_in_untouched_sources(self):
        (self.project / "main.my").write_bytes(b"func main() -> int:\r\n    return 0\r\n")
        (self.project / "untouched.my").write_bytes(b"const unused = 0\r\n")
        args = ["candidate", "--steps", 1, "--project", self.project,
                "--strict-campaign", "--corpus-out", self.output]
        mutation = lambda text, rng: [("no-op", text)]
        self.assertEqual(0, self.invoke(incremental_diff, args, self.incremental_worker, mutations=mutation))
        saved = corpus.Corpus.load(self.output, "incremental-v1")
        destination = self.root / "replay"
        saved.restore(destination, saved.cases[0])
        self.assertEqual(b"func main() -> int:\n    return 0\n", (destination / "main.my").read_bytes())
        self.assertEqual(b"const unused = 0\n", (destination / "untouched.my").read_bytes())

    def test_incremental_mismatch_and_timeout_export_attempt_without_success(self):
        def mismatch(command, **kwargs):
            self.calls.append(command)
            stdout = b"different" if len(self.calls) == 3 else b""
            return subprocess.CompletedProcess(command, 0, stdout, b"")
        args = ["candidate", "--steps", 1, "--project", self.project,
                "--strict-campaign", "--corpus-out", self.output]
        self.assertEqual(1, self.invoke(incremental_diff, args, mismatch))
        self.assertEqual(1, len(corpus.load(self.output, "incremental-v1")["cases"]))
        self.calls.clear()
        def timeout(command, **kwargs):
            self.calls.append(command)
            if len(self.calls) == 3:
                raise subprocess.TimeoutExpired(command, 300)
            return subprocess.CompletedProcess(command, 0, b"", b"")
        self.assertEqual(2, self.invoke(incremental_diff, args, timeout))
        self.assertEqual(1, len(corpus.load(self.output, "incremental-v1")["cases"]))

    def test_interface_replay_skips_catalog_and_rechecks_current_oracle(self):
        def generated(sources, roles, rng):
            return [("body literal", "same", "main", sources["main"].replace("return 0", "return 7"), None)]
        args = ["candidate-a", "--steps", 2, "--project", self.project,
                "--strict-campaign", "--corpus-out", self.output]
        self.assertEqual(0, self.invoke(interface_diff, args, self.interface_worker, catalog=generated))
        retained = corpus.load(self.output, "interfaces-v1")
        self.assertEqual(2, len(retained["cases"]))
        self.assertEqual("same", retained["cases"][0]["expect"])
        self.calls.clear()
        def changed_oracle(command, **kwargs):
            if command[2] == "oracle":
                self.calls.append((command[0], Path(command[3]).read_bytes(), "oracle"))
                return subprocess.CompletedProcess(command, 1, "new oracle disagrees", "")
            return self.interface_worker(command, **kwargs)
        def forbidden(*unused):
            raise AssertionError("catalog regenerated during replay")
        replay = ["candidate-b", "--steps", 0, "--project", self.root / "missing",
                  "--strict-campaign", "--replay-corpus", self.output]
        self.assertEqual(1, self.invoke(interface_diff, replay, changed_oracle, catalog=forbidden))
        oracles = [data for _, data, action in self.calls if action == "oracle"]
        self.assertEqual(2, len(oracles))
        self.assertTrue(all(b"return 7" in data for data in oracles))

    def test_interface_rejected_attempts_and_abnormal_workers_never_disappear(self):
        def rejected(sources, roles, rng):
            return [("signature", "changed", "main", "REJECT", "main::Shape")]
        args = ["candidate", "--steps", 2, "--project", self.project,
                "--strict-campaign", "--corpus-out", self.output]
        self.assertEqual(0, self.invoke(interface_diff, args, self.interface_worker, catalog=rejected))
        cases = corpus.load(self.output, "interfaces-v1")["cases"]
        self.assertEqual(2, len(cases))
        self.assertEqual("main::Shape", cases[0]["shape"])
        def crash(command, **kwargs):
            if command[2] == "emit" and b"REJECT" in Path(command[3]).read_bytes():
                return subprocess.CompletedProcess(command, 70, "", "host failure")
            return self.interface_worker(command, **kwargs)
        self.assertEqual(2, self.invoke(interface_diff, args, crash, catalog=rejected))
        self.assertEqual(1, len(corpus.load(self.output, "interfaces-v1")["cases"]))


if __name__ == "__main__":
    unittest.main()
