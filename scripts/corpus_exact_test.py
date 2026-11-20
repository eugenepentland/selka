#!/usr/bin/env python3
"""The parallel exactness check: corpus making, verdicts, both cache layouts and the process status, against a fake compiler."""
import contextlib
import io
import os
import stat
import tempfile
import unittest
from pathlib import Path

import corpus_exact

# A stand-in for `selka build FILE -o OUT [--cache-dir DIR | --no-cache]`. What a program says in its first line decides the build:
# FAILBOTH fails both ways, ONEWAY fails with --no-cache only, DIFFER writes other bytes when a cache directory is given, SLOW sleeps,
# ABORT writes a panic to stderr and aborts (signal 6) with --no-cache only.
# A cached build records the program's name in its cache directory, so a test can see which caches were used.
FAKE_COMPILER = '''#!/usr/bin/env python3
import hashlib, os, sys, time
args = sys.argv[1:]
program, output = args[1], args[args.index('-o') + 1]
cache = args[args.index('--cache-dir') + 1] if '--cache-dir' in args else None
first = open(program).readline()
if 'SLOW' in first:
    time.sleep(30)
if 'ABORT' in first and cache is None:
    sys.stderr.write('x' * 70000 + 'thread 1 panic: index out of bounds\\n')
    sys.stderr.flush()
    os.abort()
if 'FAILBOTH' in first or ('ONEWAY' in first and cache is None):
    sys.exit(1)
body = hashlib.sha256(open(program, 'rb').read()).hexdigest().encode()
if 'DIFFER' in first and cache is not None:
    body += b'cached'
if cache is not None:
    os.makedirs(cache, exist_ok=True)
    open(os.path.join(cache, os.path.basename(program) + '.' + str(os.getpid())), 'w').close()
open(output, 'wb').write(body)
'''


def make_tree(root, files):
    """Write `files` (path to text) under `root`."""
    for name, text in files.items():
        path = Path(root) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def fake_compiler(directory):
    """Install the fake compiler and return its path."""
    path = Path(directory) / 'fake-selka'
    path.write_text(FAKE_COMPILER)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


REPOSITORY = {
    'tests/lang/a.selka': '// plain\nfunc main() -> int:\n    return 0\n',
    'tests/lang/b.selka': '// plain\npublic func test_one() -> bool:\n    return true\n\npublic func test_two(out: Stream) -> bool:\n    return true\n',
    'tests/lang/c.selka': '// helpers only\nfunc helper() -> int:\n    return 1\n',
    'tests/lang/d.selka': '// FAILBOTH\nfunc main() -> int:\n    return 0\n',
    'tests/lang/e.selka': '// ONEWAY\nfunc main() -> int:\n    return 0\n',
    'tests/lang/f.selka': '// DIFFER\nfunc main() -> int:\n    return 0\n',
    'examples/g.selka': '// plain\nfunc main() -> int:\n    return 0\n',
}


class Corpus(unittest.TestCase):
    """Which files are programs, in what order, and what the generated `main` calls."""

    def test_roots_in_order_then_files_sorted_and_files_without_a_program_left_out(self):
        with tempfile.TemporaryDirectory() as scratch:
            make_tree(scratch + '/repo', REPOSITORY)
            programs = corpus_exact.make_corpus(scratch + '/repo', scratch + '/out')
            names = [str(p.relative_to(scratch + '/out/src')) for p in programs]
        self.assertEqual(names, ['tests/lang/a.selka', 'tests/lang/b.selka', 'tests/lang/d.selka', 'tests/lang/e.selka', 'tests/lang/f.selka',
                                 'examples/g.selka'])

    def test_a_generated_main_calls_every_test_and_passes_out_only_where_asked(self):
        text = corpus_exact.with_main(REPOSITORY['tests/lang/b.selka'])
        self.assertIn('func main(out: Stream) -> int:', text)
        self.assertIn('    if not test_one():', text)
        self.assertIn('    if not test_two(out):', text)
        self.assertTrue(text.endswith('    return failed\n'))
        self.assertIn('func main() -> int:', corpus_exact.with_main('public func test_x() -> bool:\n    return true\n'))

    def test_a_file_with_a_main_is_unchanged_and_one_with_nothing_is_none(self):
        self.assertEqual(corpus_exact.with_main(REPOSITORY['tests/lang/a.selka']), REPOSITORY['tests/lang/a.selka'])
        self.assertIsNone(corpus_exact.with_main(REPOSITORY['tests/lang/c.selka']))

    def test_the_repository_is_not_written(self):
        with tempfile.TemporaryDirectory() as scratch:
            make_tree(scratch + '/repo', REPOSITORY)
            corpus_exact.make_corpus(scratch + '/repo', scratch + '/out')
            self.assertEqual((Path(scratch) / 'repo/tests/lang/b.selka').read_text(), REPOSITORY['tests/lang/b.selka'])


