import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import statistics
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('runtime_assess', Path(__file__).with_name('assess.py'))
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

def fixture():
    inventory = a.independent_verifier.inventory()
    taxonomy = json.loads((a.EXPANDED / 'coverage.json').read_text())
    plans = []
    rows = []
    samples = []
    ratios = {'my-llvm':2.0,'my-qbe':3.0,'rust':0.5,'go':1.0,'zig-safe':1.2,'zig-fast':0.8}
    for case, meta in inventory.items():
        for profile, size in zip(('small','large'),meta['sizes']):
            plan = {'case':case,'profile':profile,'size':size,'unit':meta['unit'],'level':meta['level'],
                    'iterations':7,'calibration':{'limited':False}}
            plans.append(plan)
            for arm in a.ARMS:
                ratio = ratios[arm]
                for rnd, multiplier in enumerate((.9,1,1.1)):
                    samples.append({'case':case,'profile':profile,'size':size,'arm':arm,'round':rnd,'kernel_ns':ratio*10000*7*multiplier})
                rows.append({'case':case,'profile':profile,'size':size,'arm':arm,'iterations':7,
                             'median_ns_per_op':ratio*10000,'min_ns_per_op':ratio*9000,'max_ns_per_op':ratio*11000,
                             'median_paired_ratio_to_go':ratio,'paired_bootstrap_95_interval':[1,1] if arm=='go' else [ratio-.05,ratio+.05]})
    report = {'schema':'fixture','coverage':list(inventory),'inventory':inventory,'plans':plans,'summary':rows,'samples':samples,
              'identity':{'pinned_revision':'fixture','target_policy':{}},'rounds':3,'warmup_rounds':3,'environment':{}}
    return report,taxonomy

def replace_samples(report,case,profile,arm,values):
    for sample in report['samples']:
        if (sample['case'],sample['profile'],sample['arm'])==(case,profile,arm): sample['kernel_ns']=values[sample['round']]
    row=next(r for r in report['summary'] if (r['case'],r['profile'],r['arm'])==(case,profile,arm))
    row.update(median_ns_per_op=statistics.median(values)/row['iterations'],min_ns_per_op=min(values)/row['iterations'],max_ns_per_op=max(values)/row['iterations'])

