from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.dependency_audit import audit


class DependencyAuditTests(unittest.TestCase):
    def test_python_shadowing_and_dynamic_loading_are_not_hidden(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'main.py').write_text('import json\nimport importlib\n')
            (root / 'json.py').write_text('import third_party\n')
            result = audit(root, 'python', 'main.py')
            self.assertIn('json.py', result['files'])
            self.assertEqual(len(result['review_required']), 2)
            self.assertFalse(result['stdlib_only_proven'])
            (root / 'json').mkdir()
            (root / 'json/__init__.py').write_text('import another_dependency')
            result = audit(root, 'python', 'main.py')
            self.assertIn('json/__init__.py', result['files'])
            self.assertNotIn('json.py', result['files'])

    def test_comments_do_not_create_dependencies_and_escapes_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'project'
            root.mkdir()
            (root / 'main.zig').write_text('// @import("missing");\nconst s = @import("std");')
            self.assertEqual(audit(root, 'zig', 'main.zig')['edges'], [{'file':'main.zig', 'target':'std', 'kind':'stdlib'}])
            (root.parent / 'outside.zig').write_text('')
            (root / 'main.zig').write_text('const x = @import("../outside.zig");')
            with self.assertRaisesRegex(ValueError, 'leaves source root'):
                audit(root, 'zig', 'main.zig')

    def test_my_host_declaration_requires_review(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'main.my').write_text('module main; host fn route() -> i64 effects(host);')
            self.assertEqual(len(audit(root, 'my', 'main.my')['review_required']), 1)


if __name__ == '__main__':
    unittest.main()
