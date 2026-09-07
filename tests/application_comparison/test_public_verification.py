from pathlib import Path
import tempfile
import time
import unittest
from experiments.application_comparison import public_verification as public
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import snapshot


class PublicVerificationTests(unittest.TestCase):
    def test_all_cases_run_against_same_snapshot_and_failure_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            (source / 'main.py').write_text('import json,sys\nprint(json.dumps(json.load(sys.stdin)))\n')
            receipt = snapshot(source, root / 'captured')
            adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            cases = [dict(name='first', case={'request': 1, 'expected': 1}),
                     dict(name='wrong', case={'request': 2, 'expected': 3}),
                     dict(name='last', case={'request': 4, 'expected': 4})]
            report = public.run(root / 'captured', receipt, adapter, cases, root / 'check', lambda: 30)
            self.assertFalse(report['passed'])
            self.assertEqual([item['passed'] for item in report['results']], [True, False, True])
            self.assertEqual({item['record']['source_sha256'] for item in report['results']}, {receipt['sha256']})
            self.assertEqual([item['case'] for item in public.diagnostics(report, root / 'check')], ['first', 'wrong', 'last'])

    def test_shared_deadline_stops_later_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            (source / 'main.py').write_text('import time\ntime.sleep(10)\nprint(1)\n')
            receipt = snapshot(source, root / 'captured')
            adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            cases = [dict(name=name, case={'request': None, 'expected': 1}) for name in ('slow', 'unstarted')]
            end = time.monotonic() + 0.3
            report = public.run(root / 'captured', receipt, adapter, cases, root / 'check', lambda: end - time.monotonic())
            self.assertFalse(report['passed'])
            self.assertEqual(report['results'][1]['status'], 'not-run-deadline')
            self.assertFalse((root / 'check/001').exists())

    def test_empty_duplicate_and_invalid_cases_reject(self):
        valid = dict(name='same', case={'request': None, 'expected': None})
        for cases in ([], [valid, valid], [dict(name='bad', case={})], [valid] * 65):
            with self.assertRaises(ValueError):
                public.validate(cases)


if __name__ == '__main__':
    unittest.main()
