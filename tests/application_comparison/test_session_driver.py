import json
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import environment_receipt, session, session_driver
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import read_json


class SessionDriverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        parent = Path(self.temp.name)
        baseline = parent / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('print(99)')
        self.practice = parent / 'curriculum'
        self.practice.mkdir()
        (self.practice / 'main.py').write_text('print(42)')
        self.root = parent / 'session'
        session.prepare(self.root, baseline, language='python', block='fixture', cohort='fixture',
                        participant='fixture', model='fixture-model')
        adapter = freeze_adapter('python', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        self.settings = dict(tools={}, task_adapter=adapter, task_case={'request': None, 'expected': 99},
                             practice_source=self.practice, practice_adapter=adapter,
                             practice_case={'request': None, 'expected': 42}, practice_prompt='practice-only',
                             task_prompt='task-only-secret', transport_identity='fixture', max_turns=3)
        self.calls = 0

    def complete(self, body, timeout):
        self.calls += 1
        phase = session.load(self.root)['phase']
        if phase == 'preparing':
            self.assertNotIn('task-only-secret', json.dumps(body))
            self.assertFalse((self.root / 'work').exists())
        else:
            self.assertIn('practice-only', json.dumps(body))
            self.assertIn('task-only-secret', json.dumps(body))
        name, arguments = ('check', {}) if self.calls % 2 else ('finish', {'reason': 'completed'})
        return {'model': 'fixture-model', 'id': f'r{self.calls}', 'status': 'completed',
                'usage': {'input_tokens': 7, 'output_tokens': 3, 'total_tokens': 10},
                'output': [{'type': 'function_call', 'call_id': f'c{self.calls}',
                            'name': name, 'arguments': json.dumps(arguments)}]}

    def test_driver_runs_both_phases_with_separate_and_total_usage(self):
        result = session_driver.run_fixture(self.root, self.complete, **self.settings)
        self.assertEqual(self.calls, 4)
        self.assertEqual(result['seal_reason'], 'completed')
        self.assertEqual(result['reported_usage']['total_tokens'], 40)
        self.assertEqual(result['preparation']['reported_usage']['total_tokens'], 20)
        self.assertEqual(result['task']['reported_usage']['total_tokens'], 20)
        self.assertTrue(result['usage_complete'])
        self.assertFalse(result['comparative_claim'])
        self.assertEqual(read_json(self.root / 'driver/result.json'), result)
        with self.assertRaisesRegex(ValueError, 'fresh prepared fixture'):
            session_driver.run_fixture(self.root, self.complete, **self.settings)

    def test_environment_checks_surround_timed_phases(self):
        receipt = environment_receipt.capture()
        self.settings['environment'] = receipt
        def observed(body, timeout):
            self.assertTrue((self.root / 'driver/environment-before.json').exists())
            self.assertFalse((self.root / 'driver/environment-after.json').exists())
            return self.complete(body, timeout)
        report = session_driver.run_fixture(self.root, observed, **self.settings)
        self.assertEqual(report['environment']['status'], 'before-and-after-verified')
        self.assertEqual(report['environment']['sha256'], receipt['sha256'])
        self.assertGreater(report['environment']['verification_seconds'], 0)
        self.assertEqual(session.load(self.root)['phase'], 'sealed')
        self.assertEqual(read_json(self.root / 'driver/environment-after.json')['sha256'], receipt['sha256'])

    def test_incomplete_environment_rejects_before_model_or_clock(self):
        self.settings['environment'] = environment_receipt.capture([])
        with self.assertRaisesRegex(ValueError, 'all runtime system mounts'):
            session_driver.run_fixture(self.root, self.complete, **self.settings)
        self.assertEqual(self.calls, 0)
        self.assertEqual(session.load(self.root)['phase'], 'prepared')
        self.assertTrue((self.root / 'driver/interrupted.json').exists())
        self.assertFalse((self.root / 'driver/result.json').exists())

    def test_tool_drift_after_task_preserves_run_but_rejects_result(self):
        tool = Path(self.temp.name) / 'reference'
        tool.write_text('original')
        self.settings['tools'] = {'reference': tool}
        required = environment_receipt.session_tools(self.settings['tools'],
                       self.settings['task_adapter'], self.settings['practice_adapter'])
        self.settings['environment'] = environment_receipt.capture(tools=required)
        def change_tool(body, timeout):
            response = self.complete(body, timeout)
            if self.calls == 4:
                tool.write_text('changed')
            return response
        with self.assertRaisesRegex(ValueError, 'environment changed'):
            session_driver.run_fixture(self.root, change_tool, **self.settings)
        self.assertEqual(session.load(self.root)['phase'], 'sealed')
        self.assertTrue((self.root / 'model-task/transcript.json').exists())
        self.assertTrue((self.root / 'driver/environment-before.json').exists())
        self.assertTrue((self.root / 'driver/interrupted.json').exists())
        self.assertFalse((self.root / 'driver/result.json').exists())

    def test_reported_token_limits_are_separate_for_preparation_and_task(self):
        self.settings['max_reported_tokens'] = 10
        result = session_driver.run_fixture(self.root, self.complete, **self.settings)
        self.assertEqual(result['preparation']['stop'], 'reported-token-limit')
        self.assertEqual(result['task']['stop'], 'reported-token-limit')
        self.assertEqual(result['reported_usage']['total_tokens'], 20)
        self.assertEqual(result['seal_reason'], 'budget')
        self.assertEqual(session.load(self.root)['submissions'], [])

    def test_interrupted_transport_retains_phase_and_does_not_restart(self):
        def broken(*args, **kwargs):
            raise RuntimeError('fixture transport failure')
        with self.assertRaisesRegex(RuntimeError, 'fixture transport failure'):
            session_driver.run_fixture(self.root, broken, **self.settings)
        failure = read_json(self.root / 'driver/interrupted.json')
        self.assertEqual(failure['phase'], 'preparing')
        self.assertFalse((self.root / 'work').exists())
        self.assertFalse((self.root / 'driver/result.json').exists())
        with self.assertRaises(ValueError):
            session_driver.run_fixture(self.root, self.complete, **self.settings)

    def test_both_phases_accept_complete_named_public_packs(self):
        self.settings['practice_case'] = [dict(name=name, case={'request': None, 'expected': 42})
                                          for name in ('practice-first', 'practice-second')]
        self.settings['task_case'] = [dict(name=name, case={'request': None, 'expected': 99})
                                      for name in ('task-first', 'task-second')]
        report = session_driver.run_fixture(self.root, self.complete, **self.settings)
        self.assertEqual(report['seal_reason'], 'completed')
        practice = read_json(self.root / 'preparation-checks/0000/execution/result.json')
        task = session.load(self.root)['submissions'][0]['check']
        self.assertEqual(len(practice['results']), 2)
        self.assertEqual(len(task['results']), 2)
        self.assertTrue(practice['passed'] and task['passed'])


if __name__ == '__main__':
    unittest.main()
