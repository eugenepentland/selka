from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import adjudication, session
from experiments.application_comparison.storage import read_json, write_json


class AdjudicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        baseline = self.root / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('print(1)')
        self.attempt = self.root / 'attempt'
        session.prepare(self.attempt, baseline, language='python', block='task', cohort='cohort', participant='p1', model='fixture')
        self.evidence = self.root / 'failure.json'
        write_json(self.evidence, {'type': 'RuntimeError', 'phase': 'working'})
        self.reviews = self.root / 'reviews'

    def review(self, **changes):
        return adjudication.record(self.attempt, self.reviews, **dict(
            category='unknown', reviewer='test-reviewer', reason='Exception type alone does not establish cause.',
            evidence_paths=[self.evidence], **changes))

    def test_corrections_append_without_rewriting_outcomes_or_prior_evidence(self):
        before = (self.attempt / 'session.json').read_bytes()
        first = self.review()
        original = (self.reviews / '000000.json').read_bytes()
        write_json(self.evidence, {'type': 'RuntimeError', 'phase': 'working', 'transport_status': 500})
        second = self.review()
        self.assertEqual(second['previous'], first['sha256'])
        self.assertNotEqual(first['evidence'], second['evidence'])
        self.assertEqual((self.reviews / '000000.json').read_bytes(), original)
        self.assertEqual((self.attempt / 'session.json').read_bytes(), before)
        self.assertFalse(second['authorizes_retry'])
        self.assertFalse(second['changes_outcome'])
        self.assertEqual(adjudication.read_records(self.reviews), [first, second])
        changed = read_json(self.reviews / '000000.json')
        changed['category'] = 'participant-outcome'
        write_json(self.reviews / '000000.json', changed)
        with self.assertRaisesRegex(ValueError, 'chain changed'):
            self.review()
        self.assertFalse((self.reviews / '000002.json').exists())

    def test_drift_can_be_reviewed_but_symlinks_and_missing_evidence_cannot(self):
        (self.attempt / 'baseline/main.py').write_text('changed')
        self.review()
        link = self.root / 'link'
        link.symlink_to(self.evidence)
        with self.assertRaises(OSError):
            adjudication.record(self.attempt, self.reviews, category='unknown', reviewer='r', reason='r', evidence_paths=[link])
        with self.assertRaisesRegex(ValueError, 'one to 32'):
            adjudication.record(self.attempt, self.reviews, category='unknown', reviewer='r', reason='r', evidence_paths=[])
        self.assertEqual(len(adjudication.read_records(self.reviews)), 1)
        with self.assertRaisesRegex(ValueError, 'outside'):
            adjudication.record(self.attempt, self.attempt / 'reviews', category='unknown', reviewer='r', reason='r', evidence_paths=[self.evidence])

    def test_latest_review_stales_without_falling_back_or_crossing_sessions(self):
        state = session.load(self.attempt)
        first = self.review()
        self.assertEqual(adjudication.for_session([first], self.attempt, state)['review_category'], 'unknown')
        other = dict(state, participant='p2')
        self.assertEqual(adjudication.for_session([first], self.attempt, other)['review_status'], 'unreviewed')
        new_evidence = self.root / 'specific-error.json'
        write_json(new_evidence, {'http_status': 500})
        second = adjudication.record(self.attempt, self.reviews, category='transport-interruption', reviewer='r',
            reason='HTTP response confirms transport error.', evidence_paths=[new_evidence])
        records = adjudication.read_records(self.reviews)
        self.assertEqual(adjudication.for_session(records, self.attempt, state)['review_category'], 'transport-interruption')
        new_evidence.unlink()
        selected = adjudication.for_session(records, self.attempt, state)
        self.assertEqual(selected, {'review_status': 'stale', 'review_category': None, 'review_sha256': second['sha256']})
        self.assertEqual(adjudication.for_session([first], self.attempt, state)['review_status'], 'current')
        write_json(self.attempt / 'session.json', dict(state, phase='preparing'))
        self.assertEqual(adjudication.for_session([first], self.attempt, state)['review_status'], 'stale')


if __name__ == '__main__':
    unittest.main()
