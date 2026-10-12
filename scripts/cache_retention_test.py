#!/usr/bin/env python3
"""Developer retention CLI contracts without compiler or timing admission."""
from contextlib import redirect_stdout, redirect_stderr
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import cache_retention
from fuzz_campaign_store import Store


def hermetic(**overrides):
    """The live environment without any configured shared native store."""
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('MYLANG_COMPILER_SHARED_CACHE', 'MYLANG_TEST_SHARED_CACHE')}
    environment.update(overrides)
    return environment


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
        environment = hermetic(MYLANG_CORE_RUNTIME_CACHE=str(self.root / 'objects'),
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

    def test_legacy_object_pruner_skips_owners_and_waiters_then_reclaims_idle_claims(self):
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
        inode = claim.stat().st_ino
        foreign = work / 'foreign.lock'
        foreign.touch()
        command = ['bash', str(Path(__file__).with_name('prune-caches.sh')),
                   '--repo', str(repo), '--store-days', '0', '--exclude', '*', '--apply']
        environment = hermetic(MYLANG_CORE_RUNTIME_CACHE=str(objects),
                               XDG_CACHE_HOME=str(self.root / 'xdg'))
        for directory in (objects, units):
            with (directory / '.retention.lock').open('a') as lease:
                fcntl.flock(lease.fileno(), fcntl.LOCK_SH)
                result = subprocess.run(command, env=environment, capture_output=True,
                                        text=True, check=True)
                self.assertIn('native cache lease unavailable', result.stdout)
                self.assertTrue(artifact.exists())
                self.assertEqual(claim.stat().st_ino, inode)
        subprocess.run(command, env=environment, capture_output=True, check=True)
        self.assertFalse(artifact.exists())
        self.assertFalse(claim.exists())
        self.assertTrue(foreign.exists())
        self.assertTrue((objects / '.retention.lock').exists())
        self.assertTrue((units / '.retention.lock').exists())

    def test_pruner_collects_shared_stores_only_through_their_collector(self):
        repo = self.root / 'checkout'
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        configured = self.root / 'configured'
        (configured / 'compiler-artifacts-v2').mkdir(parents=True)
        (configured / 'compiler-artifacts-v2' / 'format').write_bytes(b'marker')
        default = self.root / 'xdg' / 'mylang' / 'native-tests' / 'native-tests-v2'
        default.mkdir(parents=True)
        (default / 'format').write_bytes(b'marker')
        calls = self.root / 'calls'
        fake = self.root / 'mylang'
        fake.write_text('#!/bin/sh\necho "$@" >> "%s"\necho collected\n' % calls)
        fake.chmod(0o755)
        command = ['bash', str(Path(__file__).with_name('prune-caches.sh')),
                   '--repo', str(repo), '--exclude', '*', '--mylang', str(fake)]
        environment = hermetic(MYLANG_CORE_RUNTIME_CACHE='', XDG_CACHE_HOME=str(self.root / 'xdg'),
                               MYLANG_COMPILER_SHARED_CACHE=str(configured))
        preview = subprocess.run(command, env=environment, capture_output=True, text=True, check=True)
        self.assertIn('shared    %s/compiler-artifacts-v2  (collected )' % configured, preview.stdout)
        subprocess.run(command + ['--apply'], env=environment, capture_output=True, check=True)
        self.assertEqual(calls.read_text().splitlines(), [
            'cache gc --shared-cache-dir %s --kind compiler' % configured,
            'cache gc --shared-cache-dir %s --kind tests' % default.parent,
            'cache gc --shared-cache-dir %s --kind compiler --apply' % configured,
            'cache gc --shared-cache-dir %s --kind tests --apply' % default.parent,
        ])
        environment['MYLANG_TEST_SHARED_CACHE'] = ''
        calls.unlink()
        subprocess.run(command, env=environment, capture_output=True, check=True)
        self.assertEqual(len(calls.read_text().splitlines()), 1)


if __name__ == '__main__':
    unittest.main()
