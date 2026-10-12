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

    def test_actual_pinned_zig_lowercase_optimize_tags_qualify(self):
        binary, source = self.identities()
        for mode in ('debug', 'release_safe', 'release_fast', 'release_small'):
            record = copy.deepcopy(self.record)
            record['producers']['tooling-units'] = producers.producer_metadata(
                self.root, 'tooling-units', self.artifact, mode)
            context = copy.deepcopy(self.context)
            context['action_controls']['optimize'] = mode
            identity = producers.qualified_identity(record, 'tooling-units', binary, source, context)
            with self.subTest(mode=mode):
                self.assertIsNotNone(identity)
                self.assertEqual(identity['mode'], mode)
        self.assertEqual(self.record['producers']['tooling-units']['mode'], 'debug')

    def test_reviewed_closure_accepts_version_three_inventory_only(self):
        self.assertEqual(self.qualify(dict(self.record, version=3)), self.qualify())
        self.assertIsNone(self.qualify(dict(self.record, version=4)))

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
                             ('abi', 'changed'), ('interface', 'changed'), ('version', 3)]:
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

    def test_writer_atomic_v3_inventory_and_invalid_labels(self):
        output = self.root / 'artifacts.json'
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/verification_artifacts.py'),
                                 str(output), '--qualify', 'tooling-units', 'Debug',
                                 'tooling-units', str(self.artifact)], cwd=self.root, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        record = json.loads(output.read_text())
        self.assertEqual(record['version'], 3)
        self.assertIsInstance(record['artifacts']['tooling-units'], str)
        self.assertIsNotNone(self.qualify(record))
        with self.assertRaises(SystemExit):
            verification_artifacts.main([str(output), 'bad', str(self.artifact), 'bad', str(self.artifact)])
        self.assertEqual(json.loads(output.read_text()), record)

    def test_writer_records_producer_recipes_for_exactly_the_artifacts(self):
        output, recipes = self.root / 'artifacts.json', self.root / 'recipes.json'
        producer = {'recipes': ['build.zig', 'src/'], 'optimize': 'Debug', 'zig_version': '0.17.0',
                    'test_runner': {'kind': 'guardian', 'dependency': 'guardian', 'location': '../guardian-zig',
                                    'runner': 'src/test_runner.zig'}}
        recipes.write_text(json.dumps([{'label': 'units', 'producer': producer}]))
        verification_artifacts.main([str(output), '--producers', str(recipes), 'units', str(self.artifact)])
        record = json.loads(output.read_text())
        self.assertEqual(record['version'], 3)
        self.assertEqual(record['artifacts'], {'units': {'path': str(self.artifact.resolve()), 'producer': producer}})
        self.assertEqual(record['producers'], {})
        with self.assertRaises(SystemExit):
            verification_artifacts.main([str(output), '--producers', str(recipes), 'cli', str(self.artifact)])
        for change in ({'recipes': []}, {'recipes': ['src/', 'src/']}, {'recipes': ['/abs/src/']},
                       {'optimize': ''}, {'test_runner': None}, {'extra': 1}):
            recipes.write_text(json.dumps([{'label': 'units', 'producer': dict(producer, **change)}]))
            with self.subTest(change=change), self.assertRaises(SystemExit):
                verification_artifacts.main([str(output), '--producers', str(recipes), 'units', str(self.artifact)])
        self.assertEqual(json.loads(output.read_text()), record)

    def test_publication_mutation_cannot_publish_success_from_manifest_alone(self):
        binary = self.stack.enter_context(Snapshot(self.root, [], [self.artifact]))
        sources = self.stack.enter_context(Snapshot(self.root, list(producers.CLOSURES['tooling-units'])))
        identity = producers.qualified_identity(self.record, 'tooling-units', binary.identity['files'], sources.identity['files'], self.context)
        self.assertIsNotNone(identity)
        self.artifact.write_bytes(b'replaced before publication')
        self.assertFalse(all(snapshot.unchanged() for snapshot in (binary, sources)))



