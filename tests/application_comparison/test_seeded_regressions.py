from pathlib import Path
import copy
import json
import shutil
import subprocess
import tempfile
import unittest
from experiments.application_comparison import seeded_regressions as seeds
from experiments.application_comparison import planner_pilot_oracle, eda_pilot_oracle
from experiments.application_comparison.execution import correct, evaluate, freeze_adapter
from experiments.application_comparison.isolation import Limits
from experiments.application_comparison.storage import digest, inventory, snapshot, source_files, verify_snapshot

ROOT = Path(__file__).resolve().parents[2]
BASELINES = ROOT / 'experiments/application_comparison/baselines'


def adapter(application, language):
    limits = Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=4 * 1024**3)
    if language == 'my':
        return freeze_adapter(language, {'byte_io': ROOT / 'zig-out/bin/mylang-io'},
            [{'phase': 'run', 'argv': ['/tools/byte_io', '--project', '/work']}], limits=limits)
    if language == 'zig':
        return freeze_adapter(language, {'zig': Path(shutil.which('zig')).resolve().parent}, [
            {'phase': 'build', 'argv': ['/tools/zig/zig', 'build-exe', 'main.zig', '-OReleaseSafe', '-femit-bin=/cache/app']},
            {'phase': 'run', 'argv': ['/cache/app']}], limits=limits)
    entry = 'planner.py' if application == 'planner' else 'inspector.py'
    return freeze_adapter(language, {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', entry]}], limits=limits)


class SeededRegressionTests(unittest.TestCase):
    def test_my_planner_seed_changes_only_exact_byte_boundary(self):
        # A multibyte manifest is schema-invalid but transport-valid. Below the
        # byte limit it must reach per-manifest validation, not envelope rejection.
        valid = '{"cases":["é"]}'.encode()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = snapshot(BASELINES / 'planner/my', root / 'original')
            seeds.create(root / 'original', root / 'seeded', receipt,
                         task='planner-input-boundary', language='my')
            for size in (1048575, 1048576, 1048577):
                raw = valid + b' ' * (size - len(valid))
                for variant, limit in (('original', 1048576), ('seeded', 1048575)):
                    with self.subTest(size=size, variant=variant):
                        run = subprocess.run([str(ROOT / 'zig-out/bin/mylang-io'),
                                              '--project', str(root / variant)],
                                             input=raw, capture_output=True, timeout=60)
                        self.assertEqual(run.returncode, 0, run.stderr)
                        self.assertEqual(json.loads(run.stdout), {'results': [{'error': 'invalid-manifest'}]} if size <= limit
                                         else {'error': 'invalid-request'})
            malformed = valid + b' ' * (1048576 - len(valid) - 1) + b'!'
            for variant in ('original', 'seeded'):
                run = subprocess.run([str(ROOT / 'zig-out/bin/mylang-io'),
                                      '--project', str(root / variant)],
                                     input=malformed, capture_output=True, timeout=60)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(json.loads(run.stdout), {'error': 'invalid-request'})

    def test_six_variants_expose_boundary_bug_and_exact_repair_passes(self):
        planner = b'{"cases":[]}'
        planner += b' ' * (1048576 - len(planner))
        eda = b'{"cases":[{"version":1,"unit":"um","width":10,"height":10,"clearance":1,"components":[{"id":"a","x":0,"y":0,"width":1,"height":1,"pins":[]},{"id":"b","x":2,"y":0,"width":1,"height":1,"pins":[]}],"nets":[]}]}'
        for task, raw, oracle in [('planner-input-boundary', planner, planner_pilot_oracle),
                                  ('eda-clearance-boundary', eda, eda_pilot_oracle)]:
            for language in ('my', 'python', 'zig'):
                with self.subTest(task=task, language=language), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    application = task.split('-')[0]
                    source = BASELINES / application / language
                    receipt = snapshot(source, root / 'original')
                    record = seeds.create(root / 'original', root / 'seeded', receipt, task=task, language=language)
                    verify_snapshot(source, receipt)
                    verify_snapshot(root / 'original', receipt)
                    frozen_adapter = adapter(application, language)
                    expected = oracle.response_bytes(raw, task)
                    buggy = evaluate(root / 'seeded', record['seeded'], frozen_adapter, None,
                                     root / 'buggy-run', request_bytes=raw)
                    self.assertFalse(correct(buggy['outcome'], expected), buggy['outcome'])
                    # A failed compile/trap is not evidence of the intended semantic bug.
                    self.assertTrue(all(step['outcome'] == 'exited' and step['returncode'] == 0
                                        for step in buggy['steps']), buggy)
                    self.assertTrue(buggy['outcome']['passed'], buggy['outcome'])
                    if application == 'planner':
                        expected_bug = {'error': 'invalid-request'}
                    else:
                        expected_bug = copy.deepcopy(expected)
                        expected_bug['results'][0]['findings'] = [{'code': 'clearance', 'subjects': ['a', 'b']}]
                    self.assertEqual(buggy['outcome']['output'], expected_bug)
                    mutation = record['mutation']
                    snapshot(root / 'seeded', root / 'repaired')
                    target = root / 'repaired' / mutation['path']
                    target.write_bytes(target.read_bytes().replace(mutation['after'].encode(), mutation['before'].encode()))
                    verify_snapshot(root / 'repaired', receipt)
                    fixed = evaluate(root / 'repaired', receipt, frozen_adapter, None,
                                     root / 'fixed-run', request_bytes=raw)
                    self.assertTrue(correct(fixed['outcome'], expected), fixed['outcome'])

    def test_changed_baseline_and_missing_mutation_site_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            (source / 'planner.py').write_text('unrelated')
            files = inventory(source_files(source))
            receipt = {'files': files, 'sha256': digest(files)}
            with self.assertRaisesRegex(ValueError, 'exactly one'):
                seeds.create(source, root / 'missing', receipt, task='planner-input-boundary', language='python')
            (source / 'planner.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                seeds.create(source, root / 'changed', receipt, task='planner-input-boundary', language='python')


if __name__ == '__main__':
    unittest.main()
