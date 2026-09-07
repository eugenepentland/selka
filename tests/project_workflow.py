#!/usr/bin/env python3
"""Exercise combined project feedback against real compiler and declared tests."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import project

COMPILER = None


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='project-workflow-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'app'
        self.root.mkdir()
        self.entry = self.root / 'main.my'
        self.entry.write_text('module main;fn main()->i64{return 42;}')
        self.manifest = self.root / 'verify.json'
        self.write_manifest()

    def write_manifest(self, *, kind='test', code='print(42)', expected='42\n', version=1):
        step = {'id': 'behavior', 'kind': kind, 'commands': [[sys.executable, '-B', '-c', code]], 'expect_stdout': expected}
        data = {'version': version, 'steps': [step]}
        if version == 2:
            data['policy'] = 'workflow-test-v1'
            step['inputs'] = ['main.my']
            step['tools'] = [sys.executable]
            step['complete'] = True
        self.manifest.write_text(json.dumps(data))

    def run_project(self):
        return project.run(COMPILER, self.entry, self.manifest, cache_dir=self.base / 'cache', symbol='main::main')

    def test_success_context_cache_and_behavior_failure(self):
        first = self.run_project()
        self.assertEqual('passed', first['status'])
        self.assertEqual('main::main', first['navigation']['symbols'][0]['id'])
        self.assertTrue(self.run_project()['navigation_cache_hit'])
        self.write_manifest(expected='wrong\n')
        failed = self.run_project()
        self.assertEqual('failed', failed['status'])
        self.assertIn('failures', project.compact(failed)['verification'])

    def test_compile_failure_does_not_execute_tests(self):
        self.entry.write_text('module main;fn main()->i64{return unknown;}')
        self.write_manifest(code="from pathlib import Path;Path('ran').write_text('bad');print(42)")
        report = self.run_project()
        self.assertEqual('failed', report['status'])
        self.assertFalse(report['check_passed'])
        self.assertIsNone(report['verification'])
        self.assertFalse((self.root / 'ran').exists())
        self.assertIn('diagnostics', report)

    def test_mutation_during_tests_discards_success(self):
        self.write_manifest(code="from pathlib import Path;Path('main.my').write_text('module main;fn main()->i64{return 3;}');print(42)")
        self.assertEqual('stale', self.run_project()['status'])

    def test_no_tests_is_not_success_and_reports_cannot_be_overwritten(self):
        self.write_manifest(kind='check')
        self.assertEqual('failed', self.run_project()['status'])
        destination = self.base / 'attempt.json'
        destination.write_text('retained')
        result = subprocess.run([sys.executable, str(Path(project.__file__)), '--compiler', str(COMPILER),
            '--entry', str(self.entry), '--manifest', str(self.manifest), '--report', str(destination)], capture_output=True, text=True)
        self.assertEqual(2, result.returncode)
        self.assertEqual('retained', destination.read_text())

    def test_v2_complete_receipts_reuse_and_invalidate(self):
        self.write_manifest(version=2)
        first = self.run_project()
        self.assertEqual('passed', first['status'])
        again = self.run_project()
        self.assertEqual('passed', again['status'])
        self.assertNotEqual('executed', again['verification']['steps'][0]['status'])
        self.entry.write_text('module main;fn main()->i64{return 43;}')
        changed = self.run_project()
        self.assertEqual('passed', changed['status'])
        self.assertNotEqual(first['identity'], changed['identity'])
        self.assertEqual('executed', changed['verification']['steps'][0]['status'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    args = parser.parse_args()
    COMPILER = args.compiler.resolve()
    unittest.main(argv=[sys.argv[0]])
