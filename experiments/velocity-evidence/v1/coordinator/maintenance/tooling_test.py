"""Coordinator fixtures only: no real gateway begin/run, compiler invocation or participant clocks."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import coordinator as c


class Tooling(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.override = patch.object(c, 'BASE', self.base)
        self.override.start()
        (self.base / 'control/A').mkdir(parents=True)
        c.write_json(self.base / 'control/A/state.json', {'participant': 'A', 'stage': 1,
                     'status': 'prepared', 'sealed_stages': []})

    def tearDown(self):
        self.override.stop()
        self.temporary.cleanup()

    def fixture(self):
        directory = c.stage_path('A', 1)
        (directory / 'public/work').mkdir(parents=True)
        for name in c.pack.checks.FILES:
            (directory / 'public/work' / name).write_text('source\n')
        source = c.pack.source_receipt(directory / 'public/work')
        c.write_json(directory / 'setup.json', {'stage': 1, 'start': source, 'previous_source': None})
        state = {'commands': 0, 'requests': 0, 'edited_checks': 0, 'pending': None,
                 'expected_source': source, 'last_checked': source, 'has_check': False, 'started_unix': 1000.0}
        c.write_json(directory / 'gateway.json', state)
        return directory, source

    def command(self, directory, source, index, passed, edited=False, operation='check'):
        folder = directory / 'commands' / f'{index:03}'
        folder.mkdir(parents=True)
        request = {'operation': operation, 'index': index, 'source_before': source, 'edited_check': edited}
        result = {'outcome': 'exited', 'returncode': 0 if passed else 1, 'boundary_error': None,
                  'isolated': True, 'source_before': source, 'source_after': source,
                  'duration_seconds': 0.5, 'time': 1000 + index * 7}
        c.write_json(folder / 'request.json', request)
        c.write_json(folder / 'result.json', result)
        c.write_json(folder / 'stdout', {'stage': 1, 'checks': [{'passed': passed}]})
        state = c.read_json(directory / 'gateway.json')
        state.update(commands=index, requests=index, has_check=True)
        state['edited_checks'] += edited
        c.write_json(directory / 'gateway.json', state)
        return request, result, folder

    def test_latest_check_must_succeed_and_match_source(self):
        directory, source = self.fixture()
        self.command(directory, source, 1, True)
        self.assertEqual(c.latest_success(directory), 1)
        self.command(directory, source, 2, False, edited=True)
        with self.assertRaisesRegex(ValueError, 'successful latest'):
            c.latest_success(directory)
        record = directory / 'commands/002/result.json'
        value = c.read_json(record); value['returncode'] = 0; c.write_json(record, value)
        with self.assertRaisesRegex(ValueError, 'successful latest'):
            c.latest_success(directory)
        c.write_json(directory / 'commands/002/stdout', {'checks': [{'passed': True}]})
        (directory / 'public/work/ledger.my').write_text('unrecorded edit\n')
        with self.assertRaisesRegex(ValueError, 'intact source'):
            c.latest_success(directory)

    def test_initial_failure_is_not_an_edited_failure_and_timing_uses_last_end(self):
        directory, source = self.fixture()
        self.command(directory, source, 1, False)
        c.preserve_initial(directory, {'returncode': 1, 'outcome': 'exited', 'duration_seconds': .5})
        self.command(directory, source, 2, True, edited=True)
        self.command(directory, source, 3, True, operation='run')
        row = c.summary_row('A', 1)
        self.assertFalse(row['initial_unchanged_check']['passed'])
        self.assertEqual(row['failed_edited_submissions'], 0)
        self.assertTrue(row['first_edited_submission_passed'])
        self.assertEqual(row['start_to_last_command_seconds'], 21)
        self.assertEqual(c.latest_success(directory), 2)

    def test_pending_command_does_not_hide_completed_timing(self):
        directory, source = self.fixture()
        self.command(directory, source, 1, False)
        state = c.read_json(directory / 'gateway.json'); state.update(commands=2, requests=2, pending=2)
        c.write_json(directory / 'gateway.json', state)
        row = c.summary_row('A', 1)
        self.assertEqual(row['start_to_last_command_seconds'], 7)
        self.assertEqual(row['pending_command'], 2)
        with self.assertRaisesRegex(ValueError, 'pending'):
            c.latest_success(directory)

    def test_first_read_is_refused_without_beginning_clock(self):
        with patch.object(c, 'config', return_value={}), patch.object(c.gateway, 'begin') as begin:
            with self.assertRaisesRegex(ValueError, 'first command'):
                c.invoke('A', 'command', {'argv': ['/bin/cat', 'TASK.md']})
            begin.assert_not_called()
            self.assertFalse((c.stage_path('A', 1) / 'gateway.json').exists())

    def test_finish_prepares_only_next_stage_without_beginning_it(self):
        directory, source = self.fixture()
        self.command(directory, source, 1, True)
        settings = {'compiler': {'path': '/frozen/compiler'}, 'model': 'fixture'}
        def seal(path, reason):
            c.write_json(path / 'seal.json', {'reason': reason, 'source': source})
        def prepare(path, compiler, stage, participant, model, kind, previous):
            path.mkdir()
            c.write_json(path / 'setup.json', {'previous_source': source['sha256']})
            self.assertEqual(previous, directory)
            self.assertEqual((stage, participant, model, kind), (2, 'A', 'fixture', 'agent'))
        state = c.read_json(self.base / 'control/A/state.json')
        with patch.object(c.pack, 'seal', side_effect=seal), patch.object(c.pack, 'prepare', side_effect=prepare), patch.object(c.gateway, 'begin') as begin:
            response = c.advance('A', state, settings, 'completed')
            begin.assert_not_called()
        self.assertEqual(response['next_stage'], 2)
        self.assertFalse(response['next_clock_started'])
        self.assertFalse(c.stage_path('A', 3).exists())
        self.assertFalse(c.stage_path('B', 1).exists())
        self.assertFalse((c.stage_path('A', 2) / 'gateway.json').exists())

    def test_failed_check_cannot_seal_as_completed(self):
        directory, source = self.fixture()
        self.command(directory, source, 1, False)
        state = c.read_json(self.base / 'control/A/state.json')
        with patch.object(c.pack, 'seal') as seal:
            with self.assertRaisesRegex(ValueError, 'successful latest'):
                c.advance('A', state, {}, 'completed')
            seal.assert_not_called()

    def test_no_grading_until_all_six_seals_exist(self):
        with patch.object(c, 'config', return_value={}):
            with self.assertRaisesRegex(ValueError, 'all six stages'):
                c.grade()


if __name__ == '__main__':
    unittest.main()
