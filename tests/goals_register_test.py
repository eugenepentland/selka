#!/usr/bin/env python3
"""The goals-register check against a small repository it writes itself: the real shape passes, and one broken copy per rule fails.

The fixture is a miniature of the real layout (a page, pins, a Lean file, `build.zig` and `build_test_inputs.zig`), so this
test depends on none of the repository's documents or sources. The compiler is a stand-in whose first line of `mode.txt`
chooses what `doctest` reports. The real page, the real pins and the real compiler are checked by the action itself
(`zig build test-goals`), which runs in the gate.
"""
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import goals_register

SCRIPT = Path(goals_register.__file__)

# A stand-in for `selka doctest PINS`: `ok` ends in "0 failed", `fail` reports one failed example, `crash` exits 3 and says nothing.
FAKE_COMPILER = '''#!/usr/bin/env python3
import pathlib, sys
mode = (pathlib.Path(__file__).with_name("mode.txt")).read_text().strip()
assert sys.argv[1] == "doctest"
if mode == "crash":
    sys.exit(3)
if mode == "fail":
    print("  docs/G01.md: 2 run, 0 checked, 0 skipped, 0 mis-tagged, 1 failed")
    print("FAILED docs/G01.md:7: expected ['E_X'], saw ['E_Y']")
    print("Doc examples: 1 files scanned, 3 blocks found, 1 run, 0 checked, 0 skipped, 0 mis-tagged, 1 failed")
    sys.exit(1)
print("Doc examples: 1 files scanned, 3 blocks found, 3 run, 0 checked, 0 skipped, 0 mis-tagged, 0 failed")
'''

PAGE = '''# Goals

## How this page is checked

Gate actions `ownership-proof` (its half) and `goals_register` run it.

## Summary

| Id | Goal | Level today | Open exceptions |
| --- | --- | --- | ---: |
| G1 | Memory safety | Proved | 0 |
| G2 | Local reasoning | Probed | 2 |
| G3 | Nothing implicit | Probed | 1 |

## A. Memory

### G1. No dead reads

- **Evidence.** `Own.check_sound` and `Own.main_no_leak` (`proofs/own/Soundness.lean`). The validator `src/validate.zig`.
  Gate action `ownership-proof`. Pinned examples G1-H1 to G1-H2.
- **Exceptions.** None reproduced.

### G2. Signatures

- **Evidence.** Pinned examples G2-X1 and G2-X2.
- **Exceptions.**
  - A body decides (G2-X1).
  - Another (G2-X2).

### G3. Implicit

- **Evidence.** `Cache.warm_eq_clean` (`proofs/own/Cache.lean`), and `port:docs/Other.md` of the port. G3-X1.
- **Exception.** One thing (G3-X1).

## Changes
'''

PINS = '''# G1 pins

**G1-H1.** One.

```selka
func main() -> int:
    return 0
```

**G1-H2.** Two.

```selka
func main() -> int:
    return 1
```

**G2-X1 and G2-X2 (both).**

```selka
func main() -> int:
    return 2
```

**G3-X1.** Three.

```selka
func main() -> int:
    return 3
```
'''

SOUNDNESS = '''/-- A doc comment that mentions
theorem fake_in_doc : True
-/
namespace Own
-- theorem fake_in_line_comment : True
section Main
theorem check_sound (x : Nat) : x = x := rfl
end Main
@[simp] protected theorem main_no_leak : True := trivial
end Own
'''

CACHE = '''namespace Cache
theorem warm_eq_clean : True := trivial
end Cache
'''

BUILD = '''    verification_registry.?.register("ownership-proof", &proof_run.step, &test_inputs.ownership_proof, true, "x");
    const goals_run = driver(b, "python3 tests/goals_register.py", rss.driver, "goals_register");
'''

