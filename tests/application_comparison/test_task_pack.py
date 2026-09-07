import copy
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import pilot_cases, task_pack
from experiments.application_comparison import planner_oracle, eda_oracle
from experiments.application_comparison.inputs import decode_case
from experiments.application_comparison.storage import digest, read_json, source_files, write_json


class TaskPackTests(unittest.TestCase):
    def test_all_six_packs_project_only_public_material_and_reproduce(self):
        for task in pilot_cases.TASKS:
            with self.subTest(task=task), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                pack = root / 'pack'
                manifest = task_pack.create(pack, task=task, hidden_seed='fixture-private-never-score')
                self.assertFalse(manifest['scored_launch_enabled'])
                self.assertEqual(manifest, task_pack.load(pack))
                task_pack.provision_public(pack, root / 'participant')
                public_files = source_files(root / 'participant')
                self.assertEqual(set(public_files), {'brief.md', 'cases.json'})
                self.assertTrue(all(b'fixture-private-never-score' not in data for data in public_files.values()))
                repeated = task_pack.create(root / 'again', task=task, hidden_seed='fixture-private-never-score')
                self.assertEqual(manifest, repeated)
                different = task_pack.create(root / 'other', task=task, hidden_seed='fixture-other-never-score')
                self.assertEqual(manifest['public'], different['public'])
                self.assertNotEqual(manifest['hidden'], different['hidden'])
                for category in ('public', 'hidden'):
                    for item in read_json(pack / category / 'cases.json'):
                        decode_case(item['case'])
                with self.assertRaises(FileExistsError):
                    task_pack.create(pack, task=task, hidden_seed='fixture-private-never-score')

    def test_each_feature_pack_rejects_unchanged_v1_behavior(self):
        for task in ('planner-priority', 'planner-cycle-groups', 'eda-pin-roles', 'eda-rotation',
                     'planner-dependency-lags', 'planner-slack'):
            oracle = planner_oracle if task.startswith('planner-') else eda_oracle
            cases = pilot_cases.build(task, seed='fixture-noop')
            distinguishes = False
            for item in cases:
                request, raw, expected = decode_case(item['case'])
                original = oracle.response(request) if raw is None else oracle.response_bytes(raw)
                distinguishes |= original != expected
            self.assertTrue(distinguishes, task)

    def test_hidden_tampering_prevents_public_provisioning(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack = root / 'pack'
            manifest = task_pack.create(pack, task='eda-rotation', hidden_seed='fixture')
            hidden = pack / 'hidden/cases.json'
            data = hidden.read_bytes()
            hidden.write_bytes(data + b' ')
            with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                task_pack.provision_public(pack, root / 'participant')
            self.assertFalse((root / 'participant').exists())
            hidden.write_bytes(data)
            changed = copy.deepcopy(manifest)
            changed['scored_launch_enabled'] = True
            changed.pop('sha256')
            changed['sha256'] = digest(changed)
            write_json(pack / 'pack.json', changed)
            with self.assertRaisesRegex(ValueError, 'changed draft'):
                task_pack.load(pack)

    def test_reviewed_coverage_boundaries_cycles_and_large_geometry(self):
        cases = {item['name']: item['case'] for item in pilot_cases.build('planner-input-boundary', seed='coverage-fixture')}
        self.assertEqual(cases['utf8-byte-limit-0']['expected'], {'results': [{'error': 'invalid-manifest'}]})
        for name in ('utf8-byte-limit-1', 'malformed-at-limit', 'trailing-data-at-limit'):
            self.assertEqual(cases[name]['expected'], {'error': 'invalid-request'})
        cases = {item['name']: item['case'] for item in pilot_cases.build('planner-cycle-groups', seed='coverage-fixture')}
        for size, result in zip((2, 4, 7, 12), cases['private-multiple-cycle-groups']['expected']['results']):
            self.assertEqual([len(group) for group in result['cycles']], [size, size])
            self.assertEqual(len(result['blocked']), size * 2 + 1)
        cases = {item['name']: item['case'] for item in pilot_cases.build('eda-clearance-boundary', seed='coverage-fixture')}
        results = cases['large-clearance-arithmetic']['expected']['results']
        self.assertEqual([any(item['code'] == 'clearance' for item in result['findings']) for result in results],
                         [False, False, True, False, False, True])
        equivalent = cases['equivalent-unit-geometry']['expected']['results']
        self.assertEqual(equivalent[0], equivalent[1])


if __name__ == '__main__':
    unittest.main()
