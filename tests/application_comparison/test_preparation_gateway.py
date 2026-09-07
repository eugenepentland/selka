import json
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import session
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.model_loop import run_preparation, run_task
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.preparation_gateway import PreparationGateway
from experiments.application_comparison.storage import read_json, write_json


class PreparationGatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        baseline = root / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('print(99)')
        (baseline / 'private-task.txt').write_text('task-only requirement')
        self.root = root / 'session'
        session.prepare(self.root, baseline, language='python', block='fixture', cohort='fixture',
                        participant='fixture', model='fixture-model')
        (self.root / 'practice/main.py').write_text('print(42)')
        self.adapter = freeze_adapter('python', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        self.task = Gateway(self.root, {}, adapter=self.adapter, public_case={'request': None, 'expected': 99})
        self.practice = PreparationGateway(self.task, self.adapter, {'request': None, 'expected': 42})
        session.start_preparation(self.root)

    def test_checked_practice_transitions_with_history_then_task_completes(self):
        index = 0
        def complete(body, timeout):
            nonlocal index
            index += 1
            name, arguments = ('check', {}) if index % 2 else ('finish', {'reason': 'completed'})
            if index <= 2:
                self.assertFalse((self.root / 'work').exists())
                self.assertNotIn('task-only requirement', json.dumps(body))
            return {'id': f'r{index}', 'model': 'fixture-model', 'status': 'completed',
                    'usage': {'input_tokens': 2, 'output_tokens': 3, 'total_tokens': 5},
                    'output': [{'type': 'function_call', 'name': name, 'arguments': json.dumps(arguments), 'call_id': f'c{index}'}]}
        settings = dict(model='fixture-model', transport_identity='fixture', max_turns=4)
        preparation = run_preparation(self.practice, complete, prompt='practice instruction', **settings)
        self.assertEqual(preparation['stop'], 'preparation-ended')
        self.assertEqual(session.load(self.root)['preparation']['outcome'], 'passed')
        self.assertEqual((self.root / 'work/main.py').read_text(), 'print(99)')
        history = read_json(self.root / 'model-preparation/transcript.json')
        task = run_task(self.task, complete, prompt='task-only requirement', history=history, **settings)
        self.assertEqual(task['stop'], 'sealed')
        self.assertEqual(session.load(self.root)['seal_reason'], 'completed')
        self.assertEqual(preparation['reported_usage']['total_tokens'], 10)
        self.assertEqual(task['reported_usage']['total_tokens'], 10)
        self.assertEqual(read_json(self.root / 'model-task/configuration.json')['initial_input'][:-1], history)

    def test_unchecked_edits_reject_and_failed_practice_does_not_drop_task(self):
        self.assertTrue(self.practice.dispatch('check', {})['passed'])
        (self.root / 'practice/main.py').write_text('print(43)')
        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
            self.practice.dispatch('finish', {'reason': 'completed'})
        self.assertFalse((self.root / 'work').exists())
        self.assertFalse(self.practice.dispatch('check', {})['passed'])
        with self.assertRaisesRegex(ValueError, 'passing check'):
            self.practice.dispatch('finish', {'reason': 'completed'})
        self.practice.dispatch('finish', {'reason': 'abandoned'})
        self.assertEqual(session.load(self.root)['preparation']['outcome'], 'failed')
        self.assertEqual(session.load(self.root)['phase'], 'working')

    def test_expired_practice_records_budget_without_model_call(self):
        path = self.root / 'session.json'
        manifest = read_json(path)
        manifest['preparation_started']['monotonic_ns'] -= 1201 * 1_000_000_000
        write_json(path, manifest)
        def unexpected(*args, **kwargs):
            self.fail('expired phase must not call model')
        result = run_preparation(self.practice, unexpected, model='fixture-model', prompt='practice', transport_identity='fixture')
        self.assertEqual(result['stop'], 'budget')
        self.assertEqual(session.load(self.root)['preparation']['outcome'], 'budget')
        self.assertEqual(session.load(self.root)['phase'], 'working')

    def test_changed_practice_configuration_rejects(self):
        with self.assertRaisesRegex(ValueError, 'configuration changed'):
            PreparationGateway(self.task, self.adapter, {'request': None, 'expected': 0})
        self.practice.public_case['expected'] = 0
        with self.assertRaisesRegex(ValueError, 'configuration changed'):
            self.practice.dispatch('check', {})


if __name__ == '__main__':
    unittest.main()
