"""Adversarial installed B1 qualification accounting and named graph mutations."""
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import run_body_check_qualification as D
sys.path.insert(0,str(Path(__file__).parents[1]))
import test_body_checks as G

class BodyQualificationTests(unittest.TestCase):
    def summary(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        n=len(manifest)+2*sum(bool(v.get('typed')) and not v.get('library') for v in manifest.values())+16
        return (f'body_check qualification: {n} workflows, {n*2} comparisons, 30 warm deployment checks, 4 live session checks; 0 failed, 0 skipped\n'
                'body_check transport: 1 valid, 13 malformed; 0 failed, 0 skipped\n'
                'body_check forged replies: 8 rejected; 0 failed, 0 skipped\n'
                'body_check publication: 2 host failures; 0 failed, 0 skipped\n')

    def test_gate_rejects_incomplete_or_duplicate_verdicts(self):
        good=self.summary();G.require_summary(good)
        for bad in (good+good,good.replace('30 warm','29 warm'),good.replace('4 live','0 live'),good.replace('13 malformed','12 malformed'),good.replace('8 rejected','0 rejected'),good.replace('2 host','1 host'),good.replace('0 skipped','1 skipped')):
            with self.assertRaises(RuntimeError):G.require_summary(bad)

    def test_frame_binds_whole_request(self):
        payload=b'raw body\x00'+ 'éλ'.encode();frame=D.frame(payload)
        self.assertEqual(frame[:8],b'SLKBCK01')
        self.assertEqual(struct.unpack('<IIII',frame[8:24]),(1,1,0,len(payload)))
        self.assertEqual(frame[32:64],D.F.hashlib.sha256(payload).digest())
        self.assertEqual(frame[64:],payload)

    def test_package_authentication_requires_all_seven(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);artifact=root/'artifact';artifact.write_bytes(b'fixture')
            for name,protocol,schema in [('test-index',1,1),('cache-plan',2,2),('lexer-pilot',1,2),('parser-pilot',1,2),('declaration-index',1,1),('type-interface',1,1),('body-check',1,1)]:
                (root/(name+'.json')).write_text(json.dumps(dict(format=1,component=name,protocol=protocol,schema=schema,artifact='artifact',sha256=D.F.digest(artifact))))
            self.assertEqual(len(D.packages(root)),7)
            manifest=root/'body-check.json';value=json.loads(manifest.read_text());value['schema']=True;manifest.write_text(json.dumps(value))
            with self.assertRaisesRegex(RuntimeError,'noninteger'):D.packages(root)
            manifest.unlink()
            with self.assertRaises(FileNotFoundError):D.packages(root)

    def test_environment_removes_caller_modes_and_oracle_controls(self):
        from unittest.mock import patch
        with patch.dict(D.os.environ,{'MYLANG_BODY_CHECK_MODE':'bad','MYLANG_TYPE_INTERFACE_MODE':'component','PILOT_REPLY':'bad'}):
            env=D.environment('shadow',Path('/components'),Path('/empty'))
        self.assertEqual(env['MYLANG_BODY_CHECK_MODE'],'shadow')
        self.assertEqual(env['MYLANG_TYPE_INTERFACE_MODE'],'reference')
        self.assertNotIn('PILOT_REPLY',env)

    def test_named_graph_parser_rejects_truncation_and_wrong_root(self):
        for data in (b'',b'SLKBKR01'+struct.pack('<II',0,0),b'SLKBKR01'+struct.pack('<II',1,1),b'SLKBKR01'+struct.pack('<II',1,0)+b'\x01'):
            with self.assertRaises(RuntimeError):D.graph_rows(data)

    def test_four_forges_change_authentic_typed_semantic_fields(self):
        rows=[]
        def add(kind,integer=0,data=b'',children=(),names=()):
            rows.append((kind,integer,data,children,names));return len(rows)-1
        def integer(value):return add(1,value)
        def record(**fields):return add(5,children=list(fields.values()),names=[k.encode() for k in fields])
        def sequence(items):return add(6,children=items)
        def tagged(name,child):return add(7,data=name.encode(),children=[child])
        span=record(start=integer(0),end=integer(1))
        node=record(ty=integer(0),span=span,data=tagged('integer',integer(7)))
        statement=record(span=span,terminates=add(2,1),data=tagged('ret',integer(0)))
        function=record(scope=record(body=integer(0),locals=sequence([])))
        batch=record(nodes=sequence([node]),statements=sequence([statement]),functions=sequence([function]))
        root=tagged('success',record(batch=batch))
        data=bytearray(b'SLKBKR01'+struct.pack('<II',len(rows),root))
        for kind,value,text,children,names in rows:
            data.extend(struct.pack('<BqI',kind,value,len(text))+text+struct.pack('<I',len(children)))
            for child in children:data.extend(struct.pack('<I',child))
            data.extend(struct.pack('<I',len(names)))
            for name in names:data.extend(struct.pack('<I',len(name))+name)
        original=bytes(data);variants=D.mutate_success(original)
        self.assertEqual(len(set(variants)),4)
        for value in variants:
            self.assertNotEqual(value,original)
            self.assertEqual(len(value),len(original))
            D.graph_rows(value)

    def test_profile_selection_is_explicit_and_nonempty(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        refusals=[n for n,v in manifest.items() if v['status']==2]
        self.assertEqual(set(refusals),{'profile_managed.my','profile_generic.my','profile_lambda.my','profile_division.my','profile_chained_comparison.my'})
        self.assertTrue(all((D.FIXTURES/Path(n).with_suffix('.input')).is_file() for n in manifest))
        self.assertTrue(manifest['library.my']['library'])

if __name__=='__main__':unittest.main()
