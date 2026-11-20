#!/usr/bin/env python3
"""The compiler-map check against a small repository it writes itself: the real shape passes, and one broken copy per rule fails.

The fixture is a miniature of the real layout (a map page, a few sources of each language, `build_test_inputs.zig`), so this test
depends on none of the repository's documents or sources. What it shows is the one thing the check is for: a file or a function
that the map names and that is renamed or removed produces a finding that names the map's line. The real page is checked by the
gate action `goals_register` (`tests/goals_register.py --map`), and alone by `python3 tests/compiler_map.py`.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import compiler_map

SCRIPT = Path(compiler_map.__file__)
PAGE_NAME = "docs/tooling/compiler-map.md"

PAGE = '''# Compiler map

1. **Parsing.** `src/parser.zig: parseModule` builds the tables; `statement` parses one.
2. **Core.** `src/core/build.zig: buildExecutable` lowers; `src/core/runtime/core_text.c: myl_core_view_slice_text`
   is C.
3. **Library.** `src/stdlib/<module>.selka` holds modules; `src/stdlib/strings.selka: starts_with_at` is one function.
4. **Tools.** `scripts/tool.py: main` and the proofs in `proofs/Own.lean: check_sound`;
   run `python3 scripts/tool.py --all`.
5. **Not checked.** `zig-out/bin/selka` and `.selka-cache/core` are outputs; `Own.check` and `E_CODE` are not paths.

```sh
python3 scripts/not_there.py
```

A directory: `src/core/`. A pattern: `src/core/runtime/core_*.c`.
'''

PARSER = '''//! the parser
pub const Parser = struct {
    pub fn parseModule(self: *Parser) u8 {
        return 0;
    }
    fn statement(self: *Parser) u8 {
        return 1;
    }
};
'''

BUILD = '''pub fn buildExecutable() void {}
'''

C_TEXT = '''/* a runtime helper */
core_borrowed_span myl_core_view_slice_text(const myl_core_site *site, int64_t start) {
    return start;
}
'''

STRINGS = '''# the module
public func starts_with_at(text: str, prefix: str, at: int) -> bool:
    return True
'''

TOOL = '''def main():
    return 0
'''

LEAN = '''namespace Own
theorem check_sound : True := trivial
end Own
'''

INPUTS = '''pub const environment_contract = [_][]const u8{"src/environment_identity.zon"};
pub const goals_register = [_][]const u8{
    "docs/**/*.md",
    "src/**/*.zig",
    "src/**/*.selka",
    "src/**/*.c",
    "scripts/**/*.py",
    "proofs/**/*.lean",
    "tests/compiler_map.py",
} ++ environment_contract;
'''

TREE = {
    PAGE_NAME: PAGE,
    "src/parser.zig": PARSER,
    "src/core/build.zig": BUILD,
    "src/core/runtime/core_text.c": C_TEXT,
    "src/core/runtime/core_rt.c": "/* rt */\n",
    "src/stdlib/strings.selka": STRINGS,
    "src/stdlib/lists.selka": "# lists\n",
    "scripts/tool.py": TOOL,
    "proofs/Own.lean": LEAN,
    "tests/compiler_map.py": "# the driver\n",
    "build_test_inputs.zig": INPUTS,
}


class Map(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        for name, text in TREE.items():
            self.write(name, text)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def edit(self, name, old, new):
        path = self.root / name
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new))

    def findings(self):
        return [str(finding) for finding in compiler_map.check(self.root, PAGE_NAME).findings]

    def line(self, needle):
        """The 1-based line of the page that holds `needle`."""
        for number, text in enumerate((self.root / PAGE_NAME).read_text().splitlines(), 1):
            if needle in text:
                return number
        self.fail("{} not in the page".format(needle))

    def only(self):
        found = self.findings()
        self.assertEqual(len(found), 1, found)
        return found[0]

    def test_the_real_shape_passes(self):
        report = compiler_map.check(self.root, PAGE_NAME)
        self.assertEqual(report.findings, [])
        self.assertEqual(report.counts["functions"], 6)
        self.assertGreaterEqual(report.counts["paths"], 9)

    def test_a_renamed_file_is_found_with_the_pages_line(self):
        (self.root / "src/parser.zig").rename(self.root / "src/parse.zig")
        self.assertEqual(self.only(), "{}:{}: path: `src/parser.zig` does not exist".format(PAGE_NAME, self.line("src/parser.zig: parseModule")))

    def test_a_removed_file_is_found_wherever_the_page_names_it(self):
        (self.root / "scripts/tool.py").unlink()
        found = self.findings()
        self.assertEqual(len(found), 2, found)
        self.assertIn("{}:{}: path: `scripts/tool.py` does not exist".format(PAGE_NAME, self.line("scripts/tool.py: main")), found)
        self.assertIn("command: `scripts/tool.py` in `python3 scripts/tool.py --all` does not exist", found[1] if "command" in found[1] else found[0])

    def test_a_renamed_function_is_found_with_the_pages_line(self):
        self.edit("src/parser.zig", "parseModule", "parseProgram")
        self.assertEqual(self.only(), "{}:{}: function: `src/parser.zig` declares no function `parseModule`".format(PAGE_NAME, self.line("parseModule")))

    def test_a_function_that_is_only_in_a_comment_does_not_count(self):
        self.edit("src/parser.zig", "    fn statement(self: *Parser) u8 {", "    // fn statement(self: *Parser) u8 {\n    fn stmt(self: *Parser) u8 {")
        self.write(PAGE_NAME, PAGE.replace("`src/parser.zig: parseModule`", "`src/parser.zig: statement`"))
        self.assertIn("function: `src/parser.zig` declares no function `statement`", self.only())

    def test_each_language_declares_a_function_its_own_way(self):
        self.edit("src/core/runtime/core_text.c", "myl_core_view_slice_text", "myl_core_view_slice_renamed")
        self.assertIn("declares no function `myl_core_view_slice_text`", self.only())
        self.edit("src/core/runtime/core_text.c", "myl_core_view_slice_renamed", "myl_core_view_slice_text")
        self.edit("src/stdlib/strings.selka", "public func starts_with_at", "public func starts_with")
        self.assertIn("declares no function `starts_with_at`", self.only())
        self.edit("src/stdlib/strings.selka", "public func starts_with", "public func starts_with_at")
        self.edit("scripts/tool.py", "def main", "def run")
        self.assertIn("declares no function `main`", self.only())
        self.edit("scripts/tool.py", "def run", "def main")
        self.edit("proofs/Own.lean", "theorem check_sound", "theorem check_other")
        self.assertIn("declares no function `check_sound`", self.only())

    def test_a_placeholder_path_needs_one_file_that_matches(self):
        for module in (self.root / "src/stdlib").glob("*.selka"):
            module.unlink()
        found = self.findings()
        self.assertTrue(any("`src/stdlib/<module>.selka` does not exist" in line for line in found), found)

    def test_a_pattern_and_a_directory_are_checked_for_existing(self):
        for source in (self.root / "src/core/runtime").glob("core_*.c"):
            source.unlink()
        found = self.findings()
        self.assertTrue(any("`src/core/runtime/core_*.c` does not exist" in line for line in found), found)

    def test_build_outputs_and_things_that_are_not_paths_are_not_checked(self):
        self.assertEqual(self.findings(), [])
        self.assertFalse(compiler_map.is_path("Own.check"))
        self.assertFalse(compiler_map.is_path("E_CODE"))
        self.assertFalse(compiler_map.is_path("/abs/path.md"))
        self.assertIsNone(compiler_map.expand(self.root, "zig-out/bin/selka"))

    def test_a_fenced_block_is_skipped_and_keeps_the_line_numbers(self):
        masked = compiler_map.mask_fences("a\n```sh\n`src/none.zig`\n```\n`b/c.md`\n")
        self.assertEqual(masked.count("\n"), 5)
        self.assertEqual([(s.text, s.line) for s in compiler_map.spans_of(masked)], [("b/c.md", 5)])

    def test_the_page_may_have_300_lines_of_120_characters(self):
        self.write(PAGE_NAME, PAGE + "x\n" * (compiler_map.LINE_LIMIT + 1))
        self.assertIn("size: the page has", " ".join(self.findings()))
        self.write(PAGE_NAME, PAGE + "y" * (compiler_map.WIDTH_LIMIT + 1) + "\n")
        found = self.findings()
        self.assertEqual(len(found), 1, found)
        self.assertIn("{}:{}: size: the line has {} characters".format(PAGE_NAME, PAGE.count("\n") + 1, compiler_map.WIDTH_LIMIT + 1), found[0])

    def test_a_named_file_outside_the_actions_inputs_is_found(self):
        self.edit("build_test_inputs.zig", '    "src/**/*.c",\n', "")
        found = self.findings()
        where = "{}:{}: inputs: `src/core/runtime/core_text.c` is not covered by `goals_register`".format(PAGE_NAME, self.line("core_text.c: myl_core"))
        self.assertTrue(any(line.startswith(where) for line in found), found)

    def test_a_page_the_inputs_do_not_cover_is_found(self):
        self.edit("build_test_inputs.zig", '    "docs/**/*.md",\n', "")
        self.assertIn("inputs: `docs/tooling/compiler-map.md` is not covered", self.only())

    def test_a_missing_list_is_found(self):
        self.edit("build_test_inputs.zig", "pub const goals_register", "pub const other_list")
        self.assertIn("build_test_inputs.zig: inputs: declares no `goals_register` list", self.only())

    def test_the_command_line_exits_one_with_each_finding_on_stderr(self):
        good = subprocess.run([sys.executable, str(SCRIPT), "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual((good.returncode, good.stderr), (0, ""))
        self.assertIn("compiler map: {} checked".format(PAGE_NAME), good.stdout)
        (self.root / "src/parser.zig").unlink()
        bad = subprocess.run([sys.executable, str(SCRIPT), "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("{}:{}: path:".format(PAGE_NAME, self.line("src/parser.zig: parseModule")), bad.stderr)
        usage = subprocess.run([sys.executable, str(SCRIPT), "--root", str(self.root / "nowhere")], capture_output=True, text=True)
        self.assertEqual(usage.returncode, 2)


class Declarations(unittest.TestCase):
    def test_a_pair_is_a_path_then_a_name_inside_one_span(self):
        for span, expected in (("src/a.zig: f", ("src/a.zig", "f")), ("tests/x.py:  g_2", ("tests/x.py", "g_2"))):
            pair = compiler_map.PAIR.match(span)
            self.assertEqual(pair.groups(), expected, span)
        for span in ("src/a.zig", "src/a.zig:f", "Note: text here", "a: b c"):
            self.assertIsNone(compiler_map.PAIR.match(span), span)


if __name__ == "__main__":
    unittest.main()
