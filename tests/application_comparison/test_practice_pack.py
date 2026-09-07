from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import practice_pack
from experiments.application_comparison.storage import read_json, source_files


class PracticePackTests(unittest.TestCase):
    def test_three_starters_have_identical_cases_and_exclude_solutions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checks = []
            for language in ('my', 'python', 'zig'):
                directory = root / language
                manifest = practice_pack.create(directory, language=language)
                self.assertEqual(practice_pack.load(directory), manifest)
                self.assertFalse(manifest['scored_launch_enabled'])
                self.assertIn('GUIDE.md', manifest['starter']['files'])
                self.assertFalse(any('solution' in name or 'test_' in name for name in source_files(directory / 'starter')))
                checks.append(read_json(directory / 'cases.json'))
                (directory / 'cases.json').write_text('[]')
                with self.assertRaisesRegex(ValueError, 'public files changed'):
                    practice_pack.load(directory)
            self.assertEqual(checks[0], checks[1])
            self.assertEqual(checks[1], checks[2])
            self.assertEqual(len(checks[0]), 21)


if __name__ == '__main__':
    unittest.main()
