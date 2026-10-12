import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('report', here / 'report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)
run = here.parent / 'runs/baseline-001'
receipt = run / 'results/csv_aggregate.small.json'
data = json.loads(receipt.read_text())
benchmark = json.loads((run / 'specs/csv_aggregate.small.json').read_text())


class ReportContract(unittest.TestCase):
    def test_complete_fresh_receipt(self):
        result = report.analyze(receipt, benchmark, 100, True)
        self.assertEqual(len(result['comparisons']), 4)
        self.assertEqual(result['arms']['checked-baseline']['managed']['rc_events'], 0)

    def test_invalid_receipts_rejected(self):
        variants = []
        bad = copy.deepcopy(data)
        bad['samples'][0]['stdout'] = '0 1\n'
        variants.append(bad)
        bad = copy.deepcopy(data)
        bad['samples'][0]['round'] = 99
        variants.append(bad)
        bad = copy.deepcopy(data)
        bad['samples'][0], bad['samples'][1] = bad['samples'][1], bad['samples'][0]
        variants.append(bad)
        bad = copy.deepcopy(data)
        bad['identities_after'] = {}
        variants.append(bad)
        bad = copy.deepcopy(data)
        bad['summary']['checked-baseline']['kernel_ns_per_iteration']['median'] = 1
        variants.append(bad)
        bad = copy.deepcopy(data)
        bad['counted']['checked-baseline']['counter_sha256'] = '0' * 64
        variants.append(bad)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.json'
            for invalid in variants:
                path.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError):
                    report.analyze(path, benchmark, 10, False)


if __name__ == '__main__':
    unittest.main()
