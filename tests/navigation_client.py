#!/usr/bin/env python3
"""Actual compiler navigation, bounded queries and source-pinned cross-root cache checks."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import navigate

COMPILER = None
MAIN = 'import lib\n\n\nfunc main() -> i64:\n    return lib.twice(2)\n'
LIB = ('\n\n\nfunc add(x: i64) -> i64:\n    return x + 1\n\n\nfunc twice(x: i64) -> i64:\n    return add(add(x))\n')


class NavigationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='navigation-clients-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'agent one'
        self.root.mkdir()
        (self.root / 'main.my').write_text(MAIN)
        (self.root / 'lib.my').write_text(LIB)
        self.cache = self.base / 'shared-cache'

    def load(self, root=None):
        return navigate.load(COMPILER, (root or self.root) / 'main.my', self.cache)

    def test_actual_definition_calls_types_and_context_bounds(self):
        index, cached = self.load()
        self.assertFalse(cached)
        self.assertTrue(index['checked'])
        definition = navigate.query(index, symbol='lib::twice', type_name='i64')
        self.assertEqual(['lib::twice'], [x['id'] for x in definition['symbols']])
        callers = navigate.query(index, symbol='lib::twice', relation='callers')
        self.assertTrue(any(x['from'] == 'main::main' and x['to'] == 'lib::twice' for x in callers['references']))
        callees = navigate.query(index, symbol='lib::twice', relation='callees')
        self.assertTrue(any(x['to'] == 'lib::add' for x in callees['references']))
        impact = navigate.query(index, symbol='lib::add', relation='impact')
        self.assertIn('main::main', {x['id'] for x in impact['symbols']})
        bounded = navigate.query(index, symbol='lib::twice', relation='context', limit=1, context_bytes=7)
        self.assertLessEqual(sum(len(x['snippet'].encode()) for x in bounded['symbols']), 7)
        self.assertGreater(bounded['omitted_symbols'], 0)
        self.assertEqual([], navigate.query(index, effect='host')['symbols'])

    def test_equivalent_roots_reuse_but_source_errors_never_keep_old_edges(self):
        first, _ = self.load()
        self.assertTrue(self.load()[1])
        other = self.base / 'agent two'
        shutil.copytree(self.root, other)
        self.assertTrue(self.load(other)[1])
        (other / 'lib.my').write_text(LIB.replace('x + 1', 'x + 2'))
        changed, reused = self.load(other)
        self.assertFalse(reused)
        self.assertNotEqual(first['snapshot_sha256'], changed['snapshot_sha256'])
        (other / 'lib.my').write_text(LIB.replace('x + 1', 'True'))
        broken, reused = self.load(other)
        self.assertFalse(reused)
        self.assertFalse(broken['checked'])
        self.assertEqual([], broken['references'])
        self.assertTrue(navigate.query(broken, symbol='lib::add')['symbols'])
        self.assertFalse(navigate.query(broken, relation='impact')['semantic_relations_available'])
        self.assertTrue(self.load(other)[1])
        (other / 'lib.my').write_text(LIB)
        self.assertTrue(self.load(other)[1])
        self.assertTrue(self.load(other)[0]['checked'])

    def test_corrupt_index_receipt_is_regenerated(self):
        original, _ = self.load()
        path = next(self.cache.glob('*.json'))
        wrapper = json.loads(path.read_text())
        wrapper['index']['references'] = []
        path.write_text(json.dumps(wrapper))
        restored, reused = self.load()
        self.assertFalse(reused)
        self.assertEqual(original['references'], restored['references'])

    def test_source_edit_during_generation_rejects_publication(self):
        original = navigate.subprocess.run
        def changed(*args, **kwargs):
            result = original(*args, **kwargs)
            # Edit only while the index itself is generated; the identity query precedes it.
            if 'index-project' in args[0]:
                (self.root / 'lib.my').write_text(LIB.replace('x + 1', 'x + 3'))
            return result
        with patch.object(navigate.subprocess, 'run', changed):
            with self.assertRaisesRegex(ValueError, 'changed during navigation'):
                self.load()
        self.assertFalse(self.cache.exists())

    def test_nonregular_inputs_and_directory_symlinks_do_not_block(self):
        fifo = self.root / 'blocked.my'
        os.mkfifo(fifo)
        with self.assertRaisesRegex(ValueError, 'regular file'):
            self.load()
        fifo.unlink()
        (self.root / 'elsewhere').symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symbolic-link directories'):
            self.load()

    def test_cache_fifo_is_replaced_and_retention_is_bounded(self):
        self.load()
        path = next(self.cache.glob('*.json'))
        path.unlink()
        os.mkfifo(path)
        self.assertFalse(self.load()[1])
        self.assertTrue(path.is_file())
        for number in range(140):
            (self.cache / f'old-{number}.json').write_text('{}')
        navigate.prune(self.cache, path)
        self.assertLessEqual(len(list(self.cache.glob('*.json'))), 128)

    def test_parse_error_partial_index_never_reuses_old_semantic_edges(self):
        self.load()
        (self.root / 'lib.my').write_text('\n\n\n'
                                          'func twice(x: i64) -> i64:\n    return x +\n')
        partial, reused = self.load()
        self.assertFalse(reused)
        self.assertFalse(partial['checked'])
        self.assertEqual([], partial['references'])
        self.assertTrue(self.load()[1])
        (self.root / 'lib.my').write_text(LIB)
        repaired, reused = self.load()
        self.assertTrue(reused)
        self.assertTrue(repaired['checked'])
        self.assertTrue(repaired['references'])

    def test_compiler_standard_sources_cache_without_disk_copies_or_temporary_symbols(self):
        (self.root / 'main.my').write_text(
            'import math\n\n\nfunc size(text: i64) -> i64:\n    return math.min[i64](text, 4)\n\n\nfunc main() -> i64:\n    return size(3)\n')
        (self.root / 'math.my').write_text('reserved names cannot shadow the compiler library')
        index, reused = self.load()
        self.assertFalse(reused)
        self.assertTrue(index['checked'])
        self.assertTrue(self.load()[1])
        self.assertTrue(any(item['path'] == '@stdlib/math.my' for item in index['snapshot']['inputs']))
        self.assertFalse(any(item['name'] == '<literal>' for item in index['symbols']))
        self.assertTrue(navigate.query(index, symbol='math::min')['symbols'])

    def test_impact_scan_limit_and_unicode_context_are_explicit(self):
        index, _ = self.load()
        for item in index['symbols']:
            item['snippet'] = 'µ🚀' * 20
        result = navigate.query(index, relation='context', context_bytes=5)
        self.assertLessEqual(sum(len(item['snippet'].encode()) for item in result['symbols']), 5)
        impact = navigate.query(index, symbol='lib::add', relation='impact', scan_limit=1)
        self.assertTrue(impact['traversal_truncated'])
        with self.assertRaises(ValueError):
            navigate.query(index, limit=1001)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    COMPILER = args.compiler.resolve()
    unittest.main(argv=[sys.argv[0]])
