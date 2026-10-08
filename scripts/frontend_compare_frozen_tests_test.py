#!/usr/bin/env python3
"""Verify that source relocation cannot conceal semantic report differences."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import frontend_compare_frozen_tests as gate
import frontend_compare_settings as settings


class SourceNormalization(unittest.TestCase):
    old = Path("/frozen/source")
    new = Path("/candidate/source")
    manifest = {"tests/input.my": "sha", "tests/other.my": "sha"}

    def report(self, root):
        return {"version": "native-tests-v1", "passed": 1, "failed": 0,
            "skipped": 0, "cached": 0, "unsupported": 0,
            "tests": [{"name": "input::test_value", "status": "passed", "reason": "",
                "at": str(root / "tests/input.my") + ":7:2"}],
            "sources": [str(root / "tests/input.my")],
            "literal": str(self.old / "tests/input.my")}

    def normalize(self, report, root, stderr=b"", enabled=True):
        return gate.normalize_sources(report, json.dumps(report).encode(), stderr,
            root, self.manifest, enabled)

    def test_disabled_preserves_every_byte_and_field(self):
        report = self.report(self.old)
        before = copy.deepcopy(report)
        stderr = b"/frozen/source/tests/input.my:7:2: error[E_BAD]: detail\n"
        actual = self.normalize(report, self.old, stderr, False)
        self.assertEqual(actual, (report, json.dumps(report).encode(), stderr, []))
        self.assertEqual(report, before)

    def test_relocation_changes_only_sources_at_and_diagnostic_filenames(self):
        old, new = self.report(self.old), self.report(self.new)
        old_before, new_before = copy.deepcopy(old), copy.deepcopy(new)
        left = self.normalize(old, self.old, b"/frozen/source/tests/input.my:7:2: error[E_BAD]: detail\n")
        right = self.normalize(new, self.new, b"/candidate/source/tests/input.my:7:2: error[E_BAD]: detail\n")
        self.assertEqual(left[:3], right[:3])
        self.assertEqual(json.loads(left[1])["literal"], str(self.old / "tests/input.my"))
        self.assertEqual(left[0]["literal"], str(self.old / "tests/input.my"))
        self.assertEqual(left[0]["tests"][0]["at"], "<source>/tests/input.my:7:2")
        self.assertEqual(left[2], b"<source>/tests/input.my:7:2: error[E_BAD]: detail\n")
        self.assertEqual(old, old_before)
        self.assertEqual(new, new_before)
        self.assertEqual(len(left[3]), 3)

    def test_semantic_fields_and_source_membership_remain_observable(self):
        original = self.normalize(self.report(self.old), self.old)[0]
        modifications = [
            lambda report: report.update(passed=2),
            lambda report: report.update(literal=str(self.new / "tests/input.my")),
            lambda report: report["tests"][0].update(status="failed"),
            lambda report: report["tests"][0].update(reason="R_ASSERT condition changed"),
            lambda report: report["tests"][0].update(name="input::test_other"),
            lambda report: report["sources"].append(str(self.new / "tests/other.my")),
            lambda report: report["tests"][0].update(at=str(self.new / "tests/input.my") + ":8:2"),
        ]
        for modification in modifications:
            report = self.report(self.new)
            modification(report)
            self.assertNotEqual(original, self.normalize(report, self.new)[0])

    def test_diagnostic_codes_messages_and_locations_remain_observable(self):
        original = self.normalize(self.report(self.old), self.old,
            b"/frozen/source/tests/input.my:7:2: error[E_BAD]: detail\n")[2]
        for stderr in (
            b"/candidate/source/tests/input.my:8:2: error[E_BAD]: detail\n",
            b"/candidate/source/tests/input.my:7:3: error[E_BAD]: detail\n",
            b"/candidate/source/tests/input.my:7:2: error[E_OTHER]: detail\n",
            b"/candidate/source/tests/input.my:7:2: error[E_BAD]: changed\n",
        ):
            self.assertNotEqual(original, self.normalize(self.report(self.new), self.new, stderr)[2])

    def test_unknown_paths_and_nonlocation_stderr_are_unchanged(self):
        report = self.report(self.old)
        report["sources"].append("/frozen/source/unknown.my")
        stderr = b"/frozen/source/tests/input.my\n/frozen/source/unknown.my:7:2: message\n"
        result = self.normalize(report, self.old, stderr)
        self.assertEqual(result[2], stderr)
        self.assertEqual(result[0]["sources"][1], "/frozen/source/unknown.my")


class ProductionIdentity(unittest.TestCase):
    def test_content_and_untracked_addition_or_removal_change_the_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir()
            source = root / "src/main.zig"
            source.write_text("pub fn main() void {}\n")
            before = gate.production_manifest(root)
            source.write_text("pub fn main() void { unreachable; }\n")
            self.assertNotEqual(before, gate.production_manifest(root))
            source.write_text("pub fn main() void {}\n")
            added = root / "src/untracked.zig"
            added.write_text("pub const extra = 1;\n")
            self.assertNotEqual(before, gate.production_manifest(root))
            added.unlink()
            self.assertEqual(before, gate.production_manifest(root))
            source.unlink()
            self.assertNotEqual(before, gate.production_manifest(root))


class ImmutableLoader(unittest.TestCase):
    def test_loading_a_frozen_helper_creates_no_cache_or_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "helper.py"
            helper.write_text("value = 42\n")
            before = {path.name: path.read_bytes() for path in root.iterdir()}
            loaded = gate.load("frozen_helper", helper)
            self.assertEqual(loaded.value, 42)
            self.assertEqual(loaded.__file__, str(helper))
            self.assertEqual(before, {path.name: path.read_bytes() for path in root.iterdir()})


class SettingsFingerprint(unittest.TestCase):
    def test_only_a_recomputed_fingerprint_can_be_rekeyed(self):
        report = {"tests": [{"name": "test_value", "status": "passed", "source": "a" * 64,
            "contract": "contract", "provider": "provider", "reason": "", "at": ""}],
            "literal": "a" * 64, "passed": 1}
        raw = json.dumps(report).encode()
        normalized, stdout, changes = settings.normalize(report, raw, "a" * 64, "c" * 64)
        self.assertEqual(normalized["literal"], "a" * 64)
        self.assertEqual(normalized["tests"][0]["contract"], "contract")
        self.assertEqual(normalized["tests"][0]["provider"], "provider")
        self.assertEqual(json.loads(stdout), normalized)
        self.assertEqual(len(changes), 1)
        self.assertEqual(report["tests"][0]["source"], "a" * 64)
        for corrupted in ("b" * 64, "incorrect-source"):
            damaged = copy.deepcopy(report)
            damaged["tests"][0]["source"] = corrupted
            with self.assertRaisesRegex(AssertionError, "incorrect derived"):
                settings.normalize(damaged, json.dumps(damaged).encode(), "a" * 64, "c" * 64)

    def test_cases_budgets_and_compiler_identity_change_independent_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry, cases = root / "input.my", root / "cases.json"
            entry.write_text("module input\n")
            cases.write_text('{"test_value":{"arguments":{}}}\n')
            argv = ["compiler", "test", str(entry), "--cases", str(cases), "--max-steps=99"]
            context = {"zig_path": "/tool/zig", "tool_digest": "1" * 64,
                "environment": {"MYL_CORE_LEAKCHECK": "1"}}
            original = settings.fields(argv, context, "a" * 64)
            changed_identity = settings.fields(argv, context, "b" * 64)
            self.assertEqual(original[:1] + original[2:], changed_identity[:1] + changed_identity[2:])
            self.assertNotEqual(settings.preimage(original), settings.preimage(changed_identity))
            cases.write_text('{"test_value":{"arguments":{"value":3}}}\n')
            self.assertNotEqual(settings.preimage(original), settings.preimage(settings.fields(argv, context, "a" * 64)))
            changed_budget = argv[:-1] + ["--max-steps=100"]
            self.assertNotEqual(settings.fields(argv, context, "a" * 64), settings.fields(changed_budget, context, "a" * 64))
            (root / "mylang.json").write_text("{}\n")
            with self.assertRaisesRegex(AssertionError, "project configuration"):
                settings.fields(argv, context, "a" * 64)


if __name__ == "__main__":
    unittest.main()
