#!/usr/bin/env python3
"""Bounded gate summaries: green, red, seeded logs and the report shape."""
import tempfile
import unittest
from pathlib import Path

import gate_summary


GREEN_LOG = '''Build Summary: 3/3 steps succeeded
test
+- verification action core member 0 success 12s
   +- compile exe selka debug native (reused)
+- verification action cli member 0 success 3s
'''


def red_log(lines, action='cli'):
    """A failing step as the pinned build runner prints it: the step header, the
    captured standard error and `error:` lines first, the failed command last."""
    return ('test\n'
            '+- verification action %s member 0 1 pass, 1 fail (2 total)\n' % action
            + '\n'.join(lines) + '\n'
            + 'failed command: python3 scripts/verification_native_telemetry.py --action-id %s '
              '--member 0 --root-id test/integration.zig -- ./test --listen=-\n' % action
            + '\n'
            'Build Summary: 2/4 steps succeeded (1 failed); 1/2 tests passed (1 failed)\n')


# Trimmed from a real `zig build test-memory-budget` run on 20 October with one
# deliberately failing `expectEqual`, before and after the proxy held stderr back.
REAL_ZIG_FAILURE = """build-slot: build slot 1, FIFO ticket 10704 after 0s
test-memory-budget
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
test: FAIL \u2014 1 failed of 8
test: RESULT {"passed":7,"failed":1,"skipped":0}
error: 'memory_budget.test.review probe: a failing assertion must show its message' failed:
       test: 8 test(s) selected
       expected 1, found 2
       /home/u/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/testing.zig:111:17: 0x12905e4 in expectEqualInner__anon_44754 (std.zig)
                       return error.TestExpectedEqual;
                       ^
       /home/u/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/testing.zig:75:5: 0x1290654 in expectEqual (memory_budget.zig)
           return expectEqualInner(T, expected, actual);
           ^
       /home/u/ai/canopy/mylang-review-gate-probe/src/memory_budget.zig:368:5: 0x129069b in test.review probe: a failing assertion must show its message (memory_budget.zig)
           try std.testing.expectEqual(@as(u32, 1), @as(u32, 2));
           ^
failed command: python3 scripts/verification_native_telemetry.py --action-id memory_budget --member 0 --root-id src/memory_budget.zig -- sh -c "..."

Build Summary: 16/18 steps succeeded (1 failed); 7/8 tests passed (1 failed)
test-memory-budget transitive failure
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
"""

REAL_SILENT_FAILURE = """test-memory-budget
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
error: 'memory_budget.test.review probe: a failing assertion must show its message' failed without output
failed command: python3 scripts/verification_native_telemetry.py --action-id memory_budget --member 0 --root-id src/memory_budget.zig -- sh -c "..."

Build Summary: 16/18 steps succeeded (1 failed); 7/8 tests passed (1 failed)
"""


