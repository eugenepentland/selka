"""Behavior checks for the supported focused-test wrapper."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import warnings
from unittest import mock


SCRIPTS = Path(__file__).parents[1] / 'scripts'
FIXTURES = SCRIPTS / 'run-report-fixtures'
sys.path.insert(0, str(SCRIPTS))
import failure_report  # noqa: E402

SPEC = importlib.util.spec_from_file_location('focused', SCRIPTS / 'focused_test.py')
focused = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(focused)


def fixture(name):
    return (FIXTURES / name).read_text(encoding='utf-8')


def said(printed):
    """A stand-in for `print` that keeps what goes to standard output (not the notes on standard error)."""
    def record(*args, **kwargs):
        if 'file' not in kwargs:
            printed.append(' '.join(map(str, args)))
    return record


def render(name, returncode, what="units 'x'"):
    return failure_report.render(fixture(name), returncode, what, 1.5)


class ValidationTests(unittest.TestCase):
    def test_focused_filter_is_required(self):
        for target in ('units', 'cli', 'golden', 'tooling', 'text-scalar'):
            with self.assertRaises(focused.FilterError):
                focused.validate(target, None)
            with self.assertRaises(focused.FilterError):
                focused.validate(target, '')
            with self.assertRaises(focused.FilterError):
                focused.validate(target, ' \t\n ')

    def test_focused_filter_is_returned_unchanged(self):
        self.assertEqual(focused.validate('units', 'arena'), 'arena')
        self.assertEqual(focused.validate('cli', 'CLI managed'), 'CLI managed')

    def test_full_refuses_a_filter_and_needs_none(self):
        self.assertIsNone(focused.validate('full', None))
        self.assertIsNone(focused.validate('full', '   '))
        with self.assertRaises(focused.FilterError):
            focused.validate('full', 'arena')

    def test_unknown_target_is_rejected(self):
        with self.assertRaises(focused.FilterError):
            focused.validate('everything', 'arena')

    def test_empty_filter_does_not_reach_the_build_command(self):
        with self.assertRaises(focused.FilterError):
            focused.validate('units', '   ')


class CommandTests(unittest.TestCase):
    def test_focused_command_names_the_target_and_filter(self):
        self.assertEqual(
            focused.command('units', 'arena'),
            [focused.zig_program(), 'build', 'test-units', '--summary', 'all', '-Dtest-filter=arena'])
        self.assertEqual(
            focused.command('cli', 'CLI managed'),
            [focused.zig_program(), 'build', 'test-cli', '--summary', 'all', '-Dtest-filter=CLI managed'])

    def test_tooling_and_explicit_legacy_namespace_route_without_losing_guard(self):
        self.assertEqual(focused.command('tooling', 'invalidation')[2], 'test-tooling-units')
        self.assertEqual(focused.command('units', 'invalidation_test.test.')[2], 'test-tooling-units')
        argv = focused.command('units', 'doc_coverage.test.sections')
        self.assertEqual(argv[2], 'test-tooling-units')
        self.assertEqual(argv[-1], '-Dtest-filter=doc_coverage_test.test.sections')
        self.assertEqual(focused.command('units', 'no-such-test')[2], 'test-units')
        with self.assertRaises(focused.FilterError):
            focused.validate('tooling', '')

    def test_full_command_has_no_filter(self):
        self.assertEqual(focused.command('full', None), [focused.zig_program(), 'build', 'test', '--summary', 'all'])

    def test_text_scalar_target_preserves_explicit_filter(self):
        self.assertEqual(focused.command('text-scalar', 'number grammar'),
                         [focused.zig_program(), 'build', 'test-text-scalar-units',
                          '--summary', 'all', '-Dtest-filter=number grammar'])


class CountTests(unittest.TestCase):
    SELECTION = 'test: 34 test(s) selected by filter: "arena"\n'
    VERDICT = ('test: PASS - 34 passed\n'
               'test: RESULT {"passed":34,"failed":0,"skipped":0}\n')

    def test_selected_count_and_result_are_read_from_the_runners_lines(self):
        found = failure_report.counts(self.SELECTION + self.VERDICT)
        self.assertEqual((found['selected'], found['passed'], found['failed'], found['processes']), (34, 34, 0, 1))
        self.assertIsNone(failure_report.counts('no runner output')['selected'])
        self.assertEqual(failure_report.counts('no runner output')['processes'], 0)

    def test_sharded_run_is_summed_over_its_processes(self):
        # `zig build test` splits its two slow roots into shards, and each shard is one process printing its own
        # count and RESULT. Reading only the last line would report one eighth of the suite as the whole of it.
        sharded = ('test: 12 test(s) selected [shard 0/8 of 100]\n'
                   'test: RESULT {"passed":12,"failed":0,"skipped":0}\n'
                   'test: 11 test(s) selected [shard 1/8 of 100]\n'
                   'test: RESULT {"passed":10,"failed":1,"skipped":0}\n')
        found = failure_report.counts(sharded)
        self.assertEqual((found['selected'], found['passed'], found['failed'], found['processes']), (23, 22, 1, 2))
        self.assertIn('over 2 test processes', failure_report.render(sharded, 1, 'full')[0])

    def test_a_passing_zig_build_log_has_only_the_build_summary_for_its_counts(self):
        self.assertEqual(failure_report.render(fixture('zig-pass.log'), 0, "units 'buffer'", 31.0),
                         ["PASS units 'buffer': 38 passed, 3521 skipped in 31.0s"])


class ReaderTests(unittest.TestCase):
    """What the failure reader prints for each form the test roots really print (fixtures: scripts/run-report-fixtures/)."""

    def test_a_pass_is_one_line_and_names_what_ran_the_count_and_the_seconds(self):
        self.assertEqual(render('terminal-pass.log', 0), ["PASS units 'x': 19 passed, 0 skipped (19 selected) in 1.5s"])

    def test_expect_equal_prints_expected_and_found_and_the_place_of_the_test(self):
        lines = render('zig-expect-int.log', 1)
        self.assertEqual(lines[0], "FAIL units 'x': 0 passed, 1 failed, 0 skipped in 1.5s")
        self.assertTrue(lines[1].startswith('FAILED integration.test.a directory test run ends with one line for the '
                                            'warnings it withheld, each counted once, the same at every width of the run'))
        self.assertIn('  expected 1, found 3', lines)
        self.assertTrue(lines[3].startswith('  at test/integration.zig:8220  try testing.expectEqual('), lines)
        self.assertEqual(len(lines), 4)

    def test_expect_equal_strings_prints_the_first_difference_not_the_two_blocks(self):
        lines = render('zig-expect-strings.log', 1)
        self.assertIn('  first difference at line 3', lines)
        self.assertIn('  expected: (end of string)', lines)
        self.assertTrue(any(line.startswith('  found: fix: left 1 warning with a repair alone') for line in lines), lines)
        self.assertFalse(any('instead found this' in line for line in lines))

    def test_a_bare_expect_prints_the_test_source_line_that_failed(self):
        lines = render('zig-expect-bool.log', 1)
        self.assertTrue(lines[1].startswith('FAILED fix_cli_test.test.CLI fix deletes a trailing return or fail'))
        self.assertTrue(lines[2].startswith('  at test/fix_cli_test.zig:6113  try testing.expect(contains(refused.stderr'),
                        lines)

    def test_an_error_returned_from_inside_names_the_test_and_the_place_it_came_from(self):
        lines = render('zig-error-return.log', 1)
        self.assertIn('  at src/advice_messages_test.zig:86  try expectAccepted(half ++', lines)
        self.assertIn('  error from src/parser.zig:1435  if (self.cursor.recovered) return error.SourceError;', lines)
        self.assertEqual(lines[0], "FAIL units 'x': 99 passed, 1 failed, 0 skipped in 1.5s")

    def test_a_compile_error_in_the_test_root_prints_the_error_and_its_source_line(self):
        lines = render('zig-compile-error.log', 1)
        self.assertEqual(lines[1], 'compile error in the test root (1); no test ran')
        self.assertEqual(lines[2], "test/integration.zig:6391:4: error: duplicate struct member name 'gitIn'")
        self.assertTrue(lines[3].startswith('  fn gitIn('))

    def test_a_filter_that_named_no_test_says_so(self):
        lines = render('guardian-nothing-ran.log', 1)
        self.assertTrue(lines[0].startswith("FAIL units 'x': 0 passed, 0 failed, 0 skipped (0 selected)"))
        self.assertTrue(any(line.startswith('no test matched the filter') for line in lines), lines)

    def test_a_panic_prints_the_panic_line_the_exit_code_and_both_places(self):
        lines = render('zig-crash-134.log', 1)
        self.assertIn('  exited with code 134', lines)
        self.assertIn('  thread 3320523 panic: index out of bounds: index 49, len 48', lines)
        self.assertTrue(any(line.startswith('  at src/compiler_test.zig:356') for line in lines), lines)
        self.assertTrue(any(line.startswith('  error from src/compiler_test.zig:204') for line in lines), lines)

    def test_a_leak_and_a_test_killed_at_its_deadline_are_named(self):
        leak = render('zig-leak.log', 1)
        self.assertIn('  leaked 9 allocations', leak)
        self.assertTrue(any(line.startswith('guardian: 0 failed of 1, 1 leaked, 9 error(s) logged') for line in leak), leak)
        deadline = render('zig-deadline.log', 1)
        self.assertIn('  timed out after 300s', deadline)
        self.assertTrue(any(line.startswith('test deadline: test/integration.zig::NETWORK-ENDPOINT-1 ran 301.0 s')
                            for line in deadline), deadline)

    def test_the_machines_crash_signature_is_named_so_that_a_lane_reruns_it_once(self):
        lines = render('zig-trap13.log', 1)
        self.assertTrue(any('trap=13' in line and 'run it once more' in line for line in lines), lines)
        self.assertTrue(any(line.startswith('  found: test/fixtures/parse-matrix/bytes_parse_float_cells.selka') for line in lines))

    def test_a_run_still_queued_for_a_build_slot_is_not_reported_as_slow_tests(self):
        self.assertEqual(failure_report.queued(fixture('build-slot-queued.log').splitlines()),
                         'still queued for a build slot (ticket 3481, position 1, 0s so far): it has not started')
        admitted = fixture('build-slot-queued.log') + 'build-slot: build slot 1, FIFO ticket 3481 after 4.323s\n'
        self.assertEqual(failure_report.queued(admitted.splitlines()), '')

    def test_a_test_binary_run_by_itself_prints_message_then_place_for_each_failure(self):
        lines = render('terminal-fail.log', 1)
        self.assertEqual(lines[0], "FAIL units 'x': 1 passed, 3 failed, 0 skipped (4 selected) in 1.5s")
        self.assertEqual([line for line in lines if line.startswith('FAILED')],
                         ['FAILED fail.test.equal ints', 'FAILED fail.test.equal strings', 'FAILED fail.test.plain expect'])
        self.assertIn('  expected 1, found 3', lines)
        self.assertIn('  expected: b', lines)
        self.assertIn('  error.TestUnexpectedResult', lines)
        self.assertEqual(len([line for line in lines if line.startswith('  at ')]), 3)


class NeverAPassTests(unittest.TestCase):
    """The exit status decides; the reading of the text only chooses what to print."""

    def test_a_failed_run_is_a_fail_whatever_the_text_says(self):
        for name in ('terminal-pass.log', 'zig-pass.log', 'build-slot-queued.log'):
            self.assertTrue(render(name, 1)[0].startswith('FAIL '), name)

    def test_a_failed_log_with_no_known_form_prints_its_last_lines_and_says_so(self):
        text = ''.join('line %d\n' % n for n in range(100))
        lines = failure_report.render(text, 3, 'cli', 2.0)
        self.assertEqual(lines[0], 'FAIL cli: no test count in the output in 2.0s')
        self.assertEqual(lines[1], 'no known failure form in the log; its last 20 lines:')
        self.assertEqual(lines[2:], ['line %d' % n for n in range(80, 100)])

    def test_a_run_that_exited_0_while_its_text_shows_a_failure_is_a_fail_and_exits_1(self):
        text = fixture('zig-expect-int.log')
        self.assertEqual(failure_report.render(text, 0, 'x')[0].split(':')[0], 'FAIL x')
        self.assertIn('exit status 0 but the output shows a failure', failure_report.render(text, 0, 'x')[0])
        self.assertEqual(failure_report.exit_status(0, text), 1)
        self.assertEqual(failure_report.exit_status(0, fixture('zig-pass.log')), 0)
        self.assertEqual(failure_report.exit_status(134, fixture('zig-pass.log')), 134)

    def test_a_crash_the_runner_counted_as_a_pass_is_still_a_failure(self):
        # The real log of a test that panicked: guardian printed `PASS - 0 passed` and RESULT failed 0.
        text = fixture('zig-crash-134.log')
        self.assertIn('test: PASS', text)
        self.assertTrue(failure_report.render(text, 1, 'x')[0].startswith('FAIL '))

    def test_fifty_failures_print_at_most_thirty_lines_with_every_name_that_fits_and_a_count_of_the_rest(self):
        one = fixture('zig-expect-int.log').split('Build Summary')[0]
        header = one.index("error: '")
        block = one[header:one.index('failed command:')]
        text = ''.join(block.replace("integration.test.a directory", "t%02d.test.a directory" % n) for n in range(50))
        lines = failure_report.render(text, 1, 'cli', 9.0)
        self.assertLessEqual(len(lines), failure_report.MAX_LINES)
        self.assertEqual(lines[0], 'FAIL cli: 50 failed in 9.0s')
        names = [line for line in lines if line.startswith('FAILED')]
        self.assertGreaterEqual(len(names), 10)
        self.assertTrue(lines[-1].startswith('... and %d more failing tests' % (50 - len(names))), lines[-1])
        self.assertTrue(names[0].startswith('FAILED t00.test.a directory test run ends'))


class RunTests(unittest.TestCase):
    """Running a command: waiting, the limit, `--wait PID`, and the last line."""

    def setUp(self):
        # A run left going at the limit is meant to outlive the wrapper; the test's Popen object is garbage collected
        # while its `sleep` still runs, which unittest would report as a ResourceWarning.
        warnings.simplefilter('ignore', ResourceWarning)

    def run_main(self, argv, script, limit=10):
        printed = []
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(focused, 'LOG_DIR', Path(tmp)), \
             mock.patch.object(focused, 'watch_run', return_value=None), \
             mock.patch.object(focused, 'command', return_value=['sh', '-c', script]), \
             mock.patch('builtins.print', side_effect=said(printed)):
            self.directory = Path(tmp)
            status = focused.main([*argv, '--limit', str(limit)])
            self.followups = []
            for follow in getattr(self, 'follow', []):
                self.followups.append(follow(self.directory))
        return status, printed

    def test_a_pass_prints_one_line_and_the_closing_line_and_saves_the_log(self):
        script = 'echo "test: 3 test(s) selected"; echo "Build Summary: 5/5 steps succeeded; 3/3 tests passed"'
        status, printed = self.run_main(['units', 'arena'], script)
        self.assertEqual(status, 0)
        self.assertEqual(printed[-2].split(' in ')[0], "PASS units 'arena': 3 passed, 0 skipped (3 selected)")
        self.assertRegex(printed[-1], r'^exit status 0; log .*/units-arena-\d{8}-\d{6}\.log$')

    def test_a_failure_prints_the_failing_test_and_keeps_the_exit_status(self):
        script = 'cat "%s"; exit 3' % (FIXTURES / 'zig-expect-int.log')
        status, printed = self.run_main(['cli', 'directory'], script)
        self.assertEqual(status, 3)
        self.assertTrue(printed[0].startswith("FAIL cli 'directory': 0 passed, 1 failed"))
        self.assertIn('  expected 1, found 3', printed)
        self.assertTrue(printed[-1].startswith('exit status 3; log '))
        self.assertTrue(all('failed command' not in line and 'Build Summary' not in line for line in printed))

    def test_a_run_at_the_limit_keeps_going_and_wait_prints_the_same_result(self):
        script = 'echo "test: 2 test(s) selected"; sleep 2; echo "Build Summary: 5/5 steps succeeded; 2/2 tests passed"'
        status, printed = self.run_main(['units', 'slow'], script, limit=0.3)
        self.assertEqual(status, focused.STILL_RUNNING)
        self.assertTrue(printed[0].startswith("still running after "), printed)
        pid = int(printed[0].split('(pid ')[1].split(')')[0])
        self.assertEqual(printed[1], 'wait: python3 scripts/focused_test.py --wait %d' % pid)
        self.assertRegex(printed[2], r'^exit status 124; log ')

    def test_wait_finds_the_run_by_pid_and_prints_its_result_each_time(self):
        printed = []
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(focused, 'LOG_DIR', Path(tmp)), \
             mock.patch.object(focused, 'watch_run', return_value=None), \
             mock.patch.object(focused, 'command',
                               return_value=['sh', '-c', 'sleep 1; echo "Build Summary: 1/1 steps succeeded; 4/4 tests passed"']), \
             mock.patch('builtins.print', side_effect=said(printed)):
            self.assertEqual(focused.main(['units', 'x', '--limit', '0.2']), focused.STILL_RUNNING)
            pid = json.loads(next(Path(tmp).glob('*.json')).read_text())['pid']
            printed.clear()
            self.assertEqual(focused.main(['--wait', str(pid), '--limit', '20']), 0)
            first = list(printed)
            printed.clear()
            self.assertEqual(focused.main(['--wait', str(pid)]), 0)
            self.assertEqual(printed[0].split(' in ')[0], first[0].split(' in ')[0])
            self.assertEqual(first[0].split(' in ')[0], "PASS units 'x': 4 passed, 0 skipped")
            self.assertEqual(focused.main(['--wait', '999999']), 2)

    def test_a_shell_killed_before_it_wrote_a_status_is_a_failure_not_a_pass(self):
        printed = []
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(focused, 'LOG_DIR', Path(tmp)), \
             mock.patch('builtins.print', side_effect=said(printed)):
            state = focused.launch(['sleep', '30'], Path(tmp) / 'x.log', "units 'x'")
            os.killpg(state['pid'], signal.SIGKILL)  # the shell and its sleep: nothing writes a status
            time.sleep(0.3)
            status = focused.finish(state, 5, 20)
        self.assertEqual(status, 1)
        self.assertIn('the run ended without an exit status', printed[0])
        self.assertTrue(printed[-1].startswith('exit status 1; log '))

    def test_main_rejects_an_empty_filter_without_running_zig(self):
        with mock.patch.object(focused, 'launch') as launch:
            self.assertEqual(focused.main(['units', '   ']), 2)
        launch.assert_not_called()

    def test_a_running_watcher_answers_instead_of_a_build_unless_no_watch_is_given(self):
        with mock.patch.object(focused, 'watch_run', return_value=3) as watched, \
             mock.patch.object(focused, 'launch') as launch:
            self.assertEqual(focused.main(['units', 'arena']), 3)
        watched.assert_called_once_with('units', 'arena')
        launch.assert_not_called()
        status, _ = self.run_main(['units', 'arena', '--no-watch'], 'exit 0')
        self.assertEqual(status, 0)

    def test_the_command_run_is_the_supported_build_target_with_the_filter(self):
        with mock.patch.object(focused, 'watch_run', return_value=None), \
             mock.patch.object(focused, 'launch', side_effect=RuntimeError('stop')) as launch:
            with self.assertRaises(RuntimeError):
                focused.main(['units', 'arena'])
        self.assertEqual(launch.call_args.args[0],
                         [focused.zig_program(), 'build', 'test-units', '--summary', 'all', '-Dtest-filter=arena'])


class ProbeTests(unittest.TestCase):
    """scripts/lane/probe.sh with a stand-in compiler: its limit, its wait command and its closing lines."""

    COMPILER = ('#!/bin/sh\ncase "$1" in\n'
                '  check) case "$2" in *refused*) echo "$2:1:1: error[E_FAKE]: no" >&2; exit 1;; esac; exit 0;;\n'
                '  run) case "$2" in *slow*) sleep 10;; esac; echo hello; exit 0;;\n'
                'esac\n')

    def probe(self, tmp, *arguments):
        env = dict(os.environ, PROBE_STORES=str(Path(tmp) / 'stores'))
        return subprocess.run(['bash', str(SCRIPTS / 'lane' / 'probe.sh'), '--compiler', str(Path(tmp) / 'fake'),
                               '--out', str(Path(tmp) / 'out'), *arguments], capture_output=True, text=True, env=env,
                              cwd=tmp, timeout=120)

    def setup_files(self, tmp, names):
        fake = Path(tmp) / 'fake'
        fake.write_text(self.COMPILER)
        fake.chmod(0o755)
        for name in names:
            (Path(tmp) / name).write_text('func main(out: Stream) -> int:\n    return 0\n')

    def test_a_finished_probe_prints_a_line_a_file_the_counts_and_the_closing_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.setup_files(tmp, ['a.selka', 'refused.selka'])
            done = self.probe(tmp, 'a.selka', 'refused.selka')
            lines = done.stdout.splitlines()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(lines[0].startswith('a.selka: check ok | debug+leakcheck ok | release ok | same | out: hello'), lines)
        self.assertTrue(lines[1].startswith('refused.selka: check REFUSED E_FAKE at line 1 (status 1), not run'), lines)
        self.assertRegex(lines[2], r'^probe: 2 files, 1 check REFUSED, 0 run not ok, 0 debug and release DIFFERENT, in \d+s$')
        self.assertRegex(lines[3], r'^exit status 0; details \(every step.s output\) .*/out$')

    def test_a_probe_at_the_limit_says_what_is_left_and_wait_prints_the_whole_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.setup_files(tmp, ['a.selka', 'slow.selka'])
            # a.selka's three fake runs need well under a second, but at load 59 they took more than one (18 November):
            # give them six, and keep slow.selka's first run (ten seconds) running past that.
            early = self.probe(tmp, '--limit', '6', 'a.selka', 'slow.selka')
            early_lines = early.stdout.splitlines()
            later = self.probe(tmp, '--wait', str(Path(tmp) / 'out'), '--limit', '60')
            again = self.probe(tmp, '--wait', str(Path(tmp) / 'out'), '--limit', '60')
        self.assertEqual(early.returncode, 124, early.stdout)
        self.assertTrue(early_lines[0].startswith('a.selka: check ok'), early_lines)
        self.assertRegex(early_lines[1], r'^still running after \d+s \(pid \d+\): 1 of 2 files done; not yet: slow.selka$')
        self.assertRegex(early_lines[2], r'^wait: scripts/lane/probe.sh --wait .*/out$')
        self.assertRegex(early_lines[3], r'^exit status 124; details .*/out$')
        self.assertEqual(later.returncode, 0, later.stdout)
        self.assertEqual([line.split(':')[0] for line in later.stdout.splitlines()[:2]], ['a.selka', 'slow.selka'])
        self.assertIn('probe: 2 files, 0 check REFUSED', later.stdout)
        self.assertEqual(again.stdout.splitlines()[:3], later.stdout.splitlines()[:3])

    def test_wait_for_a_folder_with_no_recorded_run_is_a_usage_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            nothing = self.probe(tmp, '--wait', tmp)
        self.assertEqual(nothing.returncode, 2)
        self.assertIn('no probe run recorded', nothing.stderr)


if __name__ == '__main__':
    unittest.main()
