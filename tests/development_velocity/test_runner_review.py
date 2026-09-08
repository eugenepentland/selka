"""Independent launch-review regressions: evidence, recovery and acceptance boundaries."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from experiments.application_comparison import session
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import read_json, write_json
from experiments.development_velocity import runner, telemetry


class RunnerReviewTests(unittest.TestCase):
    def make_attempt(self, directory):
        parent = Path(directory)
        baseline = parent / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('print(1)\n')
        root = parent / 'attempt'
        session.prepare(root, baseline, language='python', block='fixture', cohort='review',
                        participant='review-only', model='fixture', kind='fixture')
        session.start_preparation(root)
        session.start_task(root, 'passed')
        return root

    def test_feedback_serialized_size_respects_cap_even_with_escaping(self):
        for value in ('x' * 100000, '\\"\n' * 100000, 'é' * 100000):
            original = {'nested': {'diagnostic': value}, 'passed': False}
            bounded = runner.bounded_feedback(original, 512)
            self.assertLessEqual(len(json.dumps(bounded, ensure_ascii=False)), 512)
            self.assertEqual(original['nested']['diagnostic'], value)

    def test_dispatch_exception_retains_changed_source_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_attempt(temporary)
            gateway = telemetry.ObservedGateway(root, {})
            def mutate_then_fail(*_):
                (root / 'work/main.py').write_text('print(2)\n')
                raise RuntimeError('simulated exception after edit')
            with patch.object(Gateway, 'dispatch', side_effect=mutate_then_fail):
                with self.assertRaisesRegex(RuntimeError, 'after edit'):
                    gateway.dispatch('command', {'argv': ['/usr/bin/true']})
            evidence = root / 'telemetry/000000'
            result = read_json(evidence / 'result.json')
            self.assertEqual(result['changed_files'], ['main.py'])
            self.assertEqual((evidence / 'changed-source/main.py').read_text(), 'print(2)\n')
            self.assertEqual(result['failure']['type'], 'RuntimeError')

    def test_capture_problem_does_not_prevent_workspace_repair(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_attempt(temporary)
            gateway = telemetry.ObservedGateway(root, {})
            bad = root / 'work/bad-link'
            bad.symlink_to('main.py')
            def repair(*_):
                bad.unlink()
                return {'returncode': 0, 'stdout': '', 'stderr': ''}
            with patch.object(Gateway, 'dispatch', side_effect=repair) as dispatch:
                result = gateway.dispatch('command', {'argv': ['/bin/rm', 'bad-link']})
            self.assertEqual(dispatch.call_count, 1)
            self.assertEqual(result['returncode'], 0)
            evidence = read_json(root / 'telemetry/000000/result.json')
            self.assertFalse(evidence['source_capture_complete'])
            self.assertIsNotNone(evidence['source_capture_error'])

    def test_rejected_nondict_arguments_still_allow_attempt_summary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_attempt(temporary)
            gateway = telemetry.ObservedGateway(root, {})
            with self.assertRaises(ValueError):
                gateway.dispatch('command', [])
            session.seal(root, 'abandoned')
            report = telemetry.summarize(root)
            self.assertTrue(report['operations'][0]['failed'])
            self.assertIsNone(report['model_tokens'])

    def test_private_pass_cannot_erase_failed_public_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_attempt(temporary)
            submitted = session.submit(root)
            session.record_check(root, submitted['index'], {'source_sha256': submitted['source']['sha256'], 'passed': False})
            session.seal(root, 'completed')
            cohort = Path(temporary) / 'cohort'
            private = cohort / 'fixture/pack/private'
            private.mkdir(parents=True)
            write_json(private / 'cases.json', {'request': {}, 'expected': {}})
            registration = {'configuration': {'adapters': {'python': {}}}}
            with patch.object(runner, 'attempt_path', return_value=(root, registration, {})), \
                 patch.object(runner.public_verification, 'run', return_value={'passed': True}), \
                 patch.object(runner.telemetry, 'summarize', return_value={}), \
                 patch.object(runner.iteration_log, 'append'):
                result = runner.grade(cohort, 'fixture', 'pair-01', 'python')
            self.assertFalse(result['passed'])


if __name__ == '__main__':
    unittest.main()
