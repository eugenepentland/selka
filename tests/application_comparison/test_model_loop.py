"""Fake model responses drive real isolated tools; never scored participant runs."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import session
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.model_loop import run_task
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import digest, read_json, write_json


class ModelLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        parent = Path(self.temp.name)
        baseline = parent / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('print(42)')
        self.root = parent / 'session'
        session.prepare(self.root, baseline, language='python', block='fixture', cohort='fixture',
                        participant='fixture', model='fixture-model')
        session.start_preparation(self.root)
        session.start_task(self.root, 'passed')
        adapter = freeze_adapter('python', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        self.gateway = Gateway(self.root, {}, adapter=adapter, public_case={'request': None, 'expected': 42})
        self.requests = []

    def response(self, output, usage=True):
        result = {'id': f'response-{len(self.requests)}', 'model': 'fixture-model', 'status': 'completed', 'output': output}
        if usage:
            result['usage'] = {'input_tokens': 10, 'output_tokens': 5, 'total_tokens': 15}
        return result

    def call(self, name, arguments, identity):
        return {'type': 'function_call', 'name': name, 'arguments': json.dumps(arguments), 'call_id': identity}

    def run_loop(self, complete, **kwargs):
        return run_task(self.gateway, complete, model='fixture-model', prompt='fixture task',
                        transport_identity='fixture-provider', **kwargs)

    def test_reported_token_limit_stops_tools_and_records_overshoot(self):
        def complete(body, timeout):
            self.requests.append(body)
            return self.response([self.call('command', {'argv': ['/usr/bin/python3', '-c', 'open("should-not-exist","w").write("bad")']}, 'limited')])
        result = self.run_loop(complete, max_reported_tokens=10)
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(result['stop'], 'reported-token-limit')
        self.assertEqual(result['reported_token_overshoot'], 5)
        self.assertFalse(result['hard_billing_cap'])
        self.assertFalse((self.root / 'work/should-not-exist').exists())
        self.assertEqual(session.load(self.root)['seal_reason'], 'budget')

    def test_missing_usage_under_limit_stops_without_guessing_zero(self):
        def complete(body, timeout):
            self.requests.append(body)
            return self.response([self.call('check', {}, 'unknown')], usage=False)
        result = self.run_loop(complete, max_reported_tokens=100)
        self.assertEqual(result['stop'], 'usage-unknown')
        self.assertIsNone(result['reported_token_overshoot'])
        self.assertFalse(result['usage_complete'])
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(session.load(self.root)['submissions'], [])

    def test_frozen_limit_cannot_be_omitted_or_replaced(self):
        manifest = read_json(self.root / 'session.json')
        manifest['max_reported_tokens_per_phase'] = 100
        write_json(self.root / 'session.json', manifest)
        for value in (None, 200):
            with self.assertRaisesRegex(ValueError, 'frozen session'):
                self.run_loop(lambda *args, **kwargs: self.fail('must not request'), max_reported_tokens=value)
        self.assertFalse((self.root / 'model-task').exists())

    def test_invalid_reported_limit_rejects_before_request(self):
        with self.assertRaisesRegex(ValueError, 'positive integer'):
            self.run_loop(lambda *args, **kwargs: self.fail('must not request'), max_reported_tokens=True)
        self.assertFalse((self.root / 'model-task').exists())

    def test_real_check_and_completion_preserve_history_and_usage(self):
        reasoning = {'type': 'reasoning', 'id': 'reasoning-fixture', 'summary': []}
        practice = [{'role': 'user', 'content': 'practice history'}]
        def complete(body, timeout):
            self.assertGreater(timeout, 0)
            self.assertEqual({tool['name'] for tool in body['tools']}, {'command', 'check', 'finish'})
            self.assertTrue(all(tool['type'] == 'function' for tool in body['tools']))
            self.requests.append(copy.deepcopy(body))
            if len(self.requests) == 1:
                return self.response([reasoning, self.call('check', {}, 'c1')])
            self.assertIn(reasoning, body['input'])
            self.assertEqual(body['input'][-1]['type'], 'function_call_output')
            return self.response([self.call('finish', {'reason': 'completed'}, 'c2')])
        report = self.run_loop(complete, history=practice)
        self.assertEqual(report['stop'], 'sealed')
        saved_config = read_json(self.root / 'model-task/configuration.json')
        self.assertEqual(report['configuration_sha256'], digest(saved_config))
        self.assertEqual(len(saved_config['initial_input']), 2)
        self.assertEqual(report['reported_usage']['total_tokens'], 30)
        self.assertTrue(report['usage_complete'])
        self.assertFalse(report['comparative_claim'])
        self.assertEqual(report['record_kind'], 'fixture')
        self.assertEqual(practice, [{'role': 'user', 'content': 'practice history'}])
        self.assertEqual(session.load(self.root)['seal_reason'], 'completed')
        self.assertTrue(read_json(self.root / 'submissions/000/check/result.json')['steps'][0]['isolated'])
        self.assertTrue((self.root / 'model-task/0000/response.json').exists())

    def test_transport_timeout_preserves_unknown_usage(self):
        def complete(body, timeout):
            raise TimeoutError('fixture timeout')
        report = self.run_loop(complete)
        self.assertEqual(report['stop'], 'transport-timeout')
        self.assertFalse(report['usage_complete'])
        self.assertEqual(session.load(self.root)['seal_reason'], 'abandoned')
        self.assertTrue((self.root / 'model-task/0000/transport-timeout.json').exists())

    def test_parallel_calls_are_rejected_before_any_execution(self):
        def complete(body, timeout):
            return self.response([self.call('command', {'argv': ['/usr/bin/touch', '/work/unexpected']}, 'one'),
                                  self.call('check', {}, 'two')])
        with self.assertRaisesRegex(ValueError, 'parallel'):
            self.run_loop(complete)
        self.assertFalse((self.root / 'work/unexpected').exists())

    def test_unknown_hosted_tool_is_never_dispatched(self):
        def complete(body, timeout):
            return self.response([{'type': 'web_search_call', 'id': 'forbidden'}])
        with self.assertRaisesRegex(ValueError, 'undeclared'):
            self.run_loop(complete)
        self.assertTrue((self.root / 'model-task/failure.json').exists())
        self.assertEqual(session.load(self.root)['submissions'], [])

    def test_duplicate_call_identity_and_restart_are_rejected(self):
        def complete(body, timeout):
            return self.response([self.call('command', {'argv': ['/usr/bin/true']}, 'same')])
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.run_loop(complete)
        with self.assertRaises(FileExistsError):
            self.run_loop(complete)

    def test_missing_usage_and_no_finish_are_not_success(self):
        report = self.run_loop(lambda body, timeout: self.response([], usage=False))
        self.assertFalse(report['usage_complete'])
        self.assertEqual(report['stop'], 'model-ended-without-finish')
        self.assertEqual(session.load(self.root)['seal_reason'], 'abandoned')

    def test_late_model_response_cannot_launch_a_tool(self):
        def complete(body, timeout):
            # Advance the loop clock as well as the stored task clock.
            from unittest.mock import patch
            now = session.clock()
            now['monotonic_ns'] += 1801 * 1000000000
            self.clock_patch = patch.object(session, 'clock', return_value=now)
            self.clock_patch.start()
            self.addCleanup(self.clock_patch.stop)
            return self.response([self.call('command', {'argv': ['/usr/bin/touch', '/work/late']}, 'late')])
        report = self.run_loop(complete)
        self.assertEqual(report['stop'], 'budget')
        self.assertFalse((self.root / 'work/late').exists())
        self.assertEqual(session.load(self.root)['seal_reason'], 'budget')


if __name__ == '__main__':
    unittest.main()
