#!/usr/bin/env python3
"""Unit tests for `scripts/affected_tests.py`'s change-to-test mapping.

Every case runs against a small synthetic repository in a temporary directory,
so the mapping rules are pinned independently of the real tree's files.
"""
from __future__ import annotations

import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import affected_tests as at  # noqa: E402

FILES = {
    "src/root_test.zig": 'test {\n    _ = @import("foo_test.zig");\n    _ = @import("foo.zig");\n    _ = @import("bar_test.zig");\n}\n',
    "src/foo.zig": 'const part = @import("foo_part.zig");\npub fn computeThing() void {}\ntest "inline foo" {\n    try t.expect(true);\n}\n',
    "src/foo_part.zig": 'pub fn part() void {}\n',
    "src/foo_test.zig": 'const foo = @import("foo.zig");\n// spec: FOO-1\ntest "foo works" {\n    foo.computeThing();\n}\n',
    "src/bar_test.zig": '// spec: BAR-2\ntest "bar reports E_BAR_CODE" {\n    try expect("E_BAR_CODE");\n}\n',
    "src/core/build.zig": "pub fn lower() void {}\n",
    "test/integration.zig": 'test "CLI prints" {\n    try run();\n}\n',
    "tests/lang/python_core.my": "module python_core\n\npublic def test_core() -> bool:\n    return True\n",
    "tests/lang/text_views.my": "module text_views\n\n# spec: FOO-1\npublic def test_views() -> bool:\n    return True\n",
    "tests/lang/builtin_context.my": "module builtin_context\n\npublic def test_context() -> bool:\n    return True\n",
    "tests/guest/lists.my": "module lists\n\npublic def test_lists() -> bool:\n    return True\n",
    "docs/io.md": "# IO\n",
    "SPEC.md": "- [BAR-2] bar\n",
    "build.zig": "",
}


