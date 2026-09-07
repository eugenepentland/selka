"""Guest-only application conformance via the installed raw byte VM host."""
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import planner_oracle, eda_oracle
from experiments.application_comparison.execution import correct, evaluate, freeze_adapter
from experiments.application_comparison.isolation import Limits
from experiments.application_comparison.storage import snapshot

ROOT = Path(__file__).resolve().parents[2]


class MyBaselineTests(unittest.TestCase):
    def test_planner_contract_in_isolation(self):
        self.check_baseline('planner', planner_oracle)

    def test_eda_contract_in_isolation(self):
        self.check_baseline('eda', eda_oracle)

    def check_baseline(self, application, oracle):
        adapter = freeze_adapter('my', {'byte_io': ROOT / 'zig-out/bin/mylang-io'}, [
            {'phase': 'run', 'argv': ['/tools/byte_io', '--project', '/work']}],
            limits=Limits(wall_seconds=60, cpu_seconds=60))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = ROOT / 'experiments/application_comparison/baselines' / application / 'my'
            receipt = snapshot(baseline, root / 'source')
            request = oracle.generated_cases('public-baseline-conformance-v1', 64)
            record = evaluate(root / 'source', receipt, adapter, request, root / 'valid')
            self.assertTrue(correct(record['outcome'], oracle.response(request)), record['outcome'])
            raw = b'{"cases":[],"cases":[]}'
            record = evaluate(root / 'source', receipt, adapter, None, root / 'raw', request_bytes=raw)
            self.assertTrue(correct(record['outcome'], oracle.response_bytes(raw)), record['outcome'])


if __name__ == '__main__':
    unittest.main()
