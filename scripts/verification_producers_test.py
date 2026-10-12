#!/usr/bin/env python3
"""Reviewed producer metadata rejects stale sources and unproven boundaries."""
from contextlib import ExitStack
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import verification_artifacts
import verification_producers as producers
from verification_snapshot import Snapshot, SnapshotError

ROOT = Path(__file__).resolve().parents[1]


class ProducerTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        for name in producers.CLOSURES['tooling-units']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.artifact = self.root / 'tooling'
        self.artifact.write_bytes(b'independent-native-executable')
        self.artifact.chmod(0o755)
        self.context = {'build_configuration': 'a' * 64, 'tools': 'b' * 64,
                        'options': [], 'action_controls': {'optimize': 'Debug'}}
        self.record = {'version': 2, 'artifacts': {'tooling-units': str(self.artifact)},
                       'producers': {'tooling-units': producers.producer_metadata(
                           self.root, 'tooling-units', self.artifact, 'Debug')}}

    def identities(self, root=None, artifact=None):
        root, artifact = root or self.root, artifact or self.artifact
        source = self.stack.enter_context(Snapshot(root, list(producers.CLOSURES['tooling-units'])))
        binary = self.stack.enter_context(Snapshot(root, [], [artifact]))
        return binary.identity['files'], source.identity['files']

    def qualify(self, record=None, context=None):
        binary, source = self.identities()
        return producers.qualified_identity(record or self.record, 'tooling-units', binary,
                                            source, context or self.context)

    def test_complete_closure_qualifies(self):
        identity = self.qualify()
        self.assertEqual(identity['seed'], None)
        self.assertEqual(len(identity['sources']), 11)
        self.assertEqual(identity['implementation']['sha256'], self.record['producers']['tooling-units']['implementation']['sha256'])

    def test_independent_compiler_edit_preserves_identity(self):
        before = self.qualify()
        (self.root / 'src/compiler.zig').write_text('unrelated compiler change')
        self.assertEqual(self.qualify(), before)

    def test_transitive_semantic_change_requires_rebuild_and_revert_restores_identity(self):
        before = self.qualify()
        path = self.root / 'src/fix_plan.zig'
        original = path.read_bytes()
        path.write_bytes(original + b'\n// semantic implementation change\n')
        self.assertIsNone(self.qualify())
        changed = producers.producer_metadata(self.root, 'tooling-units', self.artifact, 'Debug')
        changed_record = copy.deepcopy(self.record)
        changed_record['producers']['tooling-units'] = changed
        self.assertNotEqual(self.qualify(changed_record), before)
        path.write_bytes(original)
        self.assertEqual(self.qualify(), before)

    def test_missing_metadata_unknown_provider_and_legacy_inventory_stay_broad(self):
        binary, source = self.identities()
        self.assertIsNone(producers.qualified_identity({'version': 1}, 'tooling-units', binary, source, self.context))
        self.assertIsNone(producers.qualified_identity({'version': 2, 'producers': {}}, 'tooling-units', binary, source, self.context))
        self.assertIsNone(producers.qualified_identity(self.record, 'mylang', binary, source, self.context))

    def test_mode_seed_abi_schema_and_tool_changes(self):
        original = self.qualify()
        for field, value in [('mode', 'ReleaseFast'), ('seed', {'sha256': 'c' * 64}),
                             ('abi', 'changed'), ('interface', 'changed'), ('version', 2)]:
            record = copy.deepcopy(self.record)
            record['producers']['tooling-units'][field] = value
            with self.subTest(field=field):
                self.assertIsNone(self.qualify(record))
        context = copy.deepcopy(self.context)
        context['tools'] = 'c' * 64
        self.assertNotEqual(self.qualify(context=context), original)
        context['action_controls']['optimize'] = 'ReleaseFast'
        self.assertIsNone(self.qualify(context=context))

    def test_artifact_replacement_never_authorizes_old_metadata(self):
        self.artifact.write_bytes(b'changed native checker')
        self.assertIsNone(self.qualify())

    def test_missing_source_duplicate_source_and_symlink_are_not_proof(self):
        binary, source = self.identities()
        self.assertIsNone(producers.qualified_identity(self.record, 'tooling-units', binary, source[:-1], self.context))
        self.assertIsNone(producers.qualified_identity(self.record, 'tooling-units', binary, source[:-1] + source[:1], self.context))
        source[0]['resolved'] = 'elsewhere'
        self.assertIsNone(producers.qualified_identity(self.record, 'tooling-units', binary, source, self.context))

    def test_new_import_and_dynamic_import_decline_narrowing(self):
        path = self.root / 'src/fix_plan.zig'
        original = path.read_text()
        path.write_text(original + '\nconst added = @import("new_semantics.zig");\n')
        self.assertIsNone(producers.producer_metadata(self.root, 'tooling-units', self.artifact, 'Debug'))
        path.write_text(original + '\nconst added = @import(comptime_name);\n')
        self.assertIsNone(producers.producer_metadata(self.root, 'tooling-units', self.artifact, 'Debug'))

    def test_source_and_artifact_aba_during_lookup_revoke_live_authority(self):
        binary = self.stack.enter_context(Snapshot(self.root, [], [self.artifact]))
        source = self.stack.enter_context(Snapshot(self.root, list(producers.CLOSURES['tooling-units'])))
        self.assertIsNotNone(producers.qualified_identity(self.record, 'tooling-units', binary.identity['files'], source.identity['files'], self.context))
        original = self.artifact.read_bytes()
        self.artifact.write_bytes(b'mutation')
        self.artifact.write_bytes(original)
        source_path = self.root / 'src/fix_plan.zig'
        original = source_path.read_bytes()
        source_path.write_bytes(b'mutation')
        source_path.write_bytes(original)
        self.assertFalse(binary.unchanged())
        self.assertFalse(source.unchanged())

    def test_mutation_during_metadata_capture_rejected(self):
        real_scan = producers.closure_supported
        calls = []
        def mutate_on_recheck(root, label):
            calls.append(label)
            if len(calls) == 2:
                path = root / 'src/fix_plan.zig'
                original = path.read_bytes()
                path.write_bytes(b'mutation')
                path.write_bytes(original)
            return real_scan(root, label)
        with patch.object(producers, 'closure_supported', side_effect=mutate_on_recheck):
            with self.assertRaises((ValueError, SnapshotError)):
                producers.producer_metadata(self.root, 'tooling-units', self.artifact, 'Debug')

    def test_equivalent_second_worktree_producer_identity(self):
        other = self.root / 'other-tree'
        shutil.copytree(self.root / 'src', other / 'src')
        artifact = other / 'separate-cache' / 'tooling'
        artifact.parent.mkdir()
        shutil.copyfile(self.artifact, artifact)
        artifact.chmod(0o755)
        record = {'version': 2, 'artifacts': {'tooling-units': str(artifact)},
                  'producers': {'tooling-units': producers.producer_metadata(other, 'tooling-units', artifact, 'Debug')}}
        binary, source = self.identities(other, artifact)
        self.assertEqual(producers.qualified_identity(record, 'tooling-units', binary, source, self.context), self.qualify())

    def test_text_scalar_embedded_oracle_identity_and_new_dependency_fallback(self):
        for name in producers.CLOSURES['text-scalar-units']:
            target = self.root / name
            if name == 'src/text_scalar_root_test.zig':
                target.write_text('test { _ = @import("number_text.zig"); _ = @import("number_text_test.zig"); _ = @import("format_spec_test.zig"); }')
            else:
                shutil.copyfile(ROOT / name, target)
        before = producers.producer_metadata(self.root, 'text-scalar-units', self.artifact, 'Debug')
        self.assertEqual(len(before['sources']), 7)
        oracle = self.root / 'src/number_grammar.txt'
        oracle.write_text(oracle.read_text() + '\nnew oracle case\n')
        changed = producers.producer_metadata(self.root, 'text-scalar-units', self.artifact, 'Debug')
        self.assertNotEqual(changed, before)
        root = self.root / 'src/text_scalar_root_test.zig'
        root.write_text(root.read_text() + '\nconst extra = @embedFile("new_oracle.txt");')
        self.assertIsNone(producers.producer_metadata(self.root, 'text-scalar-units', self.artifact, 'Debug'))

    def test_writer_atomic_v2_inventory_and_invalid_labels(self):
        output = self.root / 'artifacts.json'
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/verification_artifacts.py'),
                                 str(output), '--qualify', 'tooling-units', 'Debug',
                                 'tooling-units', str(self.artifact)], cwd=self.root, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        record = json.loads(output.read_text())
        self.assertEqual(record['version'], 2)
        self.assertIsNotNone(self.qualify(record))
        with self.assertRaises(SystemExit):
            verification_artifacts.main([str(output), 'bad', str(self.artifact), 'bad', str(self.artifact)])
        self.assertEqual(json.loads(output.read_text()), record)

    def test_publication_mutation_cannot_publish_success_from_manifest_alone(self):
        binary = self.stack.enter_context(Snapshot(self.root, [], [self.artifact]))
        sources = self.stack.enter_context(Snapshot(self.root, list(producers.CLOSURES['tooling-units'])))
        identity = producers.qualified_identity(self.record, 'tooling-units', binary.identity['files'], sources.identity['files'], self.context)
        self.assertIsNotNone(identity)
        self.artifact.write_bytes(b'replaced before publication')
        self.assertFalse(all(snapshot.unchanged() for snapshot in (binary, sources)))


if __name__ == '__main__':
    unittest.main()