class GateSummaryTests(unittest.TestCase):
    def test_green_summary_is_short_and_lists_the_slowest_actions(self):
        lines = gate_summary.summarize(text=GREEN_LOG)
        self.assertLessEqual(len(lines), gate_summary.MAX_GREEN_LINES)
        self.assertIn('verification: PASS', lines[0])
        self.assertIn('core 12.0 s', ' '.join(lines))

    def test_seeded_failure_shows_action_test_file_line_and_log_path(self):
        text = red_log(['test_network_endpoint (test/integration.zig) ... FAIL',
                        'error: expected true',
                        'test deadline: test/integration.zig::NETWORK-ENDPOINT-1 ran 301.0 s (limit 300.0 s); killed',
                        'at test/integration.zig:6618'])
        lines = gate_summary.summarize(text=text, log_directory='/logs/gate')
        joined = '\n'.join(lines)
        self.assertIn('verification: FAIL', lines[0])
        self.assertIn('failure 1/1: cli', joined)
        self.assertIn('NETWORK-ENDPOINT-1', joined)
        self.assertIn('test/integration.zig:6618', joined)
        self.assertIn('/logs/gate', joined)
        self.assertLessEqual(len(lines), gate_summary.MAX_RED_LINES + gate_summary.MAX_RED_PER_FAILURE)

    def test_red_budget_grows_by_ten_lines_per_further_failure(self):
        one = gate_summary.summarize(text=red_log(['error: first failure at src/root_test.zig:10']))
        many = gate_summary.summarize(text=''.join(
            red_log(['error: failure at src/root_test.zig:' + str(index)], action='cli%d' % index)
            for index in range(30)))
        self.assertLessEqual(len(one), gate_summary.MAX_RED_LINES)
        self.assertGreater(len(many), gate_summary.MAX_RED_LINES)
        self.assertLessEqual(len(many), gate_summary.MAX_RED_LINES + gate_summary.MAX_RED_PER_FAILURE * 29)

    def test_report_failures_name_tests_and_timed_out_rows(self):
        report = {'success': False, 'elapsed_seconds': 4.0,
                  'actions': [{'id': 'cli', 'state': 'execute', 'test_telemetry': [
                      {'tests': [{'test_id': 'test/integration.zig::NETWORK-ENDPOINT-1',
                                  'state': 'timed_out', 'elapsed_ns': 300000000000}]}]}]}
        lines = gate_summary.summarize(report=report, log_directory='/logs/gate')
        self.assertIn('verification: FAIL', lines[0])
        self.assertIn('test/integration.zig::NETWORK-ENDPOINT-1', '\n'.join(lines))
        self.assertIn('/logs/gate', '\n'.join(lines))

    def test_a_report_without_test_rows_falls_back_to_the_failing_log_block(self):
        report = {'success': False, 'elapsed_seconds': 3.0,
                  'actions': [{'id': 'fuzz_campaign', 'state': 'execute', 'test_telemetry': []}]}
        lines = gate_summary.summarize(report=report, text=red_log(['error: pruner mismatch']),
                                       log_directory='/logs/gate')
        joined = '\n'.join(lines)
        self.assertIn('failure 1/1: cli', joined)
        self.assertIn('pruner mismatch', joined)

    def test_a_real_zig_failure_names_the_test_its_message_and_its_repository_line(self):
        lines = gate_summary.summarize(text=REAL_ZIG_FAILURE)
        joined = '\n'.join(lines)
        self.assertEqual(lines[0], 'verification: FAIL')
        self.assertIn('failure 1/1: memory_budget', joined)
        self.assertIn('test: memory_budget.test.review probe: a failing assertion must show its message', joined)
        self.assertIn('expected 1, found 2', joined)
        self.assertIn('at src/memory_budget.zig:368', joined)
        self.assertNotIn('expectEqualInner', joined)
        self.assertNotIn('zig-toolchains', joined)

    def test_blocks_a_stopped_gate_got_from_beacons_do_not_inherit_what_the_killed_build_printed(self):
        text = ('BrokenPipeError: [Errno 32] Broken pipe\nsupervisor noise\n'
                + gate_summary.FAIL_FAST_MARKER + '\n'
                + "error: 'root::t.audit' failed\nexpected: 1\nat src/lazy_readers_test.zig:30\n"
                + 'failed command: python3 scripts/verification_native_telemetry.py --action-id unit --member 0 --root-id r -- ./t\n'
                + 'FAIL: test_driver (x.T)\nfailed command: sh scripts/quiet-driver.sh python3 tests/x.py\n')
        blocks = gate_summary.failure_details(text)
        self.assertEqual([block['action'] for block in blocks], ['unit', 'unknown'])
        self.assertEqual(blocks[0]['tests'], ['root::t.audit'])
        self.assertNotIn('BrokenPipeError', ' '.join(blocks[0]['lines']))
        self.assertEqual(blocks[0]['location'], 'src/lazy_readers_test.zig:30')
        self.assertEqual(blocks[1]['lines'], ['FAIL: test_driver (x.T)'])

    def test_a_failure_without_output_still_names_its_test(self):
        joined = '\n'.join(gate_summary.summarize(text=REAL_SILENT_FAILURE))
        self.assertIn('failure 1/1: memory_budget', joined)
        self.assertIn('a failing assertion must show its message (failed)', joined)

    def test_a_python_driver_failure_shows_its_assertion_and_repository_frame(self):
        text = red_log(['FAIL: test_budget (verify_cache_test.Tests.test_budget)',
                        'Traceback (most recent call last):',
                        '  File "/usr/lib/python3.12/unittest/case.py", line 58, in testPartExecutor',
                        '  File "/home/u/ai/canopy/tree/scripts/verify_cache_test.py", line 812, in test_budget',
                        'AssertionError: 3 != 4',
                        'error: process exited with code 1'], action='verification_cache')
        joined = '\n'.join(gate_summary.summarize(text=text))
        self.assertIn('failure 1/1: verification_cache', joined)
        self.assertIn('AssertionError: 3 != 4', joined)
        self.assertIn('at scripts/verify_cache_test.py:812', joined)

    def test_coordinator_logs_are_read_from_the_gate_subdirectory(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'gate').mkdir()
            (root / 'inventory').mkdir()
            (root / 'gate' / 'stderr.log').write_text(REAL_ZIG_FAILURE)
            (root / 'inventory' / 'stdout.log').write_text('inventory: 48 actions\n')
            report = {'success': False, 'elapsed_seconds': 9.0,
                      'actions': [{'id': 'memory_budget', 'state': 'execute', 'test_telemetry': [
                          {'tests': [{'test_id': 'src/memory_budget.zig::review probe', 'state': 'failed',
                                      'elapsed_ns': 1}]}]}]}
            joined = '\n'.join(gate_summary.summarize(report=report, log_directory=root))
        self.assertIn('test: src/memory_budget.zig::review probe (failed)', joined)
        self.assertIn('expected 1, found 2', joined)
        self.assertIn('at src/memory_budget.zig:368', joined)

    def test_an_action_that_ended_125_names_the_descendants_that_outlived_its_closeout(self):
        leftovers = ('supervisor: 2 descendant(s) outlived the closeout; the action ends 125\n'
                     'supervisor: leftover pid=4242 ppid=4200 sid=4242 state=S started=23:03:11Z age=3.2s '
                     'cwd=/home/u/selka cmd=rm -rf -- /home/u/selka/.zig-cache.trim-4100\n'
                     'supervisor: leftover pid=4243 ppid=4200 sid=4200 state=S started=23:03:12Z age=2.1s '
                     'cwd=/home/u/selka cmd=du -sx --block-size=1K /home/u/selka/.zig-cache\n')
        log = GREEN_LOG.replace('3/3 steps', '127/127 steps') + leftovers
        for report in (None, {'success': False, 'actions': [], 'elapsed_seconds': 5.0}):
            text = '\n'.join(gate_summary.summarize(report=report, text=log))
            self.assertIn('verification: FAIL', text)
            self.assertIn('an action ended 125 (incomplete) with no failing step; its supervisor reports:', text)
            self.assertIn('pid=4242 ppid=4200 sid=4242 state=S started=23:03:11Z age=3.2s cwd=/home/u/selka cmd=rm -rf', text)
            self.assertIn('pid=4243', text)
            self.assertNotIn('no failing step was found', text)

    def test_a_supervisor_report_quoted_inside_the_build_output_is_not_the_actions_own(self):
        # A test that runs a supervisor of its own quotes its report in its failure message, in the middle of the build's
        # output. The action's supervisor reports when the build has ended, after its last summary.
        quoted = ('AssertionError: 125 != 0\nsupervisor: 1 descendant(s) outlived the closeout\n'
                  'supervisor: leftover pid=7 ppid=1 sid=7 state=D started=1:00:00Z age=14.9s cwd=/x cmd=sleep 60\n')
        text = quoted + red_log(['error: boom'])
        self.assertEqual(gate_summary.leftover_report(text), [])
        own = text + 'supervisor: leftover pid=8 ppid=1 sid=8 state=S started=1:00:00Z age=3s cwd=/x cmd=sleep 61\n'
        self.assertEqual([line.split()[2] for line in gate_summary.leftover_report(own)], ['pid=8'])
        self.assertEqual(len(gate_summary.leftover_report(quoted)), 2)  # no summary at all: the log is read whole

    def test_the_rule_holds_per_log_file_so_a_later_build_does_not_hide_the_actions_own_report(self):
        # The joined logs read the gate's standard error first and the preparation build's after it; the preparation
        # build has its own summary, which must not push the gate's supervisor report before "the last summary".
        quoted = 'supervisor: leftover pid=7 ppid=1 sid=7 state=D started=1:00:00Z age=1s cwd=/x cmd=quoted\n'
        own = 'supervisor: leftover pid=8 ppid=1 sid=8 state=S started=1:00:00Z age=3s cwd=/x cmd=sleep 61\n'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative, text in (('gate/stderr.log', quoted + GREEN_LOG + own), ('gate/stdout.log', 'out\n'),
                                   ('preparation/stderr.log', GREEN_LOG)):
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_text(text)
            joined = gate_summary.read_logs(root)
        self.assertEqual([line.split()[2] for line in gate_summary.leftover_report(joined)], ['pid=8'])

    def test_leftovers_are_added_to_a_red_summary_that_has_its_own_failures(self):
        log = red_log(['error: boom']) + 'supervisor: leftover pid=7 ppid=1 sid=7 state=S started=1:00:00Z age=3s cwd=/x cmd=sleep 60\n'
        text = '\n'.join(gate_summary.summarize(text=log))
        self.assertIn('failure 1/1: cli', text)
        self.assertIn('also: the supervisor of an action reports:', text)
        self.assertIn('pid=7', text)

    def test_a_red_run_without_a_failing_block_still_names_what_its_log_says(self):
        lines = gate_summary.summarize(text='Build Summary: 3/4 steps succeeded (1 failed)\n')
        self.assertEqual(lines[0], 'verification: FAIL')
        self.assertEqual(lines[1:], ['failure: no step is marked failed; the log ends:',
                                     '  Build Summary: 3/4 steps succeeded (1 failed)'])
        marked = gate_summary.summarize(text='Build Summary: 3/4 steps succeeded (1 failed)\ntest\n'
                                             '+- verification action golden member 0 failure\n')
        self.assertIn('failure: the build marks golden failed', '\n'.join(marked))

    def test_the_command_line_reader_keeps_the_red_budget(self):
        import contextlib
        import io
        import tempfile
        text = ''.join(red_log(['error: broke at src/root_test.zig:%d' % index], action='a%d' % index)
                       for index in range(12))
        with tempfile.TemporaryDirectory() as directory:
            path = directory + '/gate.log'
            with open(path, 'w') as handle:
                handle.write(text)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                gate_summary.main([path])
        self.assertGreater(len(output.getvalue().splitlines()), gate_summary.MAX_GREEN_LINES)

    def summary_of(self, argument):
        import contextlib
        import io
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            gate_summary.main([str(argument)])
        return output.getvalue().splitlines()

    def test_the_stdout_log_of_a_green_gate_reads_its_partner_for_the_verdict(self):
        # F24: a green gate prints `Build Summary` to stderr.log; stdout.log, the file a person points at, holds none.
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as directory:
            gate = Path(directory) / 'last-logs' / 'gate'
            gate.mkdir(parents=True)
            (gate / 'stdout.log').write_text('15e161c2f44fbd95\n{"version":"native-tests-v1"}\ndoc-coverage: 0 failures\n')
            (gate / 'stderr.log').write_text('build-slot: gate slot 1\nBuild Summary: 214/214 steps succeeded; 5444/60322 tests passed\n')
            for name in ('stdout.log', 'stderr.log'):
                with self.subTest(name=name):
                    self.assertEqual(['verification: PASS; log: ' + str(gate)], self.summary_of(gate / name))
            self.assertEqual(self.summary_of(gate), self.summary_of(gate / 'stdout.log'))
            (gate / 'stderr.log').write_text(red_log(['error: broke at src/root_test.zig:7'], action='cli'))
            lines = self.summary_of(gate / 'stdout.log')
            self.assertEqual('verification: FAIL; log: ' + str(gate), lines[0])
            self.assertIn('failure 1/1: cli', lines)

    def test_a_step_log_without_a_verdict_stays_unknown_and_other_names_read_only_themselves(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'stdout.log').write_text('nothing that names a verdict\n')
            self.assertEqual(['verification: UNKNOWN; log: ' + str(root)], self.summary_of(root / 'stdout.log'))
            (root / 'gate.log').write_text(GREEN_LOG)
            (root / 'stderr.log').write_text(red_log(['error: not this log\'s'], action='cli'))
            self.assertEqual(['verification: PASS',
                              'slowest actions (recorded test seconds): core 12.0 s, cli 3.0 s'], self.summary_of(root / 'gate.log'))

    def test_a_saved_log_reader_never_runs_a_command(self):
        lines = gate_summary.summarize(text=GREEN_LOG)
        self.assertEqual(lines[0], 'verification: PASS')



