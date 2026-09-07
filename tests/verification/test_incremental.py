#!/usr/bin/env python3
"""Dependency selection and cache integrity regressions, no Zig required."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from verification.core import run_manifest

COMPILER = None


class Incremental(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "project"
        self.root.mkdir()
        self.cache = self.base / "cache"
        (self.root / "a.txt").write_text("ok")
        (self.root / "b.txt").write_text("ok")
        self.data = {"version": 2, "policy": "test-v1", "steps": [
            {"id": name, "kind": "test", "inputs": [name + ".txt"], "complete": True,
             "commands": [[sys.executable, "-c", f"from pathlib import Path; assert Path('{name}.txt').read_text() == 'ok'"]]}
            for name in ("a", "b")]}

    def run_jobs(self, **kwargs):
        path = self.root / "verify.json"
        path.write_text(json.dumps(self.data))
        return run_manifest(path, cache_dir=self.cache, **kwargs)

    def test_hits_and_fixture_invalidation(self):
        first = self.run_jobs()
        self.assertTrue(first["full_manifest_passed"])
        self.assertEqual([s["status"] for s in self.run_jobs()["steps"]], ["cached", "cached"])
        (self.root / "a.txt").write_text("broken")
        changed = self.run_jobs(previous=first, mode="affected")
        self.assertEqual(changed["selected"], ["a"])
        self.assertEqual([s["status"] for s in changed["steps"]], ["failed", "not-selected"])
        self.assertFalse(changed["full_manifest_passed"])

    def test_glob_membership_and_prerequisite_closure(self):
        self.data["steps"][0]["inputs"] = ["*.new"]
        self.data["steps"][1]["depends_on"] = ["a"]
        first = self.run_jobs()
        (self.root / "untracked.new").write_text("new")
        self.assertEqual(self.run_jobs(previous=first, mode="affected")["selected"], ["a", "b"])
        (self.root / "untracked.new").unlink()
        self.assertEqual(self.run_jobs(previous=first, mode="affected")["selected"], [])
        self.assertFalse(self.run_jobs(previous=first, mode="affected")["selected_passed"])

    def test_corrupt_receipt_and_policy_miss(self):
        first = self.run_jobs()
        key = first["steps"][0]["job_key"]
        (self.cache / "receipts" / (key + ".json")).write_text('{"broken":')
        self.assertEqual(self.run_jobs()["steps"][0]["status"], "executed")
        self.data["policy"] = "new-policy"
        self.assertEqual([s["status"] for s in self.run_jobs()["steps"]], ["executed", "executed"])

    def test_unknown_dependencies_full_and_uncached(self):
        self.data["steps"][0]["complete"] = False
        first = self.run_jobs()
        report = self.run_jobs(previous=first, mode="affected")
        self.assertEqual(report["selected"], ["a", "b"])
        self.assertEqual(report["steps"][0]["status"], "executed")

    def test_shadow_detects_false_declaration(self):
        self.data["steps"][0]["inputs"] = []
        first = self.run_jobs()
        (self.root / "a.txt").write_text("broken")
        report = self.run_jobs(previous=first, mode="shadow")
        self.assertEqual(report["shadow_omissions"], ["a"])

    def test_cross_worktree_and_no_wrong_source(self):
        import shutil
        first = self.run_jobs()
        other = self.base / "other"
        shutil.copytree(self.root, other)
        report = run_manifest(other / "verify.json", cache_dir=self.cache)
        self.assertEqual([s["status"] for s in report["steps"]], ["cached", "cached"])
        (other / "a.txt").write_text("bad")
        report = run_manifest(other / "verify.json", cache_dir=self.cache)
        self.assertEqual(report["steps"][0]["status"], "failed")
        self.assertEqual(first["steps"][0]["status"], "executed")

    def test_tool_environment_and_deletion_invalidate(self):
        import os
        self.data["steps"][0]["env"] = ["VERIFICATION_TEST_INPUT"]
        first = self.run_jobs()
        old = os.environ.get("VERIFICATION_TEST_INPUT")
        try:
            os.environ["VERIFICATION_TEST_INPUT"] = "changed"
            report = self.run_jobs(previous=first, mode="affected")
            self.assertEqual(report["selected"], ["a"])
        finally:
            if old is None:
                os.environ.pop("VERIFICATION_TEST_INPUT", None)
            else:
                os.environ["VERIFICATION_TEST_INPUT"] = old
        (self.root / "a.txt").unlink()
        self.assertEqual(self.run_jobs(previous=first, mode="affected")["selected"], ["a"])

    def test_mutating_input_cannot_publish_and_gc(self):
        from verification.core import collect_cache
        self.data["steps"][0]["commands"] = [[sys.executable, "-c", "from pathlib import Path; Path('a.txt').write_text('changed')"]]
        report = self.run_jobs()
        self.assertFalse(report["steps"][0]["passed"])
        self.assertEqual((self.root / "a.txt").read_text(), "ok")
        key = report["steps"][0]["job_key"]
        self.assertFalse((self.cache / "receipts" / (key + ".json")).exists())
        self.assertGreater(collect_cache(self.cache, 0)["receipts_removed"], 0)

    def test_stale_graph_forces_full_uncached_fallback(self):
        self.data["steps"][0]["module_graph"] = "missing-graph.json"
        first = self.run_jobs()
        report = self.run_jobs(previous=first, mode="affected")
        self.assertEqual(report["selected"], ["a", "b"])
        self.assertEqual(report["steps"][0]["status"], "executed")

    def test_cached_hit_race_cannot_certify_live_mutation(self):
        from unittest.mock import patch
        from verification import core
        first = self.run_jobs()
        original = core.cached
        def racing(path, key):
            result = original(path, key)
            (self.root / "a.txt").write_text("changed during hit")
            return result
        with patch.object(core, "cached", racing):
            report = self.run_jobs()
        self.assertFalse(report["source_unchanged"])
        self.assertFalse(report["full_manifest_passed"])
        self.assertTrue(first["full_manifest_passed"])

    def test_special_file_rejected_without_reading(self):
        import os
        os.mkfifo(self.root / "pipe")
        with self.assertRaises(ValueError):
            self.run_jobs()

    def test_standard_library_graph_caches_only_with_matching_compiler(self):
        if COMPILER is None:
            self.skipTest("supply --compiler to exercise actual compiler receipt")
        import subprocess
        (self.root / "main.my").write_text("module main;import std_json;fn main()->i64{return 0;}")
        process = subprocess.run([str(COMPILER), "project-dependencies", str(self.root / "main.my")],
                                 capture_output=True, check=True)
        (self.root / "graph.json").write_bytes(process.stdout)
        self.data["steps"][0].update(module_graph="graph.json", tools=[str(COMPILER)])
        first = self.run_jobs()
        self.assertTrue(first["inventory"]["a"]["complete"])
        self.assertEqual(self.run_jobs()["steps"][0]["status"], "cached")
        self.data["steps"][0]["tools"] = []
        unpinned = self.run_jobs()
        self.assertFalse(unpinned["inventory"]["a"]["complete"])
        self.assertEqual(unpinned["steps"][0]["status"], "executed")

    def test_real_compiler_graph_invalidates_imported_module(self):
        if COMPILER is None:
            self.skipTest("supply --compiler to exercise actual compiler receipt")
        import subprocess
        (self.root / "main.my").write_text("module main; import leaf; fn main() -> i64 { return leaf::value(); }")
        (self.root / "leaf.my").write_text("module leaf; export value; fn value() -> i64 { return 0; }")
        process = subprocess.run([str(COMPILER), "project-dependencies", str(self.root / "main.my")], capture_output=True, check=True)
        (self.root / "graph.json").write_bytes(process.stdout)
        self.data["steps"][0]["module_graph"] = "graph.json"
        self.data["steps"][0]["tools"] = [str(COMPILER)]
        first = self.run_jobs()
        self.assertTrue(first["inventory"]["a"]["complete"])
        self.assertEqual(self.run_jobs()["steps"][0]["status"], "cached")
        (self.root / "leaf.my").write_text("module leaf; export value; fn value() -> i64 { return 1; }")
        stale = self.run_jobs(previous=first, mode="affected")
        self.assertEqual(stale["selected"], ["a", "b"])
        self.assertFalse(stale["inventory"]["a"]["complete"])
        (self.root / "leaf.my").write_text("module leaf; export value; fn value() -> i64 { return 0; }")
        self.data["steps"][0]["commands"] = [[sys.executable, "-c", "from pathlib import Path; Path('leaf.my').write_text('mutated during verification')"]]
        mutated = self.run_jobs()
        self.assertFalse(mutated["steps"][0]["passed"])
        self.assertEqual(mutated["steps"][0]["reason"], "inputs changed during verification")

    def test_real_generated_graph_tracks_exact_manifest_bytes(self):
        if COMPILER is None:
            self.skipTest("supply --compiler to exercise generated input receipt")
        import subprocess
        (self.root / "main.my").write_text("module main; import config; fn main()->i64{return config::x();}")
        manifest = self.root / "inputs.json"
        manifest.write_text(json.dumps({"version": 1, "module": "config", "values": [{"name": "x", "type": "i64", "value": "7"}]}))
        process = subprocess.run([str(COMPILER), "project-dependencies", "main.my", "--inputs=inputs.json"], cwd=self.root, capture_output=True, check=True)
        (self.root / "graph.json").write_bytes(process.stdout)
        self.data["steps"][0].update(module_graph="graph.json", tools=[str(COMPILER)])
        first = self.run_jobs()
        self.assertTrue(first["inventory"]["a"]["complete"])
        manifest.write_text(manifest.read_text() + " ")
        stale = self.run_jobs(previous=first, mode="affected")
        self.assertFalse(stale["inventory"]["a"]["complete"])
        self.assertEqual(stale["selected"], ["a", "b"])

    def test_snapshot_byte_budget_rejects_before_read(self):
        with (self.root / "large").open("wb") as stream:
            stream.truncate(129 * 1024 * 1024)
        with self.assertRaisesRegex(ValueError, "128 MiB"):
            self.run_jobs()

    def test_tool_execute_mode_change_invalidates_success(self):
        tool = self.root / "tool"
        tool.write_text("#!/bin/sh\nexit 0\n")
        tool.chmod(0o555)
        self.data["steps"][0]["commands"] = [["./tool"]]
        first = self.run_jobs()
        self.assertTrue(first["steps"][0]["passed"])
        self.assertEqual(self.run_jobs()["steps"][0]["status"], "cached")
        tool.chmod(0o444)
        changed = self.run_jobs(previous=first, mode="affected")
        self.assertEqual(changed["selected"], ["a"])
        self.assertFalse(changed["steps"][0]["passed"])
        self.assertNotEqual(first["steps"][0]["job_key"], changed["steps"][0]["job_key"])

    def test_lock_namespace_is_bounded_and_gc_preserves_active_workspace(self):
        from verification.core import lock_path, locked, collect_cache
        paths = {lock_path(self.cache, str(index)) for index in range(10000)}
        self.assertLessEqual(len(paths), 256)
        key = "active-job"
        workspace = self.cache / "work" / key
        workspace.mkdir(parents=True)
        with locked(lock_path(self.cache, key)):
            collect_cache(self.cache, 0)
            self.assertTrue(workspace.exists())
        collect_cache(self.cache, 0)
        self.assertFalse(workspace.exists())

    def test_relative_path_resolution_rejected(self):
        import os
        from unittest.mock import patch
        with patch.dict(os.environ, {"PATH": ".:/usr/bin"}):
            with self.assertRaises(ValueError):
                self.run_jobs()

    def test_shadow_uses_identical_declared_environment(self):
        import os
        from unittest.mock import patch
        self.data["steps"][0]["commands"] = [[sys.executable, "-c", "import os; assert 'UNDECLARED_TEST_ENV' not in os.environ"]]
        with patch.dict(os.environ, {"UNDECLARED_TEST_ENV": "present"}):
            first = self.run_jobs()
            self.assertTrue(first["full_manifest_passed"])
            self.assertTrue(self.run_jobs(previous=first, mode="shadow")["full_manifest_passed"])

    def test_reject_escape_and_symlink(self):
        self.data["steps"][0]["inputs"] = ["../secret"]
        with self.assertRaises(ValueError):
            self.run_jobs()
        self.data["steps"][0]["inputs"] = ["a.txt"]
        (self.root / "alias").symlink_to("a.txt")
        with self.assertRaises(ValueError):
            self.run_jobs()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path)
    args, remaining = parser.parse_known_args()
    COMPILER = args.compiler.resolve() if args.compiler else None
    unittest.main(argv=[sys.argv[0]] + remaining)
