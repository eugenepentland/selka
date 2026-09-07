from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.build_reuse import BuildReuse
from experiments.application_comparison.execution import evaluate, freeze_adapter
from experiments.application_comparison import public_verification
from experiments.application_comparison.storage import snapshot

# A stdlib-only executable fixture exercises orchestration, not Zig performance.
APP = '''#!/usr/bin/python3
import json,sys
from pathlib import Path
assert not Path('/work/runtime-state').exists()
assert not Path('/cache/runtime-state').exists()
Path('/work/runtime-state').write_text('changed')
Path('/cache/runtime-state').write_text('changed')
Path('/cache/app').write_text('corrupted by previous input')
print(json.dumps(json.load(sys.stdin)))
'''
BUILD = "from pathlib import Path;p=Path('/cache/app');p.write_text(%r);p.chmod(0o700)" % APP


class BuildReuseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'main.zig').write_text('// orchestration fixture\n')
        self.receipt = snapshot(self.source, self.root / 'captured')

    def adapter(self, build=BUILD, check='pass', tools=None):
        return freeze_adapter('zig', tools or {}, [
            {'phase': 'check', 'argv': ['/usr/bin/python3', '-S', '-B', '-c', check]},
            {'phase': 'build', 'argv': ['/usr/bin/python3', '-S', '-B', '-c', build]},
            {'phase': 'run', 'argv': ['/cache/app']}])

    def test_one_build_fresh_runtime_copies_and_no_answer_reuse(self):
        cases = [dict(name=str(i), case={'request': i, 'expected': expected})
                 for i, expected in ((1, 1), (2, 999), (3, 3))]
        report = public_verification.run(self.source, self.receipt, self.adapter(),
                                        cases, self.root / 'suite', lambda: 30)
        self.assertEqual([r['passed'] for r in report['results']], [True, False, True])
        records = [r['record'] for r in report['results']]
        self.assertEqual([[s['phase'] for s in r['steps']] for r in records],
                         [['check', 'build', 'run'], ['run'], ['run']])
        self.assertEqual([r['build_reuse']['reused'] for r in records], [False, True, True])
        self.assertEqual(len({r['build_reuse']['binary_sha256'] for r in records}), 1)
        self.assertEqual(len(public_verification.diagnostics(report, self.root / 'suite')), 5)
        self.assertFalse((self.source / 'runtime-state').exists())

    def test_source_adapter_and_suite_changes_rebuild(self):
        reuse = BuildReuse()
        adapter = self.adapter()
        def check(number, receipt, config, cache):
            return evaluate(self.source, receipt, config, number, self.root / str(number), build_reuse=cache)
        self.assertFalse(check(1, self.receipt, adapter, reuse)['build_reuse']['reused'])
        (self.source / 'main.zig').write_text('// changed source\n')
        changed = snapshot(self.source, self.root / 'changed')
        self.assertFalse(check(2, changed, adapter, reuse)['build_reuse']['reused'])
        self.assertFalse(check(3, changed, self.adapter(check='print("new policy")'), reuse)['build_reuse']['reused'])
        self.assertFalse(check(4, changed, adapter, BuildReuse())['build_reuse']['reused'])
        self.assertTrue(check(5, changed, adapter, reuse)['build_reuse']['reused'])
        with self.assertRaises(ValueError):
            check(6, self.receipt, adapter, reuse)

    def test_live_tool_change_cannot_use_old_build(self):
        tool = self.root / 'tool'
        tool.write_text('original')
        adapter = self.adapter(tools={'fixture': tool})
        reuse = BuildReuse()
        evaluate(self.source, self.receipt, adapter, 1, self.root / 'one', build_reuse=reuse)
        tool.write_text('changed')
        with self.assertRaisesRegex(ValueError, 'tool or standard library changed'):
            evaluate(self.source, self.receipt, adapter, 1, self.root / 'two', build_reuse=reuse)

    def test_failed_prefix_not_cached_or_bypassed(self):
        for label, adapter in [('check', self.adapter(check='raise SystemExit(1)')),
                               ('build', self.adapter(build='raise SystemExit(1)'))]:
            reuse = BuildReuse()
            for i in range(2):
                record = evaluate(self.source, self.receipt, adapter, 1,
                                  self.root / f'{label}-{i}', build_reuse=reuse)
                self.assertFalse(record['outcome']['passed'])
                self.assertEqual(record['outcome']['phase'], label)
                self.assertEqual(reuse.entries, {})

    def test_deadline_prevents_reused_execution(self):
        reuse = BuildReuse()
        adapter = self.adapter()
        evaluate(self.source, self.receipt, adapter, 1, self.root / 'one', build_reuse=reuse)
        record = evaluate(self.source, self.receipt, adapter, 2, self.root / 'two',
                          build_reuse=reuse, remaining_seconds=lambda: 0)
        self.assertEqual(record['steps'], [])
        self.assertEqual(record['outcome']['failure'], 'phase-deadline')

    def test_symlink_and_source_mutating_builds_reject(self):
        for name, build in [('symlink', "from pathlib import Path;Path('/cache/app').symlink_to('/etc/passwd')"),
                            ('source', BUILD + ";Path('/work/extra').write_text('changed')")]:
            reuse = BuildReuse()
            with self.assertRaises((OSError, ValueError)):
                evaluate(self.source, self.receipt, self.adapter(build=build), 1,
                         self.root / name, build_reuse=reuse)
            self.assertEqual(reuse.entries, {})


if __name__ == '__main__':
    unittest.main()
