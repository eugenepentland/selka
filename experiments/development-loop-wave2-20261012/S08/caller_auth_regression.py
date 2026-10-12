#!/usr/bin/env python3
"""Execute the exact coordinator patch against real controlled source/watch cases."""
from contextlib import ExitStack
import hashlib
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
import verification_code_identity as identity
from verification_snapshot import Snapshot, SnapshotError


class CallerAuthentication(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='helper-auth-', dir=ROOT / '.tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'helper.py'
        self.source.write_bytes(Path(identity.__file__).read_bytes())
        spec = importlib.util.spec_from_file_location('helper_auth_fixture', self.source)
        self.helper = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = self.helper
        spec.loader.exec_module(self.helper)
        self.addCleanup(sys.modules.pop, spec.name, None)
        self.namespace = dict(Path=Path, os=os, hashlib=hashlib, code_identity=self.helper,
                              Snapshot=Snapshot, SnapshotError=SnapshotError)
        proposal = Path(__file__).with_name('caller_auth_function.py.txt').read_text()
        exec(compile(proposal, 'proposed-caller.py', 'exec'), self.namespace)
        self.authenticate = self.namespace['authenticate_code_identity']

    def test_current_source_proof_is_cached_without_warm_file_reads(self):
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            snapshots = [watched]
            self.authenticate(self.root, watched, snapshots, stack)
            with patch.object(Path, 'open', side_effect=AssertionError('warm read')):
                self.authenticate(self.root, watched, snapshots, stack)
            self.assertIs(self.namespace['_CODE_HELPER_SOURCE_PROOF'][0], self.helper._LOADED_CODE_OBJECT)
            self.assertTrue(watched.unchanged())

    def test_fake_root_attaches_actual_provider_authority_until_request_exit(self):
        fake = self.root / 'fake'
        fake.mkdir()
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(fake, []))
            snapshots = [watched]
            self.authenticate(fake, watched, snapshots, stack)
            self.assertEqual(len(snapshots), 2)
            provider = snapshots[-1]
            self.assertTrue(provider.unchanged())
            self.source.write_bytes(self.source.read_bytes().replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193'))
            self.assertFalse(provider.unchanged())
        self.assertRaises(SnapshotError, provider.unchanged)

    def test_stale_helper_before_watch_is_rejected_even_with_fresh_source_capture(self):
        self.source.write_bytes(self.source.read_bytes().replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193'))
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.assertTrue(watched.unchanged())
            self.assertRaisesRegex(self.helper.CodeIdentityError, 'does not match',
                                   self.authenticate, self.root, watched, [watched], stack)
            self.assertIsNone(self.namespace['_CODE_HELPER_SOURCE_PROOF'])

    def test_proof_cache_compares_code_object_by_identity(self):
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            original = self.helper._LOADED_CODE_OBJECT
            self.helper._LOADED_CODE_OBJECT = original.replace()
            self.assertEqual(self.helper._LOADED_CODE_OBJECT, original)
            self.assertIsNot(self.helper._LOADED_CODE_OBJECT, original)
            with patch.object(self.helper, 'authenticate_code_source', wraps=self.helper.authenticate_code_source) as authenticate:
                self.authenticate(self.root, watched, [watched], stack)
            self.assertEqual(authenticate.call_count, 1)
            self.assertIs(self.namespace['_CODE_HELPER_SOURCE_PROOF'][0], self.helper._LOADED_CODE_OBJECT)

    def test_mismatched_watched_bytes_fail_even_when_current_code_would_match(self):
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            record = watched.identity['files'][0]
            record['sha256'] = '0' * 64
            with patch.object(watched, '_identity', {'files': [record]}):
                self.assertRaisesRegex(SnapshotError, 'during', self.authenticate,
                                       self.root, watched, [watched], stack)
            self.assertIsNone(self.namespace['_CODE_HELPER_SOURCE_PROOF'])

    def test_missing_metadata_cannot_use_an_earlier_content_proof(self):
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            record = watched.identity['files'][0]
            del record['size']
            with patch.object(watched, '_identity', {'files': [record]}):
                self.assertRaisesRegex(self.helper.CodeIdentityError, 'metadata', self.authenticate,
                                       self.root, watched, [watched], stack)

    def test_cache_never_authorizes_a_closed_or_dirty_request_snapshot(self):
        with ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            self.source.write_bytes(self.source.read_bytes() + b'\n')
            # A cached code/source relation cannot make this watch pass.
            self.authenticate(self.root, watched, [watched], stack)
            self.assertFalse(watched.unchanged())
        self.assertRaises(SnapshotError, self.authenticate, self.root, watched, [watched], ExitStack())


if __name__ == '__main__':
    unittest.main()
