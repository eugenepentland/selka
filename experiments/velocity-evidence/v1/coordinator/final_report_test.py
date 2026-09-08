import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import final_report as f

class FinalReportTests(unittest.TestCase):
    def test_failed_fast_aggregate_has_raw_delta_but_no_percentage(self):
        row={'old_seconds':100, 'new_seconds':1, 'old_trusted_check_failures':0,
             'new_trusted_check_failures':1, 'fresh_accepted':True,
             'historical_replay_accepted':True, 'original_accepted':True,
             'declared_tests_passed':True,
             'old_working_metrics':dict(command_count=4,failed_commands=0,captured_output_bytes=10),
             'new_working_metrics':dict(command_count=1,failed_commands=1,captured_output_bytes=2)}
        self.assertEqual(f.main_totals([row])['elapsed_change_percent'],-99)
        for key in ('fresh_accepted','historical_replay_accepted','original_accepted','declared_tests_passed'):
            with self.subTest(key=key):
                totals=f.main_totals([dict(row, **{key:False})])
                self.assertIsNone(totals['elapsed_change_percent'])
                self.assertEqual(totals['delta_seconds'],-99)
                self.assertEqual(totals['new_seconds'],1)
                self.assertFalse(totals['comparison_eligible'])

    def test_maintenance_verdict_must_agree_with_nonempty_cases(self):
        self.assertTrue(f.grade_behavior(dict(behavior_passed=True,outcomes=[{'passed':True}])))
        self.assertFalse(f.grade_behavior(dict(behavior_passed=False,outcomes=[])))
        for outcomes in ([],[{'passed':False}]):
            with self.assertRaisesRegex(ValueError,'disagrees'):
                f.grade_behavior(dict(behavior_passed=True,outcomes=outcomes))

    def test_maintenance_stop_or_unchecked_seal_is_ineligible(self):
        source={'sha256':'fixture'}
        seal=dict(source=source,last_checked=source,final_checked=True,reason='completed')
        grade=dict(last_checked=source,final_checked=True)
        self.assertTrue(f.maintenance_eligible(seal,grade))
        for changed in (dict(seal,reason='budget'),dict(seal,final_checked=False)):
            self.assertFalse(f.maintenance_eligible(changed,grade))
        self.assertFalse(f.maintenance_eligible(seal,dict(grade,final_checked=False)))

    def test_exact_members_rejects_duplicate_and_missing_stages(self):
        f.exact_members([{'run':x} for x in f.RUNS], 'run', f.RUNS)
        for rows in ([{'run':x} for x in f.RUNS[:-1]], [{'run':f.RUNS[0]}]*6):
            with self.assertRaises(ValueError): f.exact_members(rows,'run',f.RUNS)

    def test_incomplete_collection_cannot_create_publication(self):
        with tempfile.TemporaryDirectory(dir=f.ROOT) as d:
            out=Path(d)/'publication'
            with patch.object(f,'collect',side_effect=FileNotFoundError('missing matched review')),patch.object(f.sys,'argv',['final_report.py','--output',str(out)]):
                with self.assertRaises(FileNotFoundError):f.main()
            self.assertFalse(out.exists())

    def test_evidence_mutation_rejected(self):
        with tempfile.TemporaryDirectory(dir=f.ROOT) as d:
            p=Path(d)/'receipt.json';p.write_text('{}');e=f.Evidence();e.read(p);e.verify_all();p.write_text('{"changed":true}')
            with self.assertRaises(ValueError):e.verify_all()

    def test_existing_publication_not_overwritten(self):
        with tempfile.TemporaryDirectory(dir=f.ROOT) as d:
            out=Path(d)/'publication';out.mkdir();p=out/'summary.json';p.write_text('original')
            with patch.object(f,'collect',return_value={}),patch.object(f.sys,'argv',['final_report.py','--output',str(out)]):
                with self.assertRaises(FileExistsError):f.main()
            self.assertEqual(p.read_text(),'original')

if __name__=='__main__':unittest.main()
