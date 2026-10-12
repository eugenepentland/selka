import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('measure', Path(__file__).with_name('measure.py'))
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class MeasurementContract(unittest.TestCase):
    def test_rotated_reversed_order_balances_positions(self):
        for n in (5, 6, 7):
            names = list(map(str, range(n)))
            counts = {name: [0] * n for name in names}
            for rnd in range(15):
                order = measure.balanced_order(names, rnd, 'cell')
                self.assertEqual(set(order), set(names))
                self.assertEqual(order, measure.balanced_order(names, rnd, 'cell'))
                for position, name in enumerate(order):
                    counts[name][position] += 1
            for positions in counts.values():
                self.assertLessEqual(max(positions) - min(positions), 1)
            for start in (0, n):
                block = [measure.balanced_order(names, r, 'cell') for r in range(start, start + n)]
                for name in names:
                    self.assertEqual({row.index(name) for row in block}, set(range(n)))

    def test_kernel_checksum_and_positive_clock(self):
        valid = {'status': 'ok', 'stdout': '42 100\n', 'stderr': ''}
        self.assertEqual(measure.validate(valid, 42, 'kernel')['kernel_ns'], 100)
        self.assertEqual(measure.validate(valid, 43, 'kernel')['status'], 'output_mismatch')
        self.assertEqual(measure.validate({**valid, 'stdout': '42 0\n'}, 42, 'kernel')['status'], 'output_mismatch')

    def test_exit_and_stderr_cannot_qualify(self):
        bad = {'status': 'failed', 'stdout': '42\n', 'stderr': ''}
        self.assertEqual(measure.validate(bad, '42\n', 'fixed')['status'], 'failed')
        self.assertEqual(measure.validate({**bad, 'status': 'ok', 'stderr': 'warning'}, '42\n', 'fixed')['status'], 'unexpected_stderr')

    def test_timeout_is_not_a_timing_sample(self):
        result = measure.execute([sys.executable, '-c', 'import time; time.sleep(5)'], .05, measure.runtime_environment())
        self.assertEqual(result['status'], 'timeout')
        self.assertNotIn('process_wall_ns', result)

    def test_direct_destruction_is_not_rc(self):
        totals = {k: 0 for k in ('allocs', 'reallocs', 'alloc_bytes', 'realloc_added_bytes',
                                 'peak_live_bytes', 'live_bytes_at_exit', 'runtime_retains',
                                 'runtime_releases', 'shared_retains', 'shared_releases')}
        kinds = {k: {'count': 0} for k in ('retain', 'release', 'unique_test', 'release_unique')}
        kinds['release_unique']['count'] = 30
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'counter.json'
            p.write_text(json.dumps({'version': 'mylang-counters-v1', 'totals': totals, 'kinds': kinds}))
            values = measure.counters(p)
            self.assertEqual(values['rc_events'], 0)
            self.assertEqual(values['direct_destructions'], 30)

    def test_failed_arm_preserved_and_no_receipt_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            arms = {}
            for name, value in [('good', 7), ('bad', 8)]:
                p = root / name
                p.write_text('#!' + sys.executable + '\nprint(' + str(value) + ')\n')
                p.chmod(0o755)
                arms[name] = {'binary': str(p), 'sha256': measure.digest(p), 'status': 'ok'}
            path = root / 'spec.json'
            output = root / 'result.json'
            path.write_text(json.dumps({'cell': 'test', 'protocol': 'fixed', 'expected_stdout': '7\n',
                                        'arms': arms, 'warmups': 1, 'rounds': 2, 'rss_rounds': 1}))
            command = [sys.executable, str(Path(measure.__file__)), str(path), str(output), '--cpu', str(min(measure.os.sched_getaffinity(0)))]
            subprocess.run(command, check=True, capture_output=True)
            data = json.loads(output.read_text())
            self.assertEqual(set(data['summary']), {'good', 'bad'})
            self.assertTrue(data['summary']['good']['complete'])
            self.assertFalse(data['summary']['bad']['complete'])
            self.assertIsNone(data['summary']['bad']['process_wall_ns'])
            before = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
