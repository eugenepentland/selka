"""Hand-derived expectations and independent invariants; no application imports."""
import copy
import json
import unittest
from .catalog import IDS,TASKS,MUTATIONS
from .cases import build,PUBLIC,random_request
from .oracles import expected,batch_expected

class CorpusTests(unittest.TestCase):
    def test_generated_transport_domain_ends_at_two_mib(self):
        import base64
        from experiments.application_comparison.inputs import decode_case, MAX_INPUT_BYTES
        self.assertEqual(MAX_INPUT_BYTES,2097152)
        cases=build('quota-boundary','transport-boundary')
        rawcases=[case['case'] for case in cases if 'request_base64' in case['case']]
        sizes=[len(base64.b64decode(case['request_base64'])) for case in rawcases]
        self.assertEqual(max(sizes),2097152)
        self.assertNotIn(2097153,sizes)
        maximum=next(case for case in rawcases if len(base64.b64decode(case['request_base64']))==2097152)
        self.assertEqual(maximum['expected'],{'error':'invalid-envelope'})
        self.assertEqual(len(decode_case(maximum)[1]),2097152)

    def test_pack_public_projection_excludes_seed_and_refuses_overwrite(self):
        import tempfile
        from pathlib import Path
        from .pack import create
        with tempfile.TemporaryDirectory() as temporary:
            target=Path(temporary)/'pack'
            receipt=create(target,'quota-boundary','PRIVATE_ONLY_SENTINEL')
            self.assertFalse(receipt['timed_launch_ready'])
            for public in (target/'public').iterdir():
                self.assertNotIn(b'PRIVATE_ONLY_SENTINEL',public.read_bytes())
            with self.assertRaises(FileExistsError):create(target,'quota-boundary','another')
            self.assertEqual((target/'private/seed.txt').read_text(),'PRIVATE_ONLY_SENTINEL')

    def test_catalog_has_eight_features_four_bugs_six_families(self):
        self.assertEqual(len(IDS),12);self.assertEqual(len(set(IDS)),12)
        self.assertEqual(sum(x[2]=='feature' for x in TASKS),8)
        self.assertEqual(set(MUTATIONS),{x[0] for x in TASKS if x[2]=='bugfix'})
        self.assertEqual(len(set(x[1] for x in TASKS)),6)

    def test_data_and_ascii_exact_output(self):
        self.assertEqual(expected('data-rollup',PUBLIC['data-rollup'][1]),{'groups':[{'key':'a','count':1,'total':7},{'key':'b','count':2,'total':0}]})
        self.assertEqual(expected('ascii-table',PUBLIC['ascii-table'][1]),{'widths':[4,3],'lines':['a    | xyz','long |    ']})
        self.assertEqual(expected('ascii-table',{'columns':2,'rows':[]}),{'widths':[0,0],'lines':[]})
        self.assertEqual(expected('ascii-table',{'columns':1,'rows':[['é']]}),{'error':'invalid-request'})

    def test_config_null_and_inclusive_quota(self):
        self.assertEqual(expected('config-layers',PUBLIC['config-layers'][1]),{'config':{'timeout':1000,'retries':3,'enabled':True,'label':'x'},'changed':['label']})
        self.assertEqual(expected('quota-boundary',PUBLIC['quota-boundary'][0]),{'accepted':[True,True,False],'used':5,'remaining':0})
        self.assertEqual(expected('quota-boundary',PUBLIC['quota-boundary'][1]),{'accepted':[True,False],'used':0,'remaining':0})

    def test_stateful_order_and_expiry(self):
        self.assertEqual(expected('lru-cache',PUBLIC['lru-cache'][1]),{'results':[{'evicted':None},{'evicted':None},{'value':1},{'evicted':'b'}],'entries':[{'key':'a','value':1},{'key':'c','value':3}]})
        self.assertEqual(expected('ttl-boundary',PUBLIC['ttl-boundary'][1]),{'results':[None,None],'live':[]})
        self.assertEqual(expected('ttl-boundary',PUBLIC['ttl-boundary'][2]),{'results':[None,None],'live':[]})
        q={'operations':[{'op':'put','at':5,'key':'a','value':-7,'ttl':1},{'op':'put','at':5,'key':'a','value':9,'ttl':8},{'op':'get','at':6,'key':'a'}]}
        self.assertEqual(expected('ttl-boundary',q),{'results':[None,None,9],'live':['a']})

    def test_binary_literal_endianness_and_bounds(self):
        self.assertEqual(expected('record-frames',PUBLIC['record-frames'][1]),{'hex':'ff00000103000001ff','offsets':[0,3]})
        self.assertEqual(expected('little-endian-read',PUBLIC['little-endian-read'][1]),{'values':[513,65282,255,513]})
        self.assertEqual(expected('little-endian-read',{'hex':'0102','offsets':[1]}),{'error':'out-of-bounds'})
        self.assertEqual(expected('little-endian-read',{'hex':'01','offsets':[0,True]}),{'error':'invalid-request'})

    def test_virtual_paths_component_matching(self):
        self.assertEqual(expected('snapshot-diff',PUBLIC['snapshot-diff'][1]),{'added':['/c'],'removed':['/b'],'changed':['/a']})
        self.assertEqual(expected('mount-routing',PUBLIC['mount-routing'][1]),{'paths':['/x','/root/ab','/c','/root']})
        for path in ('relative','/a/','//a','/a/../b','/./a'):
            self.assertEqual(expected('mount-routing',{'mounts':[],'paths':[path]}),{'error':'invalid-request'})

    def test_multimodule_state_and_atomic_rollback(self):
        self.assertEqual(expected('inventory-reservations',PUBLIC['inventory-reservations'][1]),{'results':['reserved','duplicate-token','released','unknown-token'],'available':[{'id':'a','quantity':5}],'active':[]})
        self.assertEqual(expected('atomic-transfers',PUBLIC['atomic-transfers'][1]),{'results':['insufficient','committed'],'balances':[{'id':'a','balance':0},{'id':'b','balance':5}]})
        q={'accounts':[{'id':'a','balance':2}],'batches':[[{'from':'a','to':'a','amount':3}],[]]}
        self.assertEqual(expected('atomic-transfers',q),{'results':['insufficient','committed'],'balances':[{'id':'a','balance':2}]})

    def test_schema_before_any_semantic_result(self):
        q=copy.deepcopy(PUBLIC['atomic-transfers'][1]);q['batches'].append([{'from':'a','to':'b','amount':None}])
        self.assertEqual(expected('atomic-transfers',q),{'error':'invalid-request'})
        for value in (True,1.0,None,'1'):
            self.assertEqual(expected('quota-boundary',{'limit':value,'used':0,'requests':[]}),{'error':'invalid-request'})
        self.assertEqual(batch_expected('quota-boundary',{'requests':[None,{'limit':0,'used':0,'requests':[]}]}),{'results':[{'error':'invalid-request'},{'accepted':[],'used':0,'remaining':0}]})

    def test_generation_deterministic_seed_sensitive_public_independent(self):
        for task in IDS:
            a=build(task,'alpha');self.assertEqual(a,build(task,'alpha'));self.assertNotEqual(a,build(task,'beta'))
            self.assertEqual(build(task,'alpha',True),build(task,'beta',True))
            for case in a:
                if 'request' in case['case']:self.assertLess(len(json.dumps(case['case']['request']).encode()),1048576)

    def test_maxima_and_off_by_one_without_reference_derived_expectations(self):
        from .boundaries import probes
        self.assertEqual(len(expected('record-frames',probes('record-frames')[0])['hex']),32*35*2)
        self.assertEqual(expected('record-frames',probes('record-frames')[0])['offsets'][-1],31*35)
        self.assertEqual(expected('little-endian-read',probes('little-endian-read')[0])['values'],[65280]*128)
        result=expected('atomic-transfers',probes('atomic-transfers')[0])
        self.assertEqual(result['results'],['committed']*32)
        self.assertEqual(sum(x['balance'] for x in result['balances']),32000000)
        for task in IDS:
            cases=probes(task)
            self.assertNotIn('error',expected(task,cases[0]))
            self.assertTrue(any(expected(task,x)=={'error':'invalid-request'} for x in cases[1:]))

    def test_signed_rollup_conservation_independent_generated_invariant(self):
        import random
        for i in range(100):
            q=random_request('data-rollup',random.Random(i),i);q['minimum']=-128000000
            result=expected('data-rollup',q)['groups']
            self.assertEqual(sum(x['total'] for x in result),sum(x['delta'] for x in q['rows']))
            self.assertEqual(sum(x['count'] for x in result),len(q['rows']))

    def test_atomic_money_conservation_across_generated_batches(self):
        import random
        for i in range(100):
            q=random_request('atomic-transfers',random.Random(i),i)
            final=expected('atomic-transfers',q)['balances']
            self.assertEqual(sum(a['balance'] for a in final),sum(a['balance'] for a in q['accounts']))
            self.assertTrue(all(a['balance']>=0 for a in final))

if __name__=='__main__':unittest.main()
