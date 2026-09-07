from pathlib import Path
import json
import tempfile
import unittest
from experiments.application_comparison import iteration_log as log


class IterationLogTests(unittest.TestCase):
    def test_events_append_and_metadata_or_history_edits_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'iteration'
            log.create(root, {'predecessor': 'frozen'})
            old = (root / 'events.jsonl').read_bytes()
            log.append(root, 'attempt', {'accepted': False, 'seconds': 9})
            self.assertTrue((root / 'events.jsonl').read_bytes().startswith(old))
            self.assertEqual(2, len(log.read(root)))
            with self.assertRaises(FileExistsError):
                log.create(root, {})
            metadata = json.loads((root / 'iteration.json').read_text())
            metadata['metadata']['predecessor'] = 'changed'
            (root / 'iteration.json').write_text(json.dumps(metadata))
            with self.assertRaisesRegex(ValueError, 'metadata changed'):
                log.append(root, 'attempt', {})
            (root / 'events.jsonl').write_text((root / 'events.jsonl').read_text().replace('"seconds": 9', '"seconds": 8'))
            with self.assertRaisesRegex(ValueError, 'corrupt'):
                log.read(root)

    def test_failed_faster_trial_is_not_a_speedup_and_slowdowns_remain(self):
        old = {'task': 'repair', 'language': 'my', 'application_seconds': 100, 'accepted': True}
        new = dict(old, application_seconds=50, accepted=False)
        self.assertIsNone(log.compare('repair', new, old)['reduction_percent'])
        new.update(application_seconds=125, accepted=True)
        self.assertEqual(-25, log.compare('repair', new, old)['reduction_percent'])
        with self.assertRaises(ValueError):
            log.compare('different', new, old)
        with self.assertRaises(ValueError):
            log.compare('repair', dict(new, application_seconds=float('nan')), old)
