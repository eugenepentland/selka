#!/usr/bin/env python3
"""Pin source extraction, staging validation and guarded atomic replacement."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'scripts'))
import migrate_embedded as migration
import spelling_census


def scratch_parent():
    """A directory for scratch trees that lies outside this checkout.

    The external-tree tests need their sources outside the repository: under a
    TMPDIR inside the checkout (as agent worktrees use) every scratch path would
    be repository-relative and take the repository's exclusions.
    """
    default = Path(tempfile.gettempdir()).absolute()
    return REPO.parent if default.is_relative_to(REPO) or default.resolve().is_relative_to(REPO) else None


class EmbeddedMigrationTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(dir=scratch_parent())
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.compiler = self.root / 'compiler'
        self.compiler.write_text('''#!/usr/bin/env python3
import pathlib, sys
p = pathlib.Path(sys.argv[-1])
text = p.read_text()
if sys.argv[1] == 'fix':
    p.write_text(text.replace('def ', 'func '))
    sys.exit(0)
sys.exit(1 if '# fail-validation' in text else 0)
''')
        self.compiler.chmod(0o755)

    def run_main(self, source):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return migration.main(['--compiler', str(self.compiler), str(source)])

    def test_func_multiline_and_inline_sources_are_recognized(self):
        text = 'const a =\n    \\\\func main() -> int:\n    \\\\    return 0\n;\nconst text = "func main() -> int:\\n    return 0\\n";\n'
        blocks = migration.extract_sources(self.root / 'sample.zig', text)
        self.assertEqual([b.kind for b in blocks], ['zig', 'zig-inline'])
        self.assertTrue(all('func main' in b.text for b in blocks))

    def test_headerless_provider_paths_group_explicitly(self):
        text = '''test "provider" {
    const library =
        \\\\public func answer() -> int:
        \\\\    return 7
    ;
    const entry =
        \\\\import lib
        \\\\func main() -> int:
        \\\\    return lib.answer()
    ;
    const files = .{ .{ .path = "lib.selka", .data = library }, .{ .path = "main.selka", .data = entry } };
}
'''
        blocks = migration.extract_sources(self.root / 'sample.zig', text)
        self.assertEqual([b.guest_path for b in blocks], ['lib.selka', 'main.selka'])
        self.assertEqual(blocks[0].scope, blocks[1].scope)

    def test_ambiguous_binding_and_incidental_strings_do_not_guess(self):
        text = 'const library =\n    \\\\func helper() -> int:\n    \\\\    return 0\n;\nconst files = .{ .{ .path = "a.selka", .data = library }, .{ .path = "b.selka", .data = library } };\n'
        block = migration.extract_sources(self.root / 'sample.zig', text)[0]
        self.assertIn('ambiguous', block.unsafe)
        plain = migration.extract_sources(self.root / 'plain.zig', 'const hint = "unrelated.selka";\nconst helper =\n    \\\\func helper() -> int:\n    \\\\    return 0\n;\n')[0]
        self.assertIsNone(plain.guest_path)

    def test_json_migration_keeps_case_ids_options_and_outcomes_bytes(self):
        source = self.root / 'cases.json'
        text = '{ "entries": { "case-id": { "case": ["def main() -> int:\\n    return 0\\n", ["--release"]], "stdout": "AA==", "status": 0 } } }\n'
        source.write_text(text)
        self.assertEqual(self.run_main(source), 0)
        updated = source.read_text()
        self.assertEqual(updated, text.replace('def main', 'func main'))
        self.assertEqual(migration.golden_outcomes(text), migration.golden_outcomes(updated))

    def test_failed_staged_validation_never_writes_source(self):
        source = self.root / 'main.selka'
        original = 'def main() -> int:\n    return 0\n# fail-validation\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original)

    def test_failed_independent_embedded_block_preserves_failed_source_and_publishes_safe_neighbor(self):
        source = self.root / 'guide.md'
        original = '```selka\ndef first() -> int:\n    return 0\n```\n```selka\ndef second() -> int:\n    return 0\n# fail-validation\n```\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original.replace('def first', 'func first'))

    def test_explicit_skip_and_fix_migration_paths_are_excluded(self):
        block = migration.extract_sources(self.root / 'guide.md', '```selka\n# migrate-embedded: skip rejection witness\ndef main():\n```\n')[0]
        self.assertIn('explicit', block.excluded)
        source = self.root / 'test/fixtures/fix-migration/old.selka'
        source.parent.mkdir(parents=True)
        source.write_text('def main():\n    return 0\n')
        selected, excluded = migration.collect_paths([source], root=self.root)
        self.assertEqual(selected, [])
        self.assertEqual(len(excluded), 1)

    def test_external_file_below_host_cache_is_migrated_and_validation_runs(self):
        directory = self.root / '.cache/task'
        directory.mkdir(parents=True)
        source = directory / 'main.selka'
        source.write_text('def main() -> int:\n    return 0\n')
        self.assertEqual(self.run_main(source), 0)
        self.assertIn('func main', source.read_text())
        original = 'def main() -> int:\n    return 0\n# fail-validation\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original)

    def test_external_tree_ignores_host_cache_but_preserves_selected_protected_subtrees(self):
        directory = self.root / '.cache/project'
        live = directory / 'main.selka'
        protected = directory / 'history/old.selka'
        fixture = directory / 'test/fixtures/fix-migration/old.selka'
        protected.parent.mkdir(parents=True)
        fixture.parent.mkdir(parents=True)
        live.write_text('func main() -> int:\n    return 0\n')
        protected.write_text('def old():\n')
        fixture.write_text('def old():\n')
        selected, excluded = migration.collect_paths([directory])
        self.assertEqual(selected, [live.absolute()])
        self.assertEqual(len(excluded), 2)
        selected_cache, exclusions = migration.collect_paths([directory.parent])
        self.assertEqual(selected_cache, [])
        self.assertEqual(len(exclusions), 1)
        internal, protections = migration.collect_paths([live], root=self.root)
        self.assertEqual(internal, [])
        self.assertEqual(len(protections), 1)

    def test_atomic_replace_preserves_mode_and_refuses_concurrent_edits(self):
        source = self.root / 'live.selka'
        source.write_bytes(b'original')
        source.chmod(0o640)
        migration.atomic_write(source, b'validated', b'original')
        self.assertEqual(source.read_bytes(), b'validated')
        self.assertEqual(source.stat().st_mode & 0o777, 0o640)
        self.assertRaises(ValueError, migration.atomic_write, source, b'overwrite', b'original')
        self.assertEqual(source.read_bytes(), b'validated')

    def test_failed_atomic_replace_keeps_original_and_cleans_stage(self):
        source = self.root / 'live.selka'
        source.write_bytes(b'original')
        with mock.patch.object(migration.os, 'replace', side_effect=OSError('replace failed')):
            self.assertRaises(OSError, migration.atomic_write, source, b'validated', b'original')
        self.assertEqual(source.read_bytes(), b'original')
        self.assertEqual(list(self.root.glob('.live.selka.*')), [])

    def test_census_sidecar_is_exact_and_stale_evidence_fails(self):
        source = self.root / 'witness.selka'
        text = 'class Old:\n    value: int\n'
        source.write_text(text)
        target = {'row': 'A8', 'spelling': 'class', 'reason': 'Intentional rejection witness.'}
        manifest = {'version': 'intentional-a8-v1', 'sources': {'witness.selka': {'sha256': hashlib.sha256(text.encode()).hexdigest(), 'target': target}}}
        (self.root / 'spelling-census.json').write_text(json.dumps(manifest))
        block = migration.extract_sources(source)[0]
        self.assertIn('intentional census', block.excluded)
        source.write_text(text + '\n')
        self.assertRaises(ValueError, spelling_census.sidecar, source, source.read_text())


class PublicationTests(unittest.TestCase):
    """The compiler boundary is deterministic; staging and publication are real."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=scratch_parent(), prefix='migration-publication-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assertFalse(self.root.absolute().is_relative_to(REPO))
        self.assertFalse(self.root.resolve().is_relative_to(REPO))
        self.path = self.root / 'mixed.zig'
        self.calls = []

    @staticmethod
    def host(sources, modules=False):
        slash = chr(92) * 2
        parts = ['const '+name+' =\n'+''.join('    '+slash+line+'\n' for line in text.splitlines())+';\n'
                 for name, text in sources.items()]
        if modules:
            parts.append('const files = .{\n'+''.join(
                '    .{ .path = "'+name+'.selka", .data = '+name+' },\n' for name in sources)+'};\n')
        return '\n'.join(parts)

    def run_driver(self, action=None, dry_run=False, include_excluded=False):
        def invoke(migrator, phase, target, stage, block):
            self.calls.append((phase, target.name))
            if action is not None:
                code = action(phase, target, stage)
            elif 'broken' in target.read_text():
                code = 1
            else:
                if phase == 'fix':
                    target.write_text(target.read_text().replace('= source', '= own source'))
                code = 0
            result = subprocess.CompletedProcess([phase], code, '', 'fixture check failed' if code else '')
            receipt = {'source': block.label, 'phase': phase, 'exit_code': code,
                       'stdout': result.stdout, 'stderr': result.stderr}
            migrator.receipts.append(receipt)
            return result, receipt

        report = self.root / 'report.json'
        args = [str(self.path), '--compiler', '/unused/compiler', '--report', str(report)]
        if dry_run:
            args.append('--dry-run')
        if include_excluded:
            args.append('--include-excluded')
        with mock.patch.object(migration.Migrator, 'invoke', invoke), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            status = migration.main(args)
        return status, json.loads(report.read_text())

    def test_safe_block_publishes_despite_unrelated_quoted_source_and_rerun_has_no_fixes(self):
        good = 'func main() -> int:\n    mut live = source\n    return 0'
        quoted = 'const quoted = "func quote() -> int:\\n    return 0\\n";\n'
        self.path.write_text(self.host({'good': good})+quoted)
        status, report = self.run_driver()
        self.assertEqual(status, 1)
        self.assertIn('mut live = own source', self.path.read_text())
        self.assertTrue(self.path.read_text().endswith(quoted))
        self.assertEqual(len(report['changes']), 1)
        self.assertEqual(len(report['unsafe']), 1)
        self.assertEqual(report['pending_changes'], [])
        self.assertFalse(report['no_pending_validated_fixes'])
        status, repeated = self.run_driver()
        self.assertEqual(status, 1)  # unresolved quoted setup remains explicit
        self.assertEqual(repeated['changes'], [])
        self.assertEqual(repeated['validated_fixes'], [])
        self.assertTrue(repeated['no_pending_validated_fixes'])

    def test_failed_independent_block_and_protected_diagnostic_remain_exact(self):
        good = self.host({'good': 'func main():\n    mut live = source'})
        broken = self.host({'bad': 'func broken():\n    mut live = source'})
        protected = '// migrate-embedded: skip intentional negative subject\n'+self.host(
            {'negative': 'func negative():\n    mut live = source'})
        self.path.write_text(good+broken+protected)
        status, report = self.run_driver()
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), good.replace('= source', '= own source')+broken+protected)
        self.assertEqual(len(report['changes']), 1)
        self.assertEqual(len(report['excluded']), 1)
        self.assertEqual(len(report['unsafe']), 1)

    def test_dry_run_reports_independent_proposal_without_writing_host(self):
        original = self.host({'good': 'func main():\n    mut live = source', 'bad': 'func broken():\n    pass'})
        self.path.write_text(original)
        status, report = self.run_driver(dry_run=True)
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(len(report['changes']), 1)
        self.assertEqual(len(report['validated_fixes']), 1)
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_conflicting_sibling_bundles_leave_host_and_pending_proposals_intact(self):
        original = self.host({'first': 'import shared\nfunc main():\n    pass',
                              'second': 'import shared\nfunc main():\n    pass',
                              'shared': 'public func value() -> int:\n    return 1'}, modules=True)
        self.path.write_text(original)

        def action(phase, target, stage):
            if phase == 'fix' and target.stem in ('first', 'second'):
                (stage / 'shared.selka').write_text('public func value() -> int:\n    return '+('2' if target.stem == 'first' else '3'))
            return 0

        status, report = self.run_driver(action)
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 1)
        self.assertEqual(len(report['validated_fixes']), 2)
        self.assertFalse(report['no_pending_validated_fixes'])
        self.assertTrue(any('conflicting' in row['reason'] for row in report['unsafe']))

    def test_overlapping_ranges_reject_whole_bundle_without_partial_merge(self):
        existing = {(4, 8): 'first'}
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            migration.merge_replacements(existing, {(10, 12): 'safe', (6, 9): 'overlap'})
        self.assertEqual(existing, {(4, 8): 'first'})
        migration.merge_replacements(existing, {(4, 8): 'first'})
        with self.assertRaisesRegex(ValueError, 'conflicting'):
            migration.merge_replacements(existing, {(4, 8): 'different'})
        self.assertEqual(existing, {(4, 8): 'first'})

    def test_merged_dependencies_are_rechecked_even_for_original_no_edit_entries(self):
        original = self.host({'first': 'import shared\nfunc main():\n    pass',
                              'second': 'import shared\nfunc main():\n    pass',
                              'shared': 'public func value() -> int:\n    return 1'}, modules=True)
        self.path.write_text(original)

        def action(phase, target, stage):
            if phase == 'fix' and target.stem == 'first':
                shared = stage / 'shared.selka'
                shared.write_text(shared.read_text().replace('return 1', 'return 2'))
            if phase == 'check' and target.stem == 'second' and 'return 2' in (stage / 'shared.selka').read_text():
                return 1
            return 0

        status, report = self.run_driver(action)
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 1)
        self.assertEqual(len(report['validated_fixes']), 1)
        self.assertTrue(any(row.get('publication_validation') and row['exit_code'] == 1 for row in report['commands']))
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_compatible_sibling_edits_publish_only_after_merged_context_checks(self):
        self.path.write_text(self.host({'first': 'import shared\nfunc main():\n    mut live = source',
                                        'second': 'import shared\nfunc main():\n    mut live = source',
                                        'shared': 'public func value() -> int:\n    return 1'}, modules=True))
        def action(phase, target, stage):
            if phase == 'fix':
                target.write_text(target.read_text().replace('= source', '= own source'))
                if target.stem == 'first':
                    shared = stage / 'shared.selka'
                    shared.write_text(shared.read_text().replace('return 1', 'return 2'))
            return 0

        status, report = self.run_driver(action)
        self.assertEqual(status, 0)
        self.assertEqual(self.path.read_text().count('= own source'), 2)
        self.assertIn('return 2', self.path.read_text())
        self.assertEqual(len(report['changes']), 3)
        self.assertEqual(report['pending_changes'], [])
        self.assertTrue(any(row.get('publication_validation') for row in report['commands']))

    def test_imports_introduced_by_fix_participate_in_merged_context_validation(self):
        original = self.host({'first': 'func main():\n    pass',
                              'shared': 'public func value() -> int:\n    return 1'}, modules=True)
        self.path.write_text(original)

        def action(phase, target, stage):
            if phase == 'fix' and target.stem == 'first':
                target.write_text('import shared\n'+target.read_text())
            if phase == 'fix' and target.stem == 'shared':
                target.write_text(target.read_text().replace('return 1', 'return 2'))
            if phase == 'check' and target.stem == 'first' and 'return 2' in (stage / 'shared.selka').read_text():
                return 1
            return 0

        status, report = self.run_driver(action)
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 2)
        self.assertTrue(any(row.get('publication_validation') and row['exit_code'] == 1 for row in report['commands']))
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_failed_importer_blocks_provider_changes_but_unrelated_failures_do_not(self):
        original = self.host({'bad': 'import shared\nfunc broken():\n    pass',
                              'shared': 'public func value():\n    mut live = source'}, modules=True)
        self.path.write_text(original)
        status, report = self.run_driver()
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 1)
        self.assertTrue(any('depends on a proposed module edit' in row['reason'] for row in report['unsafe']))
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_render_failure_retains_validated_scratch_proposal_in_fixed_point_report(self):
        original = self.host({'good': 'func main():\n    mut live = source'})
        self.path.write_text(original)
        with mock.patch.object(migration, 'render_block', side_effect=ValueError('unsupported host envelope')):
            status, report = self.run_driver()
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['validated_fixes']), 1)
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_exclusion_override_keeps_failed_importer_dependency_protection(self):
        bad = self.host({'bad': 'import shared\nfunc broken():\n    pass'})
        shared = '// migrate-embedded: skip protected provider\n'+self.host(
            {'shared': 'public func value():\n    mut live = source'})
        files = 'const files = .{ .{ .path = "shared.selka", .data = shared } };\n'
        original = bad+shared+files
        self.path.write_text(original)
        status, report = self.run_driver(include_excluded=True)
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 1)
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_atomic_write_failure_cannot_appear_as_no_pending_fixes(self):
        original = self.host({'good': 'func main():\n    mut live = source'})
        self.path.write_text(original)
        with mock.patch.object(migration, 'atomic_write', side_effect=ValueError('concurrent source change')):
            status, report = self.run_driver()
        self.assertEqual(status, 1)
        self.assertEqual(self.path.read_text(), original)
        self.assertEqual(report['changes'], [])
        self.assertEqual(len(report['pending_changes']), 1)
        self.assertEqual(len(report['validated_fixes']), 1)
        self.assertFalse(report['no_pending_validated_fixes'])

    def test_json_source_publication_preserves_all_outcome_and_option_fields(self):
        self.path = self.root / 'golden.json'
        before = {'entries': {'case': {'case': ['func main():\n    mut live = source\n', ['--release']],
                                      'returncode': 7, 'stdout': 'unchanged', 'stderr': ''}}}
        self.path.write_text(json.dumps(before))
        status, report = self.run_driver()
        after = json.loads(self.path.read_text())
        self.assertEqual(status, 0)
        self.assertEqual(after['entries']['case']['case'][0], 'func main():\n    mut live = own source\n')
        self.assertEqual(migration.golden_outcomes(json.dumps(before)), migration.golden_outcomes(json.dumps(after)))
        self.assertEqual(len(report['changes']), 1)


if __name__ == '__main__':
    unittest.main()
