"""Ensure reporting rejects damaged evidence and pairs the same rounds."""
import copy,importlib.util,json,pathlib,tempfile,types,unittest
HERE=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('micro_report',HERE.parent/'tools/report.py'); report=importlib.util.module_from_spec(spec); spec.loader.exec_module(report)
INPUT=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012')
class ReportTests(unittest.TestCase):
 def test_paired_bootstrap_constant_ratio(self):
  got=report.interval({2:60,0:20,1:40},{0:10,1:20,2:30},'constant',200)
  self.assertEqual(got['ratio'],2);self.assertEqual(got['ci95'],[2,2])
  with self.assertRaisesRegex(ValueError,'unmatched rounds'):report.interval({0:1},{1:1},'bad',200)
 def analyze_changed(self,mutate):
  base=INPUT/'experiments/micro-ownership-20261012'; d=report.load(base/'results/parity/dict_count.json'); s=d['spec']; mutate(d)
  with tempfile.TemporaryDirectory() as temp:
   p=pathlib.Path(temp)/'damaged.json';p.write_text(json.dumps(d))
   return report.analyze(INPUT,p,s,None,types.SimpleNamespace(check_artifacts=False,bootstrap=200))
 def test_missing_sample_rejected(self):
  with self.assertRaisesRegex(ValueError,'missing accepted rounds'):self.analyze_changed(lambda d:d['samples'].pop())
 def test_identity_change_rejected(self):
  with self.assertRaisesRegex(ValueError,'changed measurement identities'):self.analyze_changed(lambda d:d['identities_after'].update({'new':'0'*64}))
 def test_wrong_output_rejected(self):
  with self.assertRaisesRegex(ValueError,'fixed output mismatch'):self.analyze_changed(lambda d:d['samples'][0].update(stdout='wrong\n'))
 def test_counter_metric_change_rejected(self):
  with self.assertRaisesRegex(ValueError,'counter metrics'):self.analyze_changed(lambda d:d['counted'][report.MY[2]]['metrics'].update(allocs=0))
 def test_failed_arm_remains_unavailable(self):
  def fail(d):
   arm=report.MY[2]; state={'status':'timeout','phase':'warmups','timeout_seconds':120}
   d['arm_status'][arm]=state;d['summary'][arm]['status']=state;d['summary'][arm]['complete']=False
   for phase in ('samples','warmups','rss'):d[phase]=[v for v in d[phase] if v['arm']!=arm]
  result=self.analyze_changed(fail)
  self.assertFalse(result['arms'][report.MY[2]]['complete'])
  self.assertEqual(result['arms'][report.MY[2]]['status']['status'],'timeout')
  self.assertNotIn(report.MY[2]+'/'+report.MY[0],result['comparisons'])
if __name__=='__main__':unittest.main()
