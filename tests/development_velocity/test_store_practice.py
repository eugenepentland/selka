"""Store onboarding drills every batch operation before the clock. No model participant."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from experiments.application_comparison import iteration_log
from experiments.application_comparison.storage import path_identity, read_json, write_json
from experiments.development_velocity import runner

ARMS = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
        {'label': 'my-store', 'language': 'my', 'interface': 'store'}]
# The three onboarding repairs, in the store's canonical text; never an application solution.
REPAIRS = (('helper::multiply(6)', 'helper::multiply(7)'),
           ('return missing_nine;', 'return nine;'),
           ('return 0;', 'return -1;'))
SCRATCH = ('// Onboarding scratch declaration; added and removed during practice.\n'
           'fn practice_scratch(value: i64) -> i64 {\n    return value;\n}\n')


def repaired(text):
    for before, after in REPAIRS:
        if text.count(before) != 1:
            raise ValueError('practice repair anchor is not unique: ' + before)
        text = text.replace(before, after)
    return text


class PractisedOperations(unittest.TestCase):
    def test_only_committed_batch_operations_count(self):
        with tempfile.TemporaryDirectory(prefix='development-practised-') as temporary:
            attempt = Path(temporary)
            records = attempt / 'practice-store/records'
            records.mkdir(parents=True)
            rows = [{'verb': 'batch', 'response': {'status': 'committed',
                                                   'applied': [{'op': 'replace'}, {'op': 'add'}]}},
                    {'verb': 'batch', 'response': {'status': 'rejected', 'applied': []}},
                    {'verb': 'open', 'response': {'status': 'committed', 'applied': [{'op': 'remove'}]}}]
            for index, row in enumerate(rows):
                write_json(records / f'{index:06}.json', row)
            self.assertEqual(runner.practiced_operations(attempt), ['add', 'replace'])

    def test_an_attempt_without_a_practice_store_practises_nothing(self):
        with tempfile.TemporaryDirectory(prefix='development-practised-') as temporary:
            self.assertEqual(runner.practiced_operations(Path(temporary)), [])


@unittest.skipUnless((runner.REPO / 'zig-out/bin/mylang').is_file(), 'requires zig build outputs')
class StorePracticeDrill(unittest.TestCase):
    def test_finish_waits_for_a_committed_add_and_remove(self):
        with tempfile.TemporaryDirectory(prefix='development-store-practice-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            proof = Path(temporary) / 'proof.txt'
            proof.write_text('Test fixture readiness; never a scored launch authorization.\n')
            readiness = Path(temporary) / 'readiness.json'
            write_json(readiness, {'runtime_verified': True, 'library_verified': True,
                                   'starters_verified': True, 'cases_reviewed': True,
                                   'tasks': list(runner.catalog.IDS),
                                   'proofs': [path_identity(proof)]})
            patched = patch.object(runner, 'source_identity', return_value={'fixture': 'stable'})
            patched.start()
            self.addCleanup(patched.stop)
            frozen = runner.freeze(study, 'store-practice-fixture', readiness, arms=ARMS)
            root = Path(frozen['cohort'])
            item = next(row for row in frozen['dispatch_order'] if row['arm'] == 'my-store')
            task, pair, arm = (item[key] for key in ('task', 'pair', 'arm'))
            token = runner.prepare(root, task, pair, arm)['token']
            attempt = root / task / pair / arm

            entry = runner.agent(root, token, 'context', {'ids': ['main::answer']})['entries'][0]
            committed = runner.agent(root, token, 'batch', {
                'ops': [{'op': 'replace', 'id': 'main::answer', 'source': repaired(entry['source'])}],
                'if_match': {'main::answer': entry['hash']}})
            self.assertEqual(committed['status'], 'committed', committed)
            self.assertTrue(runner.agent(root, token, 'check', {})['passed'])
            self.assertEqual(runner.practiced_operations(attempt), ['replace'])
            with self.assertRaisesRegex(ValueError, 'still missing: add, remove'):
                runner.agent(root, token, 'finish', {'reason': 'completed'})

            added = runner.agent(root, token, 'batch', {
                'ops': [{'op': 'add', 'module': 'helper', 'source': SCRATCH}], 'if_match': {}})
            self.assertEqual(added['status'], 'committed', added)
            scratch = added['applied'][0]
            self.assertIn(scratch['id'], {row['id'] for row in runner.agent(root, token, 'open', {})['declarations']})
            with self.assertRaisesRegex(ValueError, 'still missing: remove'):
                runner.agent(root, token, 'finish', {'reason': 'completed'})
            removed = runner.agent(root, token, 'batch', {
                'ops': [{'op': 'remove', 'id': scratch['id']}],
                'if_match': {scratch['id']: scratch['hash']}})
            self.assertEqual(removed['status'], 'committed', removed)
            self.assertNotIn(scratch['id'], {row['id'] for row in runner.agent(root, token, 'open', {})['declarations']})

            self.assertTrue(runner.agent(root, token, 'check', {})['passed'])
            ready = runner.agent(root, token, 'finish', {'reason': 'completed'})
            self.assertEqual(ready['phase'], 'ready')
            recorded = read_json(attempt / 'practice-ready.json')
            self.assertEqual(recorded['batch_operations'], ['add', 'remove', 'replace'])
            self.assertEqual(recorded['outcome'], 'passed')

    def test_a_files_arm_practice_records_no_batch_operations(self):
        with tempfile.TemporaryDirectory(prefix='development-files-practice-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            proof = Path(temporary) / 'proof.txt'
            proof.write_text('Test fixture readiness; never a scored launch authorization.\n')
            readiness = Path(temporary) / 'readiness.json'
            write_json(readiness, {'runtime_verified': True, 'library_verified': True,
                                   'starters_verified': True, 'cases_reviewed': True,
                                   'tasks': list(runner.catalog.IDS),
                                   'proofs': [path_identity(proof)]})
            patched = patch.object(runner, 'source_identity', return_value={'fixture': 'stable'})
            patched.start()
            self.addCleanup(patched.stop)
            frozen = runner.freeze(study, 'files-practice-fixture', readiness, arms=ARMS)
            root = Path(frozen['cohort'])
            item = next(row for row in frozen['dispatch_order'] if row['arm'] == 'my-files')
            task, pair, arm = (item[key] for key in ('task', 'pair', 'arm'))
            token = runner.prepare(root, task, pair, arm)['token']
            # A files arm never carries the drill: abandoning practice stays available.
            self.assertEqual(runner.agent(root, token, 'finish', {'reason': 'abandoned'})['phase'], 'ready')
            recorded = read_json(root / task / pair / arm / 'practice-ready.json')
            self.assertEqual(recorded['batch_operations'], [])


if __name__ == '__main__':
    unittest.main()
