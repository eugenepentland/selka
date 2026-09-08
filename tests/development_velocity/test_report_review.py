"""Independent report acceptance checks against contradictory or missing raw proof."""
import unittest
import test_report as fixtures


class ReportReviewTests(fixtures.ReportTests):
    def test_claimed_pass_with_not_run_case_is_rejected(self):
        self.raw['results'][0].update(status='not-run-deadline', record=None)
        self.sync()
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.project()

    def test_claimed_pass_with_failed_execution_is_rejected(self):
        self.raw['results'][0].update(status='executed', record={
            'source_sha256': self.source['sha256'],
            'outcome': {'phase': 'protocol', 'passed': False, 'failure': 'invalid JSON'},
            'steps': []})
        self.sync()
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.project()

    def test_missing_final_public_raws_cannot_qualify(self):
        check = self.path / 'submissions/000/check'
        if check.exists():
            for file in check.rglob('*'):
                if file.is_file():
                    file.unlink()
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.project()


if __name__ == '__main__':
    unittest.main()
