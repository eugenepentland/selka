"""Raw evidence fixtures, with no participant execution or compiler build."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from experiments.application_comparison.storage import digest, inventory, source_files, write_json
from experiments.development_velocity import analysis, report
from experiments.application_comparison.inputs import payload


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.path=self.root/'fixture/pair-01/my'
        self.path.mkdir(parents=True)
        self.task={'task_id':'fixture','pair_ids':['pair-01'],'family':'configuration','kind':'bugfix',
                   'variant_hash':digest('variant'),'budget_seconds':100}
        self.adapter={'language':'my','commands':[{'phase':'run','argv':['/tools/host']}]}
        self.adapter['sha256']=digest(self.adapter)
        self.reg={'study_id':'study','candidate_id':'cohort','phase':'development','look':0,
                  'frozen_at':'2026-09-08T00:00:00Z','analysis':{'version':analysis.VERSION,'seed':1,
                  'bootstrap_samples':1000,'speed_margin':1.0,'quality_margin':0.0},
                  'configuration':{'adapters':{'my':self.adapter}},'configuration_hash':digest({'adapters':{'my':self.adapter}}),'tasks':[self.task],'prior_variant_hashes':[]}
        baseline=self.root/'fixture/my-baseline';baseline.mkdir()
        (baseline/'main.my').write_text('protected runtime');(baseline/'app.my').write_text('candidate')
        files=inventory(source_files(baseline));self.source={'files':files,'sha256':digest(files)}
        source=self.path/'submissions/000/source';source.mkdir(parents=True)
        for name in files:(source/name).write_bytes((baseline/name).read_bytes())
        start={'boot_id':'fixture-boot','utc_ns':1788825601000000000,'monotonic_ns':1000000000}
        end=dict(start,utc_ns=start['utc_ns']+1000000000,monotonic_ns=2000000000)
        self.manifest={'phase':'sealed','block':'fixture','pair_id':'pair-01','language':'my','cohort':'cohort',
            'participant':'attempt-my','baseline':self.source,'protected':{'main.my':files['main.my']},
            'budgets':{'task_seconds':100},'submissions':[{'index':0,'source':self.source,'scope_violations':[],
            'elapsed_seconds':0.5,'check':{'source_sha256':self.source['sha256'],'passed':True}}],
            'final_submission':0,'seal_reason':'completed','task_started':start,'sealed':end,'participant_seconds':1.0}
        self.cases=[{'name':'case','case':{'request':{},'expected':{}}}]
        casepath=self.root/'fixture/pack/private';casepath.mkdir(parents=True);write_json(casepath/'cases.json',self.cases)
        publicpath=self.root/'fixture/pack/public';publicpath.mkdir(parents=True);write_json(publicpath/'cases.json',self.cases)
        self.raw=self.pack_fixture(self.path/'private-grading')
        self.manifest['submissions'][0]['check']=dict(self.pack_fixture(self.path/'submissions/000/check'),finished=end)
        self.profile={'session_sha256':digest(self.manifest),'model_requests':None,'model_tokens':None,'queue_wait_seconds':None}
        write_json(self.path/'registration-binding.json',{'registration_sha256':digest(self.reg),
            'variant_hash':self.task['variant_hash'],'participant':'attempt-my'})
        write_json(self.path/'context-binding.json',{'version':'observed-agent-context-v1','context_id':'/root/fresh',
            'registration_sha256':digest(self.reg),'fork_turns':'none','prompt_sha256':'a'*64})
        write_json(self.path/'source-review.json',{'version':'development-source-review-v1',
            'source_sha256':self.source['sha256'],'decision':'approve','findings':[]})
        self.sync()

    def pack_fixture(self,directory):
        child=directory/'000';child.mkdir(parents=True)
        _,input_receipt=payload({})
        record={'version':'application-check-v2','source_sha256':self.source['sha256'],
            'adapter_sha256':self.adapter['sha256'],'request_sha256':input_receipt['sha256'],'input':input_receipt,
            'steps':[{'phase':'run','argv':['/tools/host'],'isolated':True,'outcome':'exited','returncode':0}],
            'outcome':{'phase':'behavior','passed':True,'output':{}}}
        write_json(child/'result.json',record);(child/'00.stdout').write_text('{}\n');(child/'00.stderr').write_text('')
        result={'version':'public-verification-pack-v1','source_sha256':self.source['sha256'],
                'cases_sha256':digest(self.cases),'passed':True,
                'results':[{'name':'case','passed':True,'status':'executed','record':record}]}
        write_json(directory/'result.json',result)
        return result

    def sync(self):
        row=self.manifest['submissions'][0] if self.manifest['submissions'] else None
        if row and row['check'] is not None and 'results' in row['check']:
            for case in row['check']['results']:case['passed']=row['check']['passed']
            write_json(self.path/'submissions/000/check/result.json',{k:v for k,v in row['check'].items() if k!='finished'})
        verification=bool(row and row['check'] and row['check']['passed'])
        eligible=bool(row and not row['scope_violations'] and self.manifest['seal_reason']=='completed')
        write_json(self.path/'session.json',self.manifest)
        write_json(self.path/'private-grading/result.json',self.raw)
        write_json(self.path/'grading-summary.json',{'session_sha256':digest(self.manifest),
            'registration_sha256':digest(self.reg),'result_sha256':digest(self.raw),
            'behavior_pass':self.raw['passed'],'verification_pass':verification,'eligible':eligible,
            'passed':self.raw['passed'] and verification and eligible})
        self.profile['session_sha256']=digest(self.manifest)
        write_json(self.path/'profile.json',self.profile)

    def project(self):
        with patch.object(report.runner,'attempt_path',return_value=(self.path,self.reg,self.task)), \
             patch.object(report.session,'load',return_value=self.manifest), \
             patch.object(report.telemetry,'summarize',return_value=self.profile):
            return report.project_attempt(self.root,self.reg,self.task,'pair-01','my',report.Evidence())

    def analyze(self, attempt):
        other=dict(attempt,attempt_id='attempt-python',participant_id='/root/other',language='python')
        return analysis.analyze({'schema_version':1,'registration':self.reg,'registration_hash':digest(self.reg),
                                 'attempts':[attempt,other]})

    def test_projection_preserves_monotonic_and_unknown_telemetry(self):
        attempt,detail=self.project()
        self.assertEqual(attempt['participant_id'],'/root/fresh')
        self.assertEqual(attempt['clock']['started_monotonic_ns'],1000000000)
        self.assertEqual(detail['raw_clocks']['started'],self.manifest['task_started'])
        self.assertIsNone(attempt['telemetry']['model_tokens'])
        self.assertTrue(self.analyze(attempt)['attempts'][0]['qualified'])

    def test_failed_fast_private_and_public_failures_receive_full_budget(self):
        self.raw['passed']=False;self.raw['results'][0]['passed']=False;self.sync()
        attempt,_=self.project();result=self.analyze(attempt)
        self.assertEqual(result['tasks'][0]['my_cost'],100)
        self.assertEqual(result['tasks'][0]['my_qualified_count'],0)
        self.raw['passed']=True;self.raw['results'][0]['passed']=True
        self.manifest['submissions'][0]['check']['passed']=False;self.sync()
        attempt,_=self.project();self.assertEqual(self.analyze(attempt)['tasks'][0]['my_cost'],100)

    def test_missing_review_pending_and_nonqualified(self):
        (self.path/'source-review.json').unlink()
        attempt,_=self.project();self.assertEqual(attempt['review'],'pending')
        self.assertEqual(self.analyze(attempt)['tasks'][0]['my_cost'],100)

    def test_stale_review_and_stale_grade_fail_closed(self):
        review=report.read_json(self.path/'source-review.json');review['source_sha256']='f'*64
        write_json(self.path/'source-review.json',review)
        with self.assertRaisesRegex(ValueError,'review source'):self.project()
        (self.path/'source-review.json').unlink()
        self.raw['passed']=False;write_json(self.path/'private-grading/result.json',self.raw)
        with self.assertRaisesRegex(ValueError,'stale session or raw'):self.project()

    def test_changed_protected_source_and_profile_rejected(self):
        (self.path/'submissions/000/source/main.my').write_text('tampered')
        with self.assertRaises(ValueError):self.project()
        (self.path/'submissions/000/source/main.my').write_text('protected runtime')
        write_json(self.path/'profile.json',{'session_sha256':'bad'})
        with self.assertRaisesRegex(ValueError,'profile'):self.project()

    def test_abandoned_no_submission_preserved(self):
        self.manifest.update(submissions=[],final_submission=None,seal_reason='abandoned')
        self.raw={'passed':False,'reason':'no-submission'};self.sync()
        (self.path/'source-review.json').unlink()
        attempt,detail=self.project();self.assertEqual(attempt['status'],'abandoned')
        self.assertIsNone(detail['source_sha256']);self.assertEqual(self.analyze(attempt)['tasks'][0]['my_cost'],100)

    def test_timeout_keeps_raw_duration_but_caps_cost(self):
        self.manifest['seal_reason']='budget';self.manifest['participant_seconds']=150
        self.manifest['sealed']['monotonic_ns']=151000000000
        self.manifest['sealed']['utc_ns']=self.manifest['task_started']['utc_ns']+150000000000
        self.sync();attempt,_=self.project();self.assertEqual(attempt['status'],'timed_out')
        result=self.analyze(attempt);self.assertEqual(result['attempts'][0]['elapsed_seconds'],150)
        self.assertEqual(result['tasks'][0]['my_cost'],100)

    def test_incomplete_profile_operation_not_hidden(self):
        with patch.object(report.runner,'attempt_path',return_value=(self.path,self.reg,self.task)), \
             patch.object(report.session,'load',return_value=self.manifest), \
             patch.object(report.telemetry,'summarize',side_effect=FileNotFoundError('unfinished operation')):
            with self.assertRaises(FileNotFoundError):report.project_attempt(self.root,self.reg,self.task,'pair-01','my',report.Evidence())

    def test_duplicate_context_cannot_qualify(self):
        attempt,_=self.project();other=dict(attempt,attempt_id='python',language='python')
        with self.assertRaisesRegex(ValueError,'context reused'):
            analysis.analyze({'schema_version':1,'registration':self.reg,'registration_hash':digest(self.reg),'attempts':[attempt,other]})

    def test_stdout_tampering_cannot_retain_claimed_pass(self):
        (self.path/'private-grading/000/00.stdout').write_text('{"unexpected":1}')
        with self.assertRaisesRegex(ValueError,'actual stdout'):self.project()

    def test_wrong_adapter_command_or_input_receipt_rejected(self):
        record=self.raw['results'][0]['record']
        record['steps'][0]['argv']=['/unregistered']
        write_json(self.path/'private-grading/000/result.json',record);self.sync()
        with self.assertRaisesRegex(ValueError,'command differs'):self.project()
        record['steps'][0]['argv']=['/tools/host'];record['request_sha256']='f'*64
        write_json(self.path/'private-grading/000/result.json',record);self.sync()
        with self.assertRaisesRegex(ValueError,'input/source/adapter'):self.project()

    def test_missing_stderr_receipt_rejected(self):
        (self.path/'submissions/000/check/000/00.stderr').unlink()
        with self.assertRaises(FileNotFoundError):self.project()

    def test_correct_but_late_case_stays_failure(self):
        self.raw['passed']=False;self.raw['results'][0]['passed']=False;self.sync()
        attempt,_=self.project();self.assertFalse(attempt['behavior_pass'])
        self.assertEqual(self.analyze(attempt)['tasks'][0]['my_cost'],100)

    def test_protocol_failure_is_preserved(self):
        record=self.raw['results'][0]['record']
        record['outcome']={'phase':'protocol','passed':False,'failure':'invalid JSON'}
        self.raw['passed']=False;self.raw['results'][0]['passed']=False
        (self.path/'private-grading/000/00.stdout').write_text('not-json')
        write_json(self.path/'private-grading/000/result.json',record);self.sync()
        attempt,_=self.project();self.assertEqual(attempt['status'],'failed')
        self.assertFalse(attempt['behavior_pass'])

    def test_phase_deadline_without_command_remains_failed_record(self):
        record=self.raw['results'][0]['record'];record['steps']=[]
        record['outcome']={'phase':'run','passed':False,'failure':'phase-deadline'}
        self.raw['passed']=False;self.raw['results'][0]['passed']=False
        write_json(self.path/'private-grading/000/result.json',record);self.sync()
        attempt,_=self.project();self.assertFalse(attempt['behavior_pass'])

    def test_scope_rejection_without_public_execution_is_retained(self):
        import shutil
        source=self.path/'submissions/000/source'
        (source/'main.my').write_text('edited protected runtime')
        files=inventory(source_files(source));receipt={'files':files,'sha256':digest(files)}
        row=self.manifest['submissions'][0];row['source']=receipt;row['scope_violations']=['main.my']
        row['check']={'source_sha256':receipt['sha256'],'passed':False,'scope_violations':['main.my'],
                      'finished':self.manifest['sealed']}
        shutil.rmtree(self.path/'submissions/000/check')
        self.raw['source_sha256']=receipt['sha256'];self.raw['results'][0]['record']['source_sha256']=receipt['sha256']
        write_json(self.path/'private-grading/000/result.json',self.raw['results'][0]['record'])
        self.manifest['seal_reason']='abandoned';(self.path/'source-review.json').unlink();self.sync()
        attempt,detail=self.project()
        self.assertFalse(attempt['verification_pass']);self.assertEqual(attempt['status'],'abandoned')
        self.assertEqual(detail['failed_public_checks'],1)
        self.assertEqual(self.analyze(attempt)['tasks'][0]['my_cost'],100)

    def test_capture_budget_rejection_without_public_execution_is_retained(self):
        import shutil
        row=self.manifest['submissions'][0];row['elapsed_seconds']=100
        row['scope_violations']=['task-budget-exceeded-during-capture']
        row['check']={'source_sha256':self.source['sha256'],'passed':False,
                      'scope_violations':row['scope_violations'],'finished':self.manifest['sealed']}
        shutil.rmtree(self.path/'submissions/000/check');self.manifest['seal_reason']='budget';self.sync()
        attempt,_=self.project();self.assertEqual(attempt['status'],'timed_out')
        self.assertFalse(attempt['verification_pass'])

    def test_compiler_phase_aggregation_keeps_inclusive_groups_separate(self):
        rows=[{'tool':'compiler','name':'project','inclusive':True,'duration_ns':3000000000},
              {'tool':'compiler','name':'parse','inclusive':False,'duration_ns':1000000000},
              {'tool':'compiler','name':'parse','inclusive':False,'duration_ns':2000000000}]
        result=report.compiler_totals([{'language':'my'},{'language':'python'}],
            [{'profile':{'compiler_phase_records':rows}},
             {'profile':{'compiler_phase_records':[{'tool':'python','name':'application_inclusive','inclusive':True,'duration_ns':4000000000}]}}])
        parse=next(x for x in result if x['name']=='parse')
        self.assertEqual(parse['calls'],2);self.assertEqual(parse['sum_duration_seconds'],3)
        self.assertFalse(parse['inclusive']);self.assertEqual(len(result),3)
        self.assertEqual(next(x for x in result if x['language']=='python')['sum_duration_seconds'],4)

    def test_missing_grade_and_noncomplete_corpus_reject(self):
        (self.path/'grading-summary.json').unlink()
        with self.assertRaises(FileNotFoundError):self.project()
        with patch.object(report.runner,'registered',return_value=self.reg):
            with self.assertRaisesRegex(ValueError,'twelve distinct'):report.project(self.root)

    def test_publication_refuses_existing_directory(self):
        out=self.root/'published';out.mkdir();(out/'marker').write_text('original')
        with patch.object(report,'project',return_value=({},{})), \
             patch.object(report.argparse.ArgumentParser,'parse_args',return_value=type('Args',(),{'cohort':self.root,'inventory':False,'output':out})()):
            with self.assertRaises(FileExistsError):report.main()
        self.assertEqual((out/'marker').read_text(),'original')

if __name__=='__main__':unittest.main()