INPUTS = '''pub const environment_contract = [_][]const u8{"src/environment_identity.zon"};
pub const ownership_proof = [_][]const u8{"proofs/"} ++ environment_contract;
pub const goals_register = [_][]const u8{
    "docs/goals.md",
    "test/fixtures/goals/",
    "src/**/*.zig",
    "proofs/**/*.lean",
    "build.zig",
    "build_test_inputs.zig",
    "tests/goals_register.py",
    "tests/test_inputs_coverage.py",
} ++ environment_contract;
'''

TREE = {
    "docs/goals.md": PAGE,
    "test/fixtures/goals/docs/G01.md": PINS,
    "test/fixtures/goals/README.md": "# Pins\n",
    "proofs/own/Soundness.lean": SOUNDNESS,
    "proofs/own/Cache.lean": CACHE,
    "src/validate.zig": "// validator\n",
    "build.zig": BUILD,
    "build_test_inputs.zig": INPUTS,
    "tests/goals_register.py": "# the driver\n",
    "tests/test_inputs_coverage.py": "# the parser\n",
}


class Register(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        for name, text in TREE.items():
            self.write(name, text)
        compiler = self.root / "fake-selka"
        compiler.write_text(FAKE_COMPILER)
        compiler.chmod(compiler.stat().st_mode | stat.S_IEXEC)
        self.compiler = str(compiler)
        self.mode("ok")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def mode(self, mode):
        (self.root / "mode.txt").write_text(mode)

    def edit(self, name, old, new):
        path = self.root / name
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new))

    def findings(self):
        return [str(finding) for finding in goals_register.check(self.root, self.compiler).findings]

    def line(self, name, needle):
        """The 1-based line of the first line of a fixture file that holds `needle`."""
        for number, text in enumerate((self.root / name).read_text().splitlines(), 1):
            if needle in text:
                return number
        self.fail("{} not in {}".format(needle, name))

    def only(self):
        found = self.findings()
        self.assertEqual(len(found), 1, found)
        return found[0]

    def test_the_real_shape_passes(self):
        report = goals_register.check(self.root, self.compiler)
        self.assertEqual(report.findings, [])
        self.assertEqual(report.counts["pinned examples"], 5)
        self.assertEqual(report.counts["theorems"], 3)
        self.assertEqual(report.counts["gate actions"], 3)
        self.assertEqual(report.counts["goals"], 3)
        self.assertTrue(report.doctest.endswith("0 failed"))

    # Rule 1: a pinned example fails.
    def test_a_failing_pin_is_reported_at_its_file_and_line(self):
        self.mode("fail")
        self.assertEqual(self.only(), "test/fixtures/goals/docs/G01.md:7: pinned example: failed: expected ['E_X'], saw ['E_Y']")

    def test_a_compiler_that_does_not_end_in_zero_failed_is_reported(self):
        self.mode("crash")
        message = self.only()
        self.assertIn("test/fixtures/goals: pinned example: `selka doctest test/fixtures/goals` exited 3 and did not end with `0 failed`", message)

    # Rule 2: a backquoted repository path does not exist.
    def test_a_missing_evidence_path_is_reported_at_its_line(self):
        self.edit("docs/goals.md", "`src/validate.zig`", "`src/gone.zig`")
        line = self.line("docs/goals.md", "`src/gone.zig`")
        self.assertIn("docs/goals.md:{}: evidence path: `src/gone.zig` does not exist".format(line), self.only())

    def test_a_directory_counts_and_a_file_of_another_repository_is_not_checked(self):
        self.edit("docs/goals.md", "`src/validate.zig`", "`test/fixtures/goals/` and `other-repo:docs/gone.md`")
        self.assertEqual(self.findings(), [])
        self.edit("docs/goals.md", "`test/fixtures/goals/`", "`test/fixtures/nowhere/`")
        self.assertIn("`test/fixtures/nowhere/` does not exist", self.only())

    def test_a_glob_must_match_a_file_and_each_match_is_an_input(self):
        self.edit("docs/goals.md", "`src/validate.zig`", "`src/*.zig`")
        self.assertEqual(self.findings(), [])
        self.edit("docs/goals.md", "`src/*.zig`", "`src/*.lean`")
        self.assertIn("`src/*.lean` does not exist", self.only())

    def test_a_path_inside_a_fenced_block_is_prose(self):
        self.edit("docs/goals.md", "## Changes\n", "## Changes\n\n```bash\ncat src/gone.zig\n```\n")
        self.assertEqual(self.findings(), [])

    # Rule 3: a theorem named with its file is not declared there.
    def test_a_theorem_the_file_does_not_declare_is_reported(self):
        self.edit("docs/goals.md", "`Own.check_sound` and", "`Own.check_unsound` and")
        message = self.only()
        line = self.line("docs/goals.md", "`Own.check_unsound`")
        self.assertIn("docs/goals.md:{}: theorem: `Own.check_unsound` is not declared in proofs/own/Soundness.lean".format(line), message)
        self.assertIn("expected `theorem check_unsound` inside `namespace Own`", message)

    def test_a_theorem_in_the_wrong_namespace_or_without_one_is_reported(self):
        self.edit("docs/goals.md", "`Cache.warm_eq_clean`", "`warm_eq_clean`")
        self.assertIn("`warm_eq_clean` is not declared in proofs/own/Cache.lean", self.only())
        self.edit("docs/goals.md", "`warm_eq_clean`", "`Own.warm_eq_clean`")
        self.assertIn("expected `theorem warm_eq_clean` inside `namespace Own`", self.only())

    def test_a_section_adds_no_namespace_and_a_comment_declares_nothing(self):
        self.edit("docs/goals.md", "`Own.check_sound` and", "`Own.Main.check_sound` and")
        self.assertIn("`Own.Main.check_sound` is not declared", self.only())
        self.edit("docs/goals.md", "`Own.Main.check_sound`", "`Own.fake_in_doc`")
        self.assertIn("`Own.fake_in_doc` is not declared", self.only())
        self.edit("docs/goals.md", "`Own.fake_in_doc`", "`Own.fake_in_line_comment`")
        self.assertIn("`Own.fake_in_line_comment` is not declared", self.only())

    def test_three_names_with_an_oxford_comma_share_one_file(self):
        self.edit("proofs/own/Soundness.lean", "end Own\n", "private lemma helper : True := trivial\nend Own\n")
        self.edit("docs/goals.md", "`Own.check_sound` and `Own.main_no_leak` (", "`Own.check_sound`, `Own.main_no_leak`, and `Own.helper` (")
        self.assertEqual(self.findings(), [])
        self.edit("docs/goals.md", "and `Own.helper` (", "and `Own.absent` (")
        self.assertIn("`Own.absent` is not declared", self.only())

    # Rule 4: a gate action is not registered.
    def test_an_unregistered_gate_action_is_reported_with_the_close_names(self):
        self.edit("docs/goals.md", "Gate action `ownership-proof`", "Gate action `ownership-proofs`")
        message = self.only()
        line = self.line("docs/goals.md", "`ownership-proofs`")
        self.assertIn("docs/goals.md:{}: gate action: `ownership-proofs` is not a verification action registered in build.zig".format(line), message)
        self.assertIn("did you mean `ownership-proof`", message)

    def test_the_words_are_read_in_any_case(self):
        self.edit("docs/goals.md", "Gate action `ownership-proof`", "GATE ACTION `ownership-proofs`")
        self.assertIn("gate action: `ownership-proofs` is not", self.only())

    def test_every_name_of_a_list_of_gate_actions_is_read(self):
        self.edit("docs/goals.md", "Gate actions `ownership-proof` (its half) and `goals_register` run it.",
                  "Gate actions `ownership-proof`, `goals_register` (the check) and `nothing-here` run it.")
        line = self.line("docs/goals.md", "`nothing-here`")
        self.assertIn("docs/goals.md:{}: gate action: `nothing-here` is not a verification action".format(line), self.only())

    # Rule 5: an example id has no pin, or a pin is never cited.
    def test_a_cited_id_without_a_pin_is_reported_at_the_page_line(self):
        self.edit("docs/goals.md", "Pinned examples G2-X1 and G2-X2.", "Pinned examples G2-X1 to G2-X3.")
        line = self.line("docs/goals.md", "G2-X1 to G2-X3")
        self.assertIn("docs/goals.md:{}: example id: G2-X3 is cited but no pin under test/fixtures/goals has that id".format(line), self.only())

    def test_a_pin_the_page_never_cites_is_reported_at_the_pin_line(self):
        self.edit("test/fixtures/goals/docs/G01.md", "**G3-X1.** Three.", "**G3-X1.** Three.\n\n```selka\nfunc main() -> int:\n    return 4\n```\n\n**G3-X2.** Four.")
        line = self.line("test/fixtures/goals/docs/G01.md", "**G3-X2.**")
        self.assertIn("test/fixtures/goals/docs/G01.md:{}: example id: pin G3-X2 is never cited in docs/goals.md".format(line), self.only())

    def test_a_pin_without_an_example_block_and_a_repeated_id_are_reported(self):
        self.edit("test/fixtures/goals/docs/G01.md", "**G1-H2.** Two.\n\n```selka\nfunc main() -> int:\n    return 1\n```\n", "**G1-H2.** Two.\n")
        self.assertIn("pin G1-H2 has no ```selka block", self.only())
        self.edit("test/fixtures/goals/docs/G01.md", "**G1-H2.** Two.", "**G1-H1.** Two.")
        self.assertTrue(any("pin G1-H1 is already defined at test/fixtures/goals/docs/G01.md:3" in line for line in self.findings()))

    def test_a_heading_may_list_ids_with_commas(self):
        self.edit("test/fixtures/goals/docs/G01.md", "**G2-X1 and G2-X2 (both).**", "**G2-X1, G2-X2 (both).**")
        self.assertEqual(self.findings(), [])

    def test_a_range_must_join_two_ids_of_one_goal_in_order(self):
        self.edit("docs/goals.md", "G1-H1 to G1-H2", "G1-H2 to G1-H1")
        self.assertIn("is not a run of ids", self.findings()[0])

    # Rule 6: the exception count of the summary table differs from the entry's list.
    def test_a_table_count_that_differs_from_the_list_is_reported_at_the_table_row(self):
        self.edit("docs/goals.md", "| G2 | Local reasoning | Probed | 2 |", "| G2 | Local reasoning | Probed | 3 |")
        row, entry = self.line("docs/goals.md", "| G2 |"), self.line("docs/goals.md", "A body decides") - 1
        message = "docs/goals.md:{}: exception count: G2 says 3 open exceptions in the summary table but the entry lists 2 (its list is at line {})"
        self.assertIn(message.format(row, entry), self.only())

    def test_exceptions_not_written_as_nested_bullets_are_reported(self):
        self.edit("docs/goals.md", "- **Exceptions.** None reproduced.", "- **Exceptions.** A thing; another thing.")
        self.assertIn("exception count: G1: `**Exceptions.**` has no nested bullets", self.only())
        self.edit("docs/goals.md", "- **Exception.** One thing (G3-X1).", "- **Exceptions.** One thing (G3-X1).")
        self.assertEqual(len(self.findings()), 2)

    def test_deeper_bullets_are_part_of_their_exception(self):
        self.edit("docs/goals.md", "  - A body decides (G2-X1).\n", "  - A body decides (G2-X1).\n    - Because of this.\n    - And of that.\n")
        self.assertEqual(self.findings(), [])

    def test_a_page_without_a_summary_table_reports_each_entry(self):
        self.edit("docs/goals.md", "| G1 | Memory safety | Proved | 0 |\n| G2 | Local reasoning | Probed | 2 |\n| G3 | Nothing implicit | Probed | 1 |\n", "")
        self.assertEqual(len([line for line in self.findings() if "has an entry but no row" in line]), 3)

    def test_a_row_without_an_entry_and_an_entry_without_a_row_are_reported(self):
        self.edit("docs/goals.md", "| G3 | Nothing implicit | Probed | 1 |", "| G4 | Nothing implicit | Probed | 1 |")
        found = self.findings()
        self.assertTrue(any("G3 has an entry but no row" in line for line in found), found)
        self.assertTrue(any("G4 has a row in the summary table but no `### G4.` entry" in line for line in found), found)

    # Rule 6, repeats: a merge that keeps both sides of an edit leaves a second row or a second field.
    def test_a_second_summary_row_for_a_goal_is_reported_with_both_lines(self):
        self.edit("docs/goals.md", "| G3 | Nothing implicit | Probed | 1 |", "| G3 | Nothing implicit | Probed | 1 |\n| G2 | Local reasoning | Probed | 3 |")
        first, second = self.line("docs/goals.md", "| G2 |"), self.line("docs/goals.md", "| G2 | Local reasoning | Probed | 3 |")
        message = "docs/goals.md:{}: duplicate row: G2 has a second row in the summary table (the first is at line {}): keep one"
        self.assertEqual(self.only(), message.format(second, first))
        self.edit("docs/goals.md", "| G2 | Local reasoning | Probed | 3 |", "| G2 | Local reasoning | Probed | 2 |")
        self.assertEqual(self.only(), message.format(second, first))

    def test_a_field_an_entry_gives_twice_is_reported_with_both_lines_and_other_places_are_not(self):
        self.edit("docs/goals.md", "  Gate action `ownership-proof`. Pinned examples G1-H1 to G1-H2.\n",
                  "  Gate action `ownership-proof`. Pinned examples G1-H1 to G1-H2.\n- **Evidence.** The same, again.\n")
        first, second = self.line("docs/goals.md", "- **Evidence.** `Own.check_sound`"), self.line("docs/goals.md", "The same, again")
        message = "docs/goals.md:{}: duplicate field: G1 gives `Evidence` twice (first at line {}): keep one"
        self.assertEqual(self.only(), message.format(second, first))
        self.edit("docs/goals.md", "- **Evidence.** The same, again.\n", "- **Level.** Proved.\n  - **Evidence.** nested.\n```bash\n- **Level.** fenced\n```\n")
        self.assertEqual(self.findings(), [])
        self.edit("docs/goals.md", "- **Level.** Proved.\n", "- **Level.** Proved.\n- **Level.** Again.\n")
        self.assertIn("duplicate field: G1 gives `Level` twice", self.only())

    # Inputs: a named path outside the action's list would leave a stale verdict.
    def test_a_path_the_action_does_not_read_as_an_input_is_reported(self):
        self.edit("build_test_inputs.zig", '    "proofs/**/*.lean",\n', "")
        found = self.findings()
        where = "docs/goals.md:{}: inputs: `proofs/own/Soundness.lean` is not covered by `goals_register`".format(self.line("docs/goals.md", "`Own.check_sound`"))
        self.assertTrue(any(where in line for line in found), found)

    def test_a_missing_list_is_reported(self):
        self.edit("build_test_inputs.zig", "pub const goals_register", "pub const other_list")
        found = self.findings()
        self.assertIn("build_test_inputs.zig: inputs: declares no `goals_register` list", found[0])
        self.assertTrue(any("`goals_register` is not a verification action registered in build.zig" in line for line in found), found)

    def test_the_command_line_exits_one_with_each_finding_on_stderr(self):
        good = subprocess.run([sys.executable, str(SCRIPT), "--compiler", self.compiler, "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn("goals register: docs/goals.md checked (", good.stdout)
        self.edit("docs/goals.md", "`src/validate.zig`", "`src/gone.zig`")
        bad = subprocess.run([sys.executable, str(SCRIPT), "--compiler", self.compiler, "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("docs/goals.md:{}: evidence path: `src/gone.zig` does not exist".format(self.line("docs/goals.md", "`src/gone.zig`")), bad.stderr)
        usage = subprocess.run([sys.executable, str(SCRIPT), "--compiler", self.compiler, "--root", str(self.root / "nowhere")], capture_output=True, text=True)
        self.assertEqual(usage.returncode, 2)

    # DL-7: the same run checks the compiler map when it is given one (`--map`), and not otherwise.
    def map_command(self, *extra):
        return subprocess.run([sys.executable, str(SCRIPT), "--compiler", self.compiler, "--root", str(self.root), *extra], capture_output=True, text=True)

    def test_the_compiler_map_is_checked_when_the_run_is_given_one(self):
        page = "docs/tooling/compiler-map.md"
        self.write(page, "# Map\n\n1. `src/validate.zig: validate` is the validator.\n")
        self.write("src/validate.zig", "pub fn validate() void {}\n")
        self.edit("build_test_inputs.zig", '    "docs/goals.md",\n', '    "docs/goals.md",\n    "docs/tooling/compiler-map.md",\n')
        report = goals_register.check(self.root, self.compiler, map_page=page)
        self.assertEqual(report.findings, [])
        self.assertEqual((report.counts["map paths"], report.counts["map functions"]), (1, 1))
        self.assertEqual(self.map_command("--map", page).returncode, 0)
        self.write("src/validate.zig", "pub fn check() void {}\n")
        bad = self.map_command("--map", page)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("{}:3: function: `src/validate.zig` declares no function `validate`".format(page), bad.stderr)
        self.assertEqual(self.map_command().returncode, 0, "without --map the page is not read")

    def test_a_compiler_map_that_is_not_there_is_a_usage_error(self):
        missing = self.map_command("--map", "docs/tooling/compiler-map.md")
        self.assertEqual(missing.returncode, 2)
        self.assertIn("the compiler map docs/tooling/compiler-map.md is not found", missing.stderr)


class Parsing(unittest.TestCase):
    def test_lean_names_follow_namespaces_sections_and_comments(self):
        text = "namespace A.B\nsection\ntheorem t1 : True := trivial\nend\nnamespace C\n/- theorem no : True -/\ntheorem _root_.t2 : True\nend C\nend A.B\ntheorem t3 : True\n"
        self.assertEqual(sorted(goals_register.lean_theorems(text)), ["A.B.t1", "t2", "t3"])

    def test_a_nested_block_comment_hides_its_declarations(self):
        text = "/- outer /- inner -/ theorem hidden : True -/\ntheorem seen : True\n"
        self.assertEqual(list(goals_register.lean_theorems(text)), ["seen"])

    def test_fences_are_masked_without_moving_lines(self):
        text = "a\n```bash\n`x/y.md`\n```\n`b`\n"
        masked = goals_register.mask_fences(text)
        self.assertEqual(masked.count("\n"), text.count("\n"))
        spans = goals_register.code_spans(masked)
        self.assertEqual([(s.text, s.line) for s in spans], [("b", 5)])

    def test_paths_need_a_slash_or_a_file_extension(self):
        for token in ("docs/goals.md", "CLAUDE.md", "proofs/arith", "test/fixtures/goals/", "build.zig"):
            self.assertTrue(goals_register.is_path(token), token)
        for token in ("/", ".md", "Own.check_sound", "port:docs/x.md", "selka doctest", "G9-H1", "E_SYNTAX", "/abs/path.md", "~/x.md"):
            self.assertFalse(goals_register.is_path(token), token)

    def test_ranges_expand_to_every_id(self):
        ids = [item[0] for item in goals_register.expand_ids("G7-X3 to G7-X6 and G9-H1 to G9-H2, G8-X1")]
        self.assertEqual(ids, ["G7-X3", "G7-X4", "G7-X5", "G7-X6", "G9-H1", "G9-H2", "G8-X1"])


if __name__ == "__main__":
    unittest.main()
