"""Behavior checks for the supported focused-test wrapper."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location('focused', Path(__file__).parents[1] / 'scripts/focused_test.py')
focused = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(focused)


class ValidationTests(unittest.TestCase):
    def test_focused_filter_is_required(self):
        for target in ('units', 'cli', 'golden'):
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
            ['zig', 'build', 'test-units', '--summary', 'all', '-Dtest-filter=arena'])
        self.assertEqual(
            focused.command('cli', 'CLI managed'),
            ['zig', 'build', 'test-cli', '--summary', 'all', '-Dtest-filter=CLI managed'])

    def test_full_command_has_no_filter(self):
        self.assertEqual(focused.command('full', None), ['zig', 'build', 'test', '--summary', 'all'])


class OutputTests(unittest.TestCase):
    SELECTION = 'guardian/test: 34 test(s) selected by filter: "arena"\n'
    VERDICT = ('guardian/test: PASS - 34 passed\n'
               'guardian/test: RESULT {"passed":34,"failed":0,"skipped":0}\n')

    def test_selected_count_is_read_from_the_pre_run_report(self):
        self.assertEqual(focused.parse_selected(self.SELECTION), 34)
        self.assertIsNone(focused.parse_selected('no runner output'))

    def test_result_is_read_from_the_closing_json_line(self):
        self.assertEqual(focused.parse_result(self.VERDICT),
                         {'passed': 34, 'failed': 0, 'skipped': 0})
        self.assertIsNone(focused.parse_result('no runner output'))

    def test_summary_distinguishes_a_full_request(self):
        lines = focused.describe('full', None, 1022, {'passed': 1022, 'failed': 0, 'skipped': 0})
        self.assertIn('focused tests: full', lines)
        self.assertIn('result: PASS - 1022 passed, 0 failed, 0 skipped', lines)

    def test_aborted_selection_is_not_reported_as_pass(self):
        lines = focused.describe('units', 'zzz', 10,
                                 {'passed': 0, 'failed': 0, 'skipped': 0, 'aborted': True}, 1)
        self.assertIn('result: FAIL - 0 passed, 0 failed, 0 skipped', lines)

    def test_nonzero_exit_without_a_runner_result_is_a_failure(self):
        lines = focused.describe('units', 'arena', None, None, 1)
        self.assertIn('result: FAIL - the build or test runner exited 1', lines)


class MainTests(unittest.TestCase):
    def run_main(self, argv, returncode, output):
        completed = subprocess.CompletedProcess(argv, returncode, output, '')
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(focused, 'LOG_DIR', Path(tmp)), \
                 mock.patch.object(focused.subprocess, 'run', return_value=completed) as run:
                status = focused.main(argv)
            logs = sorted(Path(tmp).glob('*.log'))
            contents = [log.read_text() for log in logs]
        return status, contents, run

    def test_main_preserves_the_wrapped_exit_status(self):
        status, logs, run = self.run_main(
            ['units', 'arena'], 1,
            'guardian/test: 2 test(s) selected\nFAIL\n')
        self.assertEqual(status, 1)
        self.assertEqual(len(logs), 1)
        self.assertIn('selected', logs[0])
        self.assertEqual(run.call_args.args[0],
                         ['zig', 'build', 'test-units', '--summary', 'all', '-Dtest-filter=arena'])

    def test_main_rejects_an_empty_filter_without_running_zig(self):
        with mock.patch.object(focused.subprocess, 'run') as run:
            status = focused.main(['units', '   '])
        self.assertEqual(status, 2)
        run.assert_not_called()

    def test_main_saves_the_full_log(self):
        _, logs, _ = self.run_main(['full'], 0, 'guardian/test: 5 test(s) selected\nPASS\n')
        self.assertEqual(len(logs), 1)
        self.assertIn('PASS', logs[0])


if __name__ == '__main__':
    unittest.main()
