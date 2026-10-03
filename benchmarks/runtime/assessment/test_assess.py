import copy
import importlib.util
import json
from pathlib import Path
import subprocess
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
    ratios = {'my-llvm':2.0,'my-qbe':3.0,'rust':0.5,'go':1.0,'zig-safe':1.2,'zig-fast':0.8}
    for case, meta in inventory.items():
        for profile, size in zip(('small','large'),meta['sizes']):
            plan = {'case':case,'profile':profile,'size':size,'unit':meta['unit'],'level':meta['level'],
                    'iterations':7,'calibration':{'limited':False}}
            plans.append(plan)
            for arm in a.ARMS:
                ratio = ratios[arm]
                rows.append({'case':case,'profile':profile,'size':size,'arm':arm,'iterations':7,
                             'median_ns_per_op':ratio*10000,'min_ns_per_op':ratio*9000,'max_ns_per_op':ratio*11000,
                             'median_paired_ratio_to_go':ratio,'paired_bootstrap_95_interval':[1,1] if arm=='go' else [ratio-.05,ratio+.05]})
    report = {'schema':'fixture','coverage':list(inventory),'inventory':inventory,'plans':plans,'summary':rows,
              'identity':{'pinned_revision':'fixture','target_policy':{}},'rounds':15,'warmup_rounds':3,'environment':{}}
    return report,taxonomy

class AssessmentEvidenceTests(unittest.TestCase):
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

    def test_closed_ci_boundary_and_reference_classification(self):
        self.assertEqual(a.classify([.7,.9],'rust'),'faster')
        self.assertEqual(a.classify([1.1,1.4],'my-llvm'),'slower')
        self.assertEqual(a.classify([.9,1],'rust'),'overlapping')
        self.assertEqual(a.classify([1,1.1],'my-llvm'),'overlapping')
        self.assertEqual(a.classify([1,1],'go'),'reference')
        for interval in ([1.1,.9],[0,1],[float('nan'),1]):
            with self.subTest(interval=interval),self.assertRaises(ValueError): a.classify(interval,'rust')

    def test_preserves_units_us_conversion_worst_case_and_all_480_rows(self):
        baseline,taxonomy = fixture()
        first = next(row for row in baseline['summary'] if row['arm']=='my-llvm')
        first['median_paired_ratio_to_go']=8;first['paired_bootstrap_95_interval']=[7.9,8.1]
        result = a.build_assessment(baseline,taxonomy,Path('fixture.json'),'abc',{'status':'fixture','revision':'fixture'},480)
        self.assertEqual(len(result['appendix_all_comparisons']),480)
        family = next(f for f in result['families'] if first['case'] in f['cases'])
        stat = family['statistics_by_arm']['my-llvm']
        self.assertEqual(stat['worst_observed_comparison']['case'],first['case'])
        self.assertEqual(stat['paired_median_ratio_range'],[2,8])
        self.assertEqual(stat['counts']['slower'],2*len(family['cases']))
        row = next(r for r in result['appendix_all_comparisons'] if r['arm']=='go')
        self.assertEqual(row['median_us_per_iteration'],10)
        self.assertEqual(row['unit'],baseline['inventory'][row['case']]['unit'])
        self.assertIsNone(result['interpretation']['overall_language_score'])

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
