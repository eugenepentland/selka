import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import measure_performance_ratio as P

class StrictPerformanceTests(unittest.TestCase):
    def row(self,values):return P.summarize(values)
    def test_one_slow_workflow_cannot_hide_in_average(self):
        baseline={'fast':self.row([100]*20),'slow':self.row([100]*20)}
        candidate={'fast':self.row([1]*20),'slow':self.row([151]*20)}
        result=P.verdict(baseline,candidate)
        self.assertFalse(result['passed'])
        self.assertFalse(result['rows'][1]['passed'])
    def test_tail_limit_and_exact_boundary(self):
        baseline={'x':self.row([100]*20)}
        self.assertTrue(P.verdict(baseline,{'x':self.row([150]*20)})['passed'])
        self.assertFalse(P.verdict(baseline,{'x':self.row([100]*18+[151]*2)})['passed'])
    def test_missing_empty_or_invalid_samples_fail_closed(self):
        for values in ([],[0],[-1],[True]):
            with self.assertRaises(RuntimeError):self.row(values)
        with self.assertRaises(RuntimeError):P.verdict({'x':self.row([1])},{})
    def test_inventory_requires_schema_and_exact_authenticated_packages(self):
        import json,tempfile
        with tempfile.TemporaryDirectory() as temporary:
            prefix=Path(temporary);directory=prefix/'libexec/mylang/components';directory.mkdir(parents=True)
            binary=directory/'artifact';binary.write_bytes(b'authenticated')
            versions={'test-index':(1,1),'cache-plan':(2,2),'lexer-pilot':(1,2),'parser-pilot':(1,2),'declaration-index':(1,1),'type-interface':(1,1),'body-check':(1,5)}
            for name,(protocol,schema) in versions.items():
                (directory/(name+'.json')).write_text(json.dumps({'component':name,'protocol':protocol,'schema':schema,'artifact':'artifact','sha256':P.F.digest(binary)}))
            self.assertEqual(len(P.inventory(prefix,5)),7)
            with self.assertRaises(RuntimeError):P.inventory(prefix,2)
            body=directory/'body-check.json'
            identity=json.loads(body.read_text())
            for schema in (1,2,3,4,5):
                body.write_text(json.dumps(dict(identity,schema=schema)))
                self.assertEqual(len(P.inventory(prefix,schema)),7)
            binary.write_bytes(b'replaced')
            with self.assertRaises(RuntimeError):P.inventory(prefix,5)

    def test_historical_scalar_measurement_pins_its_body_schema(self):
        from unittest.mock import patch
        import measure_body_check_adoption as historical
        with patch.object(historical.D,'packages',return_value={}) as packages:
            historical.package_inventory(Path('/frozen'),False)
        packages.assert_called_once_with(Path('/frozen'),body_schema=1)

    def test_full_sweep_preserves_every_workflow_row(self):
        names=sorted(path.name for path in P.FIXTURES.iterdir())
        self.assertEqual(names,['failures','lists','managed','records','scalar','variants'])
        phases=['check','compile-fresh-application-cache','compile-warm','test-cold','test-warm','runtime']
        baseline={name+'/'+phase:self.row([100]*20) for name in names for phase in phases}
        candidate=dict(baseline)
        candidate['failures/runtime']=self.row([151]*20)
        result=P.verdict(baseline,candidate)
        self.assertEqual(len(result['rows']),36)
        self.assertFalse(result['passed'])

    def test_warm_build_requires_replay_and_zero_new_processes(self):
        import json
        report=dict(version='cache-report-v1',program='replayed',units=0,reused=0,compiled=0,verified=0,processes=0)
        self.assertEqual(P.warm_build(json.dumps(report)),report)
        for key,value in [('program','built'),('compiled',1),('processes',1),('units',True)]:
            with self.assertRaises(RuntimeError):P.warm_build(json.dumps(dict(report,**{key:value})))

    def test_modes_are_explicit_and_do_not_inherit_callers(self):
        from unittest.mock import patch
        with patch.dict(P.os.environ,{'MYLANG_BODY_CHECK_MODE':'component','MYLANG_PARSER_MODE':'component'}):
            env=P.environment(Path('/candidate'),{'BODY_CHECK':'reference'},Path('/empty'))
        self.assertEqual(env['MYLANG_BODY_CHECK_MODE'],'reference')
        self.assertEqual(env['MYLANG_PARSER_MODE'],'reference')

if __name__=='__main__':unittest.main()
