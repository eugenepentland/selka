#!/usr/bin/env python3
"""Tests of scripts/rename_to_selka.py on small made-up trees: the suffix rule's bounds, the order of the rules, the
kept list, idempotence and project mode. Run: python3 scripts/rename_to_selka_test.py"""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rename_to_selka as program  # noqa: E402

MARKER = "### The newest entry today"


def rewrite(text, path="", **options):
    new, counts, _, _, _ = program.apply_rules(text, program.Config(**options), path)
    return new, counts


def git(root, *args):
    subprocess.run(["git", "-C", str(root), "-c", "user.email=t@example.org", "-c", "user.name=t", "-c", "commit.gpgsign=false",
                    *args], check=True, capture_output=True)


def write(root, files):
    for name, text in files.items():
        path = Path(root) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text if isinstance(text, bytes) else text.encode())


def run_main(*args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = program.main(list(args))
    return status, out.getvalue(), err.getvalue()


class RuleTests(unittest.TestCase):
    def test_suffix_rule_takes_a_source_suffix_in_every_place_text_names_one(self):
        text = 'main.my `a.my` "b.my" *.my (c.my) d.my:3 e.my, [f](g/h.my) sed s/.my/ ".my"'
        self.assertEqual(rewrite(text)[0], text.replace(".my", ".selka"))

    def test_suffix_rule_leaves_what_only_starts_like_the_suffix(self):
        for text in (".mylang", ".mypy_cache", ".mysql", ".my_format", "x.my1", ".mylang-cache/", "~/.my.cnf", "a/.my.ini",
                     "obj.my(1)", "table.my[2]"):
            expected = text.replace(".mylang-cache", ".selka-cache").replace(".mylang", ".selka")
            self.assertEqual(rewrite(text)[0], expected, text)

    def test_suffix_rule_counts_do_not_count_the_interface_suffix(self):
        new, counts = rewrite("lib.myi and lib.my")
        self.assertEqual(new, "lib.selkai and lib.selka")
        self.assertEqual((counts["suffix-interface"], counts["suffix-source"]), (1, 1))

    def test_longer_names_win_over_shorter_ones(self):
        new, counts = rewrite("zig-out/bin/mylang libexec/mylang/components mylang.commit.index mylang.json .mylang-cache")
        self.assertEqual(new, "zig-out/bin/selka libexec/selka/components selka.commit.index selka.json .selka-cache")
        for rule in ("install-bin", "install-libexec", "commit-file", "project-file", "cache-project"):
            self.assertEqual(counts[rule], 1, rule)
        self.assertEqual(counts["name-word"], 0)

    def test_the_catch_all_keeps_the_case_of_the_spelling(self):
        self.assertEqual(rewrite("mylang MYLANG MyLang Mylang mylang_core MYLANGfoo")[0], "selka SELKA Selka Selka selka_core SELKAfoo")

    def test_variables_and_per_user_directories(self):
        new, counts = rewrite("MYLANG_JOBS MYL_CORE_LEAKCHECK ~/.cache/mylang $XDG_CACHE_HOME/mylang/x ~/.config/mylang/dev-env.sh")
        self.assertEqual(new, "SELKA_JOBS SELKA_CORE_LEAKCHECK ~/.cache/selka $XDG_CACHE_HOME/selka/x ~/.config/selka/dev-env.sh")
        self.assertEqual((counts["env-mylang"], counts["env-myl-core"], counts["user-dirs"]), (1, 1, 3))

    def test_fences_and_the_prose_marker(self):
        new, counts = rewrite('```mylang\n# doc: not-mylang\n~~~mylang\n"```mylang\\n"\n```mylangx\n```my\n~~~my\n```mysql\n```my_x\n')
        self.assertEqual(new, '```selka\n# doc: not-selka\n~~~selka\n"```selka\\n"\n```selkax\n```selka\n~~~selka\n```mysql\n```my_x\n')
        self.assertEqual(counts["fence"], 5)

    def test_runner_names_change_and_the_guardian_project_does_not(self):
        text = ("--guardian-shard=1/4 --guardian-shard-plan --guardian-test-filter=x --guardian-test-list=f --guardian-filter=a "
                "guardian/test: GUARDIAN_TEST_TIMINGS ../guardian-zig guardian.toml GUARDIAN_SKIP_CHECKS guardian-check "
                "https://github.com/eugenepentland/guardian-zig")
        want = ("--test-shard=1/4 --test-shard-plan --test-filter=x --test-list=f --test-announce-filter=a test: SELKA_TEST_TIMINGS "
                "../guardian-zig guardian.toml GUARDIAN_SKIP_CHECKS guardian-check https://github.com/eugenepentland/guardian-zig")
        self.assertEqual(rewrite(text)[0], want)

    def test_the_announced_filter_and_the_runtime_filter_stay_two_flags(self):
        # tools/test_runner tells them apart by prefix: one spelling would make the second branch unreachable.
        new = rewrite("--guardian-filter=a --guardian-test-filter=b")[0]
        flags = [word.split("=")[0] for word in new.split()]
        self.assertEqual(len(set(flags)), 2, new)
        self.assertFalse(any(flag.startswith("--filter") for flag in flags))

    def test_the_checkout_and_worktree_folders_keep_their_names(self):
        text = "/home/u/ai/canopy/mylang/scripts/x.my and ~/ai/canopy/mylang-worktrees/a/.mylang-cache and ~/ai/.home-cache/mylang-rf/bin/mylang"
        want = "/home/u/ai/canopy/mylang/scripts/x.selka and ~/ai/canopy/mylang-worktrees/a/.selka-cache and ~/ai/.home-cache/mylang-rf/bin/selka"
        self.assertEqual(rewrite(text)[0], want)

    def test_a_live_file_that_names_a_path_in_a_kept_folder_keeps_the_spelling(self):
        text = '"experiments/x/main.my" !experiments/**/*.my [a](velocity/q/a.my) docs/audits/mylang-plan.md src/main.my'
        want = '"experiments/x/main.my" !experiments/**/*.my [a](velocity/q/a.my) docs/audits/mylang-plan.md src/main.selka'
        self.assertEqual(rewrite(text)[0], want)
        changed = rewrite(text, rewrite_kept=frozenset({"history-experiments", "history-velocity", "history-audits"}))[0]
        self.assertEqual(changed, text.replace(".my", ".selka").replace("mylang", "selka"))

    def test_a_line_that_says_rename_keep_is_left_alone(self):
        text = 'getenv("MYLANG_OPTIONS"); /* rename: keep */\ngetenv("MYLANG_JOBS");\n'
        self.assertEqual(rewrite(text)[0], 'getenv("MYLANG_OPTIONS"); /* rename: keep */\ngetenv("SELKA_JOBS");\n')

    def test_the_recorded_compilers_of_the_thresholds_file_keep_their_name(self):
        text = '"compiler": "/home/u/ai/.home-cache/mylang-pins/x/bin/mylang",'
        self.assertEqual(rewrite(text, "bench/parity/thresholds.json")[0], text)
        self.assertEqual(rewrite(text, "scripts/other.py")[0], '"compiler": "/home/u/ai/.home-cache/mylang-pins/x/bin/selka",')

    def test_the_symbol_group_is_off_and_one_switch_turns_it_on(self):
        text = 'myl_core_exit MYL_KIND_BYTES MYL_CORE_LOCAL @"my.f" @\\"my.{s}\\" mylang-core: mylang-core-store.timer "my." raw'
        on, _ = rewrite(text, with_symbols=True)
        self.assertEqual(on, 'selka_core_exit SELKA_KIND_BYTES SELKA_CORE_LOCAL @"selka.f" @\\"selka.{s}\\" selka-core: selka-core-store.timer "selka." raw')
        off, counts = rewrite(text)
        self.assertEqual(off, 'myl_core_exit MYL_KIND_BYTES SELKA_CORE_LOCAL @"my.f" @\\"my.{s}\\" selka-core: selka-core-store.timer "my." raw')
        self.assertEqual(counts["runtime-symbol"] + counts["producer"], 0)

    def test_the_producer_string_stays_where_it_is_written_as_the_producer_and_nowhere_else(self):
        text = ('producer: \\"mylang-core\\", isOptimized\n if (strcmp(cu.producer, "mylang-core") != 0) continue;\n'
                '/* carries producer "mylang-core". */\n"mylang-core: cache: 3 units" the old `mylang-core` executable\n')
        want = ('producer: \\"mylang-core\\", isOptimized\n if (strcmp(cu.producer, "mylang-core") != 0) continue;\n'
                '/* carries producer "mylang-core". */\n"selka-core: cache: 3 units" the old `selka-core` executable\n')
        self.assertEqual(rewrite(text, "src/core/emit_llvm.zig")[0], want)
        self.assertEqual(rewrite(text, "src/core/emit_llvm.zig", with_symbols=True)[0], text.replace("mylang-core", "selka-core"))

    def test_sibling_folders_named_without_their_parent_keep_their_names(self):
        text = "mylang-lane-s4/x mylang-map-refresh ../mylang-evidence-archive/e mylang-gate mylang-worktrees/a"
        self.assertEqual(rewrite(text)[0], text)
        other = "fix.md#mylang-fix mylang-fix-lines x-mylang-gate mylang-gates mylang-core-store.timer"
        self.assertEqual(rewrite(other)[0], "fix.md#selka-fix selka-fix-lines x-selka-gate selka-gates selka-core-store.timer")

    def test_quoted_my_symbols_only_inside_the_core(self):
        self.assertEqual(rewrite('"my.f"', "src/core/x.zig", with_symbols=True)[0], '"selka.f"')
        self.assertEqual(rewrite('"my.example.org"', "docs/x.md", with_symbols=True)[0], '"my.example.org"')
        self.assertEqual(rewrite('"my.f"', "src/core/x.zig")[0], '"my.f"')

    def test_language_labels_follow_everywhere_including_src(self):
        self.assertEqual(rewrite('lang == "my"', "bench/x.py")[0], 'lang == "selka"')
        self.assertEqual(rewrite("{ 'selka', 'my' }", "src/x.zig")[0], "{ 'selka', 'selka' }")
        self.assertEqual(rewrite('"my.example.org" "mysql" "my_x"', "docs/x.md")[0], '"my.example.org" "mysql" "my_x"')

    def test_every_rule_is_idempotent_on_its_own_output(self):
        text = ("bin/mylang MYLANG_X MYL_CORE_Y MYL_Z myl_f @\"my.q\" main.my lib.myi mylang.json .mylang-cache ```mylang\n"
                "--guardian-shard=1/2 guardian/test: GUARDIAN_TEST_X not-mylang mylang-core: MyLang ~/.cache/mylang\n")
        for symbols in (False, True):
            once, _ = rewrite(text, "src/core/x.zig", with_symbols=symbols)
            twice, counts = rewrite(once, "src/core/x.zig", with_symbols=symbols)
            self.assertEqual(once, twice)
            self.assertEqual(sum(counts.values()), 0)

    def test_the_zig_package_fingerprint_follows_the_name(self):
        zon = ".{\n    .name = .mylang,\n    .fingerprint = 0xe12764e71b51fef7,\n}\n"
        once, counts = rewrite(zon, "build.zig.zon")
        self.assertEqual(once, ".{\n    .name = .selka,\n    .fingerprint = 0x89d9bbd51b51fef7,\n}\n")
        self.assertEqual(counts["zon-fingerprint"], 1)
        self.assertEqual(rewrite(once, "build.zig.zon")[0], once)
        self.assertEqual(rewrite(zon, "other.zon")[0], zon.replace("mylang", "selka"))

    def test_the_watch_finds_length_arithmetic_after_a_suffix_literal(self):
        code = 'if (endsWith(u8, path, ".my")) path[0 .. path.len - 3] else path\n' + "x\n" * 12 + "n = len - 3\n"
        self.assertEqual(program.suffix_length_sites(code), 1)

    def test_the_table_is_ordered_longer_before_shorter_and_has_one_catch_all(self):
        names = [rule.name for rule in program.RULES]
        self.assertLess(names.index("install-bin"), names.index("name-word"))
        self.assertLess(names.index("project-file"), names.index("name-word"))
        self.assertLess(names.index("env-myl-core"), names.index("runtime-macro"))
        self.assertLess(names.index("suffix-interface"), names.index("suffix-source"))
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(all(rule.what for rule in program.RULES))

    def test_the_cut_keeps_the_decided_folders_and_rewrites_the_recorded_logs(self):
        kept = {keep.pattern for keep in program.KEPT}
        self.assertIn("docs/experiments/", kept)
        self.assertNotIn("test/fixtures/gate-summary/*.log", kept)
        self.assertNotIn("scripts/run-report-fixtures/*.log", kept)

    def test_the_default_markers_are_the_rename_entry_and_the_newest_entry_the_cut_starts_from(self):
        first, second = program.CHANGES_KEPT_FROM
        self.assertTrue(first.startswith("### The language is called `selka` now"))
        self.assertTrue(second.startswith("### The product's names live in `src/product.zig`"))

    def test_a_gitignore_keeps_each_old_line_and_adds_the_new_one_beside_it(self):
        text = (".mylang-cache/\nenv.my\n# the mylang cache\nzig-out/\nexperiments/**/.mylang-cache/\n"
                "!experiments/**/*.my\nplain.my.cnf\nlast.my")
        want = (".mylang-cache/\n.selka-cache/\nenv.my\nenv.selka\n# the selka cache\nzig-out/\n"
                "experiments/**/.mylang-cache/\nexperiments/**/.selka-cache/\n!experiments/**/*.my\n!experiments/**/*.selka\n"
                "plain.my.cnf\nlast.my\nlast.selka\n")
        once, counts = program.pair_ignore_lines(text, program.Config(), ".gitignore")
        self.assertEqual(once, want)
        self.assertEqual(counts["cache-project"], 2)
        twice, again = program.pair_ignore_lines(once, program.Config(), ".gitignore")
        self.assertEqual(twice, once)
        self.assertEqual(sum(again.values()), 0)


class TreeTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        write(self.root, {
            "src/a.my": "import b\n# see mylang.json and MYLANG_JOBS\n",
            "src/b.my": "func f():\n    pass\n",
            "mylang.json": '{"entry": "src/a.my"}\n',
            "README.md": "run `mylang check src/a.my`\n```mylang\nfunc main():\n    pass\n```\n",
            "scripts/mylang-core-store.timer": "[Timer]\n",
            "src/runtime/myl_bare.h": "#define MYL_BARE 1\n",
            "CHANGES.md": "# Changes\nthe mylang fix\n\n%s\nold mylang entry, main.my\n" % MARKER,
            "docs/audits/old.md": "mylang audit of main.my\n",
            "experiments/run/main.my": "mylang\n",
            "test/fixtures/gate-summary/g.log": "guardian/test: FAIL mylang\n",
            "docs/experiments/run.md": "the mylang run of main.my\n",
            ".gitignore": ".mylang-cache/\n.pending/\n",
            "tools/test_runner/test_runner.zig": "// Copied from guardian-zig (https://github.com/x/guardian-zig) unchanged below this line\n"
                                                 "const flag = \"--guardian-shard=\"; // mylang\n",
            "data/blob.bin": b"mylang\x00\x01main.my",
            "bench/results/r_20261009.json": "{}",
        })
        git(self.root, "init", "-q")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "start")
        self.marker = ["--changes-kept-from", MARKER, "--root", str(self.root)]

    def tearDown(self):
        self.dir.cleanup()

    def tracked(self):
        out = subprocess.run(["git", "-C", str(self.root), "ls-files"], capture_output=True, text=True).stdout
        return set(out.split())

    def test_report_changes_nothing_and_is_deterministic(self):
        first = run_main("--report", *self.marker)
        second = run_main("--report", *self.marker)
        self.assertEqual(first[0], 0)
        self.assertEqual(first[1], second[1])
        status = subprocess.run(["git", "-C", str(self.root), "status", "--porcelain"], capture_output=True, text=True).stdout
        self.assertEqual(status, "")
        self.assertIn("TOTAL:", first[1])
        self.assertIn("files moved", first[1])

    def test_apply_moves_rewrites_and_keeps(self):
        status, out, err = run_main("--apply", *self.marker)
        self.assertEqual((status, err), (0, ""), out)
        self.assertEqual(self.tracked(), {
            "src/a.selka", "src/b.selka", "selka.json", "README.md", "scripts/selka-core-store.timer", "src/runtime/myl_bare.h",
            "CHANGES.md", "docs/audits/old.md", "experiments/run/main.my", "test/fixtures/gate-summary/g.log",
            "docs/experiments/run.md", ".gitignore", "tools/test_runner/test_runner.zig", "data/blob.bin",
            "bench/results/r_20261009.json"})
        read = lambda name: (self.root / name).read_text()
        self.assertEqual(read("src/a.selka"), "import b\n# see selka.json and SELKA_JOBS\n")
        self.assertEqual(read("selka.json"), '{"entry": "src/a.selka"}\n')
        self.assertEqual(read("README.md"), "run `selka check src/a.selka`\n```selka\nfunc main():\n    pass\n```\n")
        self.assertEqual(read("src/runtime/myl_bare.h"), "#define MYL_BARE 1\n")
        self.assertEqual(read("CHANGES.md"), "# Changes\nthe selka fix\n\n%s\nold mylang entry, main.my\n" % MARKER)
        self.assertEqual(read("docs/audits/old.md"), "mylang audit of main.my\n")
        self.assertEqual(read("experiments/run/main.my"), "mylang\n")
        self.assertEqual(read("test/fixtures/gate-summary/g.log"), "test: FAIL selka\n")
        self.assertEqual(read("docs/experiments/run.md"), "the mylang run of main.my\n")
        self.assertEqual(read(".gitignore"), ".mylang-cache/\n.selka-cache/\n.pending/\n")
        self.assertEqual(read("tools/test_runner/test_runner.zig"),
                         "// Copied from guardian-zig (https://github.com/x/guardian-zig) unchanged below this line\n"
                         "const flag = \"--test-shard=\"; // selka\n")
        self.assertEqual((self.root / "data/blob.bin").read_bytes(), b"mylang\x00\x01main.my")

    def test_a_second_apply_changes_nothing_and_says_so(self):
        run_main("--apply", *self.marker)
        before = subprocess.run(["git", "-C", str(self.root), "status", "--porcelain"], capture_output=True, text=True).stdout
        status, out, _ = run_main("--apply", *self.marker)
        after = subprocess.run(["git", "-C", str(self.root), "status", "--porcelain"], capture_output=True, text=True).stdout
        self.assertEqual(status, 0)
        self.assertIn("nothing to change", out)
        self.assertEqual(before, after)

    def test_the_renames_are_git_moves(self):
        run_main("--apply", *self.marker)
        status = subprocess.run(["git", "-C", str(self.root), "status", "--porcelain"], capture_output=True, text=True).stdout
        self.assertRegex(status, r"(?m)^R[ M] src/a.my -> src/a.selka$")

    def test_a_dirty_tree_is_refused(self):
        (self.root / "README.md").write_text("changed by hand mylang\n")
        status, _, err = run_main("--apply", *self.marker)
        self.assertEqual(status, 2)
        self.assertIn("uncommitted", err)
        self.assertTrue((self.root / "src/a.my").exists())

    def test_the_program_does_not_rewrite_itself(self):
        write(self.root, {"scripts/rename_to_selka.py": 'OLD = "mylang"\n', "scripts/rename_to_selka_test.py": 'OLD = "MYLANG_"\n'})
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "program")
        run_main("--apply", *self.marker)
        self.assertEqual((self.root / "scripts/rename_to_selka.py").read_text(), 'OLD = "mylang"\n')
        self.assertEqual((self.root / "scripts/rename_to_selka_test.py").read_text(), 'OLD = "MYLANG_"\n')

    def test_the_first_marker_found_from_the_top_ends_the_rewritten_part(self):
        changes = "# Changes\nthe mylang fix\n\n### the rename\nmylang.json is selka.json now\n\n### the old one\nold mylang entry\n"
        cut = changes.index("### the rename")
        for markers in (("### the rename", "### the old one"), ("### the old one", "### the rename")):
            parts = program.split_kept("CHANGES.md", changes, program.Config(changes_kept_from=markers))
            self.assertEqual(parts, ("", changes[:cut], changes[cut:]))
        # A branch that predates the rename has only the older entry, and the same list serves it.
        before = changes[:cut] + changes[changes.index("### the old one"):]
        parts = program.split_kept("CHANGES.md", before, program.Config(changes_kept_from=("### the rename", "### the old one")))
        self.assertEqual(parts[2], "### the old one\nold mylang entry\n")

    def test_a_file_that_says_rename_keep_file_in_its_first_lines_is_not_rewritten(self):
        write(self.root, {"src/hints.zig": "//! rename: keep-file\nconst old = \"MYLANG_X\";\n", "src/late.zig": "\n" * 9 + "// rename: keep-file\nconst x = \"MYLANG_X\";\n"})
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "marked")
        run_main("--apply", *self.marker)
        self.assertEqual((self.root / "src/hints.zig").read_text(), "//! rename: keep-file\nconst old = \"MYLANG_X\";\n")
        self.assertIn("SELKA_X", (self.root / "src/late.zig").read_text())

    def test_a_missing_changes_marker_is_refused(self):
        status, _, err = run_main("--apply", "--root", str(self.root), "--changes-kept-from", "### not there")
        self.assertEqual(status, 2)
        self.assertIn("marker", err)

    def test_a_name_that_would_replace_a_file_is_refused(self):
        write(self.root, {"src/b.selka": "already here\n"})
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "clash")
        status, _, err = run_main("--apply", *self.marker)
        self.assertEqual(status, 2)
        self.assertIn("two files become src/b.selka", err)

    def test_the_symbol_group_is_off_unless_asked(self):
        run_main("--apply", *self.marker)
        self.assertIn("src/runtime/myl_bare.h", self.tracked())
        self.assertEqual((self.root / "src/runtime/myl_bare.h").read_text(), "#define MYL_BARE 1\n")

    def test_with_symbols_renames_runtime_names_and_their_files(self):
        run_main("--apply", "--with-symbols", *self.marker)
        self.assertIn("src/runtime/selka_bare.h", self.tracked())
        self.assertEqual((self.root / "src/runtime/selka_bare.h").read_text(), "#define SELKA_BARE 1\n")

    def test_rewrite_kept_overrides_one_entry(self):
        run_main("--apply", "--rewrite-kept", "history-doc-experiments", *self.marker)
        self.assertEqual((self.root / "docs/experiments/run.md").read_text(), "the selka run of main.selka\n")
        self.assertEqual((self.root / "docs/audits/old.md").read_text(), "mylang audit of main.my\n")

    def test_an_untracked_folder_is_neither_a_reason_to_refuse_nor_touched(self):
        write(self.root, {".guardian/cache/x.my": "mylang MYLANG_X\n", "scratch.my": "mylang\n"})
        status, out, err = run_main("--apply", *self.marker)
        self.assertEqual((status, err), (0, ""), out)
        self.assertEqual((self.root / ".guardian/cache/x.my").read_text(), "mylang MYLANG_X\n")
        self.assertEqual((self.root / "scratch.my").read_text(), "mylang\n")
        self.assertTrue((self.root / "src/a.selka").exists())

    def test_the_report_lists_what_no_rule_covers(self):
        write(self.root, {"src/c.zig": 'const call = thing.my(1);\nconst tag = "```my";\n'})
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "label")
        _, out, _ = run_main("--report", *self.marker)
        self.assertIn("src/c.zig:1: [suffix-left] const call = thing.my(1);", out)
        self.assertNotIn("src/c.zig:2", out)
        self.assertIn("-- src (", out)


