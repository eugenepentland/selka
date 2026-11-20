#!/usr/bin/env python3
"""Edit check scheduling (E3): the packing of chunks by expected seconds, the duration records and the report parser."""
import json
import os
import tempfile
import unittest

import edit_check


ROOT_TESTS = ("units", "cli", "core")
WIDE_REPORT = """test: SLOW  8.71s  integration.test.slow one
All 3 tests passed.
test: test wall 12.40s; slowest over 1ms:
test:   8.71s  integration.test.slow one
test:   2.40s  integration.test.middle one
test:   0.05s  integration.test.small one
test: PASS - 3 passed
test: RESULT {"passed":3,"failed":0,"skipped":0}
"""


class PackTest(unittest.TestCase):
    def test_packing_keeps_every_item_exactly_once(self):
        weights = {"a": 9.0, "b": 4.0, "c": 4.0, "d": 1.0, "e": 0.5, "f": 0.5, "#unnamed": 2.0}
        packed = edit_check.pack_longest_first(weights, 3)
        flat = sorted(item for _seconds, items in packed for item in items)
        self.assertEqual(flat, sorted(weights))
        self.assertLessEqual(len(packed), 3)
        self.assertTrue(all(items for _seconds, items in packed))

    def test_lists_come_out_longest_first_with_their_expected_seconds(self):
        weights = {"big": 10.0, "mid": 6.0, "small": 1.0, "tiny": 0.5}
        packed = edit_check.pack_longest_first(weights, 2)
        seconds = [entry[0] for entry in packed]
        self.assertEqual(seconds, sorted(seconds, reverse=True))
        self.assertEqual(packed[0], (10.0, ["big"]))
        self.assertEqual(packed[1], (7.5, ["mid", "small", "tiny"]))
        self.assertAlmostEqual(sum(seconds), 17.5)

    def test_no_more_lists_than_items_and_never_an_empty_list(self):
        packed = edit_check.pack_longest_first({"only": 3.0}, 20)
        self.assertEqual(packed, [(3.0, ["only"])])

    def test_a_test_with_no_recorded_duration_gets_the_mean_of_its_binary(self):
        recorded = {"known_slow": 4.0, "known_fast": 0.0}
        weights = edit_check.expected_seconds(["known_slow", "known_fast", "new_one"], recorded, False)
        self.assertEqual(weights["known_slow"], 4.0)
        self.assertEqual(weights["known_fast"], 0.0)
        self.assertEqual(weights["new_one"], 2.0)

    def test_nothing_recorded_uses_the_default_for_every_test(self):
        weights = edit_check.expected_seconds(["a", "b"], {}, True)
        self.assertEqual(weights, {"a": edit_check.DEFAULT_TEST_SECONDS, "b": edit_check.DEFAULT_TEST_SECONDS,
                                   edit_check.UNNAMED: edit_check.DEFAULT_TEST_SECONDS})


EVERY_GUESTS = ["tests/lang/a.selka", "tests/lang/b.selka", "tests/lang/sub/c.selka"]
NO_CHOICE = {root: False for root in ROOT_TESTS}