class AssessmentEvidenceTests(unittest.TestCase):
    def test_candidate_assessment_records_new_source_revision(self):
        baseline, taxonomy = fixture()
        baseline['identity'].pop('pinned_revision')
        baseline['identity']['source_revision'] = 'a' * 40
        with patch.object(a, 'bootstrap_ratio_interval', side_effect=lambda values, ref, seed:
                          [statistics.median(values) / statistics.median(ref)] * 2):
            result = a.build_assessment(baseline, taxonomy, Path('fixture.json'), 'abc',
                                        {'status': 'fixture', 'revision': 'fixture'}, 480)
        self.assertEqual(result['evidence_verification']['compiler_source_revision_recorded'], 'a' * 40)

    def test_refuses_wrong_or_duplicate_micro_case_and_application_coverage(self):
        baseline,taxonomy = fixture()
        bad = copy.deepcopy(taxonomy); first = next(iter(bad['areas']));bad['areas'][first].pop()
        with self.assertRaisesRegex(ValueError,'micro case coverage'): a.validate_coverage(baseline,bad)
        bad = copy.deepcopy(taxonomy);bad['areas'][first].append(bad['areas'][first][0])
        with self.assertRaisesRegex(ValueError,'micro case coverage'): a.validate_coverage(baseline,bad)
        bad = copy.deepcopy(taxonomy);bad['applications'].pop('word_count')
        with self.assertRaisesRegex(ValueError,'application case coverage'): a.validate_coverage(baseline,bad)

    def test_refuses_unit_drift_missing_size_and_missing_arm(self):
        baseline,taxonomy = fixture()
        baseline['plans'][0]['unit']='one element instead of one complete pass'
        with self.assertRaisesRegex(ValueError,'units'): a.validate_coverage(baseline,taxonomy)
        baseline,taxonomy = fixture();baseline['plans'].pop()
        with self.assertRaisesRegex(ValueError,'plan coverage'): a.validate_coverage(baseline,taxonomy)
        baseline,taxonomy = fixture();baseline['summary'].pop()
        with self.assertRaisesRegex(ValueError,'all-six-arm'): a.validate_coverage(baseline,taxonomy)

    def test_closed_ci_boundaries_fastest_ties_and_unusual_intervals(self):
        self.assertEqual(a.classify([.7,.9],False),'interval_below_reference')
        self.assertEqual(a.classify([1.1,1.4],False),'slower')
        self.assertEqual(a.classify([.9,1],False),'overlapping')
        self.assertEqual(a.classify([1,1.1],False),'overlapping')
        self.assertEqual(a.classify([1,1],True),'fastest')
        self.assertEqual(a.classify([1.1,1.4],True),'fastest')
        for interval in ([1.1,.9],[0,1],[float('nan'),1]):
            with self.subTest(interval=interval),self.assertRaises(ValueError): a.classify(interval,False)

    def test_preserves_units_worst_case_all_480_cells_and_removes_old_go_fields(self):
        baseline,taxonomy = fixture()
        first = next(row for row in baseline['summary'] if row['arm']=='my-llvm')
        replace_samples(baseline,first['case'],first['profile'],'my-llvm',[700000,800000,900000])
        with patch.object(a,'bootstrap_ratio_interval',side_effect=lambda values,ref,seed: [statistics.median(values)/statistics.median(ref)]*2):
            result = a.build_assessment(baseline,taxonomy,Path('fixture.json'),'abc',{'status':'fixture','revision':'fixture'},480)
        self.assertEqual(len(result['appendix_all_comparisons']),480)
        self.assertEqual(len({(r['case'],r['profile'],r['arm']) for r in result['appendix_all_comparisons']}),480)
        family = next(f for f in result['families'] if first['case'] in f['cases'])
        stat = family['statistics_by_arm']['my-llvm']
        self.assertEqual(stat['worst_observed_comparison']['case'],first['case'])
        self.assertEqual(stat['ratio_to_fastest_range'][0],4)
        self.assertGreater(stat['ratio_to_fastest_range'][1],20)
        self.assertEqual(stat['counts']['slower'],2*len(family['cases']))
        row = next(r for r in result['appendix_all_comparisons'] if r['arm']=='go')
        self.assertEqual(row['median_us_per_iteration'],10)
        self.assertEqual(row['unit'],baseline['inventory'][row['case']]['unit'])
        self.assertTrue(all(r['ratio_to_fastest']>=1 for r in result['appendix_all_comparisons']))
        for row in result['appendix_all_comparisons']:
            self.assertNotIn('median_paired_ratio_to_go',row)
            self.assertNotIn('paired_bootstrap_95_interval',row)
            self.assertNotIn('classification_vs_go',row)
        self.assertIsNone(result['interpretation']['overall_language_score'])

    def test_winner_changes_per_case_per_profile_and_exact_ties(self):
        baseline,taxonomy=fixture()
        first,second=list(baseline['inventory'])[:2]
        replace_samples(baseline,first,'small','go',[700,1400,2100])
        replace_samples(baseline,first,'large','my-qbe',[700,1400,2100])
        replace_samples(baseline,second,'small','my-llvm',[35000,35000,35000])
        replace_samples(baseline,second,'small','rust',[35000,35000,35000])
        # Rust remains the winner of the second case's large profile.
        plans=a.validate_coverage(baseline,taxonomy)
        with patch.object(a,'bootstrap_ratio_interval',side_effect=lambda values,ref,seed: [statistics.median(values)/statistics.median(ref)]*2):
            rows=a.comparison_rows(baseline,plans)
        for case,profile,reference in ((first,'small','go'),(first,'large','my-qbe'),(second,'small','my-llvm'),(second,'large','rust')):
            chosen=[r for r in rows if r['case']==case and r['profile']==profile]
            self.assertTrue(all(r['reference_arm']==reference for r in chosen))
            self.assertEqual(next(r for r in chosen if r['arm']==reference)['ratio_to_fastest'],1)
        tied=[r for r in rows if r['case']==second and r['profile']=='small']
        self.assertEqual(tied[0]['fastest_arms'],['my-llvm','rust'])
        self.assertEqual({r['arm'] for r in tied if r['classification_vs_fastest']=='fastest'},{'my-llvm','rust'})

    def test_actual_bootstrap_uses_paired_indexes_against_non_go_reference(self):
        self.assertEqual(a.bootstrap_ratio_interval([2,200,20000],[1,100,10000],'paired'),[2,2])
        plans={('probe',64,'small'):{'unit':'one job','level':'micro','iterations':1,'calibration':{'limited':False}}}
        samples=[];rows=[]
        for arm in a.ARMS:
            values=[1,10,100] if arm=='rust' else [2,50,101] if arm=='go' else [5,80,1000]
            for rnd,value in enumerate(values): samples.append({'case':'probe','size':64,'profile':'small','arm':arm,'round':rnd,'kernel_ns':value})
            rows.append({'case':'probe','size':64,'profile':'small','arm':arm,'iterations':1,'median_ns_per_op':statistics.median(values),'min_ns_per_op':min(values),'max_ns_per_op':max(values),
                         'median_paired_ratio_to_go':999,'paired_bootstrap_95_interval':[999,999]})
        comparisons=a.comparison_rows({'rounds':3,'samples':samples,'summary':rows},plans)
        go=next(r for r in comparisons if r['arm']=='go')
        self.assertEqual(go['reference_arm'],'rust')
        self.assertEqual(go['ratio_to_fastest'],5)
        self.assertEqual(statistics.median([2/1,50/10,101/100]),2)
        self.assertEqual(go['reference_median_ns_per_iteration'],10)
        self.assertEqual(go['bootstrap_95_interval_to_fastest'],[1.01,5])
        # A different arm wins the first round (value .1), but Rust still has the lowest observed median.
        samples[0]['kernel_ns']=.1;rows[0]['min_ns_per_op']=.1
        comparisons=a.comparison_rows({'rounds':3,'samples':samples,'summary':rows},plans)
        self.assertTrue(all(r['reference_arm']=='rust' for r in comparisons))

    def test_missing_duplicate_raw_rounds_and_inconsistent_summary_fail(self):
        baseline,taxonomy=fixture();plans=a.validate_coverage(baseline,taxonomy)
        baseline['samples'].pop()
        with self.assertRaisesRegex(ValueError,'missing paired raw rounds'): a.comparison_rows(baseline,plans)
        baseline,taxonomy=fixture();plans=a.validate_coverage(baseline,taxonomy)
        baseline['samples'].append(baseline['samples'][0])
        with self.assertRaisesRegex(ValueError,'duplicate raw round'): a.comparison_rows(baseline,plans)
        baseline,taxonomy=fixture();plans=a.validate_coverage(baseline,taxonomy)
        baseline['summary'][0]['median_ns_per_op']*=2
        with self.assertRaisesRegex(ValueError,'summary median differs'): a.comparison_rows(baseline,plans)

    def test_loader_binds_exact_baseline_bytes_and_requests_no_current_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'baseline.json';raw=b'{"schema":"fixture"}';path.write_bytes(raw)
            calls=[]
            def verifier(report,artifacts): calls.append(artifacts);return 480
            self.assertEqual(a.load_verified(path,a.sha(raw),verifier)[1],480)
            self.assertEqual(calls,[False])
            path.write_bytes(raw+b'\n')
            with self.assertRaisesRegex(ValueError,'SHA256 mismatch'): a.load_verified(path,a.sha(raw),verifier)
            self.assertEqual(calls,[False])

    def test_historical_audit_uses_archived_blobs_and_detects_source_mismatch(self):
        content=b'original measurement document'
        identity={'sources':{'expanded/README.md':a.sha(content)}}
        archived=subprocess.CompletedProcess([],0,content,b'')
        with patch.object(a.subprocess,'run',return_value=archived) as command:
            audited=a.historical_source_audit(identity,a.HISTORICAL_REVISION,Path('/repo'))
            self.assertEqual(audited['status'],'verified_historical_sources')
            self.assertIn(a.HISTORICAL_REVISION+':benchmarks/runtime/expanded/README.md',command.call_args.args[0])
        changed=subprocess.CompletedProcess([],0,b'changed document',b'')
        with patch.object(a.subprocess,'run',return_value=changed),self.assertRaisesRegex(ValueError,'source mismatch'):
            a.historical_source_audit(identity,a.HISTORICAL_REVISION,Path('/repo'))
        missing=subprocess.CompletedProcess([],128,b'',b'missing commit')
        with patch.object(a.subprocess,'run',return_value=missing):
            self.assertEqual(a.historical_source_audit(identity,a.HISTORICAL_REVISION,Path('/repo'))['status'],'historical_sources_unavailable_or_incomplete')

    def test_markdown_renders_string_application_review_and_breadth_gaps(self):
        baseline,taxonomy=fixture()
        taxonomy['application_review']={'word_count':{'represents':'tokenization and dictionary counting','limits':['five distinct words']}}
        taxonomy['confidence_gaps']=['large working sets'];taxonomy['excluded_workloads']=['network waits']
        with patch.object(a,'bootstrap_ratio_interval',side_effect=lambda values,ref,seed: [statistics.median(values)/statistics.median(ref)]*2):
            result=a.build_assessment(baseline,taxonomy,Path('fixture.json'),'abc',{'status':'fixture','revision':'fixture'},480)
        output=a.markdown(result)
        self.assertIn('word_count represents: tokenization and dictionary counting.',output)
        self.assertNotIn('t; o; k; e; n',output)
        self.assertIn('Confidence gaps: large working sets.',output)
        self.assertIn('Excluded workloads: network waits.',output)
        self.assertIn('not an equivalence proof or acceptance threshold',output)

    def test_output_cannot_replace_raw_baseline_profiles_or_taxonomy(self):
        baseline=a.DEFAULT_BASELINE;taxonomy=a.EXPANDED/'coverage.json'
        for output in (baseline,baseline.with_suffix('.md'),taxonomy,a.EXPANDED/'results/profiles/profiles.json'):
            with self.subTest(output=output),self.assertRaisesRegex(ValueError,'preserve'):
                a.protect_inputs(output,(baseline,baseline.with_suffix('.md'),taxonomy))
        a.protect_inputs(a.HERE/'results/test.json',(baseline,taxonomy))

if __name__=='__main__': unittest.main()