class ProjectTests(unittest.TestCase):
    FILES = {
        "main.my": "import lib\n# mylang\n",
        "lib.my": "public func f() -> int:\n    return 1\n",
        "lib.myi": "interface\n",
        "mylang.json": '{"entry": "main.my"}\n',
        ".gitignore": ".mylang-cache/\nzig-out/\n",
        "run.sh": "MYLANG_JOBS=2 mylang check main.my\nmylang_helper=1\n",
        "docs/guide.md": "```mylang\nfunc main():\n    pass\n```\nthe mylang command\n",
        ".mylang-cache/skipped.my": "cache\n",
        "data.bin": b"main.my\x00",
    }

    def test_a_folder_that_is_not_a_repository_is_renamed_in_place(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, self.FILES)
            status, out, err = run_main("--project", folder)
            self.assertEqual((status, err), (0, ""), out)
            names = sorted(str(p.relative_to(folder)) for p in Path(folder).rglob("*") if p.is_file())
            self.assertEqual(names, sorted([".gitignore", ".mylang-cache/skipped.my", "data.bin", "docs/guide.md", "lib.selka",
                                            "lib.selkai", "main.selka", "run.sh", "selka.json"]))
            read = lambda name: (Path(folder) / name).read_text()
            self.assertEqual(read("main.selka"), "import lib\n# selka\n")
            self.assertEqual(read("selka.json"), '{"entry": "main.selka"}\n')
            self.assertEqual(read(".gitignore"), ".mylang-cache/\n.selka-cache/\nzig-out/\n")
            self.assertEqual(read("run.sh"), "SELKA_JOBS=2 selka check main.selka\nmylang_helper=1\n")
            self.assertEqual(read("docs/guide.md"), "```selka\nfunc main():\n    pass\n```\nthe selka command\n")
            self.assertEqual((Path(folder) / "data.bin").read_bytes(), b"main.my\x00")
            self.assertIn("mylang_helper", out)

    def test_project_mode_applies_neither_the_symbol_group_nor_the_repository_kept_list(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, {"experiments/x.my": "a\n", "c.h": "myl_core MYL_X\n"})
            run_main("--project", folder)
            self.assertTrue((Path(folder) / "experiments/x.selka").exists())
            self.assertEqual((Path(folder) / "c.h").read_text(), "myl_core MYL_X\n")

    def test_a_link_follows_what_it_points_at(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, {"lib/sqlite.my": "x\n"})
            os.symlink("lib/sqlite.my", Path(folder) / "sqlite.my")
            status, out, err = run_main("--project", folder)
            self.assertEqual((status, err), (0, ""), out)
            link = Path(folder) / "sqlite.selka"
            self.assertTrue(link.is_symlink())
            self.assertEqual(os.readlink(link), "lib/sqlite.selka")
            self.assertEqual(link.read_text(), "x\n")
            self.assertEqual(run_main("--project", folder)[1].strip().split(":")[0], "nothing to change")

    def test_project_mode_takes_the_shell_variable_and_the_installed_command_path(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, {"env.sh": 'export MYLANG=${MYLANG:-$HOME/ai/canopy/mylang-gate/zig-out/bin/mylang}\n"$MYLANG" check a.my\n'})
            run_main("--project", folder)
            self.assertEqual((Path(folder) / "env.sh").read_text(),
                             'export SELKA=${SELKA:-$HOME/ai/canopy/mylang-gate/zig-out/bin/selka}\n"$SELKA" check a.selka\n')

    def test_a_second_project_run_changes_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, self.FILES)
            run_main("--project", folder)
            status, out, _ = run_main("--project", folder)
            self.assertEqual(status, 0)
            self.assertIn("nothing to change", out)

    def test_a_project_report_changes_nothing_and_counts_what_the_crossing_would_do(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, self.FILES)
            listing = lambda: sorted(str(p.relative_to(folder)) for p in Path(folder).rglob("*") if p.is_file())
            before = listing()
            status, out, err = run_main("--project", folder, "--report")
            self.assertEqual((status, err), (0, ""), out)
            self.assertIn("TOTAL:", out)
            self.assertEqual(listing(), before)
            self.assertEqual((Path(folder) / "main.my").read_text(), self.FILES["main.my"])
            status, out, err = run_main("--project", folder, "--apply")
            self.assertEqual((status, err), (0, ""), out)
            self.assertTrue((Path(folder) / "selka.json").exists())
            self.assertFalse((Path(folder) / "mylang.json").exists())

    def test_a_repository_project_uses_git_mv(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, {"main.my": "mylang\n", "mylang.json": "{}\n"})
            git(folder, "init", "-q")
            git(folder, "add", "-A")
            git(folder, "commit", "-q", "-m", "x")
            status, out, err = run_main("--project", folder)
            self.assertEqual((status, err), (0, ""), out)
            porcelain = subprocess.run(["git", "-C", folder, "status", "--porcelain"], capture_output=True, text=True).stdout
            self.assertRegex(porcelain, r"(?m)^R[ M] main.my -> main.selka$")
            self.assertRegex(porcelain, r"(?m)^R[ M] mylang.json -> selka.json$")


if __name__ == "__main__":
    unittest.main()
