#!/usr/bin/env python3
"""scripts/lane/handback.sh against scratch git repositories with stand-in tools.

Each test builds a small repository (a `main` commit, then a lane change) whose scripts, compiler and Zig are stand-ins that
fail on a marker word in the file they are given, and runs `handback.py` on it. They prove which checks each kind of change
selects, that the exit status alone decides a verdict, that a stale compiler stops the run, that a check that does not fit the
budget is listed LATER and is run by `--rest`, and that a background check is waited for. Run: python3 scripts/lane/handback_test.py
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HANDBACK = Path(__file__).resolve().parent / "handback.py"
STUB_COMPILER = '''#!/usr/bin/env python3
import shutil
import sys
a = sys.argv[1:]
cmd = a[0]
def text(p):
    return open(p).read()
if cmd == "fmt":
    if "BADFMT" in text(a[1]):
        print(a[1] + ":1:1: error[E_FMT]: not formatted as `selka fmt` would")
        sys.exit(1)
elif cmd == "lint":
    if "BADLINT" in text(a[1]):
        print("L_TEST: 1 finding\\nlint: 1 finding(s): 1 blocking, 0 report")
        sys.exit(3)
elif cmd == "doc-coverage":
    print("doc-coverage: 0 failures")
elif cmd == "doctest":
    t = text(a[a.index("--filter") + 1])
    if "HISTORICAL" in t:
        print("Doc examples: 0 files scanned, 0 blocks found, 0 run, 0 checked, 0 skipped, 0 mis-tagged, 0 failed")
        print("Doc examples: no executable blocks found; the extractor or the filter is wrong")
        sys.exit(1)
    if "NOBLOCKS" in t:
        print("Doc examples: 1 files scanned, 16 blocks found, 0 run, 0 checked, 0 skipped, 0 mis-tagged, 0 failed")
        print("Doc examples: no executable blocks found; the extractor or the filter is wrong")
        sys.exit(1)
    if "BADEXAMPLE" in t:
        print("docs/x.md:12: example 2 failed: expected output 3, found 4")
        print("Doc examples: 1 files scanned, 4 blocks found, 3 run, 0 checked, 0 skipped, 0 mis-tagged, 1 failed")
        sys.exit(1)
    print("Doc examples: 1 files scanned, 4 blocks found, 3 run, 1 checked, 0 skipped, 0 mis-tagged, 0 failed")
elif cmd == "build":
    t = text(a[1])
    shutil.copy(a[1], a[a.index("-o") + 1])
    if "BUILDFAIL" in t:
        print(a[1] + ":3:1: error[E_STAND_IN]: the program requires an entry point")
        sys.exit(1)
    if "NOCOUNT" not in t:
        print("selka: union-tags: %d payload reads not justified by a tag test (counted in builds, refused by the gate)" % t.count("UNJUSTIFIED"))
'''
STUB_ZIG = '''#!/bin/sh
shift; shift
rc=0
for f in "$@"; do if grep -q BADZIG "$f"; then echo "$f"; rc=1; fi; done
exit $rc
'''
STUB_PRECOMMIT = '''#!/bin/sh
if [ -n "${STUB_PRECOMMIT_FAIL:-}" ]; then printf '%s\\n' "$STUB_PRECOMMIT_FAIL"; echo "precommit: FAIL (3 s): 1 blocking; report-only (ignore): 5 findings"; exit 1; fi
[ -n "${STUB_PRECOMMIT_SLEEP:-}" ] && sleep "$STUB_PRECOMMIT_SLEEP"
echo "precommit: PASS (3 s)"
'''
STUB_CHEAP = '''import os
import sys
if os.environ.get("STUB_CHEAP_FAIL"):
    print(os.environ["STUB_CHEAP_FAIL"])
    sys.exit(1)
if os.environ.get("STUB_CHEAP_LIES"):
    print("cheap checks: passed (every one)")
    sys.exit(1)
print("cheap checks: passed (zig-format 0.9 s)")
'''
STUB_SWEEP = '''import sys
print("noalloc lint: 3 live sources pass" if "noalloc" in sys.argv[0] else "program check: 216 programs, 0 failures")
'''
PRODUCERS = '''CLOSURES = {
    'tooling-units': (
        'src/tooling_root_test.zig', 'src/doc_coverage.zig',
    ),
}
'''
UNITTEST = '''import os
import unittest


class T(unittest.TestCase):
    def test_it(self):
        self.assertFalse(os.environ.get("STUB_UNITTEST_FAIL"), "stub failure: " + os.environ.get("STUB_UNITTEST_FAIL", ""))
'''
GUEST_TESTS = '''import strings

public func test_a() -> bool:
    return True


public func test_b() -> bool fails str:
    return True


public func test_c(flag: bool) -> bool:
    return flag
'''


def long_parent(test):
    """A folder 210 characters deep to make scratch repositories in: a lane's TMPDIR is long, and so is its log folder."""
    base = tempfile.mkdtemp()
    test.addCleanup(shutil.rmtree, base, True)
    parent = Path(base, "a" * 70, "b" * 70, "c" * 70)
    parent.mkdir(parents=True)
    return parent


