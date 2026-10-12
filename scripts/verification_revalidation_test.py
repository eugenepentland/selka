#!/usr/bin/env python3
"""Prove delayed tool validation rejects mutation before execution or success.

The coordinator source remains unchanged. A scoped fixture suppresses only its
first role-tagged tool check, modeling removal of that redundant immediate call.
All retained acquisition/admission/lookup/publication checks continue normally.
"""
import unittest
from unittest.mock import patch

import verify_cache_test as fixtures
from verification_snapshot import Snapshot, RetainedSession


class DeferredToolValidation(fixtures.VerificationCoordinator):
    def defer_first_tools_check(self):
        original = Snapshot.unchanged
        skipped = []
        def check(snapshot):
            if getattr(snapshot, 'verification_role', None) == 'tools' and not skipped:
                skipped.append(True)
                return True
            return original(snapshot)
        self.stack.enter_context(patch.object(Snapshot, 'unchanged', check))
        return skipped

    def change_during_resolution(self):
        calls = []
        def resolve(_zig, _environment):
            calls.append(True)
            if len(calls) == 2:
                original = self.tool.read_bytes()
                self.tool.write_bytes(b'tool mutation during second resolution')
                self.tool.write_bytes(original)
            return [], [self.zig, self.tool]
        self.stack.enter_context(patch.object(fixtures.coordinator, 'tool_contract', side_effect=resolve))

    def test_deferred_warm_lookup_rejects_tool_aba_without_admission(self):
        with RetainedSession() as retained, retained.activate():
            self.assertEqual(self.execute(), 0)
            self.admissions.clear()
            self.change_during_resolution()
            skipped = self.defer_first_tools_check()
            with self.assertRaises(fixtures.coordinator.VerificationError) as caught:
                self.execute()
            self.assertEqual(caught.exception.status, fixtures.coordinator.RETRY)
            self.assertEqual(skipped, [True])
            self.assertEqual(self.admissions, [])
            report = fixtures.coordinator.read_record(self.cache / 'last-run.json')
            self.assertFalse(report['success'])
            self.assertEqual(report['status'], fixtures.coordinator.RETRY)

    def test_deferred_cold_admission_rejects_tool_aba_without_success(self):
        self.change_during_resolution()
        skipped = self.defer_first_tools_check()
        with self.assertRaises(fixtures.coordinator.VerificationError):
            self.execute()
        self.assertEqual(skipped, [True])
        self.assertEqual(self.receipts(), [])

    def test_deferred_unmodified_warm_request_preserves_complete_reuse(self):
        with RetainedSession() as retained, retained.activate():
            self.assertEqual(self.execute(), 0)
            self.admissions.clear()
            skipped = self.defer_first_tools_check()
            self.assertEqual(self.execute(), 0)
            self.assertEqual(skipped, [True])
            self.assertEqual(self.admissions, [])
            self.assertEqual(self.states(), {'unit':'reused', 'docs':'reused'})
            report = fixtures.coordinator.read_record(self.cache / 'last-run.json')
            self.assertTrue(report['inputs_stable'])
            self.assertEqual(report['snapshot_statistics']['files_hashed'], 0)
            self.assertEqual(report['snapshot_statistics']['directories_enumerated'], 0)


def load_tests(loader, _tests, _pattern):
    return unittest.TestSuite(DeferredToolValidation(name) for name in loader.getTestCaseNames(DeferredToolValidation)
                              if name.startswith('test_deferred_'))


if __name__ == '__main__':
    unittest.main()
