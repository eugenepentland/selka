#!/usr/bin/env python3
"""Protection regressions for broad wave-1 migration selection."""
from pathlib import Path
import tempfile
import json
import hashlib
from unittest.mock import patch
import unittest
import migrate_embedded as migration
import regenerate_language_wave1 as regeneration

class ProtectionTests(unittest.TestCase):
    def test_reviewed_tuple_original_groups_are_exact_and_protected(self):
        evidence = migration.ROOT / 'experiments/language-wave1-20261014/L10/R3'
        manifest = json.loads((evidence / 'L08-protected-diagnostic-inputs.json').read_text())
        self.assertEqual(len(manifest['inputs']), 21)
        for row in manifest['inputs']:
            path = migration.ROOT / row['path']
            with self.subTest(path=row['path'], digest=row['guest_sha256']):
                matches = [b for b in migration.extract_sources(path)
                           if hashlib.sha256(b.text.encode()).hexdigest() == row['guest_sha256']]
                self.assertTrue(matches)
                self.assertTrue(migration.path_exclusion(path) or all(b.excluded for b in matches))
        path = migration.ROOT / 'src/tuple_retirement_before.zig'
        originals = json.loads((evidence / 'L08-original-record-key-inputs.json').read_text())
        texts = [b.text for b in migration.extract_sources(path)]
        self.assertIsNotNone(migration.path_exclusion(path))
        for row in originals:
            self.assertIn(row['source'], texts)
        self.assertIsNone(migration.path_exclusion(migration.ROOT / 'src/prelude_builtins_test.zig'))

    def test_protected_trees_and_live_components(self):
        for name in ('experiments/probe.my', 'docs/audits/probe.md', 'docs/design/probe.md',
                     'docs/adr/probe.md', 'test/fixtures/fix-migration/old.selka',
                     '.selka-mut-modules/a.selka', 'tests/lang/.selka-mut-modules/a.selka',
                     'selfhost/parser.selka', 'velocity/suites/idioms/sort.my', 'test/fixtures/rejected.selka',
                     'tests/fixtures/idioms/ternary.selka',
                     'velocity/devspeed-trials-20260923/results/friction/T2-mylangprimer.md',
                     'velocity/devspeed-trials-20260923/kit/PRIMER.md',
                     'src/core/a02_public_constructors_original.selka',
                     'src/wave1_c0_negative_captures_test.zig',
                     'src/core/r3_effect_fixture_before_test.zig'):
            with self.subTest(name=name):
                self.assertIsNotNone(migration.path_exclusion(migration.ROOT / name))
        for name in ('selfhost/components/cache_plan/tests.selka', 'velocity/suites/live/sort.my',
                     'docs/functions.md', 'src/callbacks_test.zig', 'tests/lang/a04_numeric_format_ownership.selka',
                     'tests/lang/format_specs.selka', 'test/core/row_float_format.selka'):
            with self.subTest(name=name):
                self.assertIsNone(migration.path_exclusion(migration.ROOT / name))

    def test_default_roots_select_live_guests_and_preserve_mixed_verifier_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = {'src/stdlib/local.selka', 'tests/ported/old.selka', 'tests/value_semantics/nested.selka',
                    'tests/stress/recursive.selka', 'tests/verification/smoke.selka',
                    'test/fixtures/domains.selka', 'tests/fixtures/interfaces/main.selka',
                    'test/fixtures/application-cache/application.selka',
                    'test/fixtures/environment.selka', 'test/fixtures/external-capabilities.selka',
                    'test/fixtures/mutation-markers.selka', 'test/fixtures/resource-io.selka',
                    'test/fixtures/resources.selka',
                    'tests/fixtures/module_projects/core/shapes.selka',
                    'tests/fixtures/incremental/model.selka', 'tests/fixtures/interfaces_generic/items.selka',
                    'src/core/a02_indirect_owned_fixture.selka',
                    'src/core/a02_public_constructors_fixture.selka',
                    'src/core/a02_scalar_child_fixture.selka',
                    'src/core/a02_scalar_child_reduced.selka',
                    'src/core/a05_scalar_mut_fixture.selka',
                    'src/core/a07_lifecycle_fixture.selka',
                    'src/core/compact_sret_narrow.selka',
                    'src/core/gap_sort_fixture.selka'}
            outside = {'test/fixtures/rejected.selka', 'tests/fixtures/other_graph.selka',
                       'tests/verification/mistyped.selka',
                       'src/core/list_exchange_sibling_fixture.selka',
                       'src/core/list_exchange_sibling_zero_fixture.selka',
                       'src/core/list_exchange_wide_discard_fixture.selka'}
            for name in live | outside:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('func main() -> int:\n    return 1\n')
            roots = [root / name for name in regeneration.LIVE_ROOTS if (root / name).exists()]
            selected, _ = migration.collect_paths(roots, root=root)
            self.assertEqual({path.relative_to(root).as_posix() for path in selected}, live)
            verifier, excluded = migration.collect_paths([root / 'tests/verification'], root=root)
            self.assertEqual(verifier, [root / 'tests/verification/smoke.selka'])
            self.assertTrue(any(item['path'].endswith('mistyped.selka') for item in excluded))

    def test_component_directory_selects_live_sources_and_preserves_legacy_seed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / 'selfhost/components/cache_plan/main.selka'
            legacy = root / 'selfhost/parser.selka'
            live.parent.mkdir(parents=True)
            for path in (live, legacy):
                path.write_text('func main() -> int:\n    return 0\n')
            selected, excluded = migration.collect_paths([root / 'selfhost/components'], root=root)
            self.assertEqual(selected, [live])
            self.assertEqual(excluded, [])
            selected, excluded = migration.collect_paths([root / 'selfhost'], root=root)
            self.assertEqual(selected, [live])
            self.assertTrue(any(item['path'] == str(legacy) for item in excluded))

    def test_diagnostic_fence_stays_exact_and_acceptance_is_selected(self):
        original = '# doc: expect-error E_UNKNOWN_TYPE\nfunc main():\n    const x: Missing = 1\n'
        host = '```selka\n'+original+'```\n\n```selka\nfunc main():\n    const x = [1] * 3\n```\n'
        blocks = migration.extract_sources(migration.ROOT / 'docs/functions.md', host)
        self.assertEqual(len(blocks), 2)
        self.assertEqual(blocks[0].text, original)
        self.assertIsNotNone(blocks[0].excluded)
        self.assertIsNone(blocks[1].excluded)

    def test_zig_rejection_preserved_acceptance_remains_live(self):
        rejected = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, 'func main():\n    const x = [1] * 3\n')
        migration.mark_block(rejected, 'try expectError("E_TYPE", source);')
        self.assertIsNotNone(rejected.excluded)
        message_rejection = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, rejected.text)
        migration.mark_block(message_rejection, 'try reject(source, "wrong argument type");')
        self.assertIsNotNone(message_rejection.excluded)
        old_fix = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, rejected.text)
        migration.mark_block(old_fix, 'try migrated(allocator,')
        self.assertIsNotNone(old_fix.excluded)
        accepted = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, rejected.text)
        migration.mark_block(accepted, 'try run(source);')
        self.assertIsNone(accepted.excluded)
        adjacent_acceptance = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, rejected.text)
        migration.mark_block(adjacent_acceptance, 'try accepts(try rejects("E_TYPE", other);', before_context='try accepts(')
        self.assertIsNone(adjacent_acceptance.excluded)

    def test_following_fixture_marker_does_not_skip_prior_success(self):
        block = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, 'func main() -> int:\n    return 1\n')
        before = 'try run(allocator, '
        migration.mark_block(block, before+'), 1);\n// migrate-embedded: skip next fixture\n', before_context=before)
        self.assertIsNone(block.excluded)

    def test_positive_run_and_result_do_not_inherit_next_rejection(self):
        for helper in ('run', 'result', 'executes'):
            block = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, 'func main() -> int:\n    return 1\n')
            before = 'try '+helper+'(allocator, '
            migration.mark_block(block, before+'), 1);\ntry reject(', before_context=before)
            self.assertIsNone(block.excluded)

    def test_long_adjacent_skip_marks_only_its_quoted_source(self):
        host = '// migrate-embedded: skip '+('reason ' * 40)+'\n'
        host += 'try custom("func main() -> int:\\n    return 1\\n");\n'
        host += '\n' * 8 + 'try custom("func main() -> int:\\n    return 2\\n");\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/quoted_test.zig', host)
        self.assertEqual(len(blocks), 2)
        self.assertIsNotNone(blocks[0].excluded)
        self.assertIsNone(blocks[1].excluded)

    def test_refusal_helpers_preserve_original_negative_source(self):
        for helper in ('refuses', 'refusedBinding'):
            with self.subTest(helper=helper):
                block = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1,
                                              'func main() -> int:\n    return if True then 1 else 2\n')
                migration.mark_block(block, 'try '+helper+'(allocator, source, "E_TYPE");')
                self.assertIsNotNone(block.excluded)

    def test_diagnostic_table_metadata_protects_original_source(self):
        slash = chr(92) * 2
        host = '.{ .source =\n    '+slash+'func main() -> int:\n    '+slash+'    return 1\n, .diagnostic = "OVERLAP" },\n'
        block = migration.extract_sources(migration.ROOT / 'src/table_test.zig', host)[0]
        self.assertEqual(block.excluded, 'intentional Zig diagnostic table input')

    def test_named_negative_provenance_tracks_outcome_without_skipping_success(self):
        slash = chr(92) * 2
        source = lambda name, value: 'const '+name+' =\n    '+slash+'func main() -> int:\n    '+slash+'    return '+value+'\n;\n'
        host = source('bad', '1') + source('good', '2')
        host += 'test "mixed" {\n    _ = try check(good);\n    try t.expectError(error.OutOfMemory, compileFailingAllocator(good));\n    const outcome = check(bad);\n    try t.expectError(error.SourceError, outcome);\n}\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/mixed_test.zig', host)
        self.assertIsNotNone(blocks[0].excluded)
        self.assertIsNone(blocks[1].excluded)

    def test_named_runtime_fixture_is_traced_without_neighbor_acceptance(self):
        slash = chr(92) * 2
        fixture = lambda name: 'const '+name+' =\n    '+slash+'func main() -> int:\n    '+slash+'    return 1\n;\n'
        host = fixture('negative') + fixture('positive')
        host += 'test "both" {\n    try invoke("run", positive, 0, "1", "");\n    try invoke("run", negative, 1, "", "R_LIST_BOUNDS");\n}\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/runtime_test.zig', host)
        self.assertIsNotNone(blocks[0].excluded)
        self.assertIsNone(blocks[1].excluded)

    def test_named_local_provenance_does_not_cross_same_named_positive_scope(self):
        slash = chr(92) * 2
        source = '    const source: []const u8 =\n        '+slash+'func main() -> int:\n        '+slash+'    return 1\n    ;\n'
        host = 'test "negative" {\n'+source+'    try t.expectError(error.SourceError, check(source));\n}\n'
        host += 'test "positive" {\n'+source+'    _ = try check(source);\n}\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/local_test.zig', host)
        self.assertIsNotNone(blocks[0].excluded)
        self.assertIsNone(blocks[1].excluded)

    def test_runtime_trap_and_exact_core_fixture_paths_are_protected(self):
        block = migration.SourceBlock(Path('test.zig'), 'zig', 0, 1, 'func main():\n    return 1\n')
        migration.mark_block(block, ', 1, "", "R_LIST_BOUNDS");')
        self.assertIsNotNone(block.excluded)
        for name in migration.PRESERVED_CORE_FIXTURES:
            self.assertIsNotNone(migration.path_exclusion(migration.ROOT / name))
        self.assertIsNone(migration.path_exclusion(migration.ROOT / 'tests/lang/list_exchange.selka'))

    def test_mixed_host_preserves_only_excluded_block_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / 'mixed.md'
            protected = '```selka\n# doc: expect-error E_TYPE\nfunc bad():\n    const x: int = "wrong"\n```\n'
            accepted = '```selka\nfunc good():\n    const x = [1] * 3\n```\n'
            path.write_text(protected + accepted)
            before = regeneration.protected_snapshot(root, ['mixed.md'])
            self.assertNotIn('mixed.md', before['files'])
            path.write_text(protected + accepted.replace('[1] * 3', 'lists.filled(3, 1)'))
            self.assertEqual(before, regeneration.protected_snapshot(root, ['mixed.md']))
            path.write_text((protected + accepted).replace('"wrong"', '"changed"'))
            self.assertNotEqual(before, regeneration.protected_snapshot(root, ['mixed.md']))

    def test_publication_is_tracked_only_and_seed_components_are_manual(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selected = []
            for name in ('live.selka', 'scratch.selka', 'selfhost/components/test.selka'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('func main():\n    pass\n')
                selected.append(path)
            self.assertEqual(regeneration.tracked_live_sources(selected, ['live.selka', 'selfhost/components/test.selka'], root), [root / 'live.selka'])

    def test_embedded_tracked_filter_preserves_untracked_hosts(self):
        with tempfile.TemporaryDirectory(dir=migration.ROOT / 'test', prefix='wave1-selection-') as temporary:
            root = Path(temporary)
            tracked = root / 'tracked.md'
            scratch = root / 'scratch.md'
            tracked.write_text('```selka\n# doc: expect-error E_TYPE\nfunc bad():\n    pass\n```\n')
            original = '```selka\nfunc main():\n    const x = [1] * 2\n```\n'
            scratch.write_text(original)
            report = root / 'receipt.json'
            with patch.object(migration, 'ROOT', root), patch.object(migration.subprocess, 'check_output', return_value=b'tracked.md\0'):
                status = migration.main([str(root), '--tracked-only', '--compiler', '/nonexistent/compiler', '--report', str(report)])
            self.assertEqual(status, 0)
            self.assertEqual(scratch.read_text(), original)
            receipt = json.loads(report.read_text())
            self.assertTrue(any(item['reason'] == 'untracked source' for item in receipt['excluded']))

    def test_preceding_reject_helper_does_not_exclude_new_global_acceptance(self):
        slash = chr(92) * 2
        host = 'fn reject() !void {\n    try t.expectError(error.SourceError, check());\n}\nconst accepted =\n    '+slash+'func main() -> int:\n    '+slash+'    return 1\n;\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/example_test.zig', host)
        self.assertEqual(len(blocks), 1)
        self.assertIsNone(blocks[0].excluded)

    def test_skip_comment_before_global_declaration_is_retained(self):
        slash = chr(92) * 2
        host = '// migrate-embedded: skip intentional legacy diagnostic provider\nconst source =\n    '+slash+'domain D: int:\n    '+slash+'    pass\n;\n'
        blocks = migration.extract_sources(migration.ROOT / 'src/example_test.zig', host)
        self.assertEqual(len(blocks), 1)
        self.assertIsNotNone(blocks[0].excluded)

    def test_collection_prunes_hidden_and_frozen_subdirectories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ('velocity/suites/idioms/a.selka', 'velocity/suites/live/a.selka',
                         'tests/lang/.selka-mut-modules/a.selka', '.tmp-any-worker/a.selka', '.cache-other/a.selka', 'tests/lang/a.selka'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('func main():\n    pass\n')
            selected, excluded = migration.collect_paths([root], root=root)
            self.assertEqual([path.relative_to(root).as_posix() for path in selected],
                             ['tests/lang/a.selka', 'velocity/suites/live/a.selka'])
            self.assertEqual(len(excluded), 4)

if __name__ == '__main__':
    unittest.main()
