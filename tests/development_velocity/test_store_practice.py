"""Account for committed operations in retained development study records."""
from pathlib import Path
import tempfile
import unittest

from experiments.application_comparison.storage import write_json
from experiments.development_velocity import runner


class PractisedOperations(unittest.TestCase):
    def test_only_committed_batch_operations_count(self):
        with tempfile.TemporaryDirectory(prefix='development-practised-') as temporary:
            attempt = Path(temporary)
            records = attempt / 'practice-store/records'
            records.mkdir(parents=True)
            rows = [{'verb': 'batch', 'response': {'status': 'committed',
                                                   'applied': [{'op': 'replace'}, {'op': 'add'}]}},
                    {'verb': 'batch', 'response': {'status': 'rejected', 'applied': []}},
                    {'verb': 'open', 'response': {'status': 'committed', 'applied': [{'op': 'remove'}]}}]
            for index, row in enumerate(rows):
                write_json(records / f'{index:06}.json', row)
            self.assertEqual(runner.practiced_operations(attempt), ['add', 'replace'])

    def test_an_attempt_without_a_practice_store_practises_nothing(self):
        with tempfile.TemporaryDirectory(prefix='development-practised-') as temporary:
            self.assertEqual(runner.practiced_operations(Path(temporary)), [])


if __name__ == '__main__':
    unittest.main()
