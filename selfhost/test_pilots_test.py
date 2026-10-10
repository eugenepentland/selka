#!/usr/bin/env python3
"""Adversarial qualification selections and actual pilot input manifests."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import test_pilots as pilots


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class QualificationTests(unittest.TestCase):
    def test_full_parser_rejects_missing_or_incomplete_corpus(self):
        full = '3 passed, 0 failed, 0 skipped; complete field AST/diagnostic comparison for declared fixtures\n'
        roundtrip = 'oracle-only roundtrip: 7 selected modules, 5 AST, 1 diagnostics, 1 verified lexical exclusions, 0 failures, 0 skipped; no Selka parity asserted\n'
        corpus = 'full corpus: 7 selected modules; 5 exact AST, 1 exact diagnostics, 0 mismatches, 0 unsupported, 1 verified lexical exclusions; 0 skipped\n'
        complete = full + roundtrip + corpus
        pilots.require_full_parser(complete, 3, 7)
        for output, fixtures, modules in [(full, 3, 7), (roundtrip, 3, 7), (complete, 4, 7),
                (complete, 3, 8), (complete.replace('0 failures', '1 failures'), 3, 7),
                (full + complete, 3, 7), (complete, 0, 7), (full + roundtrip, 3, 7),
                (complete.replace('0 mismatches', '1 mismatches'), 3, 7),
                (complete.replace('0 unsupported', '1 unsupported'), 3, 7),
                (complete.replace('1 verified lexical', '0 verified lexical'), 3, 7),
                (complete.replace('1 verified lexical', '2 verified lexical'), 3, 7),
                (complete.replace('5 exact AST', '6 exact AST'), 3, 7)]:
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                pilots.require_full_parser(output, fixtures, modules)

    def test_installed_parser_requires_complete_checks_and_component_only_edit(self):
        summary = 'parser component: 3 fixtures (2 AST, 1 diagnostics), 5 framed exchanges, 28 malformed/invocation checks, 3 deployment checks; 0 failures, 0 skipped\n'
        edit = 'component implementation edit: changed producer artifact, unchanged host, complete selected fixture comparison passed\n'
        pilots.require_parser_component(summary + edit, 3)
        for output in (summary, edit, summary + edit + summary,
                       (summary + edit).replace('28 malformed', '27 malformed'),
                       (summary + edit).replace('5 framed', '4 framed'),
                       (summary + edit).replace('0 skipped', '1 skipped')):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                pilots.require_parser_component(output, 3)

    def test_complete_two_mode_selection(self):
        pilots.require_guest('3 passed, 0 cached, 0 failed, 0 skipped\n' * 2, 3, modes=2)

    def test_empty_cached_failed_skipped_missing_mode_fail_closed(self):
        for output, expected, modes in [('', 1, 1), ('0 passed, 0 cached, 0 failed, 0 skipped', 0, 1),
                ('2 passed, 1 cached, 0 failed, 0 skipped', 3, 1),
                ('2 passed, 0 cached, 1 failed, 0 skipped', 3, 1),
                ('2 passed, 0 cached, 0 failed, 1 skipped', 3, 1),
                ('3 passed, 0 cached, 0 failed, 0 skipped', 3, 2)]:
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                pilots.require_guest(output, expected, modes)

    def test_seed_verification_failure_stops_before_guest_execution(self):
        args = SimpleNamespace(lane='probes', zig='zig', builder=Path('builder'), compiler=Path('compiler'), component_dir=Path('components'))
        with mock.patch.object(pilots, 'execute', side_effect=RuntimeError('invalid receipt')) as execute:
            with self.assertRaisesRegex(RuntimeError, 'invalid receipt'):
                pilots.qualify(args)
            self.assertEqual(execute.call_count, 1)
            self.assertEqual(execute.call_args.args[0][-1], '--seed-only')

    def test_routing_and_guest_selection_cannot_override_qualification(self):
        args = SimpleNamespace(lane='probes', zig='pinned-zig', builder=Path('builder'), compiler=Path('compiler'), component_dir=Path('components'))
        with tempfile.TemporaryDirectory() as temporary:
            seed = Path(temporary) / 'seed'
            seed.write_bytes(b'verified fake seed')
            expected = len(pilots.re.findall(r'^public func test_[A-Za-z0-9_]+\(', (pilots.ROOT / pilots.SOURCES['probes']).read_text(), pilots.re.M))
            outputs = [str(seed) + '\n', f'{expected} passed, 0 cached, 0 failed, 0 skipped\n' * 2]
            with mock.patch.dict(pilots.os.environ, {'MYLANG_LEXER_MODE': 'component', 'MYLANG_TEST_FILTER': 'nothing', 'MYL_CORE_LEAKCHECK': '0'}), mock.patch.object(pilots, 'execute', side_effect=outputs) as execute, contextlib.redirect_stdout(io.StringIO()):
                pilots.qualify(args)
            environment = execute.call_args.args[1]
            self.assertEqual(environment['MYLANG_LEXER_MODE'], 'reference')
            self.assertEqual(environment['MYLANG_ZIG'], 'pinned-zig')
            self.assertEqual(environment['MYLANG_COMPONENT_DIR'], 'components')
            self.assertEqual(environment['MYL_CORE_LEAKCHECK'], '1')
            self.assertNotIn('MYLANG_TEST_FILTER', environment)

    def test_child_failure_is_not_a_green_summary(self):
        result = SimpleNamespace(returncode=1, stdout='11 passed, 0 cached, 0 failed, 0 skipped\n', stderr='bad receipt')
        with mock.patch.object(pilots.subprocess, 'run', return_value=result), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(RuntimeError):
                pilots.execute(['fake'], {})

    def test_manifest_membership_edits_and_removal_invalidate_each_lane(self):
        inputs = load('pilot_declared_inputs', pilots.ROOT / 'tests/test_inputs_coverage.py')
        manifest = load('pilot_input_manifest', pilots.ROOT / 'tests/input_manifest.py')
        lists = inputs.declared_lists((pilots.ROOT / 'build_test_inputs.zig').read_text())
        for lane, fixture in [('lexer', 'selfhost/tests/fixtures/lexer_pilot/'),
                              ('parser', 'selfhost/tests/fixtures/parser_pilot/'),
                              ('probes', 'selfhost/probes/compiler/')]:
            entries = lists['pilot_' + lane]
            self.assertIn(fixture, entries)
            self.assertTrue(inputs.covered('selfhost/test_pilots.py', entries))
            self.assertTrue(inputs.covered('selfhost/component-seed.json', entries))
            self.assertTrue(inputs.covered(fixture + 'new.fixture', entries))
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                path = directory / 'new.fixture'
                baseline = manifest.manifest([str(directory) + '/'], {})
                path.write_bytes(b'first')
                added = manifest.manifest([str(directory) + '/'], {})
                path.write_bytes(b'edit')
                edited = manifest.manifest([str(directory) + '/'], {})
                path.unlink()
                removed = manifest.manifest([str(directory) + '/'], {})
                self.assertNotEqual(baseline, added)
                self.assertNotEqual(added, edited)
                self.assertNotEqual(edited, removed)
                self.assertEqual(baseline, removed)
        self.assertTrue(inputs.covered('src/parser.zig', lists['pilot_parser']))
        self.assertTrue(inputs.covered('tests/lang/any_new_fixture.my', lists['pilot_parser']))
        self.assertTrue(inputs.covered('tests/value_semantics/any_new_fixture.my', lists['pilot_parser']))
        self.assertTrue(inputs.covered('selfhost/components/lexer_pilot/lexer.my', lists['pilot_parser']))


if __name__ == '__main__':
    unittest.main()
