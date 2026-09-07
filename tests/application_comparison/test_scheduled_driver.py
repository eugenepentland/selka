import json
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import cohort, cohort_sessions, scheduled_driver, session, task_pack
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import read_json, write_json

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class ScheduledDriverTests(unittest.TestCase):
    def test_scheduled_repair_uses_complete_public_pack_and_frozen_limits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            task = 'planner-input-boundary'
            pack = root / 'pack'
            task_pack.create(pack, task=task, hidden_seed='private-scheduled-fixture-never-score')
            frozen = root / 'cohort'
            cohort.freeze(frozen, blocks=[dict(id=task, application='planner', tier='small', family='local-boundary')],
                seed='fixture-schedule', model_settings={'model': 'fixture-model', 'max_reported_tokens_per_phase': 100},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20, max_output_tokens=37, max_turns=6),
                baseline_paths={f'planner/small/{language}': ROOT / 'baselines/planner' / language for language in cohort.LANGUAGES},
                task_paths={task: pack})
            envelope = root / 'attempt'
            cohort_sessions.prepare_fixture(frozen, task + '-r1-python', envelope)
            practice = root / 'practice'
            practice.mkdir()
            (practice / 'main.py').write_text('print(42)')
            task_adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'planner.py']}])
            practice_adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            settings = dict(tools={}, task_adapter=task_adapter, practice_source=practice,
                practice_adapter=practice_adapter, practice_case={'request': None, 'expected': 42},
                practice_prompt='Practice emitting a JSON integer.', transport_identity='fixture')
            state_file = envelope / 'session/session.json'
            original = read_json(state_file)
            changed = read_json(state_file)
            changed['budgets']['task_seconds'] += 1
            write_json(state_file, changed)
            with self.assertRaisesRegex(ValueError, 'no longer matches'):
                scheduled_driver.run_fixture(frozen, envelope, lambda *args, **kwargs: self.fail('must not call model'), **settings)
            self.assertFalse((envelope / 'session/driver').exists())
            write_json(state_file, original)
            calls = []
            def complete(body, timeout):
                calls.append(body)
                self.assertEqual(body['max_output_tokens'], 37)
                self.assertNotIn('private-scheduled-fixture-never-score', json.dumps(body))
                if len(calls) in (1, 4):
                    name, args = 'check', {}
                elif len(calls) == 3:
                    name, args = 'command', {'argv': ['/usr/bin/python3', '-c',
                        "from pathlib import Path; p=Path('planner.py'); p.write_text(p.read_text().replace('if len(payload) >= MAX_INPUT_BYTES:', 'if len(payload) > MAX_INPUT_BYTES:'))"]}
                else:
                    name, args = 'finish', {'reason': 'completed'}
                return {'model': 'fixture-model', 'id': f'r{len(calls)}', 'status': 'completed',
                    'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
                    'output': [{'type': 'function_call', 'call_id': f'c{len(calls)}', 'name': name, 'arguments': json.dumps(args)}]}
            report = scheduled_driver.run_fixture(frozen, envelope, complete, **settings)
            self.assertEqual(len(calls), 5)
            self.assertEqual(report['preparation']['reported_token_limit'], 100)
            self.assertEqual(report['task']['reported_token_limit'], 100)
            self.assertEqual(report['seal_reason'], 'completed')
            checked = session.load(envelope / 'session')['submissions'][0]['check']
            self.assertTrue(checked['passed'])
            self.assertEqual(len(checked['results']), 3)
            self.assertFalse(report['comparative_claim'])


if __name__ == '__main__':
    unittest.main()
