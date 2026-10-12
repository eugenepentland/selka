import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location('trial', HERE / 'prepare_trial.py')
trial = importlib.util.module_from_spec(loader)
loader.loader.exec_module(trial)
COMMON = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/text-gaps-20261012/coordinator/common-001/build-receipt.json')


class CommonTrialContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest, cls.entries, cls.files = trial.common_inputs(COMMON)
        cls.spec = json.loads((HERE.parent / 'runs/common-final-001/specs/json_transform.small.json').read_text())

    def test_common_is_distinct_from_original_baseline(self):
        original = copy.deepcopy(self.spec)
        result = trial.augment(original, self.manifest, self.entries, self.files, COMMON)
        self.assertEqual(list(result['arms']), ['checked-baseline', 'checked-common', 'checked-candidate', 'zig-safe', 'zig-fast', 'rust', 'go'])
        self.assertEqual(result['arms']['checked-baseline'], self.spec['arms']['checked-baseline'])
        self.assertEqual(result['arms']['checked-common']['sha256'], self.entries['runtime']['sha256'])
        self.assertEqual(set(result['counted']), {'checked-baseline', 'checked-common', 'checked-candidate'})
        self.assertTrue(self.files.issubset(set(result['files'])))
        self.assertEqual((result['warmups'], result['rounds'], result['rss_rounds']), (3, 15, 3))

    def test_changed_benchmark_cannot_join_trial(self):
        entries = copy.deepcopy(self.entries)
        entries['runtime']['source_sha256'] = '0' * 64
        with self.assertRaises(AssertionError):
            trial.augment(copy.deepcopy(self.spec), self.manifest, entries, self.files, COMMON)


if __name__ == '__main__':
    unittest.main()
