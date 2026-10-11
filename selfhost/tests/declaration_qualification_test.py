"""Adversarial declaration qualification boundary checks."""
import importlib.util
import json
from pathlib import Path
import sys
import struct
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parent))
import run_declaration_qualification as D
sys.path.insert(0, str(Path(__file__).parents[1]))
import test_declarations as G

class DeclarationQualificationTests(unittest.TestCase):
    def test_declaration_package_is_not_optional_or_boolean_versioned(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'producer'
            binary.write_bytes(b'fixture artifact')
            for name, protocol, schema in [('test-index', 1, 1), ('cache-plan', 2, 2),
                                           ('lexer-pilot', 1, 2), ('parser-pilot', 1, 2)]:
                (root / f'{name}.json').write_text(json.dumps({'format': 1, 'protocol': protocol,
                    'schema': schema, 'component': name, 'artifact': 'producer', 'sha256': D.F.digest(binary)}))
            with self.assertRaises(FileNotFoundError):
                D.packages(root)
            (root / 'declaration-index.json').write_text(json.dumps({'format': True, 'protocol': 1,
                'schema': 1, 'component': 'declaration-index', 'artifact': 'producer', 'sha256': D.F.digest(binary)}))
            with self.assertRaisesRegex(RuntimeError, 'noninteger'):
                D.packages(root)
            for name in ('declaration-index', 'type-interface', 'body-check'):
                (root / f'{name}.json').write_text(json.dumps({'format': 1, 'protocol': 1,
                    'schema': 11 if name == 'body-check' else 1, 'component': name, 'artifact': 'producer', 'sha256': D.F.digest(binary)}))
            self.assertEqual(len(D.packages(root)), 7)
            old = json.loads((root / 'body-check.json').read_text())
            old['schema'] = 6
            (root / 'body-check.json').write_text(json.dumps(old))
            with self.assertRaisesRegex(RuntimeError, 'body-check: invalid qualified identity'):
                D.packages(root)

    def test_gate_requires_complete_exact_counts(self):
        good = ('declaration qualification: 30 workflows, 60 comparisons, 30 warm deployment checks, 4 live session checks; 0 failed, 0 skipped\n'
                'declaration transport: 1 valid, 19 malformed; 0 failed, 0 skipped\n'
                'declaration forged replies: 8 rejected; 0 failed, 0 skipped\n')
        G.require_summary(good)
        for bad in (good.replace('60 comparisons', '58 comparisons'),
                    good.replace('19 malformed', '0 malformed'), good + good,
                    good.replace('0 skipped', '1 skipped')):
            with self.assertRaises(RuntimeError):
                G.require_summary(bad)

    def test_request_frame_binds_complete_payload(self):
        payload = b'module facts\x00Unicode ' + 'é'.encode()
        frame = D.frame(payload)
        self.assertEqual(frame[:8], b'SLKDIX01')
        self.assertEqual(struct.unpack('<IIII', frame[8:24]), (1, 1, 0, len(payload)))
        self.assertEqual(frame[32:64], D.F.hashlib.sha256(payload).digest())
        self.assertEqual(frame[64:], payload)

    def test_caller_modes_and_oracle_controls_removed(self):
        with patch.dict(D.os.environ, {'MYLANG_DECLARATION_MODE':'reference', 'PILOT_REPLY':'bad'}):
            env = D.environment('component', Path('/components'), Path('/empty'))
        self.assertEqual(env['MYLANG_DECLARATION_MODE'], 'component')
        self.assertEqual(env['MYLANG_PARSER_MODE'], 'reference')
        self.assertNotIn('PILOT_REPLY', env)

    def test_boundary_restores_helpers_after_failure(self):
        original = D.F.FRONTENDS, D.F.environment, D.F.packages
        with self.assertRaises(ValueError), D.declaration_boundary():
            self.assertEqual(D.F.FRONTENDS, ('declaration-index',))
            raise ValueError('abort')
        self.assertEqual((D.F.FRONTENDS, D.F.environment, D.F.packages), original)

    def test_six_packages_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(FileNotFoundError):
                D.packages(Path(temporary))

    def test_fixture_selection_nonempty_and_unique(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        self.assertGreaterEqual(len(manifest), 15)
        for name, spec in manifest.items():
            self.assertTrue((D.FIXTURES/Path(name).with_suffix('.input')).is_file())
            self.assertIn(spec['status'],(0,1))

if __name__ == '__main__': unittest.main()
