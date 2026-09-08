"""Fixture cohorts exercise real freezing and isolated onboarding; no agent scores."""
from pathlib import Path
import random
import shutil
import tempfile
import unittest
from unittest.mock import patch

from experiments.application_comparison import iteration_log, session
from experiments.application_comparison.storage import path_identity, read_json
from experiments.development_velocity import runner, report

DEFAULT = runner.DEFAULT_ARMS


def readiness_fixture(temporary):
    proof = Path(temporary) / 'proof.txt'
    proof.write_text('Test fixture readiness; never a scored launch authorization.\n')
    path = Path(temporary) / 'readiness.json'
    runner.write_json(path, {'runtime_verified': True, 'library_verified': True,
                             'starters_verified': True, 'cases_reviewed': True,
                             'tasks': list(runner.catalog.IDS), 'proofs': [path_identity(proof)]})
    return path


class RegisteredArms(unittest.TestCase):
    def test_store_arm_freeze_fails_closed_without_the_store_scripts(self):
        arms = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
                {'label': 'my-store', 'language': 'my', 'interface': 'store'}]
        with tempfile.TemporaryDirectory(prefix='development-arms-') as temporary:
            study = Path(temporary) / 'study'
            study.mkdir()
            with patch.object(runner, 'STORE_TOOLS', {'store_server': 'scripts/absent_store_server.py'}):
                with self.assertRaisesRegex(ValueError, 'store interface requires scripts/absent_store_server.py'):
                    runner.freeze(study, 'fixture', readiness_fixture(temporary), arms=arms)
            self.assertFalse((study / 'fixture').exists())

    @unittest.skipUnless((runner.REPO / 'zig-out/bin/mylang').is_file(), 'requires zig build outputs')
    def test_store_arm_freezes_and_prepares_per_attempt_stores(self):
        arms = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
                {'label': 'my-store', 'language': 'my', 'interface': 'store'}]
        with tempfile.TemporaryDirectory(prefix='development-store-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            with patch.object(runner, 'source_identity', return_value={'fixture': 'stable'}):
                frozen = runner.freeze(study, 'fixture', readiness_fixture(temporary), arms=arms)
                root = Path(frozen['cohort'])
                config = runner.registered(root)['configuration']
                self.assertEqual(sorted(config['store_tools']), ['my-store'])
                self.assertEqual(sorted(config['store_tools']['my-store']), ['store_importer', 'store_server'])
                for name in runner.STORE_TOOLS:
                    identity = config['store_tools']['my-store'][name]
                    self.assertEqual(runner.path_identity(identity['path']), identity)
                entry = next(row for row in frozen['dispatch_order'] if row['arm'] == 'my-store')
                task, pair = entry['task'], entry['pair']
                # Both arms receive identical canonical source; only WORKFLOW.md differs.
                files, store = (root / task / (label + '-baseline') for label in ('my-files', 'my-store'))
                self.assertEqual(sorted(runner.source_files(files)), sorted(runner.source_files(store)))
                differing = [name for name, data in runner.source_files(files).items()
                             if runner.source_files(store)[name] != data]
                self.assertEqual(differing, ['.trial-public/WORKFLOW.md'])
                self.assertIn(b'declaration-store session', (store / '.trial-public/WORKFLOW.md').read_bytes())
                guide = root / 'my-store-frozen-practice/starter/GUIDE.md'
                self.assertIn(b'Repairs are made through `batch`', guide.read_bytes())
                self.assertNotIn(b'batch', (root / 'my-files-frozen-practice/starter/GUIDE.md').read_bytes())

                runner.prepare(root, task, pair, 'my-store')
                attempt = root / task / pair / 'my-store'
                self.assertEqual(session.load(attempt)['arm'], 'declaration-store')
                self.assertFalse((attempt / 'work').exists())
                module = runner.store_module(config['tools']['my-store'])
                for name in ('store.sqlite', 'practice-store.sqlite'):
                    with module.Store(attempt / name) as database:
                        self.assertEqual(database.branches(), ['base', 'work'])
                        self.assertTrue(database.verify_chain())
                with module.Store(attempt / 'store.sqlite') as database:
                    with module.Compiler(config['tools']['my-store']['compiler']) as compiler:
                        database.render_branch('work', attempt / 'rendered', compiler=compiler)
                rendered = {name: data for name, data in runner.source_files(attempt / 'rendered').items()}
                self.assertEqual(rendered, runner.source_files(store))

    def test_invalid_arm_definitions_reject(self):
        for arms in ([DEFAULT['candidate']], {'candidate': DEFAULT['candidate']},
                     [DEFAULT['candidate'], DEFAULT['candidate']],
                     [DEFAULT['comparator'], dict(DEFAULT['candidate'], interface='shell')],
                     [DEFAULT['comparator'], dict(DEFAULT['candidate'], language='zig')],
                     [DEFAULT['comparator'], dict(DEFAULT['candidate'], label='../escape')],
                     [DEFAULT['comparator'], {'label': 'my', 'language': 'my'}]):
            with self.subTest(arms=arms), self.assertRaises(ValueError):
                runner.arm_definitions(arms)
        self.assertEqual(runner.arm_definitions(None), DEFAULT)
        self.assertEqual(runner.arm_definitions([DEFAULT['comparator'], DEFAULT['candidate']]), DEFAULT)

    def test_default_arms_keep_the_legacy_dispatch_randomization(self):
        legacy, armed = random.Random(20260908 + 1), random.Random(20260908 + 1)
        ordered = [DEFAULT[role] for role in runner.ROLES]
        expected, actual = [], []
        for item in runner.catalog.catalog()['tasks']:
            languages = ['my', 'python']
            legacy.shuffle(languages)
            expected.append([{'task': item['id'], 'pair': 'pair-01', 'language': name} for name in languages])
            order = list(ordered)
            armed.shuffle(order)
            actual.append([{'task': item['id'], 'pair': 'pair-01', 'arm': arm['label'],
                            'language': arm['language'], 'interface': arm['interface']} for arm in order])
        legacy.shuffle(expected)
        armed.shuffle(actual)
        self.assertEqual([[{k: v for k, v in row.items() if k in ('task', 'pair', 'language')}
                           for row in pair] for pair in actual], expected)

    def test_two_my_arms_key_inputs_and_attempt_paths_by_label(self):
        # Both arms are files arms until the store server exists; only the labels differ.
        arms = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
                {'label': 'my-second', 'language': 'my', 'interface': 'files'}]
        with tempfile.TemporaryDirectory(prefix='development-arms-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            with patch.object(runner, 'source_identity', return_value={'fixture': 'stable'}):
                frozen = runner.freeze(study, 'fixture', readiness_fixture(temporary), arms=arms)
                root = Path(frozen['cohort'])
                reg = runner.registered(root)
                config = reg['configuration']
                self.assertEqual(config['arms'], {'comparator': arms[0], 'candidate': arms[1]})
                for name in ('tools', 'adapters', 'practice'):
                    self.assertEqual(sorted(config[name]), ['my-files', 'my-second'])
                self.assertNotIn('store_tools', config)
                self.assertEqual(reg['analysis']['version'], runner.analysis.ARM_VERSION)
                entry = frozen['dispatch_order'][0]
                self.assertEqual(set(entry), {'task', 'pair', 'arm', 'language', 'interface'})
                self.assertEqual(entry['language'], 'my')
                self.assertFalse((root / entry['task'] / 'python-baseline').exists())
                attempt, _, _ = runner.attempt_path(root, entry['task'], entry['pair'], 'my-second')
                self.assertEqual(attempt, root / entry['task'] / entry['pair'] / 'my-second')
                with self.assertRaisesRegex(ValueError, 'unregistered attempt'):
                    runner.attempt_path(root, entry['task'], entry['pair'], 'my')
                runner.prepare(root, entry['task'], entry['pair'], entry['arm'])
                prepared = root / entry['task'] / entry['pair'] / entry['arm']
                self.assertEqual(session.load(prepared)['arm'], 'main')
                self.assertEqual(read_json(prepared / 'participant-token.json')['arm'], entry['arm'])
                listed = report.inventory(root)
                self.assertEqual(listed['version'], 'development-inventory-v2')
                self.assertEqual(listed['arms'], {'comparator': arms[0], 'candidate': arms[1]})
                self.assertEqual(len(listed['attempts']), 24)
                row = next(r for r in listed['attempts'] if r['arm'] == entry['arm']
                           and r['task'] == entry['task'])
                self.assertEqual((row['language'], row['interface'], row['phase']),
                                 ('my', 'files', 'preparing'))


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
                configuration = runner.registered(root)['configuration']
                self.assertEqual(configuration['arms'], DEFAULT)
                for name in ('tools', 'adapters', 'practice'):
                    self.assertEqual(sorted(configuration[name]), ['my', 'python'])
                self.assertNotIn('store_tools', configuration)
                self.assertTrue(all(row['arm'] == row['language'] and row['interface'] == 'files'
                                    for row in frozen['dispatch_order']))
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