class Fixture:
    """A scratch repository on branch `lane` cut from `main`, with stand-in tools; `run` is handback.py on it."""

    def __init__(self, test, parent=None):
        self.dir = tempfile.TemporaryDirectory(dir=parent)
        test.addCleanup(self.dir.cleanup)
        self.root = Path(self.dir.name) / "repo"
        self.home = Path(self.dir.name) / "logs"
        self.root.mkdir()
        self.git("init", "-q", "-b", "main", ".")
        self.write(".gitignore", "zig-out/\n")
        self.write("scripts/precommit.sh", STUB_PRECOMMIT, 0o755)
        self.write("scripts/gate_cheap_checks.py", STUB_CHEAP)
        self.write("scripts/check_noalloc.py", STUB_SWEEP)
        self.write("scripts/check_programs.py", STUB_SWEEP)
        self.write("scripts/verification_producers.py", PRODUCERS)
        self.write("scripts/verification_producers_test.py", UNITTEST)
        self.write("scripts/verification_shard_plan_test.py", UNITTEST)
        self.write("scripts/my_format_exclusions.json", '{"tests/fixtures/": "deliberately ill-formed"}\n')
        self.write("tests/incremental_diff.py", 'print("incremental-diff: 120 steps (seed 1), 0 mismatches; cold check clean 41")\n')
        self.write("src/tooling_root_test.zig", 'test {\n    _ = @import("doc_coverage.zig");\n}\n')
        self.write("src/doc_coverage.zig", "pub fn f() void {}\n")
        self.write("src/sema.zig", "pub fn g() void {}\n")
        self.write("src/sema_test.zig", 'test "g" {}\n')
        self.write("src/core/runtime/rt.c", "int x;\n")
        self.write("docs/guide.md", "# Guide\n")
        self.write("tests/lang/old.selka", GUEST_TESTS)
        self.write("tests/fixtures/ill.selka", "x\n")
        self.write("zig-out/bin/selka", STUB_COMPILER, 0o755)
        self.write("zig", STUB_ZIG, 0o755)
        self.commit("base")
        self.git("checkout", "-q", "-b", "lane")
        self.compiler = self.root / "zig-out" / "bin" / "selka"
        future = time.time() + 30  # newer than every source, as a build after the edits is
        os.utime(self.compiler, (future, future))

    def git(self, *args):
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid", GIT_COMMITTER_NAME="t",
                   GIT_COMMITTER_EMAIL="t@example.invalid")
        out = subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True, env=env)
        assert out.returncode == 0, out.stderr
        return out.stdout

    def write(self, rel, text, mode=0o644):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(mode)

    def commit(self, message="change"):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run(self, *args, **env):
        full = dict(os.environ, HANDBACK_HOME=str(self.home), KIT_ROOT=str(Path(self.dir.name) / "kit"), **env)
        argv = [sys.executable, "-B", str(HANDBACK), "--root", str(self.root), "--compiler", str(self.compiler),
                "--zig", str(self.root / "zig"), *args]
        out = subprocess.run(argv, capture_output=True, text=True, env=full, timeout=120)
        return out.returncode, out.stdout + out.stderr

    def plan(self, *args):
        """{check: 'RUN' or 'SKIP'} from --plan."""
        rc, out = self.run("--plan", *args)
        assert rc == 0, out
        return {m.group(2): m.group(1).strip() for m in re.finditer(r"^(RUN |SKIP) ([^:]+(?::[^:\s]+)?):", out, re.M)}


