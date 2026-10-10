"""Adversarial tests of the compiler-wide qualification verdict boundary."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('qualification', Path(__file__).with_name('run_frontend_qualification.py'))
Q = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(Q)


def report(**changes):
    value = {'version': 'native-tests-v1', 'tests': [
        {'name': 'input::test_a', 'status': 'passed'},
        {'name': 'input::test_b', 'status': 'passed'}],
        'passed': 2, 'cached': 0, 'failed': 0, 'skipped': 0, 'unsupported': 0}
    value.update(changes)
    return 0, json.dumps(value).encode(), b''


class QualificationTests(unittest.TestCase):
    def test_routing_and_authority_cannot_leak(self):
        with patch.dict(os.environ, {'PILOT_TRUSTED': '1', 'PILOT_REPLY': 'evil',
                                    'MYLANG_PARSER_MODE': 'component', 'MYLANG_COMPONENT_DIR': '/evil'}):
            env = Q.environment('shadow', Path('/verified'), Path('/empty'))
        self.assertNotIn('PILOT_TRUSTED', env)
        self.assertNotIn('PILOT_REPLY', env)
        self.assertEqual(env['MYLANG_PARSER_MODE'], 'shadow')
        self.assertEqual(env['MYLANG_COMPONENT_DIR'], '/verified')
        self.assertEqual(env['PATH'], '/empty')

    def test_empty_selection_is_not_green(self):
        with self.assertRaisesRegex(RuntimeError, 'selection'):
            Q.test_counts(report(tests=[], passed=0))

    def test_cached_forced_verdict_is_not_green(self):
        with self.assertRaisesRegex(RuntimeError, 'cached verdicts'):
            Q.test_counts(report(passed=0, cached=2))

    def test_skipped_and_unsupported_are_not_green(self):
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            Q.test_counts(report(skipped=1))
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            Q.test_counts(report(unsupported=1))

    def test_duplicate_status_counts_do_not_hide_bad_test(self):
        with self.assertRaisesRegex(RuntimeError, 'status'):
            Q.test_counts(report(tests=[{'name': 'a', 'status': 'passed'}, {'name': 'b', 'status': 'failed'}]))

    def test_duplicate_names_do_not_count_as_two_tests(self):
        with self.assertRaisesRegex(RuntimeError, 'duplicate'):
            Q.test_counts(report(tests=[{'name': 'a', 'status': 'passed'}, {'name': 'a', 'status': 'passed'}]))

    def test_artifact_basename_cannot_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'test-index.json').write_text(json.dumps({
                'format': 1, 'component': 'test-index', 'protocol': 1, 'schema': 1,
                'artifact': '../outside', 'sha256': '0' * 64}))
            with self.assertRaisesRegex(RuntimeError, 'unsafe'):
                Q.packages(root)

    def test_artifact_digest_is_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'producer').write_bytes(b'changed')
            (root / 'test-index.json').write_text(json.dumps({
                'format': 1, 'component': 'test-index', 'protocol': 1, 'schema': 1,
                'artifact': 'producer', 'sha256': '0' * 64}))
            with self.assertRaisesRegex(RuntimeError, 'digest'):
                Q.packages(root)

    def test_stdout_equality_cannot_hide_stderr_mismatch(self):
        q = object.__new__(Q.Qualification)
        q.modes, q.comparisons, q.records = ['shadow'], 0, []
        results = iter([(0, b'equal', b''), (0, b'equal', b'host failure')])
        q.run = lambda *args: next(results)
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            q.compare('check', ['check', 'fixture'])


if __name__ == '__main__':
    unittest.main()
