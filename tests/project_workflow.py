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
        self.entry.write_text('\nfunc main() -> i64:\n    return 42\n')
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

    def run_cli(self, destination, *extra):
        return subprocess.run([sys.executable, str(Path(project.__file__)), '--compiler', str(COMPILER),
            '--entry', str(self.entry), '--manifest', str(self.manifest), '--cache-dir', str(self.base / 'cache'),
            '--report', str(destination), *extra], capture_output=True, text=True)

    def test_compact_cli_retains_full_evidence_and_opt_in_details(self):
        destination = self.base / 'attempt.json'
        result = self.run_cli(destination)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('', result.stderr)
        receipt = json.loads(result.stdout)
        full = json.loads(destination.read_text())
        self.assertEqual(str(destination.resolve()), receipt['report_path'])
        self.assertEqual('project-feedback-v1', receipt['version'])
        self.assertEqual('project-workflow-v1', full['version'])
        self.assertEqual('passed', receipt['status'])
        self.assertNotIn('navigation', receipt)
        self.assertNotIn('sources', receipt['identity'])
        self.assertEqual(64, len(receipt['identity']['sources_sha256']))
        self.assertEqual(full['identity']['compiler_sha256'], receipt['identity']['compiler_sha256'])
        self.assertEqual(1, receipt['verification']['step_counts']['passed'])
        self.assertEqual(1, receipt['declared_test_steps'])
        self.assertIsNone(receipt['verification']['test_case_count'])
        self.assertIn('navigation', full)
        self.assertIn('sources', full['identity'])
        self.assertIn('verify: behavior', full['verification_log'])
        self.assertEqual('42\n', full['verification']['steps'][0]['commands'][0]['stdout'])
        detailed = self.run_cli(self.base / 'details.json', '--details')
        self.assertEqual(0, detailed.returncode, detailed.stderr)
        self.assertIn('navigation', json.loads(detailed.stdout))

    def test_compact_output_does_not_scale_with_step_count_or_streams(self):
        report = self.run_project()
        baseline = len(json.dumps(project.compact(report)))
        original_digest = project.compact(report)['identity']['sources_sha256']
        report['identity']['sources']['additional.my'] = 'different'
        self.assertNotEqual(original_digest, project.compact(report)['identity']['sources_sha256'])
        template = report['verification']['steps'][0]
        rows = [dict(template, id='step-' + str(i)) for i in range(1000)]
        report['verification'].update(steps=rows, selected=[row['id'] for row in rows])
        report['navigation'] = {'large_context': 'x' * 1000000}
        self.assertLess(len(json.dumps(project.compact(report))), baseline + 200)
        for row in rows:
            row.update(status='failed', commands=[{'passed': False, 'stdout': 'x' * 100000,
                'stderr': 'y' * 100000, 'exit': 1}] * 10)
        summary = project.compact(report)['verification']
        self.assertEqual(1000, summary['step_counts']['failed'])
        self.assertEqual(3, len(summary['failures']))
        self.assertEqual(997, summary['failures_omitted'])
        self.assertEqual(8, summary['failures'][0]['commands_omitted'])
        self.assertLess(len(json.dumps(summary)), 12000)

    def test_compile_failure_excerpt_and_cli_status(self):
        self.entry.write_text('\nfunc main() -> i64:\n    return unknown\n')
        result = self.run_cli(self.base / 'compile-failed.json')
        self.assertEqual(1, result.returncode)
        self.assertIn('E_UNKNOWN_NAME', json.dumps(json.loads(result.stdout)['diagnostics']))

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
        self.entry.write_text('\nfunc main() -> i64:\n    return unknown\n')
        self.write_manifest(code="from pathlib import Path;Path('ran').write_text('bad');print(42)")
        report = self.run_project()
        self.assertEqual('failed', report['status'])
        self.assertFalse(report['check_passed'])
        self.assertIsNone(report['verification'])
        self.assertFalse((self.root / 'ran').exists())
        self.assertIn('diagnostics', report)

    def test_mutation_during_tests_discards_success(self):
        self.write_manifest(code="from pathlib import Path;Path('main.my').write_text('module main\\n\\nfunc main() -> i64:\\n    return 3\\n');print(42)")
        self.assertEqual('stale', self.run_project()['status'])

    def test_v1_test_and_fixture_changes_invalidate_acceptance(self):
        for filename in ('test_cli.py', 'fixture.json'):
            (self.root / filename).write_text('before')
            self.write_manifest(code="from pathlib import Path;Path(" + repr(filename) + ").write_text('after');print(42)")
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

    def test_malformed_manifest_retains_infrastructure_failure_report(self):
        self.manifest.write_text('{broken')
        destination = self.base / 'failed-attempt.json'
        result = subprocess.run([sys.executable, str(Path(project.__file__)), '--compiler', str(COMPILER),
            '--entry', str(self.entry), '--manifest', str(self.manifest), '--report', str(destination)], capture_output=True, text=True)
        self.assertEqual(2, result.returncode)
        report = json.loads(destination.read_text())
        self.assertEqual('infrastructure-failure', report['status'])
        self.assertTrue(report['check_passed'])
        self.assertTrue(report['identity_unchanged'])

    def test_v2_complete_receipts_reuse_and_invalidate(self):
        self.write_manifest(version=2)
        first = self.run_project()
        self.assertEqual('passed', first['status'])
        again = self.run_project()
        self.assertEqual('passed', again['status'])
        self.assertNotEqual('executed', again['verification']['steps'][0]['status'])
        counts = project.compact(again)['verification']['step_counts']
        self.assertEqual(1, counts['cached'])
        self.assertEqual(1, counts['passed'])
        self.assertEqual(0, counts['executed'])
        self.entry.write_text('\nfunc main() -> i64:\n    return 43\n')
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