class PlanTest(unittest.TestCase):
    def test_chunks_of_each_binary_partition_its_selection(self):
        chosen = {"units": ["u.test a"], "cli": ["cli.test %03d" % i for i in range(200)],
                  "core": ["core.test %03d" % i for i in range(300)]}
        unnamed = {"units": False, "cli": False, "core": True}
        jobs = edit_check.plan_jobs(chosen, unnamed, {}, 20, 7.0, [])
        for root in ROOT_TESTS:
            parts = [part for _s, job_root, _label, part in jobs if job_root == root]
            expected = sorted(chosen[root] + ([edit_check.UNNAMED] if unnamed[root] else []))
            self.assertEqual(sorted(item for part in parts for item in part), expected)

    def test_jobs_come_longest_first_and_the_guest_jobs_are_among_them(self):
        chosen = {"units": [], "cli": ["cli.test a", "cli.test b"], "core": ["core.test c"]}
        recorded = {"cli": {"cli.test a": 30.0, "cli.test b": 0.5}, "core": {"core.test c": 2.0}}
        guests = edit_check.plan_guests(["tests/lang/b.selka"], EVERY_GUESTS, "selka", {"tests/lang/b.selka": 0.2}, 45.0)
        guests += edit_check.plan_guests(["tests/lang/a.selka"], EVERY_GUESTS, "selka", {"tests/lang/a.selka": 90.0}, 45.0)
        jobs = edit_check.plan_jobs(chosen, NO_CHOICE, recorded, 20, 7.0, guests)
        seconds = [job[0] for job in jobs]
        self.assertEqual(seconds, sorted(seconds, reverse=True))
        self.assertEqual(jobs[0][1:4], ("guests", "guests-0", ["selka", "test", "tests/lang/a.selka"]))
        self.assertEqual(jobs[1][3], ["cli.test a"])
        self.assertEqual(jobs[-1][1:3], ("guests", "guests-0"))

    def test_no_guest_job_and_no_empty_binary_when_nothing_is_selected(self):
        chosen = {"units": ["u.test"], "cli": [], "core": []}
        jobs = edit_check.plan_jobs(chosen, NO_CHOICE, {}, 20, 7.0, [])
        self.assertEqual([job[1] for job in jobs], ["units"])

    def test_the_chunk_count_follows_the_expected_seconds(self):
        chosen = {"units": [], "cli": ["cli.test %03d" % i for i in range(100)], "core": []}
        jobs = edit_check.plan_jobs(chosen, NO_CHOICE, {}, 20, 10.0, [])
        self.assertEqual(len(jobs), 10)
        few = edit_check.plan_jobs(chosen, NO_CHOICE, {}, 2, 10.0, [])
        self.assertLessEqual(len(few), 8)


class GuestPlanTest(unittest.TestCase):
    def test_no_guest_file_selected_plans_no_job(self):
        self.assertEqual([], edit_check.plan_guests([], EVERY_GUESTS, "selka", {}, 40.0))

    def test_every_guest_file_is_one_directory_job_with_the_directory_seconds(self):
        planned = edit_check.plan_guests(list(EVERY_GUESTS), EVERY_GUESTS, "selka", {}, 33.0)
        self.assertEqual(planned, [(33.0, "guests", "guests", ["selka", "test", "tests/lang"])])

    def test_one_file_is_one_job_with_its_record(self):
        planned = edit_check.plan_guests(["tests/lang/b.selka"], EVERY_GUESTS, "selka", {"tests/lang/b.selka": 2.5}, 40.0)
        self.assertEqual(planned, [(2.5, "guests", "guests-0", ["selka", "test", "tests/lang/b.selka"])])

    def test_an_unrecorded_file_gets_the_mean_of_the_recorded_selected_files(self):
        recorded = {"tests/lang/a.selka": 1.0, "tests/lang/b.selka": 3.0}
        every = EVERY_GUESTS + ["tests/lang/d.selka"]
        planned = edit_check.plan_guests(["tests/lang/a.selka", "tests/lang/b.selka", "tests/lang/sub/c.selka"], every,
                                         "selka", recorded, 40.0)
        self.assertEqual([entry[0] for entry in planned], [1.0, 3.0, 2.0])
        self.assertEqual([entry[3][-1] for entry in planned], ["tests/lang/a.selka", "tests/lang/b.selka", "tests/lang/sub/c.selka"])

    def test_nothing_recorded_gives_the_per_file_default(self):
        planned = edit_check.plan_guests(["tests/lang/a.selka"], EVERY_GUESTS, "selka", {}, 40.0)
        self.assertEqual(planned[0][0], edit_check.GUEST_FILE_SECONDS)

    def test_each_selected_file_runs_exactly_once(self):
        chosen = ["tests/lang/a.selka", "tests/lang/sub/c.selka"]
        planned = edit_check.plan_guests(chosen, EVERY_GUESTS, "selka", {}, 40.0)
        self.assertEqual(sorted(entry[3][-1] for entry in planned), chosen)


