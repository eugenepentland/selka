"""Real guest smoke runs for checkout, relocation and namespace launcher layouts."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from experiments.application_comparison import isolation

ROOT = Path(__file__).resolve().parents[2]
BASELINES = ROOT / 'experiments/application_comparison/baselines'

# Importing each actual driver verifies its public names without invoking a stress
# suite. A nonempty application result verifies that the selected binary works.
EDA = """import test_cli as driver
assert driver.invoke({'cases': []}) == {'results': []}
answer = driver.result(driver.board(components=[driver.component('a', width=3, height=2)]))
assert answer['findings'] == []
assert '<rect id="a" x="0" y="0" width="3" height="2"' in answer['svg']
print(driver.EXE)
"""
PLANNER = """import test_cli as driver
assert driver.call({'cases': []}) == {'results': []}
assert driver.run([driver.job('a', 3, ['b']), driver.job('b', 2)]) == {
    'order': ['b', 'a'], 'layers': [['b'], ['a']],
    'timings': [{'id': 'a', 'start': 2, 'finish': 5}, {'id': 'b', 'start': 0, 'finish': 2}],
    'makespan': 5}
from test_cli import HOST, ROOT
assert HOST == driver.HOST and ROOT == driver.ROOT
print(driver.HOST)
"""


class PortableMyLaunchers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        candidate = Path(os.environ.get('MYLANG_IO', ROOT / 'zig-out/bin/mylang-io')).resolve()
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            if 'MYLANG_IO' in os.environ:
                raise RuntimeError('MYLANG_IO must name an executable real byte host')
            raise unittest.SkipTest('Build mylang-io or set MYLANG_IO for real launcher tests')
        cls.host = candidate

    def copy_project(self, parent, application):
        source = BASELINES / application / 'my'
        target = parent / application
        shutil.copytree(source, target, ignore=shutil.ignore_patterns('__pycache__', '.mylang-cache'))
        return target

    def probe(self, project, code, override=None):
        env = dict(os.environ)
        env.pop('MYLANG_IO', None)
        if override is not None:
            env['MYLANG_IO'] = str(override)
        return subprocess.run([sys.executable, '-B', '-c', code], cwd=project,
                              capture_output=True, env=env, timeout=60)

    def expect_success(self, completed, expected_host):
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors='replace'))
        self.assertEqual(completed.stdout.decode().strip(), str(expected_host))

    def test_checkout_ancestor_discovery_and_explicit_override(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            built = root / 'zig-out/bin/mylang-io'
            built.parent.mkdir(parents=True)
            built.symlink_to(self.host)
            nested = root / 'experiments/application_comparison/baselines'
            nested.mkdir(parents=True)
            for name, code in [('eda', EDA), ('planner', PLANNER)]:
                with self.subTest(application=name):
                    project = self.copy_project(nested, name)
                    mounted = Path("/tools/byte_io")
                    selected = mounted.resolve() if mounted.is_file() and os.access(mounted, os.X_OK) else self.host
                    self.expect_success(self.probe(project, code), selected)
                    self.expect_success(self.probe(project, code, self.host), self.host)

    def test_shallow_relocation_with_override(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, code in [('eda', EDA), ('planner', PLANNER)]:
                with self.subTest(application=name):
                    project = self.copy_project(root, name)
                    self.expect_success(self.probe(project, code, self.host), self.host)

    def test_invalid_override_never_falls_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            built = root / 'zig-out/bin/mylang-io'
            built.parent.mkdir(parents=True)
            built.symlink_to(self.host)
            nonexecutable = root / 'not executable'
            nonexecutable.write_text('not a binary\n')
            nonexecutable.chmod(0o600)
            for name in ('eda', 'planner'):
                project = self.copy_project(root, name)
                for bad in ('', root / 'missing', root, nonexecutable):
                    with self.subTest(application=name, override=str(bad)):
                        result = self.probe(project, 'import test_cli', bad)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(b'MYLANG_IO must name an executable file', result.stderr)

    def test_isolated_work_uses_mounted_tool_without_override(self):
        with tempfile.TemporaryDirectory() as temporary:
            for name, code in [('eda', EDA), ('planner', PLANNER)]:
                with self.subTest(application=name):
                    project = self.copy_project(Path(temporary), name)
                    result = isolation.run(project, ['/usr/bin/python3', '-B', '-c', code],
                                           tools={'byte_io': self.host},
                                           limits=isolation.Limits(wall_seconds=60, cpu_seconds=60))
                    self.assertTrue(result['isolated'], result['stderr'].decode(errors='replace'))
                    self.assertEqual(result['returncode'], 0, result['stderr'].decode(errors='replace'))
                    self.assertEqual(result['stdout'], b'/tools/byte_io\n')
                    missing = isolation.run(project, ['/usr/bin/python3', '-B', '-c', 'import test_cli'])
                    self.assertTrue(missing['isolated'], missing['stderr'].decode(errors='replace'))
                    self.assertNotEqual(missing['returncode'], 0)
                    self.assertIn(b'Cannot find mylang-io; set MYLANG_IO', missing['stderr'])
                    self.assertNotIn(b'IndexError', missing['stderr'])


if __name__ == '__main__':
    unittest.main()