class Verdicts(unittest.TestCase):
    """The four outcomes of one program."""

    def test_each_outcome(self):
        self.assertEqual(corpus_exact.classify(0, 0, True), 'identical')
        self.assertEqual(corpus_exact.classify(0, 0, False), 'different')
        self.assertEqual(corpus_exact.classify(1, 2, False), 'both-fail')
        self.assertEqual(corpus_exact.classify(0, 1, False), 'one-way')
        self.assertEqual(corpus_exact.classify(124, 0, False), 'one-way')

    def test_the_environment_points_every_store_into_the_work_directory(self):
        env = corpus_exact.child_environment('/work', {'XDG_CACHE_HOME': '/home/u/.cache', 'PATH': '/bin'})
        self.assertEqual(env['XDG_CACHE_HOME'], '/work/xdg')
        self.assertEqual(env['SELKA_CORE_RUNTIME_CACHE'], '/work/store')
        self.assertEqual(env['SELKA_STAGE_SHARED_CACHE'], '/work/stage-shared')
        self.assertEqual(env['ZIG_GLOBAL_CACHE_DIR'], '/home/u/.cache/zig')
        kept = corpus_exact.child_environment('/work', {'ZIG_GLOBAL_CACHE_DIR': '/zig-global'})
        self.assertEqual(kept['ZIG_GLOBAL_CACHE_DIR'], '/zig-global')


