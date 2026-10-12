"""Live directory fixtures selected by membership, executed as real unittest cases."""
from pathlib import Path
import unittest

FIXTURES = Path(__file__).resolve().parents[1] / 'test' / 'membership'


class Membership(unittest.TestCase):
    pass


def check(path):
    def test(self):
        self.assertEqual(path.read_text().strip(), '1', str(path))
    return test


for fixture in sorted(FIXTURES.glob('*.txt')):
    setattr(Membership, 'test_' + fixture.stem, check(fixture))