def status_of(out, name):
    """The line of a check: (status word, the rest) or None."""
    m = re.search(r"^(PASS|FAIL|SKIP|LATER) %s\b(.*)$" % re.escape(name), out, re.M)
    return (m.group(1), m.group(2)) if m else None


class SelectionTests(unittest.TestCase):
    def test_a_docs_only_change_runs_the_cheap_ones_and_the_page_only(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        plan = fx.plan()
        self.assertEqual({k for k, v in plan.items() if v == "RUN"},
                         {"precommit", "cheap-checks", "doc-coverage", "doctest:docs/guide.md"})
        for name in ("zig-fmt", "my-fmt", "my-lint", "union-tags", "noalloc", "programs", "producers", "shard-plans",
                     "incremental-diff", "newly-refused"):
            self.assertEqual(plan[name], "SKIP", name)

    def test_the_whole_run_of_a_docs_only_change_passes_and_ends_with_the_count(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run()
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"(?m)^PASS precommit \(\d+s\)$")
        self.assertRegex(out, r"(?m)^PASS cheap-checks \(\d+s\): cheap checks: passed")
        self.assertRegex(out, r"(?m)^PASS doc-coverage \(\d+s\): doc-coverage: 0 failures$")
        self.assertRegex(out, r"(?m)^PASS doctest:docs/guide.md \(\d+s\): 1 files scanned, 4 blocks found")
        self.assertRegex(out, r"(?m)^SKIP zig-fmt: no Zig file changed$")
        last = out.strip().splitlines()[-1]
        self.assertRegex(last, r"^handback: 4 passed, 0 failed, 10 skipped, 0 later; exit 0; log .+/logs/repo/")
        self.assertTrue((Path(last.rsplit("log ", 1)[1]) / "handback.log").is_file())

    def test_a_verdict_deciding_zig_file_selects_the_slow_pair_and_a_test_file_does_not(self):
        fx = Fixture(self)
        fx.write("src/sema.zig", "pub fn g() void {}\n// edit\n")
        plan = fx.plan()
        self.assertEqual((plan["zig-fmt"], plan["incremental-diff"], plan["newly-refused"], plan["noalloc"], plan["programs"]),
                         ("RUN",) * 5)
        self.assertEqual(plan["shard-plans"], "SKIP")  # no Zig test was added
        fx2 = Fixture(self)
        fx2.write("src/sema_test.zig", 'test "g" {}\n// edit\n')
        plan2 = fx2.plan()
        self.assertEqual((plan2["zig-fmt"], plan2["incremental-diff"], plan2["newly-refused"]), ("RUN", "SKIP", "SKIP"))

    def test_the_c_runtime_and_a_pure_tooling_unit_do_not_decide_a_verdict(self):
        fx = Fixture(self)
        fx.write("src/core/runtime/rt.c", "int x;\n// edit\n")
        fx.write("src/doc_coverage.zig", "pub fn f() void {}\n// edit\n")
        plan = fx.plan()
        self.assertEqual((plan["incremental-diff"], plan["newly-refused"]), ("SKIP", "SKIP"))
        self.assertEqual(plan["producers"], "SKIP")  # edited, not added, and not the root or the closure list

    def test_the_standard_library_in_selka_decides_a_verdict(self):
        fx = Fixture(self)
        fx.write("src/stdlib/strings.selka", "func f() -> int:\n    return 1\n")
        plan = fx.plan()
        self.assertEqual((plan["newly-refused"], plan["my-fmt"], plan["noalloc"]), ("RUN", "RUN", "RUN"))

    def test_my_files_select_the_formatter_and_the_linter_except_where_the_formatter_does_not_look(self):
        fx = Fixture(self)
        fx.write("tests/lang/old.selka", GUEST_TESTS + "\n# edit\n")
        self.assertEqual(fx.plan()["my-fmt"], "RUN")
        fx2 = Fixture(self)
        fx2.write("experiments/x/probe.my", "func main() -> int:\n    return 0\n")
        fx2.write("tests/fixtures/ill.selka", "y\n")
        plan = fx2.plan()
        self.assertEqual((plan["my-fmt"], plan["my-lint"], plan["noalloc"]), ("SKIP", "SKIP", "RUN"))
        rc, out = fx2.run("--plan")
        self.assertIn("my-fmt: no live .selka file changed (", out)

    def test_only_a_new_guest_test_file_selects_union_tags(self):
        fx = Fixture(self)
        fx.write("tests/lang/old.selka", GUEST_TESTS + "\n# edit\n")
        fx.write("tests/lang/helper_support.selka", "func h() -> int:\n    return 1\n")
        self.assertEqual(fx.plan()["union-tags"], "SKIP")  # a changed file and a module without tests
        fx.write("tests/lang/fresh.selka", GUEST_TESTS)
        self.assertEqual(fx.plan()["union-tags"], "RUN")

    def test_a_zig_file_added_under_the_tooling_root_selects_the_closure_check(self):
        fx = Fixture(self)
        fx.write("src/other.zig", "pub fn o() void {}\n")
        self.assertEqual(fx.plan()["producers"], "SKIP")  # added, but the tooling root does not reach it
        fx.write("src/tooling_root_test.zig", 'test {\n    _ = @import("doc_coverage.zig");\n    _ = @import("other.zig");\n}\n')
        self.assertEqual(fx.plan()["producers"], "RUN")

    def test_a_zig_test_or_a_shard_plan_selects_the_shard_plan_test(self):
        fx = Fixture(self)
        fx.write("src/sema_test.zig", 'test "g" {}\n\ntest "added one" {}\n')
        self.assertEqual(fx.plan()["shard-plans"], "RUN")
        fx2 = Fixture(self)
        fx2.write("tests/shard-plans/unit.json", "{}\n")
        self.assertEqual(fx2.plan()["shard-plans"], "RUN")
        fx3 = Fixture(self)
        fx3.write("src/newtest.zig", 'test "brand new" {}\n')  # untracked
        self.assertEqual(fx3.plan()["shard-plans"], "RUN")

    def test_the_base_is_the_merge_base_with_main_and_the_tree_counts_committed_or_not(self):
        fx = Fixture(self)
        fx.write("docs/lane.md", "# lane\n")
        fx.commit("lane commit")
        fx.git("checkout", "-q", "main")
        fx.write("src/sema.zig", "pub fn g() void {}\n// main moved\n")
        fx.commit("main moves")
        fx.git("checkout", "-q", "lane")
        fx.write("docs/guide.md", "# Guide\n\nuncommitted\n")
        plan = fx.plan()
        self.assertEqual(plan["zig-fmt"], "SKIP")  # main's own change to sema.zig is not the lane's
        self.assertEqual(plan["doctest:docs/lane.md"], "RUN")
        self.assertEqual(plan["doctest:docs/guide.md"], "RUN")
        fx.git("add", "-A")
        self.assertEqual(fx.plan()["doctest:docs/guide.md"], "RUN")  # staged counts too
        self.assertNotIn("doctest:docs/lane.md", fx.plan("HEAD"))  # a named base: only what is not committed yet
        self.assertEqual(fx.plan("HEAD")["doctest:docs/guide.md"], "RUN")

    def test_force_with_and_only_select_by_name(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        self.assertEqual(fx.plan("--with", "incremental-diff")["incremental-diff"], "RUN")
        rc, out = fx.run("--only", "precommit")
        self.assertEqual(rc, 0, out)
        self.assertEqual(status_of(out, "precommit")[0], "PASS")
        self.assertIsNone(status_of(out, "cheap-checks"))  # not asked for: not printed, not counted
        self.assertTrue(out.strip().splitlines()[-1].startswith("handback: 1 passed, 0 failed, 0 skipped, 0 later; exit 0"))


class VerdictTests(unittest.TestCase):
    def test_a_failing_tool_is_a_fail_with_its_own_words_and_exit_1(self):
        fx = Fixture(self)
        fx.write("src/sema.zig", "pub fn g() void {} // BADZIG\n")
        fx.write("tests/lang/old.selka", GUEST_TESTS + "# BADFMT BADLINT\n")
        rc, out = fx.run("--only", "zig-fmt,my-fmt,my-lint")
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"(?m)^FAIL zig-fmt \(\d+s\): needs `zig fmt`: src/sema.zig$")
        self.assertRegex(out, r"(?m)^FAIL my-fmt \(\d+s\): 1 of 1 file\(s\): E_FMT tests/lang/old.selka:1: not formatted")
        self.assertRegex(out, r"(?m)^FAIL my-lint \(\d+s\): 1 of 1 file\(s\): lint: 1 finding\(s\): 1 blocking")
        self.assertTrue(out.strip().splitlines()[-1].startswith("handback: 0 passed, 3 failed, 0 skipped, 0 later; exit 1; log "))

    def test_the_exit_status_decides_not_the_words(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run("--only", "cheap-checks", STUB_CHEAP_LIES="1")
        self.assertEqual(rc, 1, out)
        self.assertEqual(status_of(out, "cheap-checks")[0], "FAIL")  # it printed "passed" and exited 1
        self.assertIn("cheap checks: passed (every one)", out)  # the parse chose what to print, not the verdict

    def test_a_failure_prints_at_most_ten_detail_lines_and_cuts_long_ones(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        many = "\n".join("x" * 400 + " error number %d" % i for i in range(40))
        rc, out = fx.run("--only", "precommit", STUB_PRECOMMIT_FAIL=many)
        self.assertEqual(rc, 1)
        detail = [l for l in out.splitlines() if l.startswith("   ")]
        self.assertEqual(len(detail), 10)
        body = out.splitlines()[:-1]  # the last line names the log folder in full, whatever its length
        self.assertTrue(all(len(l) <= 175 for l in body), max(len(l) for l in body))
        self.assertIn("-- precommit", out)

    def test_a_cheap_checks_failure_shows_the_first_problem(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run("--only", "cheap-checks", STUB_CHEAP_FAIL="noise\nerror: docs/x.md:3: coverage is missing")
        self.assertEqual(rc, 1)
        self.assertRegex(out, r"(?m)^FAIL cheap-checks \(\d+s\): error: docs/x.md:3: coverage is missing$")

    def test_doctest_forms_a_page_without_examples_is_skipped_a_failing_example_fails(self):
        fx = Fixture(self)
        fx.write("docs/none.md", "# none NOBLOCKS\n")
        fx.write("docs/history.md", "# old HISTORICAL\n")
        fx.write("docs/bad.md", "# bad BADEXAMPLE\n")
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run("--only", "doctest")
        self.assertEqual(rc, 1, out)
        self.assertEqual(status_of(out, "doctest:docs/none.md")[0], "SKIP")
        self.assertEqual(status_of(out, "doctest:docs/history.md")[0], "SKIP")
        self.assertEqual(status_of(out, "doctest:docs/bad.md")[0], "FAIL")
        self.assertEqual(status_of(out, "doctest:docs/guide.md")[0], "PASS")
        self.assertIn("docs/bad.md", out)
        self.assertIn("expected output 3, found 4", out)

    def test_union_tags_builds_a_stand_in_main_that_calls_the_tests_it_can(self):
        fx = Fixture(self)
        fx.write("tests/lang/fresh.selka", GUEST_TESTS)
        rc, out = fx.run("--only", "union-tags")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"PASS union-tags \(\d+s\): 1 file\(s\), 0 payload reads not justified; "
                              r"tests/lang/fresh.selka: 1 of 3 tests take parameters and are not called")
        log = Path(out.strip().splitlines()[-1].rsplit("log ", 1)[1])
        built = (log / "union-tags-0.bin").read_text()
        self.assertIn("func main() -> int fails str:", built)
        self.assertIn("    _ = test_a()\n", built)
        self.assertIn("    _ = try test_b()\n", built)
        self.assertNotIn("test_c()", built)
        self.assertEqual((fx.root / "tests/lang/fresh.selka").read_text(), GUEST_TESTS)  # the stand-in never touches the tree

    def test_union_tags_counts_fail_and_a_build_that_prints_no_count_is_not_a_pass(self):
        fx = Fixture(self)
        fx.write("tests/lang/fresh.selka", GUEST_TESTS + "# UNJUSTIFIED UNJUSTIFIED\n")
        rc, out = fx.run("--only", "union-tags")
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL union-tags \(\d+s\): tests/lang/fresh.selka: union-tags: 2 payload reads not justified")
        fx2 = Fixture(self, long_parent(self))  # the stand-in's path in the compiler's message is 250 characters long
        fx2.write("tests/lang/fresh.selka", GUEST_TESTS + "# BUILDFAIL\n")
        rc2, out2 = fx2.run("--only", "union-tags")
        self.assertEqual(rc2, 1, out2)
        self.assertGreater(len(str(fx2.home)), 200)
        self.assertRegex(out2, r"(?m)^FAIL union-tags \(\d+s\): E_STAND_IN tests/lang/fresh.selka:3: the program requires an entry point "
                               r"\[the build of tests/lang/fresh.selka was refused\]$")
        fx3 = Fixture(self)
        fx3.write("tests/lang/fresh.selka", GUEST_TESTS + "# NOCOUNT\n")
        rc3, out3 = fx3.run("--only", "union-tags")
        self.assertEqual(rc3, 1, out3)  # exit 0 and no count line: not a pass
        self.assertRegex(out3, r"FAIL union-tags \(\d+s\): tests/lang/fresh.selka: build printed no count")

    def test_a_long_folder_never_cuts_the_diagnostic_away_in_any_check(self):
        fx = Fixture(self, long_parent(self))
        self.assertGreater(len(str(fx.root)), 200)
        fx.write("tests/lang/old.selka", GUEST_TESTS + "# BADFMT BADLINT\n")
        fx.write("tests/lang/fresh.selka", GUEST_TESTS + "# BUILDFAIL\n")
        fx.write("docs/bad.md", "# bad BADEXAMPLE\n")
        rc, out = fx.run("--only", "my-fmt,union-tags,doctest")
        self.assertEqual(rc, 1, out)
        for line in out.splitlines()[:-1]:  # the last line names the log folder in full, whatever its length
            self.assertLessEqual(len(line), 175, line)
        self.assertRegex(out, r"(?m)^FAIL my-fmt \(\d+s\): 1 of 2 file\(s\): E_FMT tests/lang/old.selka:1: not formatted")
        self.assertRegex(out, r"(?m)^FAIL union-tags \(\d+s\): E_STAND_IN tests/lang/fresh.selka:3: ")
        self.assertRegex(out, r"(?m)^FAIL doctest:docs/bad.md \(\d+s\): docs/x.md:12: example 2 failed")
        self.assertNotIn(str(fx.root), out)

    def test_union_tags_with_no_test_it_can_call_builds_nothing_and_skips(self):
        fx = Fixture(self)
        fx.write("tests/lang/params.selka", "public func test_c(flag: bool) -> bool:\n    return flag\n")
        rc, out = fx.run("--only", "union-tags")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"(?m)^SKIP union-tags: tests/lang/params.selka: no test function without a parameter to call$")
        self.assertTrue(out.strip().splitlines()[-1].startswith("handback: 0 passed, 0 failed, 1 skipped"))

    def test_union_tags_builds_a_file_that_has_a_main_as_it_is(self):
        fx = Fixture(self)
        text = GUEST_TESTS + "\nfunc main() -> int:\n    return 0\n"
        fx.write("tests/lang/withmain.selka", text)
        rc, out = fx.run("--only", "union-tags")
        self.assertEqual(rc, 0, out)
        log = Path(out.strip().splitlines()[-1].rsplit("log ", 1)[1])
        self.assertEqual((log / "union-tags-0.bin").read_text(), text)

    def test_union_tags_copies_the_sibling_modules_a_test_imports(self):
        fx = Fixture(self)
        fx.write("tests/lang/fresh_support.selka", "func helper() -> int:\n    return 1\n")
        fx.write("tests/lang/fresh.selka", "import fresh_support as support\n" + GUEST_TESTS)
        rc, out = fx.run("--only", "union-tags")
        self.assertEqual(rc, 0, out)
        log = Path(out.strip().splitlines()[-1].rsplit("log ", 1)[1])
        self.assertTrue((log / "standin" / "0" / "fresh_support.selka").is_file())

    def test_producers_names_a_file_the_closure_list_lacks_and_passes_once_it_is_named(self):
        fx = Fixture(self)
        fx.write("src/fresh.zig", "pub fn f() void {}\n")
        fx.write("src/tooling_root_test.zig", 'test {\n    _ = @import("doc_coverage.zig");\n    _ = @import("fresh.zig");\n}\n')
        rc, out = fx.run("--only", "producers")
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL producers \(\d+s\): src/fresh.zig is reached from src/tooling_root_test.zig but not named in CLOSURES")
        fx.write("scripts/verification_producers.py", PRODUCERS.replace("'src/doc_coverage.zig',", "'src/doc_coverage.zig', 'src/fresh.zig',"))
        rc, out = fx.run("--only", "producers")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"PASS producers \(\d+s\): Ran 1 test")

    def test_a_failing_unit_test_of_the_scripts_is_a_fail_with_its_first_line(self):
        fx = Fixture(self)
        fx.write("tests/shard-plans/unit.json", "{}\n")
        rc, out = fx.run("--only", "shard-plans", STUB_UNITTEST_FAIL="names are not sorted")
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL shard-plans \(\d+s\): .*(FAIL|Assertion|stub failure)")
        self.assertIn("names are not sorted", out)


class SummaryTests(unittest.TestCase):
    def test_the_newly_refused_answer_is_one_line_of_sums(self):
        sys.path.insert(0, str(HANDBACK.parent))
        import handback
        out = ("newly-refused: selka commit x against kit y, 8 units in 255s\n"
               "artifacts-site: newly refused 0, no longer refused 1, warnings +152 -51, fix --check edits by code: W_COPY_MOVE 3\n"
               "selka-sqlite: newly refused 2, no longer refused 0, warnings +0 -0, fix --check edits by code: none\n")
        self.assertEqual(handback.refused_summary(out), "2 projects, newly refused 2, no longer refused 1")
        self.assertEqual(handback.refused_summary("nothing"), "no project line in its output")


class HostTests(unittest.TestCase):
    def test_a_compiler_older_than_the_sources_stops_the_run_in_one_line(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        old = time.time() - 3600
        os.utime(fx.compiler, (old, old))
        rc, out = fx.run()
        self.assertEqual(rc, 2, out)
        self.assertEqual(len(out.strip().splitlines()), 1)
        self.assertRegex(out, r"^handback: zig-out/bin/selka is older than src/[\w/.]+ by \d+ s; build it .*nothing was run")

    def test_a_missing_compiler_or_zig_stops_the_run_and_a_test_file_edit_does_not_make_it_stale(self):
        fx = Fixture(self)
        os.utime(fx.root / "src" / "sema_test.zig", (time.time() + 100, time.time() + 100))
        rc, out = fx.run("--only", "precommit")
        self.assertEqual(rc, 0, out)  # only a file that is no test file counts against the compiler
        fx.compiler.unlink()
        rc, out = fx.run()
        self.assertEqual((rc, out.count("\n")), (2, 1))
        self.assertIn("zig-out/bin/selka is missing", out)
        full = dict(os.environ, HANDBACK_HOME=str(fx.home))
        full.pop("ZIG", None)
        fx.write("zig-out/bin/selka", STUB_COMPILER, 0o755)
        os.utime(fx.compiler, (time.time() + 200, time.time() + 200))
        out = subprocess.run([sys.executable, "-B", str(HANDBACK), "--root", str(fx.root), "--compiler", str(fx.compiler)],
                             capture_output=True, text=True, env=full)
        self.assertEqual(out.returncode, 2, out.stdout)
        self.assertIn("no pinned Zig", out.stdout)

    def test_a_check_that_does_not_fit_the_budget_is_later_and_rest_runs_it(self):
        fx = Fixture(self)
        fx.write("src/sema.zig", "pub fn g() void {}\n// edit\n")
        rc, out = fx.run("--only", "incremental-diff,newly-refused", "--budget", "20")
        self.assertEqual(rc, 3, out)  # nothing failed, but two checks are still to run
        self.assertRegex(out, r"(?m)^LATER incremental-diff: about 40 s, more than the \d+ s left of this command; "
                              r"run: scripts/lane/handback.sh --only incremental-diff --bg$")
        self.assertRegex(out, r"(?m)^LATER newly-refused: about 420 s")
        self.assertRegex(out.strip().splitlines()[-1], r"^handback: 0 passed, 0 failed, 0 skipped, 2 later; exit 3; log ")
        rc, out = fx.run("--rest", "--budget", "100")
        self.assertEqual(rc, 3, out)  # the incremental diff ran and passed; newly-refused (420 s) still does not fit
        self.assertEqual(status_of(out, "incremental-diff")[0], "PASS")
        self.assertIn("120 steps (seed 1), 0 mismatches", out)
        self.assertRegex(out, r"(?m)^LATER newly-refused: about 420 s")

    def test_rest_with_nothing_left_and_without_an_earlier_run_say_so(self):
        fx = Fixture(self)
        rc, out = fx.run("--rest")
        self.assertEqual(rc, 2, out)
        self.assertIn("no earlier run", out)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        fx.run()
        rc, out = fx.run("--rest")
        self.assertEqual(rc, 0, out)
        self.assertIn("left nothing to run", out)

    def test_a_check_that_outlives_the_deadline_is_ended_and_listed_later_not_passed(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        started = time.time()
        rc, out = fx.run("--only", "precommit", "--budget", "9", STUB_PRECOMMIT_SLEEP="60", HANDBACK_GRACE="0")
        self.assertLess(time.time() - started, 30)
        self.assertEqual(rc, 3, out)
        self.assertRegex(out, r"(?m)^LATER precommit: did not finish in \d+ s and was ended; run: scripts/lane/handback.sh --only precommit --bg$")

    def test_a_slow_check_runs_detached_and_wait_prints_its_answer(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run("--only", "precommit", "--bg", STUB_PRECOMMIT_SLEEP="2")
        self.assertEqual(rc, 3, out)
        self.assertRegex(out, r"(?m)^RUNNING precommit: pid \d+, log ")
        self.assertIn("scripts/lane/handback.sh --wait", out)
        rc, out = fx.run("--wait")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"(?m)^PASS precommit \(\d+s\)$")
        self.assertRegex(out.strip().splitlines()[-1], r"^handback: 1 passed, 0 failed, 0 skipped, 0 later; exit 0")
        rc, out = fx.run("--wait")
        self.assertEqual(rc, 2)
        self.assertIn("no background run to wait for", out)

    def test_bg_without_a_check_to_run_is_refused(self):
        fx = Fixture(self)
        fx.write("docs/guide.md", "# Guide\n\nmore\n")
        rc, out = fx.run("--bg")
        self.assertEqual(rc, 2, out)
        self.assertIn("--bg needs --only", out)


if __name__ == "__main__":
    unittest.main()
