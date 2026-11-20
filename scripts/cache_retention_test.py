#!/usr/bin/env python3
"""Developer retention CLI contracts without compiler or timing admission."""
from contextlib import redirect_stdout, redirect_stderr
import atexit
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import cache_retention
import core_store_gc
from fuzz_campaign_store import Store


# The user's own native object store(s), named before any test changes the environment. Every pruner or collector run of this
# module forbids them through SELKA_STORE_GC_DENY, and its environment points the store somewhere private, so a gate that runs this
# file collects nothing of the real store (it used to run `core_store_gc.py --apply` on all 2 million entries of it, in every lane's
# gate, and that run stalled builds).
USER_STORES = core_store_gc.user_store_roots(os.environ)
if os.environ.get('SELKA_CORE_RUNTIME_CACHE'):
    USER_STORES.append(os.environ['SELKA_CORE_RUNTIME_CACHE'])
PRIVATE_ROOT = tempfile.mkdtemp(prefix='retention-private-')
atexit.register(shutil.rmtree, PRIVATE_ROOT, True)


def hermetic(**overrides):
    """The live environment without any configured shared native store and with a private object store.

    `SELKA_CORE_RUNTIME_CACHE` and `XDG_CACHE_HOME` default to directories of this process's own, unless a test names others, and
    the user's stores are on the collector's deny list; `assert_private` refuses an environment that still reaches one.
    """
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('SELKA_COMPILER_SHARED_CACHE', 'SELKA_TEST_SHARED_CACHE')}
    environment.update(SELKA_CORE_RUNTIME_CACHE=str(Path(PRIVATE_ROOT) / 'objects'),
                       XDG_CACHE_HOME=str(Path(PRIVATE_ROOT) / 'xdg'),
                       **{core_store_gc.DENY_ENVIRONMENT: os.pathsep.join(USER_STORES)})
    environment.update(overrides)
    assert_private(environment)
    return environment


def assert_private(environment):
    """Fail unless the pruner run with `environment` would collect a store that is not one of the user's.

    The store `prune-caches.sh` collects is `SELKA_CORE_RUNTIME_CACHE` when set (empty: none), else `XDG_CACHE_HOME/selka/
    core-runtime` when absolute, else `$HOME/.cache/selka/core-runtime`.
    """
    if 'SELKA_CORE_RUNTIME_CACHE' in environment:
        selected = [environment['SELKA_CORE_RUNTIME_CACHE']] if environment['SELKA_CORE_RUNTIME_CACHE'] else []
    else:
        selected = core_store_gc.user_store_roots(environment)[:1]
    real = {os.path.realpath(path) for path in USER_STORES}
    for path in selected:
        if os.path.realpath(path) in real:
            raise AssertionError(f'a test would run the pruner on the real per-user store {path}')


