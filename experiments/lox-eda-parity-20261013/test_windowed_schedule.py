import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

import windowed_schedule as schedule


class WindowedScheduleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / 'attempt'
        schedule.save(self.destination / 'pins.json', {'input': 'digest'})
        schedule.save(self.destination / 'specs/a.json', {'arms': {'zig-fast': ['zig'], 'mylang-zero-rc': ['guest']}})

    def complete(self, job):
        stem, generated, output, spec, settings = job
        schedule.save(generated, spec)
        start, rounds, warmups, _ = settings
        value = {'spec': spec, 'spec_sha256': schedule.sha(generated), 'round_start': start,
                 'rounds': rounds, 'warmups': warmups, 'measurement_harness_sha256': schedule.sha(schedule.HERE / 'measure.py'),
                 'identities': {'input': 'digest'}, 'prior_receipt': None}
        if 'prior_receipt' in spec:
            prior = Path(spec['prior_receipt'])
            value['prior_receipt'] = {'path': str(prior), 'sha256': schedule.sha(prior)}
        schedule.save(output, value)

    def test_resume_preserves_exact_thirteen_chunk_order(self):
        jobs = schedule.pending(self.destination)
        self.assertEqual(len(jobs), 13)
        self.assertEqual([j[4] for j in jobs], schedule.CHUNKS)
        for job in jobs[:3]:
            self.complete(job)
        self.assertEqual(schedule.pending(self.destination)[0][0], 'a.chunk03')

    def test_receipt_gap_refused(self):
        jobs = schedule.pending(self.destination)
        for job in jobs[:3]:
            self.complete(job)
        jobs[1][2].unlink()
        with self.assertRaisesRegex(AssertionError, 'receipt gap'):
            schedule.pending(self.destination)

    def test_changed_execution_spec_refused(self):
        job = schedule.pending(self.destination)[0]
        self.complete(job)
        value = json.loads(job[2].read_text())
        value['spec']['arms']['mylang-zero-rc'] = ['different']
        schedule.save(job[2], value)
        with self.assertRaisesRegex(AssertionError, 'changed execution spec'):
            schedule.pending(self.destination)

    def test_changed_receipt_identity_refused(self):
        job = schedule.pending(self.destination)[0]
        self.complete(job)
        value = json.loads(job[2].read_text())
        value['identities']['input'] = 'changed'
        schedule.save(job[2], value)
        with self.assertRaisesRegex(AssertionError, 'changed receipt identities'):
            schedule.pending(self.destination)

    def test_window_finishes_chunk_then_yields_without_nested_admission(self):
        first = schedule.pending(self.destination)[0]
        args = types.SimpleNamespace(root=self.root, freeze=self.root / 'freeze', window_seconds=0.000001, cpu=8)
        calls = []

        def execute(command, **kwargs):
            calls.append(command)
            self.complete(first)
            return types.SimpleNamespace(returncode=0)

        with patch.object(schedule, 'validate_pins'), patch.object(schedule.subprocess, 'run', execute):
            schedule.window(args, self.destination, self.destination / 'windows/000')
        self.assertEqual(len(calls), 1)
        self.assertNotIn('build-slot.sh', ' '.join(calls[0]))
        self.assertEqual(calls[0][-2:], ['--guest-timeout', '120'])
        result = json.loads((self.destination / 'windows/000/result.json').read_text())
        self.assertFalse(result['complete'])
        self.assertEqual(schedule.pending(self.destination)[0][0], 'a.chunk01')

    def test_unreviewed_interruption_refused(self):
        _, generated, _, spec, _ = schedule.pending(self.destination)[0]
        schedule.save(generated, spec)
        args = types.SimpleNamespace(root=self.root, freeze=self.root / 'freeze', window_seconds=55, cpu=8)
        with patch.object(schedule, 'validate_pins'), self.assertRaisesRegex(AssertionError, 'unreviewed interrupted chunk'):
            schedule.window(args, self.destination, self.destination / 'windows/000')


if __name__ == '__main__':
    unittest.main()
