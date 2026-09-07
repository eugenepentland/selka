from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from experiments.application_comparison import environment_receipt, verified_grading
from experiments.application_comparison.execution import freeze_adapter


class VerifiedGradingTests(unittest.TestCase):
    def test_missing_runtime_coverage_prevents_hidden_grading(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'attempt'
            with patch.object(verified_grading.pack_grading, 'grade_fixture') as grade:
                with self.assertRaisesRegex(ValueError, 'all runtime system mounts'):
                    verified_grading.grade_fixture(None, [], {}, root, environment=environment_receipt.capture([]))
                grade.assert_not_called()
            self.assertTrue((root / 'interrupted.json').exists())
            self.assertFalse((root / 'result.json').exists())

    def test_tool_drift_preserves_intermediate_work_but_rejects_final_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / 'tool'
            executable.write_text('first')
            adapter = freeze_adapter('python', {'tool': executable}, [{'phase':'run', 'argv':['/tools/tool']}])
            adapters = {'python': adapter}
            receipt = verified_grading.capture(adapters)
            def changed(pack, roots, supplied, output):
                output.mkdir()
                (output / 'intermediate').write_text('retained')
                executable.write_text('other')
                return {'fixture': True}
            with patch.object(verified_grading.pack_grading, 'grade_fixture', side_effect=changed):
                with self.assertRaisesRegex(ValueError, 'environment changed'):
                    verified_grading.grade_fixture(None, [], adapters, root / 'attempt', environment=receipt)
            self.assertTrue((root / 'attempt/pack/intermediate').exists())
            self.assertTrue((root / 'attempt/interrupted.json').exists())
            self.assertFalse((root / 'attempt/result.json').exists())
            with self.assertRaises(FileExistsError):
                verified_grading.grade_fixture(None, [], adapters, root / 'attempt', environment=receipt)


if __name__ == '__main__':
    unittest.main()
