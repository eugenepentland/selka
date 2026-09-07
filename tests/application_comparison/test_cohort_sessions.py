from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import cohort, cohort_sessions, session, task_pack, practice_pack, scheduled_driver
from unittest.mock import patch
from experiments.application_comparison.storage import source_files

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class CohortSessionTests(unittest.TestCase):
    def test_scheduled_repair_trio_gets_variant_public_files_and_common_budgets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            task = 'planner-input-boundary'
            pack = root / 'pack'
            task_pack.create(pack, task=task, hidden_seed='private-provision-fixture-never-score')
            frozen = root / 'cohort'
            practices = {}
            for language in cohort.LANGUAGES:
                practices[language] = root / ('practice-' + language)
                practice_pack.create(practices[language], language=language)
            manifest = cohort.freeze(frozen,
                blocks=[dict(id=task, application='planner', tier='small', family='local-boundary')],
                seed='fixture-schedule', model_settings={'model': 'fixture'},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20,
                             max_output_tokens=4096, max_turns=100),
                baseline_paths={f'planner/small/{language}': ROOT / 'baselines/planner' / language
                                for language in cohort.LANGUAGES}, task_paths={task: pack}, practice_paths=practices)
            self.assertEqual(manifest['version'], 'application-cohort-v2')
            public_receipts = []
            first_trio = []
            for row in manifest['schedule']:
                if row['repetition'] != 1:
                    continue
                with self.subTest(language=row['language']):
                    envelope = root / row['session_id']
                    result = cohort_sessions.prepare_fixture(frozen, row['session_id'], envelope)
                    public_receipts.append(result['public'])
                    self.assertEqual(result['model_budgets'], {'max_output_tokens': 4096, 'max_turns': 100})
                    self.assertEqual(result['row'], row)
                    self.assertFalse(result['comparative_claim'])
                    active = envelope / 'session'
                    state = session.load(active)
                    self.assertEqual(state['pair_id'], row['pair_id'])
                    self.assertIn('.trial-practice-guide/GUIDE.md', state['protected'])
                    if row['language'] == 'python':
                        arguments = dict(tools={}, task_adapter=None, practice_adapter=None, transport_identity='fixture')
                        with self.assertRaisesRegex(ValueError, 'cannot be overridden'):
                            scheduled_driver.run_fixture(frozen, envelope, None, practice_prompt='changed', **arguments)
                        with patch.object(scheduled_driver.session_driver, 'run_fixture', return_value='captured') as driver:
                            self.assertEqual(scheduled_driver.run_fixture(frozen, envelope, None, **arguments), 'captured')
                            bound = driver.call_args.kwargs
                            self.assertEqual(bound['practice_source'], frozen / 'practice/python/starter')
                            self.assertEqual(len(bound['practice_case']), 21)
                            self.assertIn('three', bound['practice_prompt'])
                    self.assertEqual(state['budgets'], {'preparation_seconds': 1200, 'task_seconds': 1800, 'max_submissions': 20})
                    self.assertFalse((active / 'work').exists())
                    self.assertEqual(source_files(active / 'practice'), {})
                    session.start_preparation(active)
                    session.start_task(active, 'passed')
                    files = source_files(active / 'work')
                    mutation = result['mutation']['mutation']
                    self.assertIn(mutation['after'].encode(), files[mutation['path']])
                    self.assertIn('.trial-public/brief.md', files)
                    self.assertIn('.trial-public/cases.json', files)
                    self.assertEqual(files['.trial-practice-guide/GUIDE.md'],
                        (frozen / 'practice' / row['language'] / 'starter/GUIDE.md').read_bytes())
                    self.assertTrue(all(b'private-provision-fixture-never-score' not in data for data in files.values()))
                    (active / 'work/.trial-public/brief.md').write_text('changed')
                    submission = session.submit(active)
                    self.assertTrue(submission['scope_violations'])
                    session.seal(active, 'abandoned')
                    first_trio.append(active)
                    with self.assertRaises(FileExistsError):
                        cohort_sessions.prepare_fixture(frozen, row['session_id'], envelope)
                    other = root / ('duplicate-' + row['session_id'])
                    with self.assertRaises(FileExistsError):
                        cohort_sessions.prepare_fixture(frozen, row['session_id'], other)
                    self.assertFalse(other.exists())
            self.assertTrue(all(receipt == public_receipts[0] for receipt in public_receipts))
            self.assertEqual(len(session.matched_trio(first_trio)), 3)
            second = next(row for row in manifest['schedule'] if row['repetition'] == 2 and row['language'] == 'python')
            envelope = root / second['session_id']
            cohort_sessions.prepare_fixture(frozen, second['session_id'], envelope)
            active = envelope / 'session'
            session.start_preparation(active)
            session.start_task(active, 'passed')
            session.seal(active, 'abandoned')
            mixed = [active if session.load(path)['language'] == 'python' else path for path in first_trio]
            with self.assertRaisesRegex(ValueError, 'pair_id'):
                session.matched_trio(mixed)
            with self.assertRaisesRegex(ValueError, 'not in the frozen schedule'):
                cohort_sessions.prepare_fixture(frozen, '../unscheduled', root / 'invalid')
            self.assertFalse((root / 'invalid').exists())


if __name__ == '__main__':
    unittest.main()
