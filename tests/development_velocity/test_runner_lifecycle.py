"""Fixture cohorts exercise real freezing and isolated onboarding; no agent scores."""
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from experiments.application_comparison import iteration_log, session
from experiments.application_comparison.storage import path_identity, read_json
from experiments.development_velocity import runner, report


class RunnerLifecycle(unittest.TestCase):
    def test_freeze_practice_and_dispatch_preserve_clock_boundary(self):
        with tempfile.TemporaryDirectory(prefix='development-fixture-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            proof = Path(temporary) / 'proof.txt'
            proof.write_text('Test fixture readiness; never a scored launch authorization.\n')
            readiness = {'runtime_verified': True, 'library_verified': True,
                         'starters_verified': True, 'cases_reviewed': True,
                         'tasks': list(runner.catalog.IDS), 'proofs': [path_identity(proof)]}
            readiness_path = Path(temporary) / 'readiness.json'
            runner.write_json(readiness_path, readiness)
            # A concurrent report author is allowed during this fixture. Production
            # retains real harness identities and refuses changes after freezing.
            with patch.object(runner, 'source_identity', return_value={'fixture': 'stable'}):
                frozen = runner.freeze(study, 'fixture', readiness_path)
                root = Path(frozen['cohort'])
                item = frozen['dispatch_order'][0]
                task, pair, language = (item[k] for k in ('task', 'pair', 'language'))
                prepared = runner.prepare(root, task, pair, language)
                token = prepared['token']
                with self.assertRaisesRegex(ValueError, 'invalid participant token'):
                    runner.agent(root, '../outside', 'check', {})
                with self.assertRaisesRegex(ValueError, 'unknown or duplicate'):
                    runner.agent(root, '0' * 32, 'check', {})
                attempt = root / task / pair / language
                self.assertNotIn('task_started', session.load(attempt))
                frozen_practice = root / (language + '-frozen-practice') / 'contract.md'
                original = frozen_practice.read_bytes()
                frozen_practice.write_bytes(original + b'changed')
                with self.assertRaisesRegex(ValueError, 'practice changed'):
                    runner.registered(root)
                frozen_practice.write_bytes(original)
                private = root / task / 'pack/private/cases.json'
                original = private.read_bytes()
                private.write_bytes(original + b' ')
                with self.assertRaisesRegex(ValueError, 'task inputs changed'):
                    runner.attempt_path(root, task, pair, language)
                private.write_bytes(original)
                # Copy the known unrelated onboarding repairs, never an app solution.
                solution = runner.REPO / 'experiments/application_comparison/practice' / language / 'solution'
                shutil.copytree(solution, attempt / 'practice', dirs_exist_ok=True)
                checked = runner.agent(root, token, 'check', {})
                self.assertTrue(checked['passed'], checked)
                ready = runner.agent(root, token, 'finish', {'reason': 'completed'})
                self.assertEqual(ready['phase'], 'ready')
                self.assertNotIn('task_started', session.load(attempt))
                runner.bind_context(root, task, pair, language, '/root/fixture-only', 'a' * 64)
                with self.assertRaisesRegex(ValueError, 'already bound'):
                    runner.bind_context(root, task, pair, language, '/root/fixture-only', 'a' * 64)
                main = attempt / 'practice' / ('main.my' if language == 'my' else 'main.py')
                original = main.read_bytes()
                main.write_bytes(original + b'\n')
                with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                    runner.begin(root, task, pair, language)
                main.write_bytes(original)
                runner.begin(root, task, pair, language)
                self.assertEqual(session.load(attempt)['phase'], 'working')
                # A sealed failure remains a retained terminal attempt.
                runner.agent(root, token, 'finish', {'reason': 'abandoned'})
                result = runner.grade(root, task, pair, language)
                self.assertFalse(result['passed'])
                raw = read_json(attempt / 'private-grading/result.json')
                summary = read_json(attempt / 'grading-summary.json')
                self.assertEqual(runner.digest(raw), summary['result_sha256'])
                self.assertEqual(raw['reason'], 'no-submission')
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    runner.grade(root, task, pair, language)
                # Exercise real raw public/private receipts for a checked failure.
                item = frozen['dispatch_order'][1]
                task, pair, language = (item[k] for k in ('task', 'pair', 'language'))
                runner.prepare(root, task, pair, language)
                attempt = root / task / pair / language
                runner.participant(root, task, pair, language, 'finish', {'reason': 'abandoned'})
                runner.bind_context(root, task, pair, language, '/root/fixture-only-second', 'b' * 64)
                runner.begin(root, task, pair, language)
                checked = runner.participant(root, task, pair, language, 'check', {})
                self.assertFalse(checked['passed'])
                runner.participant(root, task, pair, language, 'finish', {'reason': 'completed'})
                self.assertFalse(runner.grade(root, task, pair, language)['passed'])
                reg = runner.registered(root)
                task_row = next(row for row in reg['tasks'] if row['task_id'] == task)
                evidence = report.Evidence()
                projected, detail = report.project_attempt(root, reg, task_row, pair, language, evidence)
                self.assertEqual(projected['status'], 'failed')
                self.assertFalse(projected['verification_pass'])
                self.assertEqual(projected['review'], 'pending')
                evidence.check()


if __name__ == '__main__':
    unittest.main()
