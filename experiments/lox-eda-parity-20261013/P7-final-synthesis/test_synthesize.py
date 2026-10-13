import importlib.util
from pathlib import Path
import unittest
import tempfile
import subprocess
import json
import sys

spec = importlib.util.spec_from_file_location('synthesis', Path(__file__).with_name('synthesize.py'))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ManagedSummary(unittest.TestCase):
    def test_positive_zero_and_incomplete_denominators(self):
        def arm(status, allocs=None, live=None):
            return {'status': {'status': status}, 'metrics': {'allocs': allocs, 'live_bytes_at_exit': live}}
        cells = {
            'eda-positive': {'counters': {'arms': {'mylang-zero-rc': arm('ok', 4, 0), 'mylang-before': arm('ok', 8, 0)}}},
            'eda-zero': {'counters': {'arms': {'mylang-zero-rc': arm('ok', 0, 0), 'mylang-before': arm('ok', 0, 0)}}},
            'eda-censored': {'counters': {'arms': {'mylang-zero-rc': arm('timeout'), 'mylang-before': arm('ok', 8, 0)}}},
        }
        result = helper.managed({'cells': cells})['groups']['eda']
        self.assertEqual(result['case_denominator'], 3)
        self.assertEqual(result['candidate_counted'], 2)
        self.assertEqual(result['before_counted'], 3)
        self.assertEqual(result['metrics']['allocs']['positive_matched_pairs'], 1)
        self.assertEqual(result['metrics']['allocs']['geometric_mean_ratio'], 0.5)
        self.assertEqual(result['metrics']['allocs']['unmatched'], ['eda-censored'])
        self.assertEqual(len(result['metrics']['allocs']['zero_pairs']), 1)
        self.assertIsNone(result['metrics']['live_bytes_at_exit']['geometric_mean_ratio'])
        self.assertEqual(len(result['metrics']['live_bytes_at_exit']['zero_pairs']), 2)

    def test_failed_metrics_are_not_treated_as_observations(self):
        r = {'cells': {'vm-failed': {'counters': {'arms': {'mylang-zero-rc': {'status': 'failed', 'metrics': {'allocs': 99}}}}}}}
        result = helper.managed(r)
        self.assertIsNone(result['cases']['vm-failed']['mylang-zero-rc']['metrics']['allocs'])
        self.assertEqual(result['groups']['vm']['candidate_counted'], 0)


class Publication(unittest.TestCase):
    def test_synthetic_sixty_case_publication_keeps_censors(self):
        worker = Path(__file__).resolve().parents[3]
        private = worker / '.tmp/lox-eda-parity/P7-final-synthesis'
        private.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=private) as tmp:
            tmp = Path(tmp)
            root = tmp / 'synthetic-root'
            exp = root / 'experiments/lox-eda-parity-20261013'
            attempt = exp / 'attempts/runtime-003'
            attempt.mkdir(parents=True)
            (exp / 'summarize.py').write_bytes(Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/lox-eda-parity-20261013/summarize.py').read_bytes())
            cells = {}
            for group, count in [('tree', 13), ('vm', 13), ('eda', 34)]:
                for i in range(count):
                    arms = {n: {'status': 'ok', 'wall_seconds': 1, 'rss_kib': 2} for n in ['mylang-zero-rc', 'mylang-before', 'zig-fast']}
                    if i == 0:
                        arms['mylang-zero-rc'] = {'status': 'relative_timeout', 'wall_seconds': None, 'rss_kib': None}
                    cells[f'{group}-{i}'] = {'arms': arms, 'parity_pass': i != 0}
            (attempt / 'parity-report.json').write_text(json.dumps({'scope': 60, 'cells': cells, 'all_cases_pass': False}))
            for name in ['configuration.json', 'pins.json']:
                (attempt / name).write_text('{}\n')
            output = tmp / 'result'
            command = [sys.executable, str(Path(__file__).with_name('synthesize.py')), '--root', str(root), '--output', str(output)]
            run = subprocess.run(command, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads((output / 'synthesis.json').read_text())
            self.assertEqual(result['runtime_and_rss']['groups']['all']['denominator'], 60)
            self.assertEqual(len(result['runtime_and_rss']['groups']['all']['candidate_incomplete']), 3)
            self.assertEqual(result['runtime_and_rss']['groups']['all']['wall_seconds_over_zig']['pairs'], 57)
            self.assertTrue((output / 'COMPLETE').exists())
            self.assertFalse((exp / '__pycache__').exists())
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            root_write = command[:-2] + ['--output', str(root / 'forbidden-result')]
            self.assertNotEqual(subprocess.run(root_write, capture_output=True).returncode, 0)
            self.assertFalse((root / 'forbidden-result').exists())


if __name__ == '__main__':
    unittest.main()
