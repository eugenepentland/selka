#!/usr/bin/env python3
"""Only reviewed key namespaces normalize; changed dependencies stay different."""
import copy
import unittest
from verification_planning_timing import semantic_payload


class SemanticComparison(unittest.TestCase):
    def payload(self):
        return {'domain': 'selka-verification-action-v4', 'common': {'version': 1, 'tools': 'pinned-tools'},
                'files': [{'path': 'source', 'sha256': 'content'}], 'membership': {'steps': ['test']}}

    def test_reviewed_migration_normalizes_without_mutating_actual_payload(self):
        old = self.payload()
        new = copy.deepcopy(old)
        new['domain'] = 'selka-verification-action-v5'
        new['common']['version'] = 2
        self.assertEqual(semantic_payload(old), semantic_payload(new))
        self.assertEqual(old['domain'], 'selka-verification-action-v4')
        self.assertEqual(new['common']['version'], 2)

    def test_dependency_member_or_tool_changes_remain_distinct(self):
        old = self.payload()
        for field, value in [('files', []), ('membership', {}), ('common', {'version': 1, 'tools': 'changed'})]:
            new = copy.deepcopy(old)
            new[field] = value
            with self.subTest(field=field):
                self.assertNotEqual(semantic_payload(old), semantic_payload(new))

    def test_unknown_version_or_domain_rejects_comparison(self):
        old = self.payload()
        old['domain'] = 'selka-verification-action-v6'
        with self.assertRaises(ValueError):
            semantic_payload(old)
        old = self.payload()
        old['common']['version'] = 3
        with self.assertRaises(ValueError):
            semantic_payload(old)


if __name__ == '__main__':
    unittest.main()