class NativeProducerTests(unittest.TestCase):
    """Version-3 recipe producers for the native roots (mylang, units, core, cli)."""

    PRODUCER = {'recipes': ['src/', 'build.zig'], 'optimize': 'Debug', 'zig_version': '0.16.0',
                'test_runner': 'guardian-zig-test-runner-v1'}

    def record(self, entry=None, producers=None):
        entry = {'path': '/abs/units', 'producer': copy.deepcopy(self.PRODUCER)} if entry is None else entry
        return {'version': 3, 'artifacts': {'units': entry}, 'producers': producers or {}}

    def test_declared_beside_the_artifact_or_in_producers(self):
        self.assertEqual(producers.native_producer(self.record(), 'units'), (self.PRODUCER, ''))
        listed = self.record('/abs/units', {'units': copy.deepcopy(self.PRODUCER)})
        self.assertEqual(producers.native_producer(listed, 'units'), (self.PRODUCER, ''))
        twice = self.record(producers={'units': copy.deepcopy(self.PRODUCER)})
        self.assertEqual(producers.native_producer(twice, 'units'), (None, 'producer declared twice'))

    def test_missing_or_malformed_producers_fall_back(self):
        self.assertEqual(producers.native_producer(dict(self.record(), version=2), 'units')[0], None)
        self.assertEqual(producers.native_producer(self.record('/abs/units'), 'units'), (None, 'no producer declared'))
        # A reviewed closure in producers (no recipes) is not a native producer.
        closure = self.record('/abs/units', {'units': {'version': 2, 'label': 'units'}})
        self.assertEqual(producers.native_producer(closure, 'units'), (None, 'no producer declared'))
        for change in ({'recipes': []}, {'recipes': ['/abs/src/']}, {'recipes': ['src/', 'src/']},
                       {'recipes': 'src/'}, {'optimize': ''}, {'zig_version': None}, {'test_runner': ''},
                       {'extra': 1}):
            producer = dict(self.PRODUCER, **change)
            with self.subTest(change=change):
                found, reason = producers.native_producer(self.record({'path': '/abs/units', 'producer': producer}), 'units')
                self.assertIsNone(found)
                self.assertTrue(reason)
        without = {name: value for name, value in self.PRODUCER.items() if name != 'test_runner'}
        self.assertIsNone(producers.native_producer(self.record({'path': '/abs/units', 'producer': without}), 'units')[0])

    def files(self, root):
        return {'src/': [{'path': 'src/a.zig', 'sha256': 'a' * 64, 'size': 1, 'mode': 0o644, 'uid': root, 'gid': root}],
                'build.zig': [{'path': 'build.zig', 'sha256': 'b' * 64, 'size': 2, 'mode': 0o644, 'uid': root, 'gid': root}]}

    def test_identity_binds_content_and_producer_fields_but_no_location_or_owner(self):
        first = producers.native_identity('units', self.PRODUCER, self.files(1).__getitem__)
        self.assertEqual(first, producers.native_identity('units', self.PRODUCER, self.files(2).__getitem__))
        self.assertEqual([row['path'] for row in first['sources']], ['build.zig', 'src/a.zig'])
        self.assertNotIn('uid', first['sources'][0])
        for change in ({'optimize': 'ReleaseFast'}, {'zig_version': '0.17.0'}, {'test_runner': 'other'}):
            with self.subTest(change=change):
                self.assertNotEqual(producers.native_identity('units', dict(self.PRODUCER, **change),
                                                              self.files(1).__getitem__), first)
        changed = self.files(1)
        changed['src/'][0]['sha256'] = 'c' * 64
        self.assertNotEqual(producers.native_identity('units', self.PRODUCER, changed.__getitem__), first)

    def test_components_producer_binds_the_seed_pin_and_component_sources(self):
        producer = {'recipes': ['./*.zig', 'selfhost/*.zig', 'selfhost/components/', 'selfhost/component-seed.json'],
                    'optimize': 'debug', 'zig_version': '0.17.0', 'test_runner': {'kind': 'none'}}
        record = {'version': 3, 'producers': {},
                  'artifacts': {'components': {'path': '/abs/components/test-index.json', 'producer': producer}}}
        self.assertEqual(producers.native_producer(record, 'components'), (producer, ''))
        def row(path, digest):
            return {'path': path, 'sha256': digest * 64, 'size': 1, 'mode': 0o644}
        files = {'./*.zig': [row('build.zig', 'a')], 'selfhost/*.zig': [row('selfhost/components.zig', 'b')],
                 'selfhost/components/': [row('selfhost/components/test_index/main.my', 'c')],
                 'selfhost/component-seed.json': [row('selfhost/component-seed.json', 'd')]}
        first = producers.native_identity('components', producer, files.__getitem__)
        self.assertEqual(len(first['sources']), 4)
        files['selfhost/component-seed.json'] = [row('selfhost/component-seed.json', 'e')]
        self.assertNotEqual(producers.native_identity('components', producer, files.__getitem__), first)

    def test_a_recipe_selecting_nothing_is_an_error_not_an_empty_identity(self):
        selections = dict(self.files(1), **{'build.zig': []})
        with self.assertRaisesRegex(producers.ProducerError, 'selects no watched input: build.zig'):
            producers.native_identity('units', self.PRODUCER, selections.__getitem__)



if __name__ == '__main__':
    unittest.main()
