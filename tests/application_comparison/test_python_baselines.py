"""Independent conformance checks; these are baseline construction, not trials."""
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.execution import correct, evaluate, freeze_adapter
from experiments.application_comparison import planner_oracle, eda_oracle
from experiments.application_comparison.storage import snapshot

BASELINES = Path(__file__).resolve().parents[2] / 'experiments/application_comparison/baselines'


class PythonBaselineTests(unittest.TestCase):
    def test_planner_contract_in_isolation(self):
        self.check_baseline('planner', 'planner.py', planner_oracle)

    def test_eda_contract_in_isolation(self):
        self.check_baseline('eda', 'inspector.py', eda_oracle)

    def check_baseline(self, application, entry, oracle):
        adapter = freeze_adapter('python', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', entry]}])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = snapshot(BASELINES / application / 'python', root / 'source')
            request = oracle.generated_cases('public-baseline-conformance-v1', 64)
            record = evaluate(root / 'source', receipt, adapter, request, root / 'valid')
            self.assertTrue(correct(record['outcome'], oracle.response(request)))
            malformed = [b'{"cases":[],"cases":[]}', b'\xff', b'{"cases":[NaN]}',
                         b'{"cases":[9223372036854775808]}', b'{"cases":[1e999]}',
                         b'{', b' ' * (1024 * 1024 + 1),
                         b'{"cases":["\\ud800"]}', b'{"\\udc00":0}', b'{"cases":["\\ud83d\\ude00"]}',
                         b'{"cases":[' + b'[' * 62 + b'0' + b']' * 62 + b']}',
                         b'{"cases":[' + b'[' * 63 + b'0' + b']' * 63 + b']}']
            for index, raw in enumerate(malformed):
                with self.subTest(index=index):
                    record = evaluate(root / 'source', receipt, adapter, None,
                                      root / f'raw-{index}', request_bytes=raw)
                    self.assertTrue(correct(record['outcome'], oracle.response_bytes(raw)), record['outcome'])
                    self.assertTrue(record['steps'][0]['isolated'])


if __name__ == '__main__':
    unittest.main()
