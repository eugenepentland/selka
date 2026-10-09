#!/usr/bin/env python3
"""Pin source extraction, staging validation and guarded atomic replacement."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
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
    default = Path(tempfile.gettempdir()).resolve()
    return REPO.parent if default.is_relative_to(REPO) else None


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
    const files = .{ .{ .path = "lib.my", .data = library }, .{ .path = "main.my", .data = entry } };
}
'''
        blocks = migration.extract_sources(self.root / 'sample.zig', text)
        self.assertEqual([b.guest_path for b in blocks], ['lib.my', 'main.my'])
        self.assertEqual(blocks[0].scope, blocks[1].scope)

    def test_ambiguous_binding_and_incidental_strings_do_not_guess(self):
        text = 'const library =\n    \\\\func helper() -> int:\n    \\\\    return 0\n;\nconst files = .{ .{ .path = "a.my", .data = library }, .{ .path = "b.my", .data = library } };\n'
        block = migration.extract_sources(self.root / 'sample.zig', text)[0]
        self.assertIn('ambiguous', block.unsafe)
        plain = migration.extract_sources(self.root / 'plain.zig', 'const hint = "unrelated.my";\nconst helper =\n    \\\\func helper() -> int:\n    \\\\    return 0\n;\n')[0]
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
        source = self.root / 'main.my'
        original = 'def main() -> int:\n    return 0\n# fail-validation\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original)

    def test_failed_embedded_block_prevents_partial_host_write(self):
        source = self.root / 'guide.md'
        original = '```mylang\ndef first() -> int:\n    return 0\n```\n```mylang\ndef second() -> int:\n    return 0\n# fail-validation\n```\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original)

    def test_explicit_skip_and_fix_migration_paths_are_excluded(self):
        block = migration.extract_sources(self.root / 'guide.md', '```mylang\n# migrate-embedded: skip rejection witness\ndef main():\n```\n')[0]
        self.assertIn('explicit', block.excluded)
        source = self.root / 'test/fixtures/fix-migration/old.my'
        source.parent.mkdir(parents=True)
        source.write_text('def main():\n    return 0\n')
        selected, excluded = migration.collect_paths([source], root=self.root)
        self.assertEqual(selected, [])
        self.assertEqual(len(excluded), 1)

    def test_external_file_below_host_cache_is_migrated_and_validation_runs(self):
        directory = self.root / '.cache/task'
        directory.mkdir(parents=True)
        source = directory / 'main.my'
        source.write_text('def main() -> int:\n    return 0\n')
        self.assertEqual(self.run_main(source), 0)
        self.assertIn('func main', source.read_text())
        original = 'def main() -> int:\n    return 0\n# fail-validation\n'
        source.write_text(original)
        self.assertEqual(self.run_main(source), 1)
        self.assertEqual(source.read_text(), original)

    def test_external_tree_ignores_host_cache_but_preserves_selected_protected_subtrees(self):
        directory = self.root / '.cache/project'
        live = directory / 'main.my'
        protected = directory / 'history/old.my'
        fixture = directory / 'test/fixtures/fix-migration/old.my'
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
        source = self.root / 'live.my'
        source.write_bytes(b'original')
        source.chmod(0o640)
        migration.atomic_write(source, b'validated', b'original')
        self.assertEqual(source.read_bytes(), b'validated')
        self.assertEqual(source.stat().st_mode & 0o777, 0o640)
        self.assertRaises(ValueError, migration.atomic_write, source, b'overwrite', b'original')
        self.assertEqual(source.read_bytes(), b'validated')

    def test_failed_atomic_replace_keeps_original_and_cleans_stage(self):
        source = self.root / 'live.my'
        source.write_bytes(b'original')
        with mock.patch.object(migration.os, 'replace', side_effect=OSError('replace failed')):
            self.assertRaises(OSError, migration.atomic_write, source, b'validated', b'original')
        self.assertEqual(source.read_bytes(), b'original')
        self.assertEqual(list(self.root.glob('.live.my.*')), [])

    def test_census_sidecar_is_exact_and_stale_evidence_fails(self):
        source = self.root / 'witness.my'
        text = 'class Old:\n    value: int\n'
        source.write_text(text)
        target = {'row': 'A8', 'spelling': 'class', 'reason': 'Intentional rejection witness.'}
        manifest = {'version': 'intentional-a8-v1', 'sources': {'witness.my': {'sha256': hashlib.sha256(text.encode()).hexdigest(), 'target': target}}}
        (self.root / 'spelling-census.json').write_text(json.dumps(manifest))
        block = migration.extract_sources(source)[0]
        self.assertIn('intentional census', block.excluded)
        source.write_text(text + '\n')
        self.assertRaises(ValueError, spelling_census.sidecar, source, source.read_text())


if __name__ == '__main__':
    unittest.main()
