from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import reference_validation, task_pack
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import read_json

ROOT = Path(__file__).resolve().parents[2]


class ReferenceValidationTests(unittest.TestCase):
    def test_existing_correct_repair_reference_passes_full_pack(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack = root / 'pack'
            task_pack.create(pack, task='eda-clearance-boundary', hidden_seed='public-reference-fixture-never-score')
            adapter = freeze_adapter('python', {}, [
                {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'inspector.py']}])
            result = reference_validation.validate(pack,
                ROOT / 'experiments/application_comparison/baselines/eda/python', adapter, root / 'validation')
            self.assertTrue(result['passed'])
            self.assertEqual(result['case_count'], 11)
            self.assertEqual({row['category'] for row in result['results']}, {'public', 'hidden'})
            self.assertFalse(result['comparative_claim'])
            self.assertEqual(result, read_json(root / 'validation/result.json'))
            for row in result['results']:
                self.assertTrue(all(step['isolated'] for step in row['execution']['steps']))
            with self.assertRaises(FileExistsError):
                reference_validation.validate(pack,
                    ROOT / 'experiments/application_comparison/baselines/eda/python', adapter, root / 'validation')

    def test_wrong_reference_preserves_failure_and_continues_other_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack, source = root / 'pack', root / 'source'
            task_pack.create(pack, task='eda-rotation', hidden_seed='public-reference-fixture-never-score')
            source.mkdir()
            (source / 'main.py').write_text('print(\'{"error":"invalid-request"}\')\n')
            adapter = freeze_adapter('python', {}, [
                {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            result = reference_validation.validate(pack, source, adapter, root / 'validation')
            self.assertFalse(result['passed'])
            self.assertEqual(result['case_count'], 9)
            self.assertTrue(any(row['passed'] for row in result['results']))
            self.assertTrue(any(not row['passed'] for row in result['results']))


if __name__ == '__main__':
    unittest.main()
