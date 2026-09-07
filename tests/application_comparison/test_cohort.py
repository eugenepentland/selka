from collections import Counter, defaultdict
import copy
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import cohort
from experiments.application_comparison.storage import digest, read_json, write_json


def blocks():
    return [dict(id=f'{app}-{index}', application=app, tier='small', family=family)
            for app in ('planner', 'eda') for index, family in enumerate(('local-boundary', 'shared-contract', 'feature'))]


class CohortTests(unittest.TestCase):
    def test_pilot_has_36_matched_sessions_and_balanced_positions(self):
        rows = cohort.schedule(blocks(), seed='public-fixture-v1')
        self.assertEqual(len(rows), 36)
        self.assertEqual(rows, cohort.schedule(list(reversed(blocks())), seed='public-fixture-v1'))
        self.assertNotEqual(rows, cohort.schedule(blocks(), seed='public-fixture-v2'))
        self.assertEqual(len({row['session_id'] for row in rows}), 36)
        pairs = defaultdict(list)
        for row in rows:
            pairs[row['pair_id']].append(row)
        for trio in pairs.values():
            self.assertEqual({row['language'] for row in trio}, set(cohort.LANGUAGES))
            self.assertEqual(len({(row['block'], row['repetition']) for row in trio}), 1)
        positions = Counter((row['language'], row['position_in_trio']) for row in rows)
        self.assertEqual(set(positions.values()), {4})
        self.assertTrue(all(row['status'] == 'not-launched' for row in rows))

    def test_main_design_has_144_sessions(self):
        tasks = [dict(id=f'{app}-{tier}-{family}', application=app, tier=tier, family=family)
                 for app in ('planner', 'eda') for tier in ('small', 'medium', 'large') for family in cohort.FAMILIES]
        self.assertEqual(len(cohort.schedule(tasks, seed='main-fixture')), 144)

    def test_snapshots_survive_origin_edits_but_reject_frozen_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            (source / 'main.txt').write_text('original')
            tasks = blocks()
            baseline_paths = {f'{app}/small/{language}': source for app in ('planner', 'eda') for language in cohort.LANGUAGES}
            task_paths = {task['id']: source for task in tasks}
            destination = root / 'cohort'
            manifest = cohort.freeze(destination, blocks=tasks, seed='fixture', model_settings={'model': 'fixture'},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20,
                             max_output_tokens=4096, max_turns=100), baseline_paths=baseline_paths, task_paths=task_paths)
            self.assertFalse(manifest['launch_authorized'])
            (source / 'main.txt').write_text('origin changed')
            self.assertEqual(cohort.load(destination), manifest)
            with self.assertRaises(FileExistsError):
                cohort.freeze(destination, blocks=tasks, seed='fixture', model_settings={'model': 'fixture'},
                    budgets=manifest['budgets'], baseline_paths=baseline_paths, task_paths=task_paths)
            (destination / 'tasks/planner-0/main.txt').write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                cohort.load(destination)
            (destination / 'tasks/planner-0/main.txt').write_text('original')
            changed = read_json(destination / 'cohort.json')
            changed['budgets']['task_seconds'] += 1
            write_json(destination / 'cohort.json', changed)
            with self.assertRaisesRegex(ValueError, 'definition changed'):
                cohort.load(destination)

    def test_invalid_identity_inventory_and_duplicates_reject(self):
        with self.assertRaises(ValueError):
            cohort.schedule([dict(id='../escape', application='eda', tier='small', family='feature')], seed='fixture')
        with self.assertRaises(ValueError):
            cohort.schedule(blocks() + blocks(), seed='fixture')

    def test_incomplete_or_invalid_rehashed_manifest_rejects(self):
        # A checksum detects accidental edits; it is not schema validation or authentication.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            (source / 'main.txt').write_text('baseline')
            destination = root / 'cohort'
            manifest = cohort.freeze(destination, blocks=blocks(), seed='fixture',
                model_settings={'model': 'fixture'},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20,
                             max_output_tokens=4096, max_turns=100),
                baseline_paths={key: source for key in cohort.inventory(cohort.schedule(blocks(), seed='fixture'))['baselines']},
                task_paths={block['id']: source for block in blocks()})
            mutations = [
                lambda item: item['receipts'].pop('tasks'),
                lambda item: item['receipts']['baselines'].pop('planner/small/my'),
                lambda item: item['receipts']['tasks'].pop('planner-0'),
                lambda item: item['receipts']['tasks'].update({'extra': {}}),
                lambda item: item.update(receipts=[]),
                lambda item: item.update(record_kind='scored'),
                lambda item: item.update(comparative_claim=True),
                lambda item: item.update(launch_authorized=True),
                lambda item: item['model_settings'].update(model=123),
                lambda item: item['budgets'].update(task_seconds=True),
                lambda item: item['budgets'].pop('max_turns'),
            ]
            for index, mutate in enumerate(mutations):
                with self.subTest(mutation=index):
                    changed = copy.deepcopy(manifest)
                    mutate(changed)
                    changed.pop('sha256')
                    changed['sha256'] = digest(changed)
                    write_json(destination / 'cohort.json', changed)
                    with self.assertRaises(ValueError):
                        cohort.load(destination)

    def test_malformed_blocks_reject_with_validation_error(self):
        for malformed in (None, {}, [None], [dict(id=[], application='eda', tier='small', family='feature')]):
            with self.subTest(blocks=malformed), self.assertRaises(ValueError):
                cohort.schedule(malformed, seed='fixture')


if __name__ == '__main__':
    unittest.main()