class SyntheticRepo(unittest.TestCase):
    """Point the module at a throwaway repository for the duration of a test."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="affected-tests-")
        self.root = Path(self.directory.name)
        for path, text in FILES.items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text(text)
        self.saved = at.ROOT
        at.ROOT = self.root
        self.corpus = at.Corpus()

    def tearDown(self) -> None:
        at.ROOT = self.saved
        self.directory.cleanup()

    def select(self, changes: dict[str, list[str]]) -> at.Selection:
        return at.select(sorted(changes), changes, self.corpus)


class Mapping(SyntheticRepo):
    def test_a_compiler_source_selects_its_tests_its_test_file_and_callers(self) -> None:
        sel = self.select({"src/foo.zig": ["pub fn computeThing() void {}"]})
        self.assertIn("foo.test.", sel.unit)
        self.assertIn("foo_test.test.", sel.unit)
        self.assertIn("foo_test.test.foo works", sel.unit)
        self.assertIn("tests/lang/python_core.my", sel.guest)

    def test_a_module_split_out_of_a_facade_is_tested_through_it(self) -> None:
        sel = self.select({"src/foo_part.zig": ["pub fn part() void {}"]})
        self.assertIn("foo_test.test.", sel.unit)
        self.assertNotIn("foo.test.", sel.unit)

    def test_a_spec_tag_in_the_diff_selects_the_tests_carrying_it(self) -> None:
        sel = self.select({"SPEC.md": ["- [BAR-2] bar, reworded"]})
        self.assertIn("bar_test.test.bar reports E_BAR_CODE", sel.unit)
        self.assertIn("SPEC.md", sel.doctest)
        sel = self.select({"src/foo_test.zig": ["// spec: FOO-1"]})
        self.assertIn("tests/lang/text_views.my", sel.guest)

    def test_a_diagnostic_code_in_the_diff_selects_the_tests_asserting_it(self) -> None:
        sel = self.select({"src/foo.zig": ['return error("E_BAR_CODE");']})
        self.assertIn("bar_test.test.bar reports E_BAR_CODE", sel.unit)

    def test_the_new_core_selects_test_core_and_the_guest_smoke(self) -> None:
        for path in ("src/core/build.zig", "src/core/runtime/core_rt.c", "test/core/rc_lists.my"):
            sel = self.select({path: ["x"]})
            self.assertEqual(sorted(sel.steps), ["test-core"])
            self.assertFalse(sel.unit)
            self.assertIn("tests/lang/python_core.my", sel.guest)
        builds, _ = at.plan(self.select({"src/core/build.zig": ["x"]}), "zig")
        self.assertTrue(any(c.argv[:3] == ["zig", "build", "affected-compiler"] and "test-core" in c.argv for c in builds))

    def test_the_retired_back_end_steps_are_never_selected(self) -> None:
        sel = self.select({"src/qbe_build.zig": ["x"], "src/native_text.c": ["int x;"], "vendor/qbe/main.c": ["x"]})
        retired = {"test-qbe", "test-qbe-build", "test-native-memory", "test-native-heap", "test-llvm-adapter", "test-c-ffi"}
        self.assertFalse(retired & set(sel.steps))

    def test_a_guest_test_file_runs_itself(self) -> None:
        sel = self.select({"tests/lang/python_core.my": ["    return True"], "tests/guest/lists.my": ["x"]})
        self.assertEqual(sorted(sel.guest), ["tests/guest/lists.my", "tests/lang/python_core.my"])
        self.assertFalse(sel.unit)

    def test_a_page_runs_its_doctest_and_doc_coverage(self) -> None:
        sel = self.select({"docs/io.md": ["new prose"]})
        self.assertIn("docs/io.md", sel.doctest)
        self.assertEqual(sel.doc_coverage, ["docs/io.md"])

    def test_a_cli_test_edit_selects_that_test(self) -> None:
        sel = self.select({"test/integration.zig": [' test "CLI prints" {', "    try run();"]})
        self.assertIn("integration.test.CLI prints", sel.cli)

    def test_the_build_graph_is_left_to_the_gate(self) -> None:
        sel = self.select({"build.zig": ["x"]})
        self.assertTrue(sel.empty())
        self.assertTrue(any("full gate" in note for note in sel.notes))

    def test_the_plan_filters_each_root_and_builds_the_compiler_for_guests(self) -> None:
        sel = self.select({"src/foo.zig": ["pub fn computeThing() void {}"]})
        builds, guests = at.plan(sel, "zig")
        units = next(c for c in builds if "test-units-sharded" in c.argv)
        self.assertIn("-Dtest-filter=foo_test.test.", units.argv)
        self.assertTrue(any("affected-compiler" in c.argv for c in builds))
        lang = [c for c in guests if "tests/lang/python_core.my" in c.argv]
        self.assertEqual(len(lang), 2)
        self.assertNotIn("--release", lang[0].argv)
        self.assertIn(at.LANG_CACHE, lang[0].argv)
        self.assertIn("--release", lang[1].argv)
        self.assertIn("--verify-facts", lang[1].argv)
        self.assertIn(at.LANG_RELEASE_CACHE, lang[1].argv)
        self.assertEqual(lang[1].env.get("MYL_CORE_LEAKCHECK"), "1")
        # The plan adds no tool variable of its own (no QBE path since S5).
        self.assertEqual(lang[1].env.get("MYLANG_QBE"), os.environ.get("MYLANG_QBE"))


class Git(SyntheticRepo):
    def git(self, *args: str) -> None:
        subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def test_the_diff_covers_commits_edits_and_untracked_files_since_the_base(self) -> None:
        self.git("init", "-q", "-b", "main")
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "add", ".")
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "base")
        (self.root / "src" / "foo.zig").write_text(FILES["src/foo.zig"] + "// edited\n")
        (self.root / "docs" / "new.md").write_text("# new\n")
        base, how = at.resolve_base(None)
        self.assertIn("merge-base", how)
        files = at.changed_files(base)
        self.assertEqual(files, ["docs/new.md", "src/foo.zig"])
        lines = at.diff_lines(base, files)
        self.assertIn("// edited", lines["src/foo.zig"])
        self.assertIn("# new", lines["docs/new.md"])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = at.main(["--dry-run"])
        self.assertEqual(status, 0)
        self.assertIn("NOT the gate", out.getvalue())
        self.assertIn("zig build test --summary all", out.getvalue())
        self.assertIn("zig build fmt-check", out.getvalue())
        self.assertNotIn("test-qbe", out.getvalue())


if __name__ == "__main__":
    unittest.main()