FIXTURES = Path(__file__).resolve().parents[1] / 'test' / 'fixtures' / 'gate-summary'


class RealFailureFixtures(unittest.TestCase):
    """One trimmed log of each kind of failure a gate had on 13 November (lane DL-4, item 4b): the summary names the
    failing step and its first diagnostics, and never says that no failing step was found."""

    def summary(self, name, **options):
        text = (FIXTURES / name).read_text()
        lines = gate_summary.summarize(text=text, **options)
        joined = '\n'.join(lines)
        self.assertEqual(lines[0], 'verification: FAIL')
        self.assertNotIn('no failing step was found', joined)
        self.assertLessEqual(len(lines), gate_summary.MAX_RED_LINES)
        return joined

    def test_a_my_format_beacon_names_the_driver_and_the_file_line(self):
        joined = self.summary('my-format-beacon.log')
        self.assertIn('failure 1/1: scripts/check_my_format.py', joined)
        self.assertIn('tests/lang/a04_list_extrema.selka:31:11: formatting differs', joined)

    def test_with_the_inventory_a_beacon_names_the_executed_action(self):
        plan = {'groups': [{'id': 'my_format', 'inputs': ['scripts/check_my_format.py']},
                           {'id': 'noalloc_lint', 'inputs': ['scripts/check_my_format.py']}]}
        report = {'success': False, 'actions': [{'id': 'my_format', 'state': 'execute'},
                                                {'id': 'noalloc_lint', 'state': 'reused'}]}
        lines = gate_summary.summarize(report=report, text=(FIXTURES / 'my-format-beacon.log').read_text(), plan=plan)
        self.assertIn('failure 1/1: my_format (scripts/check_my_format.py)', lines)

    def test_a_zig_format_failure_names_the_action_and_the_file(self):
        joined = self.summary('zig-format.log')
        self.assertIn('failure 1/1: zig-format', joined)
        self.assertIn('error: test/fix_cli_test.zig: non-conforming formatting', joined)

    def test_a_guardian_failure_names_each_finding_with_its_check(self):
        joined = self.summary('guardian.log')
        self.assertIn('failure 1/1: guardian', joined)
        self.assertIn('src/dl4_probe.zig: doc-comments: pub fn probe: has no /// doc comment', joined)

    def test_a_doc_coverage_failure_names_the_missing_anchor_from_standard_output(self):
        joined = self.summary('doc-coverage.log')
        self.assertIn('failure 1/1: doc-coverage', joined)
        self.assertIn("! declared-borrowed-results: 'docs/managed-memory.md' has no heading", joined)
        self.assertNotIn('guardian:', joined, 'the green Guardian step printed before the block is not its text')

    def test_an_inputs_coverage_beacon_names_the_undeclared_path(self):
        joined = self.summary('inputs-coverage-beacon.log')
        self.assertIn('failure 1/1: tests/test_inputs_coverage.py', joined)
        self.assertIn('test/fix_cli_test.zig:3688: names velocity/README.md', joined)

    def test_a_failing_zig_test_in_one_shard_names_the_test_its_message_and_its_line(self):
        joined = self.summary('zig-test.log')
        self.assertIn('failure 1/1: cli', joined)
        self.assertIn('CLI fix applies every structured fix across modules to a fixed point (failed)', joined)
        self.assertIn('expected 7, found 1', joined)
        self.assertIn('at test/fix_cli_test.zig:130', joined)

    def test_a_failing_guest_test_names_the_failed_member_and_the_test_not_the_parent(self):
        joined = self.summary('guest-test.log')
        self.assertIn('failure 1/1: language', joined)
        self.assertNotIn('verify-ir-proof', joined)
        self.assertIn('a04_list_extrema::test_dynamic_list_extrema_borrow_and_copy_independently failed: '
                      'expected true, got false', joined)

    def test_a_driver_that_fails_on_standard_error_only_names_its_script_and_assertion(self):
        joined = self.summary('driver-stderr-beacon.log')
        self.assertIn('failure 1/1: tests/test_affected_tests.py', joined)
        self.assertIn('AssertionError: dl4 probe: a driver that fails on standard error only', joined)
        self.assertIn('at tests/test_affected_tests.py:244', joined)

    def test_a_test_killed_by_its_deadline_names_the_test_and_that_it_timed_out(self):
        joined = self.summary('deadline-beacon.log')
        self.assertIn('failure 1/1: unit', joined)
        self.assertIn("nominal layout expansion bounds distinct array identities' timed out", joined)

    def test_descendants_that_survived_name_each_process(self):
        joined = self.summary('leftover.log')
        self.assertIn('an action ended 125 (incomplete) with no failing step; its supervisor reports:', joined)
        self.assertIn('supervisor: leftover pid=2117000 ppid=2111435', joined)

    def test_a_compile_error_in_preparation_names_the_step_and_the_source_line(self):
        joined = self.summary('compile-error.log')
        self.assertIn('failure 1/2: compile test debug native', joined)
        self.assertIn('failure 2/2: compile exe selka debug native', joined)
        self.assertIn('src/diagnostic_codes.zig:524:5: error: dl4 probe: a compile error in the compiler', joined)

    def test_a_green_step_that_wrote_to_standard_error_is_not_named(self):
        text = ('verification-docs\n+- verification action docs member 0 success\n'
                'error: a green step printed this\nfailed command: python3 tests/docs.py\n'
                + (FIXTURES / 'zig-format.log').read_text())
        joined = self.summary_text(text)
        self.assertIn('failure 1/1: zig-format', joined)
        self.assertNotIn('a green step printed this', joined)

    def test_a_green_member_that_wrote_an_error_line_is_not_named_when_nothing_is_marked_failed(self):
        text = ('verification-docs\n+- verification action docs member 0 success\n'
                'error: a green step printed this\nfailed command: python3 tests/docs.py\n'
                'Build Summary: 2/3 steps succeeded (1 failed)\n')
        joined = self.summary_text(text)
        self.assertNotIn('failure 1/1: docs', joined)

    def test_inputs_that_changed_while_the_gate_waited_name_the_changed_path(self):
        import json
        report = json.loads((FIXTURES / 'inputs-changed.last-run.json').read_text())
        joined = '\n'.join(gate_summary.summarize(report=report))
        self.assertIn('failure: inputs changed while the gate ran (status 75)', joined)
        self.assertIn('first changed: tests/lang/README.md (inotify:modify)', joined)

    OVERSHOOT_LOG = ('verification-unit\n+- verification action unit member 5 failure\n'
                     'error: memory usage peaked at 1.53GB (1528537088 bytes), exceeding the declared upper bound of 0.40GB '
                     '(402653184 bytes)\nfailed command: cd . && python3 scripts/verification_native_telemetry.py '
                     '--action-id unit --member 5 -- x\n\n')

    def test_a_step_that_failed_without_telemetry_is_named_beside_the_failing_tests(self):
        text = ('verification-docs\n+- verification action docs member 0 failure\nerror: process exited with code 1\n'
                'failed command: sh scripts/quiet-driver.sh python3 tests/docs.py\n'
                'Build Summary: 221/224 steps succeeded (2 failed)\n')
        report = {'success': False, 'actions': [{'id': 'verification_cache', 'state': 'execute', 'test_telemetry': [
            {'tests': [{'test_id': 'gate_summary_test.Probe.test_x', 'state': 'failed'}]}]}]}
        joined = '\n'.join(gate_summary.summarize(report=report, text=text))
        self.assertIn('failure 1/2: verification_cache', joined)
        self.assertIn('failure 2/2: docs', joined)

    def test_a_memory_overshoot_is_a_note_not_a_failure_as_the_build_counts_it(self):
        # The real line of 13 November: the build marks the member `failure` but counts every step as succeeded and exits 0.
        passed = gate_summary.summarize(text=self.OVERSHOOT_LOG + 'Build Summary: 31/31 steps succeeded\n')
        self.assertEqual(passed[0], 'verification: PASS')
        self.assertIn('note: unit member 5 exceeded its declared memory bound: 1.53GB against 0.40GB (the build fails '
                      'no step for it)', passed)
        self.assertEqual(gate_summary.failed_actions(self.OVERSHOOT_LOG), [])
        report = {'success': False, 'actions': [{'id': 'verification_cache', 'state': 'execute', 'test_telemetry': [
            {'tests': [{'test_id': 'gate_summary_test.Probe.test_x', 'state': 'failed'}]}]}]}
        joined = '\n'.join(gate_summary.summarize(report=report, text=self.OVERSHOOT_LOG))
        self.assertIn('failure 1/1: verification_cache', joined)
        self.assertNotIn('failure 2/2', joined)

    def test_a_gate_that_restarted_says_so_in_its_verdict_line(self):
        import json
        report = json.loads((FIXTURES / 'restarted.last-run.json').read_text())
        line = gate_summary.summarize(report=report)[0]
        self.assertIn('verification: PASS', line)
        self.assertIn('restarted 1 time(s): tests/lang/README.md changed', line)

    def test_a_crash_inside_a_driver_s_child_names_the_driver_and_the_crash(self):
        # Composed from real formats (the 13 November log was overwritten); see the fixture's first line.
        joined = self.summary('driver-crash-composed.log')
        self.assertIn('failure 1/1: tests/mode_differential.py', joined)
        self.assertIn('seed 10 (.selka-cache/mode-differential/kept/seed-10/run/gen.selka): plain fails for the whole '
                      'program: crash compiler-fault: crash-state: si_code=0x80 trap=13', joined)

    def summary_text(self, text):
        lines = gate_summary.summarize(text=text)
        self.assertNotIn('no failing step was found', '\n'.join(lines))
        return '\n'.join(lines)

    def test_no_constructed_red_log_says_that_no_failing_step_was_found(self):
        cases = ['', 'Build Summary: 1/2 steps succeeded (1 failed)\n', 'error: something broke\n',
                 gate_summary.FAIL_FAST_MARKER + '\n', 'step deadline: verification action x member 0 ran 1801.0 s '
                 '(limit 1800.0 s); killed\nBuild Summary: 1/2 steps succeeded (1 failed)\n']
        reports = [None, {'success': False, 'status': 75, 'actions': [],
                          'stability_diagnostics': {'reasons': [{'path': 'src/a.zig'}]}},
                   {'success': False, 'status': 124, 'actions': [], 'admissions': [
                       {'kind': 'gate', 'timed_out': True, 'execution_limits': {'timeout_seconds': 5400}}]},
                   {'success': False, 'status': 2, 'stage': 'preparation', 'error': 'artifact preparation failed',
                    'actions': []}]
        for text in cases:
            for report in reports:
                with self.subTest(text=text, report=report):
                    lines = gate_summary.summarize(report=report, text=text)
                    if lines[0].startswith('verification: FAIL'):
                        self.assertGreater(len(lines), 1)
                    self.assertNotIn('no failing step was found', '\n'.join(lines))

if __name__ == '__main__':
    unittest.main()