class GuestRecordTest(unittest.TestCase):
    def test_a_file_job_records_its_file_and_the_directory_run_records_the_job(self):
        durations = {"tests": {}, "jobs": {}}
        edit_check.record_guest_runs(durations, [(["selka", "test", "tests/lang/a.selka"], 1.25),
                                                 (["selka", "test", "tests/lang"], 44.0)])
        self.assertEqual(durations, {"tests": {"guests": {"tests/lang/a.selka": 1.25}}, "jobs": {"guests": 44.0}})

    def test_the_guest_records_round_trip_through_the_store(self):
        with tempfile.TemporaryDirectory() as directory:
            durations = {"tests": {"guests": {"tests/lang/a.selka": 1.25}}, "jobs": {"guests": 44.0}}
            edit_check.save_durations(directory, durations)
            self.assertEqual(edit_check.load_durations(directory), durations)


class ExpectedSecondsTest(unittest.TestCase):
    def test_the_default_applies_only_where_nothing_is_recorded(self):
        self.assertEqual(edit_check.expected_seconds(["a", "b"], {"a": 2.0}, False, 9.0), {"a": 2.0, "b": 2.0})
        self.assertEqual(edit_check.expected_seconds(["a"], {}, False, 9.0), {"a": 9.0})


class ReportTest(unittest.TestCase):
    def test_the_wide_report_gives_the_listed_tests_and_the_wall(self):
        wall, listed = edit_check.parse_report(WIDE_REPORT)
        self.assertAlmostEqual(wall, 12.40)
        self.assertEqual(listed, {"integration.test.slow one": 8.71,
                                  "integration.test.middle one": 2.40,
                                  "integration.test.small one": 0.05})

    def test_a_log_without_the_wall_line_gives_nothing(self):
        self.assertEqual(edit_check.parse_report("test: SLOW  8.71s  integration.test x\n"), (None, {}))

    def test_a_record_keeps_listed_times_floors_the_rest_and_takes_the_unnamed_remainder(self):
        with tempfile.TemporaryDirectory() as directory:
            log = os.path.join(directory, "run-cli-0.log")
            with open(log, "w") as handle:
                handle.write(WIDE_REPORT)
            recorded = {"cli": {"integration.test.slow one": 99.0}}
            edit_check.record_runs(recorded, [("cli", ["integration.test.slow one", "integration.test.other",
                                                       edit_check.UNNAMED], log)])
            self.assertEqual(recorded["cli"]["integration.test.slow one"], 8.71)
            self.assertEqual(recorded["cli"]["integration.test.other"], edit_check.FLOOR_SECONDS)
            self.assertAlmostEqual(recorded["cli"][edit_check.UNNAMED], 12.40 - 8.71)

    def test_a_full_report_keeps_the_old_record_of_an_unlisted_test(self):
        with tempfile.TemporaryDirectory() as directory:
            log = os.path.join(directory, "run-core-0.log")
            rows = "".join("test:   %d.00s  core.test %03d\n" % (1, index) for index in range(edit_check.WIDE_LINES))
            with open(log, "w") as handle:
                handle.write("test: test wall 100.00s; slowest over 1ms:\n" + rows)
            recorded = {"core": {"core.test unlisted": 5.0}}
            edit_check.record_runs(recorded, [("core", ["core.test unlisted"], log)])
            self.assertEqual(recorded["core"]["core.test unlisted"], 5.0)


class StoreTest(unittest.TestCase):
    def test_durations_round_trip_and_a_bad_file_falls_back_to_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            durations = {"tests": {"cli": {"integration.test a": 1.5}}, "jobs": {"guests": 33.0}}
            edit_check.save_durations(directory, durations)
            self.assertEqual(edit_check.load_durations(directory), durations)
            with open(os.path.join(directory, edit_check.DURATIONS_FILE), "w") as handle:
                handle.write("{not json")
            self.assertEqual(edit_check.load_durations(directory), {"tests": {}, "jobs": {}})
            with open(os.path.join(directory, edit_check.DURATIONS_FILE), "w") as handle:
                json.dump({"format": "other", "tests": {}}, handle)
            self.assertEqual(edit_check.load_durations(directory), {"tests": {}, "jobs": {}})


