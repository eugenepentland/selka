#!/usr/bin/env python3
"""Exercise corpus selection and failure propagation against the live formatter."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
COMPILER = None


class CorpusFormatTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'examples').mkdir()
        self.manifest({})

    def manifest(self, entries):
        (self.root / 'scripts/selka_format_exclusions.json').write_text(json.dumps(entries))

    def run_gate(self):
        return subprocess.run(['python3', str(REPO / 'scripts/check_selka_format.py'),
                               '--compiler', COMPILER, '--root', str(self.root)],
                              capture_output=True, text=True)

    def test_canonical_live_source_passes(self):
        (self.root / 'examples/main.selka').write_text('func main() -> int:\n    return 0\n')
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1 checked', result.stdout)

    def test_new_unformatted_live_source_fails_without_rewriting(self):
        source = self.root / 'examples/new.selka'
        original = 'func main()->int:\n    return 0\n'
        source.write_text(original)
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn('formatting differs', result.stderr)
        self.assertEqual(source.read_text(), original)

    def test_malformed_live_source_fails(self):
        (self.root / 'examples/broken.selka').write_text('func main(\n')
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn('broken.selka', result.stderr)

    def test_explicit_migration_exclusion_preserves_rejected_bytes(self):
        directory = self.root / 'test/fixtures/fix-migration'
        directory.mkdir(parents=True)
        source = directory / 'old.selka'
        original = 'module old\ndef main():\n\treturn 0\n'
        source.write_text(original)
        self.manifest({'test/fixtures/fix-migration/': 'Pre-migration rejection input.'})
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1 deliberate exclusions', result.stdout)
        self.assertEqual(source.read_text(), original)

    def test_exclusion_does_not_hide_adjacent_live_source(self):
        (self.root / 'examples/legacy.selka').write_text('module legacy\n')
        (self.root / 'examples/new.selka').write_text('func broken(\n')
        self.manifest({'examples/legacy.selka': 'Legacy module-header evidence.'})
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn('new.selka', result.stderr)

    def test_stale_and_unreasoned_exclusions_fail(self):
        self.manifest({'examples/missing.selka': 'Removed evidence.'})
        self.assertEqual(self.run_gate().returncode, 2)
        (self.root / 'examples/main.selka').write_text('func main() -> int:\n    return 0\n')
        self.manifest({'examples/main.selka': ''})
        self.assertEqual(self.run_gate().returncode, 2)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    COMPILER = str(Path(args.compiler).resolve())
    unittest.main(argv=['test_selka_format.py'])
