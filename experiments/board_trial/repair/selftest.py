"""Execute known fixture restorations; this verifies the harness, not agent ability."""
import argparse
ASSETS = None  # set from --assets in __main__; the host wrapper links this generated module
from pathlib import Path
import tempfile
import shutil
import sys
import unittest
from unittest.mock import patch
import grading

import cases
import study
import tasks
from storage import command, read_json, write_json

COMPILER = study.ROOT / 'zig-out/bin/mylang'
ZIG = Path('/home/epentland/.local/bin/zig')


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mylang-repair-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def prepare(self, language='guest', task='admission'):
        root = self.directory / (language + '-' + task)
        study.prepare(root, language, task, COMPILER, ZIG, 'fixture-self-test', 'none', assets=ASSETS)
        return root

    def restore(self, root):
        manifest = read_json(root / 'manifest.json')
        tasks.copy_files(root / 'base', root / 'work', manifest['editable'])

    def test_all_ten_seeds_fail_and_known_restorations_pass_development_and_fresh_cases(self):
        for language in ('guest', 'zig'):
            for task in tasks.TASKS:
                with self.subTest(language=language, task=task):
                    root = self.prepare(language, task)
                    failed = study.check(root)
                    self.assertFalse(failed['outcome']['passed'])
                    phase = ('guest-check' if language == 'guest' else 'zig-compile') if task in ('identity', 'units', 'state') else 'behavior'
                    self.assertEqual(phase, failed['outcome']['phase'])
                    self.restore(root)
                    repaired = study.check(root)
                    self.assertTrue(repaired['outcome']['passed'], repaired)
                    self.assertTrue(repaired['edited_submission'])
                    self.assertTrue((root / 'attempts/001/patch.diff').read_text())
                    self.assertFalse((root / 'grading').exists())
                    study.seal(root, 'completed')
                    report = study.grade(root)
                    self.assertEqual('fixture', report['kind'])
                    self.assertFalse(report['attempts'][0]['outcome']['passed'])
                    self.assertTrue(report['attempts'][1]['outcome']['passed'])
                    self.assertIsNone(report['comparative_claim'])
                    print(f'fixture {language}/{task}: expected failure, restoration and fresh grading verified', flush=True)

    def test_boundary_checks_reject_early_edits_extra_files_and_changed_context(self):
        root = self.prepare()
        self.restore(root)
        with self.assertRaisesRegex(ValueError, 'seeded baseline'):
            study.check(root)
        tasks.seed(root / 'work', 'guest', 'admission')
        study.check(root)
        unexpected = root / 'work/override.my'
        unexpected.write_text('fn main()->i64{return 0;}')
        rejected = study.check(root)
        self.assertEqual('source-boundary', rejected['outcome']['phase'])
        self.assertTrue(rejected['edited_submission'])
        unexpected.unlink()
        with (root / 'work/guest/model.my').open('a') as stream:
            stream.write('\n// changed context\n')
        rejected = study.check(root)
        self.assertEqual('source-boundary', rejected['outcome']['phase'])
        study.seal(root, 'abandoned')
        self.assertEqual(3, len(study.attempts(root)))

    def test_sealing_requires_recorded_candidate_and_stops_checks(self):
        root = self.prepare('zig', 'units')
        with self.assertRaisesRegex(ValueError, 'sealed'):
            study.grade(root)
        study.check(root)
        self.restore(root)
        with self.assertRaisesRegex(ValueError, 'record the current'):
            study.seal(root, 'completed')
        study.check(root)
        study.seal(root, 'completed')
        with self.assertRaisesRegex(ValueError, 'sealed'):
            study.check(root)
        tasks.seed(root / 'work', 'zig', 'units')
        report = study.grade(root)
        self.assertTrue(report['attempts'][-1]['outcome']['passed'])
        with self.assertRaisesRegex(ValueError, 'only once'):
            study.grade(root)

    def test_frozen_snapshot_tampering_is_rejected(self):
        root = self.prepare('zig', 'units')
        study.check(root)
        study.seal(root, 'abandoned')
        path = root / 'attempts/000/source/unit_conversion.zig'
        path.write_text(tasks.UNIT_ZIG)
        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
            study.grade(root)


    def test_pair_shares_post_seal_cases_and_resumes_without_regenerating_them(self):
        left, right = self.prepare('guest', 'units'), self.prepare('zig', 'units')
        for root in (left, right):
            study.check(root)
            study.begin(root)
            self.restore(root)
            study.check(root)
            study.seal(root, 'completed')
        original = grading.one
        def interrupted(root, manifest, rows, inputs):
            if root == right:
                raise RuntimeError('injected coordinator interruption')
            return original(root, manifest, rows, inputs)
        with patch.object(grading, 'one', interrupted):
            with self.assertRaisesRegex(RuntimeError, 'interruption'):
                study.grade(left, right)
        seed = read_json(left / 'manifest.json')['grading_plan']['seed']
        report = study.grade(left, right)
        self.assertTrue(report['paired'])
        self.assertEqual(seed, read_json(right / 'manifest.json')['grading_plan']['seed'])
        self.assertEqual(report['reports'][0]['cases_sha256'], report['reports'][1]['cases_sha256'])
        self.assertTrue(all(row['final_passed'] for row in report['reports']))

    def test_check_budget_counts_repeated_checks_and_scope_rejections(self):
        root = self.prepare('zig', 'units')
        manifest = read_json(root / 'manifest.json')
        manifest['max_checks'] = 2
        write_json(root / 'manifest.json', manifest)
        first = study.check(root)
        second = study.check(root)
        self.assertFalse(first['edited_submission'])
        self.assertFalse(second['edited_submission'])
        with self.assertRaisesRegex(ValueError, 'budget exhausted'):
            study.check(root)
        study.seal(root, 'budget')

    def test_changed_tools_and_compiler_snapshots_are_rejected(self):
        root = self.prepare('zig', 'units')
        path = root / 'compiler/compiler.zig'
        path.write_text(path.read_text() + '\n// changed compiler\n')
        with self.assertRaisesRegex(ValueError, 'compiler implementation changed'):
            study.check(root)
        path.write_bytes((study.ROOT / 'src/compiler.zig').read_bytes())
        copied_tool = self.directory / 'compiler-copy'
        shutil.copyfile(COMPILER, copied_tool)
        manifest = read_json(root / 'manifest.json')
        manifest['tools']['compiler']['path'] = str(copied_tool)
        write_json(root / 'manifest.json', manifest)
        with copied_tool.open('ab') as stream:
            stream.write(b'changed tool')
        with self.assertRaisesRegex(ValueError, 'tool changed'):
            study.check(root)


    def test_symlink_submission_is_recorded_without_copying_external_bytes(self):
        root = self.prepare('zig', 'units')
        study.check(root)
        outside = self.directory / 'outside-source'
        outside.write_text('external bytes must not enter the snapshot')
        (root / 'work/linked.zig').symlink_to(outside)
        rejected = study.check(root)
        self.assertEqual('source-boundary', rejected['outcome']['phase'])
        self.assertEqual({'symlink': str(outside)}, rejected['candidate_files']['linked.zig'])
        self.assertFalse((root / 'attempts/001/source/linked.zig').exists())
        study.seal(root, 'abandoned')

    def test_command_timeout_retains_failure_and_stream_files(self):
        result = command(self.directory, 'timeout', [sys.executable, '-c', 'import time; time.sleep(5)'], timeout=0.01)
        self.assertEqual('timeout', result['status'])
        self.assertIsNone(result['returncode'])
        self.assertTrue((self.directory / 'timeout.stdout').is_file())
        self.assertTrue((self.directory / 'timeout.stderr').is_file())
        self.assertEqual(result, read_json(self.directory / 'timeout.json'))

    def test_generator_is_reproducible_and_not_the_development_corpus(self):
        generated = cases.boards('fixture-seed')
        self.assertEqual(generated, cases.boards('fixture-seed'))
        self.assertNotEqual(generated, cases.boards('different-seed'))
        self.assertEqual(128, len(generated))
        for case in generated:
            self.assertEqual(case['expected'], cases.oracle.evaluate(case['input'], case['unavailable']))
        self.assertEqual(64, len(cases.units('fixture-seed')))
        self.assertTrue(set(cases.units('fixture-seed')).isdisjoint(cases.UNIT_DEVELOPMENT))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True,
                        help='the generated qbe_build_assets module the host wrapper links')
    args = parser.parse_args()
    COMPILER, ZIG, ASSETS = args.compiler.resolve(), args.zig.resolve(), args.assets.resolve()
    unittest.main(argv=['repair-selftest'])