class EngineEnvironmentTest(unittest.TestCase):
    def test_only_the_guest_runs_get_the_engine_checks_and_both_are_placement_variables(self):
        self.assertEqual(edit_check.ENGINE_GUEST_ENVIRONMENT, {"SELKA_ENGINE_VERIFY": "16", "SELKA_ENGINE_SHADOW_LOG": "@user"})
        self.assertNotIn("SELKA_ENGINE_VERIFY", edit_check.test_environment("scratch"))
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "environment_identity.zon")) as handle:
            contract = handle.read()
        placement = contract[contract.index(".placement"):contract.index(".dropped")]
        for name in list(edit_check.ENGINE_GUEST_ENVIRONMENT) + [edit_check.ENGINE_TAG]:
            self.assertIn('"%s"' % name, placement)



class CheapCheckTest(unittest.TestCase):
    """The edit check runs the gate's cheap checks (DL-4 item 4a). A finding is printed when it arrives and fails the
    edit check, but the build and the tests still run (decision D-DL4-8); only the gate stops before any test."""

    def finding(self, index):
        import gate_cheap_checks
        return gate_cheap_checks.Finding("zig-format", "zig fmt would change this line",
                                         "src/a%d.zig" % index)

    def test_the_build_is_not_ended_and_also_builds_the_registry_guard(self):
        import inspect
        from unittest import mock
        self.assertNotIn("stop", inspect.signature(edit_check.build).parameters)
        with mock.patch.object(edit_check, "slot") as slot:
            edit_check.build(None)
        self.assertIn("test-verification-registry", slot.call_args.args)

    def test_a_finding_is_printed_when_it_arrives_and_runs_no_less(self):
        line = edit_check.finding_line("zig-format", [self.finding(1), self.finding(2)])
        self.assertIn("cheap check zig-format failed; the tests still run", line)
        self.assertIn("src/a1.zig: zig fmt would change", line)
        self.assertIn("(and 1 more)", line)

    def test_findings_fail_the_edit_check_and_are_repeated_within_twenty_lines(self):
        summary = ["ran units: 10 named, unnamed no, exit 0"] * 17
        for printed in (0, 3, 6):
            lines = edit_check.closing_lines(summary, [self.finding(index) for index in range(9)], [], "time: x",
                                             printed)
            self.assertLessEqual(printed + len(lines), 20)
            self.assertEqual(lines[-1], edit_check.FAIL_LINE)
            self.assertIn("failures: cheap checks (zig-format)", lines)
            self.assertIn("  src/a0.zig: zig fmt would change this line", lines)
        passed = edit_check.closing_lines(summary, [], [], "time: x", 0)
        self.assertEqual(passed[-1], edit_check.GATE_LINE)
        self.assertEqual(passed[-3], "failures: none")


def process_ended(pid):
    """Whether a process is gone or a zombie (the gate runs tests under a subreaper, which reaps orphans later)."""
    try:
        with open("/proc/%d/stat" % pid) as handle:
            return handle.read().rsplit(") ", 1)[1].split()[0] in ("Z", "X")
    except (OSError, IndexError):
        return True