class Run(unittest.TestCase):
    """The whole check against the fake compiler: counts, status, cache layout."""

    def run_check(self, *extra):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', REPOSITORY)
        compiler = fake_compiler(scratch.name)
        work = scratch.name + '/work'
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = corpus_exact.main(['--compiler', str(compiler), '--repo', scratch.name + '/repo', '--work', work,
                                        '--keep'] + list(extra))
        return status, output.getvalue(), Path(work)

    def test_counts_and_status_with_a_shared_cache(self):
        status, text, work = self.run_check('--jobs', '3')
        # Six programs, two passes: three identical, one failing both ways, one one-way, one different.
        self.assertIn('builds 12: identical 6, different 2, failed both ways 2, failed one way 2', text)
        self.assertEqual(status, 1)
        findings = (work / 'different.txt').read_text().splitlines()
        self.assertEqual(len(findings), 4)
        self.assertEqual(sum(line.startswith('one-way') for line in findings), 2)
        self.assertEqual(sum(line.startswith('different') for line in findings), 2)
        self.assertEqual([p.name for p in work.glob('cache*')], ['cache'])

    def test_every_worker_gets_its_own_cache_when_asked(self):
        status, text, work = self.run_check('--jobs', '3', '--shard-caches')
        self.assertIn('builds 12: identical 6, different 2, failed both ways 2, failed one way 2', text)
        self.assertEqual(status, 1)
        self.assertEqual(sorted(p.name for p in work.glob('cache*')), ['cache0', 'cache1', 'cache2'])

    def test_a_clean_corpus_exits_zero_and_removes_the_work_directory(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', {'tests/lang/a.selka': REPOSITORY['tests/lang/a.selka'],
                                           'tests/lang/d.selka': REPOSITORY['tests/lang/d.selka']})
        compiler = fake_compiler(scratch.name)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = corpus_exact.main(['--compiler', str(compiler), '--repo', scratch.name + '/repo',
                                        '--work', scratch.name + '/work', '--jobs', '2'])
        self.assertEqual(status, 0)
        self.assertIn('builds 4: identical 2, different 0, failed both ways 2, failed one way 0', output.getvalue())
        self.assertNotIn('died', output.getvalue())
        self.assertFalse((Path(scratch.name) / 'work').exists())

    def test_a_build_that_dies_keeps_the_end_of_its_stderr_and_the_summary_says_where(self):
        # FR83: three compiler deaths in two days left no trace, because every build's stderr went to /dev/null.
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', {'tests/lang/a.selka': REPOSITORY['tests/lang/a.selka'],
                                           'tests/lang/d.selka': REPOSITORY['tests/lang/d.selka'],
                                           'tests/lang/x.selka': '// ABORT\nfunc main() -> int:\n    return 0\n'})
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = corpus_exact.main(['--compiler', str(fake_compiler(scratch.name)), '--repo', scratch.name + '/repo',
                                        '--work', scratch.name + '/work', '--jobs', '2'])
        text = output.getvalue()
        # The counts are what they were: the aborted side is a failure of that side.
        self.assertIn('builds 6: identical 2, different 0, failed both ways 2, failed one way 2', text)
        self.assertEqual(status, 1)
        deaths = Path(scratch.name) / 'work' / 'deaths'
        self.assertIn(f'2 builds died of a signal: stderr kept in {deaths}', text)
        # The counts follow the deaths line, so a caller that shows the last lines still shows them.
        self.assertLess(text.index('builds died of a signal'), text.index('builds 6: identical'))
        kept = sorted(deaths.iterdir())
        self.assertEqual([p.name for p in kept], ['0001-x-plain-status-6.stderr', '0002-x-plain-status-6.stderr'])
        stderr = kept[0].read_bytes()
        self.assertEqual(len(stderr), corpus_exact.STDERR_KEPT)
        self.assertTrue(stderr.endswith(b'thread 1 panic: index out of bounds\n'))
        # A refusal (status 1) is not a death, and neither is the compiler's status 2 (a program that cannot link).
        self.assertFalse(any('-d-' in p.name for p in kept))
        self.assertEqual([corpus_exact.died(s) for s in (0, 1, 2, corpus_exact.TIMED_OUT, -6, 134)], [False, False, False, False, True, True])

    def test_the_second_pass_runs_the_list_backwards(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', REPOSITORY)
        order = []

        def record(job, program, cache_dir):
            order.append(program.name)
            return 'identical', 0, 0

        original = corpus_exact.check_program
        corpus_exact.check_program = record
        self.addCleanup(setattr, corpus_exact, 'check_program', original)
        with contextlib.redirect_stdout(io.StringIO()):
            corpus_exact.main(['--compiler', str(fake_compiler(scratch.name)), '--repo', scratch.name + '/repo',
                               '--work', scratch.name + '/work', '--jobs', '1'])
        forward = ['a.selka', 'b.selka', 'd.selka', 'e.selka', 'f.selka', 'g.selka']
        self.assertEqual(order, forward + forward[::-1])

    def test_a_build_past_the_timeout_is_a_failure_of_that_side(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', {'tests/lang/s.selka': '// SLOW\nfunc main() -> int:\n    return 0\n'})
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = corpus_exact.main(['--compiler', str(fake_compiler(scratch.name)), '--repo', scratch.name + '/repo',
                                        '--work', scratch.name + '/work', '--jobs', '1', '--timeout', '1'])
        self.assertEqual(status, 0)
        self.assertIn('failed both ways 2', output.getvalue())
        self.assertIn('2 builds timed out', output.getvalue())

    def test_corpus_only_builds_nothing_and_counts_the_programs(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', REPOSITORY)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = corpus_exact.main(['--corpus-only', '--repo', scratch.name + '/repo', '--work', scratch.name + '/work'])
        self.assertEqual(status, 0)
        self.assertIn('corpus: 6 programs (tests/lang 5, examples 1); 12 builds over two passes', output.getvalue())
        self.assertEqual(len((Path(scratch.name) / 'work/list.txt').read_text().splitlines()), 6)

    def test_a_missing_compiler_is_a_usage_error(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        make_tree(scratch.name + '/repo', REPOSITORY)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            status = corpus_exact.main(['--compiler', scratch.name + '/nothing', '--repo', scratch.name + '/repo',
                                        '--work', scratch.name + '/work'])
        self.assertEqual(status, 2)


if __name__ == '__main__':
    unittest.main()