class RetentionCLI(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='retention-cli-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.store = Store(self.root)
        self.blob = self.store.put_blob(b'unreferenced artifact')

    def command(self, *args):
        output, error = io.StringIO(), io.StringIO()
        with redirect_stdout(output), redirect_stderr(error):
            code = cache_retention.main(['--cache-dir', str(self.root), *args])
        return code, output.getvalue(), error.getvalue()

    def test_default_is_dry_run_and_apply_is_explicit(self):
        code, output, error = self.command('gc', '--max-bytes', '0')
        self.assertEqual((code, error), (0, ''))
        self.assertTrue(json.loads(output)['dry_run'])
        self.assertIsNotNone(self.store.read_blob(self.blob))
        code, output, error = self.command('gc', '--max-bytes', '0', '--apply')
        self.assertEqual((code, error), (0, ''))
        self.assertFalse(json.loads(output)['dry_run'])
        self.assertIsNone(self.store.read_blob(self.blob))

    def test_pin_unpin_retains_payload_and_gc_reports_active_lease(self):
        pin = hashlib.sha256(b'user pin').hexdigest()
        self.assertEqual(self.command('pin', pin, '--blob', self.blob)[0], 0)
        code, output, _ = self.command('gc', '--max-bytes', '0', '--apply')
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(output)['budget_unmet'])
        self.assertEqual(self.command('unpin', pin)[0], 0)
        with self.store.lease():
            code, output, _ = self.command('gc', '--apply')
            self.assertEqual(code, 0)
            self.assertTrue(json.loads(output)['skipped_active'])
        self.assertEqual(self.command('gc', '--apply')[0], 0)
        self.assertIsNone(self.store.read_blob(self.blob))

    def test_invalid_limit_and_unknown_format_return_error_without_deletion(self):
        code, output, error = self.command('gc', '--max-bytes', '-1', '--apply')
        self.assertEqual(code, 2)
        self.assertEqual(output, '')
        self.assertIn('max_bytes', error)
        self.assertIsNotNone(self.store.read_blob(self.blob))
        (self.root / 'format.json').write_bytes(b'foreign format')
        code, output, error = self.command('gc', '--apply')
        self.assertEqual((code, output), (2, ''))
        self.assertIn('format', error)
        self.assertTrue((self.root / 'blobs' / self.blob).is_file())

    def test_legacy_pruner_preserves_native_retention_in_scratch(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        protected = repo / '.tmp-native' / 'shared-cache' / 'compiler-artifacts-v2'
        protected.mkdir(parents=True)
        (protected / '.retention.lock').write_bytes(b'')
        artifact = protected / 'program.o'
        artifact.write_bytes(b'retained')
        expendable = repo / '.tmp-unmanaged' / 'build-cache'
        expendable.mkdir(parents=True)
        (expendable / 'object.o').write_bytes(b'disposable')
        environment = hermetic(SELKA_CORE_RUNTIME_CACHE=str(self.root / 'objects'),
                               XDG_CACHE_HOME=str(self.root / 'xdg'))
        result = subprocess.run([
            'bash', str(Path(__file__).with_name('prune-caches.sh')),
            '--repo', str(repo), '--include-primary', '--idle-days', '0',
            '--quiet-minutes', '0', '--apply',
        ], env=environment, capture_output=True, text=True, check=True)
        self.assertIn('retention-managed cache', result.stdout)
        self.assertEqual(artifact.read_bytes(), b'retained')
        self.assertTrue((protected / '.retention.lock').is_file())
        self.assertFalse(expendable.exists())

    def test_object_pruner_evicts_beside_builders_and_leaves_a_claim_a_build_holds(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        objects = self.root / 'objects'
        units = objects / 'units-v1'
        work = units / 'work'
        work.mkdir(parents=True)
        artifact = units / ('a' * 64 + '.o')
        artifact.write_bytes(b'object')
        os.utime(artifact, (1, 1))
        claim = work / ('a' * 64 + '.lock')
        claim.touch()
        held = work / ('b' * 64 + '.lock')
        held.touch()
        foreign = work / 'foreign.lock'
        foreign.touch()
        command = ['bash', str(Path(__file__).with_name('prune-caches.sh')),
                   '--repo', str(repo), '--store-days', '0', '--exclude', '*', '--apply']
        environment = hermetic(SELKA_CORE_RUNTIME_CACHE=str(objects),
                               XDG_CACHE_HOME=str(self.root / 'xdg'))
        # Builds hold the namespace leases shared for as long as they build, and a claim exclusively while it works. The
        # collector neither waits for the leases nor skips the store: it evicts what has been idle, and probes the claims.
        with (objects / '.retention.lock').open('a') as root_lease, (units / '.retention.lock').open('a') as unit_lease, \
                held.open('a') as busy:
            fcntl.flock(root_lease.fileno(), fcntl.LOCK_SH)
            fcntl.flock(unit_lease.fileno(), fcntl.LOCK_SH)
            fcntl.flock(busy.fileno(), fcntl.LOCK_EX)
            result = subprocess.run(command, env=environment, capture_output=True, text=True, check=True)
            self.assertIn('"skipped_active": false', result.stdout)
            self.assertFalse(artifact.exists())
            self.assertFalse(claim.exists())
            self.assertTrue(held.exists())
        self.assertTrue(foreign.exists())
        self.assertTrue((objects / '.retention.lock').exists())
        self.assertTrue((units / '.retention.lock').exists())

    def test_list_kept_uses_cached_sizes_and_never_runs_du(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True)
        (repo / 'tracked').write_text('tracked\n')
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=fixture',
                        '-c', 'user.email=fixture@example.invalid', 'add', 'tracked'], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '-m', 'fixture'], check=True)
        tree = self.root / 'kept'
        subprocess.run(['git', '-C', str(repo), 'worktree', 'add', '--detach', str(tree)], check=True)
        (tree / '.zig-cache' / 'o').mkdir(parents=True)
        stamp = int((tree / '.zig-cache' / 'o').stat().st_mtime)
        (tree / '.prune-keep').write_text('owner=fixture\nreason=test\nuntil=2999-01-01\n')
        (repo / '.git' / 'prune-caches.sizes').write_text('%s\t%d\t2048\n' % (tree, stamp))
        fake = self.root / 'fake-bin'
        fake.mkdir()
        called = self.root / 'du-called'
        (fake / 'du').write_text('#!/bin/sh\ntouch "%s"\nexit 99\n' % called)
        (fake / 'du').chmod(0o755)
        environment = hermetic(PATH=str(fake) + os.pathsep + os.environ.get('PATH', ''))
        result = subprocess.run(['bash', str(Path(__file__).with_name('prune-caches.sh')),
                                 '--repo', str(repo), '--list-kept'],
                                env=environment, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('zig-cache 2 MiB', result.stdout)
        self.assertIn('owner=fixture reason=test until=2999-01-01', result.stdout)
        self.assertFalse(called.exists(), 'list-kept ran du')

    def test_registered_service_checkout_is_never_pruned(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True)
        (repo / 'tracked').write_text('service\n')
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=fixture',
                        '-c', 'user.email=fixture@example.invalid', 'add', 'tracked'], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '-m', 'fixture'], check=True)
        service = self.root / 'service'
        subprocess.run(['git', '-C', str(repo), 'worktree', 'add', '--detach', str(service)], check=True)
        cached = service / '.zig-cache' / 'o' / 'keep'
        cached.parent.mkdir(parents=True)
        cached.write_bytes(b'must survive')
        gitdir = Path(subprocess.check_output(
            ['git', '-C', str(service), 'rev-parse', '--path-format=absolute', '--git-dir'],
            text=True).strip())
        (gitdir / 'selka-service-worktree.json').write_text('{"version": 1}\n')
        result = subprocess.run(['bash', str(Path(__file__).with_name('prune-caches.sh')),
                                 '--repo', str(repo), '--include-primary', '--idle-days', '0',
                                 '--quiet-minutes', '0', '--apply'],
                                env=hermetic(), capture_output=True, text=True, check=True)
        self.assertIn('registered service checkout', result.stdout)
        self.assertTrue(cached.exists())

    def test_pruner_collects_shared_stores_only_through_their_collector(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        configured = self.root / 'configured'
        (configured / 'compiler-artifacts-v2').mkdir(parents=True)
        (configured / 'compiler-artifacts-v2' / 'format').write_bytes(b'marker')
        default = self.root / 'xdg' / 'selka' / 'native-tests' / 'native-tests-v3'
        default.mkdir(parents=True)
        (default / 'format').write_bytes(b'marker')
        calls = self.root / 'calls'
        fake = self.root / 'selka'
        fake.write_text('#!/bin/sh\necho "$@" >> "%s"\necho collected\n' % calls)
        fake.chmod(0o755)
        command = ['bash', str(Path(__file__).with_name('prune-caches.sh')),
                   '--repo', str(repo), '--exclude', '*', '--selka', str(fake)]
        environment = hermetic(SELKA_CORE_RUNTIME_CACHE='', XDG_CACHE_HOME=str(self.root / 'xdg'),
                               SELKA_COMPILER_SHARED_CACHE=str(configured))
        preview = subprocess.run(command, env=environment, capture_output=True, text=True, check=True)
        self.assertIn('shared    %s/compiler-artifacts-v2  (collected )' % configured, preview.stdout)
        subprocess.run(command + ['--apply'], env=environment, capture_output=True, check=True)
        self.assertEqual(calls.read_text().splitlines(), [
            'cache gc --shared-cache-dir %s --kind compiler' % configured,
            'cache gc --shared-cache-dir %s --kind tests' % default.parent,
            'cache gc --shared-cache-dir %s --kind compiler --apply' % configured,
            'cache gc --shared-cache-dir %s --kind tests --apply' % default.parent,
        ])
        environment['SELKA_TEST_SHARED_CACHE'] = ''
        environment['SELKA_STAGE_SHARED_CACHE'] = ''
        calls.unlink()
        subprocess.run(command, env=environment, capture_output=True, check=True)
        self.assertEqual(len(calls.read_text().splitlines()), 1)


class RealStoreIsNeverCollectedByATest(unittest.TestCase):
    """A gate action must not name the user's own store: the pruner run on it, with `--apply`, ran for 25 minutes in each gate."""

    def test_the_default_environment_of_a_test_is_private_and_denies_the_real_store(self):
        environment = hermetic()
        self.assertTrue(environment['SELKA_CORE_RUNTIME_CACHE'].startswith(PRIVATE_ROOT))
        self.assertTrue(environment['XDG_CACHE_HOME'].startswith(PRIVATE_ROOT))
        for store in core_store_gc.user_store_roots(os.environ):
            self.assertIn(store, environment[core_store_gc.DENY_ENVIRONMENT].split(os.pathsep))

    def test_an_environment_that_reaches_the_real_store_is_refused_before_a_pruner_runs(self):
        for store in core_store_gc.user_store_roots(os.environ):
            with self.assertRaises(AssertionError):
                hermetic(SELKA_CORE_RUNTIME_CACHE=store)
        unset = {key: value for key, value in hermetic().items() if key != 'SELKA_CORE_RUNTIME_CACHE'}
        unset['XDG_CACHE_HOME'] = ''
        with self.assertRaises(AssertionError):
            assert_private(unset)
        assert_private(hermetic(SELKA_CORE_RUNTIME_CACHE=''))

    def test_the_pruner_and_the_collector_refuse_a_denied_store_even_when_asked_to_apply(self):
        with tempfile.TemporaryDirectory(prefix='denied-') as temporary:
            home = Path(temporary) / 'home'
            denied = home / '.cache' / 'selka' / 'core-runtime'
            (denied / 'units-v1').mkdir(parents=True)
            repo = Path(temporary) / 'checkout'
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            environment = {key: value for key, value in os.environ.items() if not key.startswith('SELKA_')}
            environment.update(HOME=str(home), XDG_CACHE_HOME='', **{core_store_gc.DENY_ENVIRONMENT: str(denied)})
            direct = subprocess.run([sys.executable, str(Path(core_store_gc.__file__)), '--store', str(denied), '--apply'],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(direct.returncode, 2, direct.stdout + direct.stderr)
            self.assertTrue(json.loads(direct.stdout)['refused'])
            pruner = subprocess.run(['bash', str(Path(__file__).with_name('prune-caches.sh')), '--repo', str(repo),
                                     '--exclude', '*', '--apply'], env=environment, capture_output=True, text=True)
            self.assertIn('is named by ' + core_store_gc.DENY_ENVIRONMENT, pruner.stdout + pruner.stderr)
            self.assertEqual([entry.name for entry in denied.iterdir() if entry.name.startswith('.size-ledger')], [])
            self.assertFalse((denied / '.last-maintenance.json').exists())

    def test_only_reviewed_gate_drivers_run_the_pruner_or_the_collector(self):
        # Every Python gate driver that names either must be listed here, and a listed one builds its environment with
        # `hermetic()` (this module) or collects a temporary root it made itself (core_store_gc_test.py).
        reviewed = {'cache_retention_test.py', 'core_store_gc_test.py', 'core_store_gc.py', 'prune-caches.sh'}
        root = Path(__file__).resolve().parents[1]
        pattern = re.compile(r'prune-caches\.sh|core_store_gc\.py|core_store_gc\b.*\.maintain|import core_store_gc')
        named = set()
        for directory in ('scripts', 'tests', 'test'):
            for path in sorted((root / directory).rglob('*.py')):
                if path.name in reviewed or '__pycache__' in path.parts:
                    continue
                if pattern.search(path.read_text(errors='ignore')):
                    named.add(str(path.relative_to(root)))
        self.assertEqual(named, set(), 'a gate driver runs the store pruner or collector; review it and add it to this list so it '
                                       'cannot reach the real per-user store')


if __name__ == '__main__':
    unittest.main()