class ShadowTest(unittest.TestCase):
    """`edit_check_shadow.py` as `verify_cache.py` runs it after a gate failed on tests (stage 6)."""

    def run_shadow(self, store, *arguments, impact_body=None):
        import subprocess
        import sys
        impact = os.path.join(store, "fake-impact")
        if impact_body is not None:
            with open(impact, "w") as handle:
                handle.write("#!%s\nimport sys\n%s\n" % (sys.executable, impact_body))
            os.chmod(impact, 0o755)
        script = os.path.join(edit_check.ROOT, "scripts", "edit_check_shadow.py")
        result = subprocess.run([sys.executable, script, "--store", store, "--impact", impact, "--source", "verify_cache",
                                 *arguments], capture_output=True, text=True, timeout=60)
        lines = open(os.path.join(store, "shadow.jsonl")).read().splitlines()
        return result, json.loads(lines[-1]), len(lines)

    SELECTION = ("args = sys.argv; out = args[args.index('--selection') + 1]\n"
                 "open(out, 'w').write('cli\\tnamed\\tfix_cli_test.test.CLI fix\\tr\\n'"
                 "'guests\\tnamed\\ttests/lang/a04_list_extrema.selka\\tr\\n')")

    def test_a_failing_gate_records_whether_its_tests_were_selected_by_their_gate_ids(self):
        with tempfile.TemporaryDirectory() as store:
            open(os.path.join(store, "coverage-map.json.gz"), "w").close()
            result, record, count = self.run_shadow(
                store, "--map", os.path.join(store, "coverage-map.json.gz"),
                "--failed", "test/integration.zig::fix_cli_test.test.CLI fix",
                "--failed", "a04_list_extrema::test_dynamic_list_extrema_borrow_and_copy_independently",
                "--failed", "src/root_test.zig::lexer_test.test.not selected", impact_body=self.SELECTION)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(count, 1)
        self.assertEqual(record["missed"], ["src/root_test.zig::lexer_test.test.not selected"])
        self.assertEqual((record["covered"], record["selected"], record["source"]), (False, 2, "verify_cache"))
        self.assertIn("missed 1", result.stdout)

    def test_a_cut_list_of_failures_leaves_covered_undecided_unless_one_was_missed(self):
        with tempfile.TemporaryDirectory() as store:
            open(os.path.join(store, "m.json.gz"), "w").close()
            _, record, _ = self.run_shadow(store, "--map", os.path.join(store, "m.json.gz"), "--unlisted", "7",
                                           "--failed", "test/integration.zig::fix_cli_test.test.CLI fix",
                                           impact_body=self.SELECTION)
            self.assertEqual((record["covered"], record["unlisted"]), (None, 7))
            _, record, _ = self.run_shadow(store, "--map", os.path.join(store, "m.json.gz"), "--unlisted", "7",
                                           "--failed", "src/root_test.zig::x.test.missed", impact_body=self.SELECTION)
            self.assertFalse(record["covered"])

    def test_a_timeout_ends_the_impact_tool_s_whole_process_group_and_records_it(self):
        with tempfile.TemporaryDirectory() as store:
            open(os.path.join(store, "m.json.gz"), "w").close()
            pid = os.path.join(store, "grandchild")
            body = ("import subprocess, time\nchild = subprocess.Popen(['sleep', '60'])\n"
                    "open(%r, 'w').write(str(child.pid))\ntime.sleep(60)" % pid)
            result, record, _ = self.run_shadow(store, "--map", os.path.join(store, "m.json.gz"), "--failed", "x::y",
                                                "--timeout", "1", impact_body=body)
            self.assertEqual((result.returncode, record["covered"]), (2, None))
            self.assertIn("the impact tool passed 1 s", record["error"])
            self.assertTrue(process_ended(int(open(pid).read())), "what the tool started ended too")

    def test_a_shadow_that_cannot_decide_records_why(self):
        with tempfile.TemporaryDirectory() as store:
            _, record, _ = self.run_shadow(store, "--map", os.path.join(store, "missing.json.gz"), "--failed", "x::y")
            self.assertIn("no impact tool", record["error"])
            open(os.path.join(store, "m.json.gz"), "w").close()
            result, record, count = self.run_shadow(store, "--map", os.path.join(store, "m.json.gz"), "--failed", "x::y",
                                                    impact_body="sys.exit(3)")
            self.assertEqual((result.returncode, record["covered"], count), (2, None, 2))
            self.assertIn("the impact tool failed", record["error"])
            _, record, count = self.run_shadow(store, "--map", os.path.join(store, "m.json.gz"), "--failed", "x::y",
                                               "--timeout", "0.5", impact_body="import time; time.sleep(5)")
            self.assertEqual(count, 3)
            self.assertIn("the impact tool passed", record["error"])

if __name__ == "__main__":
    unittest.main()
