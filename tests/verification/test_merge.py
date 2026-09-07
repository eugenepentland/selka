import json
import os
from unittest.mock import patch
import subprocess
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from verification.merge import candidate, digest, git, validate, verify_candidate


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)/'repo'
        self.root.mkdir()
        git(self.root, 'init', '-b', 'main')
        git(self.root, 'config', 'user.name', 'Test')
        git(self.root, 'config', 'user.email', 'test@localhost')
        (self.root/'left').write_text('1')
        (self.root/'right').write_text('1')
        (self.root/'verify.json').write_text(json.dumps({'version': 2, 'policy': 'merge-test', 'steps': [
            {'id': 'behavior', 'kind': 'test', 'complete': True, 'inputs': ['left', 'right'],
             'commands': [[sys.executable, '-c', "from pathlib import Path; assert int(Path('left').read_text())+int(Path('right').read_text()) <= 3"]]}]}))
        self.commit('base')
        self.base = git(self.root, 'rev-parse', 'HEAD')

    def commit(self, message):
        git(self.root, 'add', '.')
        git(self.root, 'commit', '-m', message)
        return git(self.root, 'rev-parse', 'HEAD')

    def branch(self, name, file):
        git(self.root, 'checkout', '-b', name, self.base)
        (self.root/file).write_text('2')
        result = self.commit(name)
        git(self.root, 'checkout', 'main')
        return result

    def verify(self, changes, verifier=None):
        return verify_candidate(self.root, 'main', changes, 'verify.json',
                                cache_dir=Path(self.temporary.name)/'cache', verifier=verifier)

    def test_combination_detects_behavior_conflict(self):
        left = self.branch('left-change', 'left')
        right = self.branch('right-change', 'right')
        self.assertTrue(validate(self.root, self.verify([left])))
        self.assertTrue(validate(self.root, self.verify([right])))
        with self.assertRaisesRegex(ValueError, 'verification failed'):
            self.verify([left, right])
        self.assertEqual(git(self.root, 'rev-parse', 'main'), self.base)

    def test_base_tree_and_tamper(self):
        certificate = self.verify([])
        with self.assertRaisesRegex(ValueError, 'tree changed'):
            validate(self.root, certificate, expected_tree='incorrect')
        altered = dict(certificate, tree='incorrect')
        with self.assertRaisesRegex(ValueError, 'invalid merge'):
            validate(self.root, altered)
        (self.root/'new').write_text('new base')
        self.commit('advance')
        with self.assertRaisesRegex(ValueError, 'base moved'):
            validate(self.root, certificate)

    def test_external_tool_environment_and_missing_evidence(self):
        tool = Path(self.temporary.name)/'external-tool'
        tool.write_text('tool-v1')
        manifest = self.root/'verify.json'
        data = json.loads(manifest.read_text())
        data['steps'][0].update(tools=[str(tool)], env=['MYLANG_MERGE_TEST'])
        manifest.write_text(json.dumps(data))
        self.commit('declare external identities')
        with patch.dict(os.environ, {'MYLANG_MERGE_TEST': 'one'}):
            certificate = self.verify([])
            with patch.dict(os.environ, {'MYLANG_MERGE_TEST': 'two'}):
                with self.assertRaisesRegex(ValueError, 'inputs, tools, environment'):
                    validate(self.root, certificate)
            tool.write_text('tool-v2')
            with self.assertRaisesRegex(ValueError, 'inputs, tools, environment'):
                validate(self.root, certificate)
            tool.write_text('tool-v1')
            certificate['report']['steps'] = []
            certificate.pop('digest')
            certificate['digest'] = digest(certificate)
            with self.assertRaisesRegex(ValueError, 'missing required'):
                validate(self.root, certificate)

    def test_participating_branch_move_invalidates_certificate(self):
        self.branch('feature', 'left')
        certificate = self.verify(['feature'])
        git(self.root, 'checkout', 'feature')
        (self.root/'left').write_text('3')
        self.commit('feature moved')
        git(self.root, 'checkout', 'main')
        with self.assertRaisesRegex(ValueError, 'participating change moved'):
            validate(self.root, certificate)

    def test_merge_cli_scheduler_and_nonexecuting_validation(self):
        scripts = Path(__file__).resolve().parents[2]/'scripts'
        base = Path(self.temporary.name)
        database = base/'scheduler.db'
        output = base/'certificate.json'
        options = ['--scheduler', str(database), '--scheduler-cpus', '1',
                   '--scheduler-memory', '128', '--scheduler-workers', '1',
                   '--job-memory', '64', '--priority', 'interactive', '--exclusive']
        result = subprocess.run([sys.executable, '-m', 'verification.merge', '--repo', str(self.root),
                                 '--base', 'main', '--manifest', 'verify.json', '--cache-dir', str(base/'cache'),
                                 '--output', str(output), *options], cwd=scripts, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(output.exists())
        with sqlite3.connect(database) as db:
            self.assertEqual(db.execute('SELECT cpus,memory,workers FROM config').fetchone(), (1, 128, 1))
        unused = base/'never-created.db'
        result = subprocess.run([sys.executable, '-m', 'verification.merge', '--repo', str(self.root),
                                 '--validate', str(output), '--scheduler', str(unused)],
                                cwd=scripts, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(unused.exists())
        result = subprocess.run([sys.executable, str(scripts/'verify.py'), str(self.root/'verify.json'),
                                 '--cache-dir', str(base/'cache'), *options],
                                cwd=scripts, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['full_manifest_passed'])

    def test_source_mutation_blocks_certificate(self):
        def mutate(manifest, **kwargs):
            (manifest.parent/'left').write_text('4')
            return {'full_manifest_passed': True}
        with self.assertRaisesRegex(ValueError, 'mutated'):
            self.verify([], mutate)


if __name__ == '__main__':
    unittest.main()
