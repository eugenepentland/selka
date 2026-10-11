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
        n=len(manifest)+2*sum(bool(v.get('typed')) and not v.get('library') for v in manifest.values())+sum('result' in v for v in manifest.values())+sum('library_check_status' in v for v in manifest.values())+16
        return (f'body_check qualification: {n} workflows, {n*2} comparisons, 30 warm deployment checks, 4 live session checks; 0 failed, 0 skipped\n'
                'body_check transport: 1 valid, 22 malformed; 0 failed, 0 skipped\n'
                'body_check forged replies: 92 rejected; 0 failed, 0 skipped\n'
                'body_check publication: 2 host failures; 0 failed, 0 skipped\n')

    def test_gate_rejects_incomplete_or_duplicate_verdicts(self):
        good=self.summary();G.require_summary(good)
        for bad in (good+good,good.replace('30 warm','29 warm'),good.replace('4 live','0 live'),good.replace('22 malformed','18 malformed'),good.replace('92 rejected','8 rejected'),good.replace('2 host','1 host'),good.replace('0 skipped','1 skipped')):
            with self.assertRaises(RuntimeError):G.require_summary(bad)

    def test_flow_diagnostics_pin_ordered_repairs_and_related_spans(self):
        manifest = json.loads((D.FIXTURES/'manifest.json').read_text())
        names = [name for name, spec in manifest.items() if 'diagnostics' in spec and not name.startswith('bytes_')]
        self.assertEqual(len(names), 6)
        scalar = manifest['checked_implicit_scalar_discard_error.my']['diagnostics'][0]
        self.assertEqual(scalar['edits'], [{'bytes': {'start': 59, 'end': 59}, 'text': '_ = '}])
        pending = manifest['checked_implicit_pending_discard_error.my']['diagnostics'][0]
        self.assertEqual(pending['edits'], [])
        path = manifest['checked_short_circuit_path_error.my']['diagnostics'][0]
        self.assertEqual(path['notes'][0]['bytes'], {'start': 327, 'end': 333})
        annotated = manifest['checked_pending_list_annotated_error.my']
        self.assertEqual(annotated['boundary'], 'retained-generic-bound')
        self.assertEqual(annotated['diagnostics'][0]['code'], 'E_GENERIC_REQUIREMENT')
        raw = {'code': 'E', 'message': 'test', 'location': {'bytes': {'start': 1, 'end': 2}},
               'notes': [], 'fix': {'edits': [{'bytes': {'start': 1, 'end': 1}, 'text': 'é'}]}}
        self.assertEqual(D.diagnostic_contract(raw)['edits'][0]['text'].encode(), b'\xc3\xa9')

    def test_forged_payload_changes_force_new_component_execution(self):
        from contextlib import ExitStack
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
            work=Path(temporary)
            q=SimpleNamespace(work=work,source=work,compiler=Path('/compiler'),
                              empty_path=work,modes=['shadow','component'])
            captures={name:b'0'*64 for name in ('variant_named_order.my','checked_try_fail.my',
                                               'checked_loop_consumption.my','optional_parse_int_demand.my')}
            mutators=['mutate_success','mutate_lists','mutate_records','mutate_variants','mutate_matches',
                      'mutate_propagation','mutate_transfer','mutate_catalog_recipes']
            has_buffers=hasattr(D,'mutate_buffers')
            if has_buffers:mutators.append('mutate_buffers')
            expected=20 if has_buffers else 18
            for name in mutators:
                stack.enter_context(patch.object(D,name,return_value=[b'changed']))
            stack.enter_context(patch.object(D,'FORGED_CHECKS',expected))
            def execute(command,env,cwd):
                self.assertIn('--no-cache',command)
                self.assertEqual(Path(env['BODY_REPLY']).read_bytes(),b'changed')
                return (2,b'',b'ComponentProtocol')
            spy=stack.enter_context(patch.object(D.F,'execute',side_effect=execute))
            inputs=[None,q,work,b'0'*64,b'0'*64,b'0'*64,captures]
            if has_buffers:inputs.append(b'0'*64)
            self.assertEqual(D.forged_replies(*inputs),expected)
            self.assertEqual(spy.call_count,expected)

    def test_capture_and_publication_require_new_wrapper_side_effects(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temporary:
            work=Path(temporary)
            q=SimpleNamespace(work=work,source=work,compiler=Path('/compiler'),empty_path=work)
            request=work/'capture-request-component.bin'
            reply=work/'capture-reply-component.bin'
            request.write_bytes(b'stale request')
            reply.write_bytes(b'stale reply')
            def execute(command,env,cwd):
                self.assertIn('--no-cache',command)
                self.assertFalse(request.exists())
                self.assertFalse(reply.exists())
                Path(env['BODY_REQUEST']).write_bytes(b'fresh request')
                Path(env['BODY_CAPTURE']).write_bytes(b'fresh reply')
                self.assertEqual(env['BODY_MUTATE'],str(work/'lexer-pilot.json'))
                return (2,b'',b'ComponentMissing')
            with patch.object(D.F,'execute',side_effect=execute):
                result,actual_request,actual_reply=D.capture_exchange(None,q,work,work/'real','main.my',mutate=True)
            self.assertEqual(result[0],2)
            self.assertEqual((actual_request,actual_reply),(b'fresh request',b'fresh reply'))

    def test_frame_binds_whole_request(self):
        payload=b'raw body\x00'+ 'éλ'.encode();frame=D.frame(payload)
        self.assertEqual(frame[:8],b'SLKBCK01')
        self.assertEqual(struct.unpack('<IIII',frame[8:24]),(1,10,0,len(payload)))
        self.assertEqual(frame[32:64],D.F.hashlib.sha256(payload).digest())
        self.assertEqual(frame[64:],payload)

    def test_package_authentication_requires_all_seven(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);artifact=root/'artifact';artifact.write_bytes(b'fixture')
            for name,protocol,schema in [('test-index',1,1),('cache-plan',2,2),('lexer-pilot',1,2),('parser-pilot',1,2),('declaration-index',1,1),('type-interface',1,1),('body-check',1,10)]:
                (root/(name+'.json')).write_text(json.dumps(dict(format=1,component=name,protocol=protocol,schema=schema,artifact='artifact',sha256=D.F.digest(artifact))))
            self.assertEqual(len(D.packages(root)),7)
            manifest=root/'body-check.json';value=json.loads(manifest.read_text());value['schema']=6;manifest.write_text(json.dumps(value))
            with self.assertRaisesRegex(RuntimeError,'invalid qualified identity'):D.packages(root)
            value['schema']=1;manifest.write_text(json.dumps(value))
            self.assertEqual(len(D.packages(root,body_schema=1)),7)
            with self.assertRaisesRegex(RuntimeError,'invalid qualified identity'):D.packages(root)
            value['schema']=True;manifest.write_text(json.dumps(value))
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

    def test_body_value_policy_does_not_expand_syntax_or_other_transport_limits(self):
        from unittest.mock import patch
        import run_parser_pilot as P
        import run_declaration_qualification as C
        import run_type_interface_qualification as T
        self.assertEqual(D.BODY_VALUE_LIMIT,2097152)
        self.assertEqual((D.SCHEMA,D.MALFORMED_CHECKS,D.FORGED_CHECKS),(10,22,92))
        for count,root in ((1048577,0),(2097152,2097151)):
            # Admitted body header; the deliberately absent rows fail next.
            with self.assertRaisesRegex(RuntimeError,'truncated captured kind'):
                D.graph_rows(b'SLKBKR01'+struct.pack('<II',count,root))
        for count,root in ((2097153,0),(2097152,2097152)):
            with self.assertRaisesRegex(RuntimeError,'bad captured outcome root'):
                D.graph_rows(b'SLKBKR01'+struct.pack('<II',count,root))
        with self.assertRaisesRegex(AssertionError,'invalid syntax value count/root'):
            P.wire_tree(b'SLKAST01'+struct.pack('<II',1048577,0))
        with tempfile.TemporaryDirectory() as temporary:
            work=Path(temporary)
            body_requests=[]
            def body_execute(command,env,cwd,timeout):
                request=Path(command[2]).read_bytes()
                body_requests.append(request)
                if len(body_requests)>1:return (2,b'',b'fixture refusal')
                payload=b'SLKBKR01'
                return (0,request[:16]+struct.pack('<II',1,len(payload))+request[24:64]+payload,b'')
            valid=D.frame(b'SLKBKI01'+struct.pack('<II',1,0))
            with patch.object(D.F,'execute',side_effect=body_execute), patch.object(D,'mutate_input',return_value=[b'bad']*5):
                verdict=D.transport(Path('/fixture'),work,{},valid)
            self.assertEqual(verdict['malformed'],22)
            headers=[struct.unpack('<II',r[72:80]) for r in body_requests if len(r)>=80 and r[64:72]==b'SLKBKI01']
            self.assertIn((2097153,0),headers)
            self.assertIn((1,2097152),headers)
            for module,magic,reply,tail,expected in (
                (C,b'SLKDCR01',struct.pack('<III',0,0,0),20,19),
                (T,b'SLKTYR01',struct.pack('<IIIIII',0,1,0,1,0,0),56,35),
            ):
                requests=[]
                def execute(command,env,cwd,timeout):
                    request=Path(command[2]).read_bytes()
                    requests.append(request)
                    if len(requests)>1:return (2,b'',b'fixture refusal')
                    payload=magic+reply
                    return (0,request[:16]+struct.pack('<II',1,len(payload))+request[24:64]+payload,b'')
                with patch.object(module.F,'execute',side_effect=execute):
                    verdict=module.transport(Path('/fixture'),work,{})
                self.assertEqual(verdict['malformed'],expected)
                # Independent key/catalog caps still probe 65,537, not 2M.
                self.assertTrue(any(len(r)>=64+tail and 65537 in struct.unpack('<'+'I'*(tail//4),r[-tail:]) for r in requests[1:]))
                self.assertTrue(any(len(r)>1048576 and struct.pack('<I',1048577) in r for r in requests[1:]))

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

    def test_input_mutations_preserve_bounded_graph_and_corrupt_dto_kinds(self):
        rows=[(4,b'source',[],[]),(5,b'',[0],[b'source']),
              (2,b'',[],[]),(0,b'',[],[]),(5,b'',[2,3],[b'available',b'identity']),
              (5,b'',[4],[b'byte_buffer']),(5,b'',[5],[b'templates']),
              (5,b'',[1,6],[b'context',b'catalog'])]
        payload=bytearray(b'SLKBKI01'+struct.pack('<II',len(rows),7))
        for kind,data,children,names in rows:
            payload.extend(struct.pack('<BqI',kind,0,len(data))+data+struct.pack('<I',len(children)))
            for child in children:payload.extend(struct.pack('<I',child))
            payload.extend(struct.pack('<I',len(names)))
            for name in names:payload.extend(struct.pack('<I',len(name))+name)
        variants=D.mutate_input(bytes(payload))
        self.assertEqual(len(variants),5)
        self.assertEqual(len(set(variants)),5)
        for value in variants:
            self.assertEqual(len(value),len(payload))
            self.assertNotEqual(value,payload)
            D.graph_rows(value,b'SLKBKI01')

    def test_list_recipe_forgeries_keep_frame_shape_and_change_only_target_values(self):
        rows = []
        def add(kind, integer=0, data=b'', children=(), names=()):
            rows.append((kind, integer, data, children, names))
            return len(rows)-1
        def record(**fields):
            return add(5, children=list(fields.values()), names=[key.encode() for key in fields])
        identity, element = add(1, 27), add(1, 0)
        start, end = add(1, 0), add(1, 4)
        span = record(start=start, end=end)
        recipe = record(id=identity, element=element, span=span)
        tagged_recipe = add(7,data=b'list',children=[recipe])
        output = record(recipes=add(6, children=[tagged_recipe]))
        root = add(7, data=b'success', children=[output])
        payload = bytearray(b'SLKBKR01' + struct.pack('<II', len(rows), root))
        for kind, value, data, children, names in rows:
            payload.extend(struct.pack('<BqI', kind, value, len(data)) + data + struct.pack('<I', len(children)))
            for child in children:
                payload.extend(struct.pack('<I', child))
            payload.extend(struct.pack('<I', len(names)))
            for name in names:
                payload.extend(struct.pack('<I', len(name)) + name)
        original = bytes(payload)
        variants = D.mutate_lists(original)
        self.assertEqual(len(set(variants)), 4)
        wanted = [(identity, 28), (element, 27), (element, 7), (end, 2147483647)]
        before, _ = D.graph_rows(original)
        for changed, (target, value) in zip(variants, wanted):
            after, actual_root = D.graph_rows(changed)
            self.assertEqual(actual_root, root)
            self.assertEqual(len(changed), len(original))
            self.assertEqual(after[target]['integer'], value)
            for index, (a, b) in enumerate(zip(before, after)):
                self.assertEqual(b, dict(a, integer=value) if index == target else a)

    def test_record_forgery_targets_duplicate_out_of_bounds_read_and_update_indices(self):
        rows = []
        def add(kind, integer=0, data=b'', children=(), names=()):
            rows.append((kind, integer, data, children, names))
            return len(rows)-1
        def record(**fields):
            return add(5, children=list(fields.values()), names=[key.encode() for key in fields])
        def tagged(name, child):
            return add(7, data=name, children=[child])
        first, second, projection, update = [add(1, value) for value in (0, 1, 0, 1)]
        initializers = [record(index=first), record(index=second)]
        constructor_node = record(data=tagged(b'record', add(6, children=initializers)))
        field_node = record(data=tagged(b'field', record(index=projection)))
        update_node = record(data=tagged(b'update', record(fields=add(6, children=[record(index=update)]))))
        batch = record(nodes=add(6, children=[constructor_node, field_node, update_node]))
        root = tagged(b'success', record(batch=batch))
        payload = bytearray(b'SLKBKR01' + struct.pack('<II', len(rows), root))
        for kind, value, data, children, names in rows:
            payload.extend(struct.pack('<BqI', kind, value, len(data)) + data + struct.pack('<I', len(children)))
            for child in children:
                payload.extend(struct.pack('<I', child))
            payload.extend(struct.pack('<I', len(names)))
            for name in names:
                payload.extend(struct.pack('<I', len(name)) + name)
        original = bytes(payload)
        variants = D.mutate_records(original)
        self.assertEqual(len(set(variants)), 4)
        before, _ = D.graph_rows(original)
        for changed, (target, value) in zip(variants, [(first, 1), (first, 2), (projection, 2147483647), (update, 2147483647)]):
            after, actual_root = D.graph_rows(changed)
            self.assertEqual(actual_root, root)
            self.assertEqual(len(changed), len(original))
            self.assertEqual(after[target]['integer'], value)
            for index, (a, b) in enumerate(zip(before, after)):
                self.assertEqual(b, dict(a, integer=value) if index == target else a)

    def test_record_manifest_promotes_recursive_lists_and_keeps_global_invariant_refusals(self):
        manifest = json.loads((D.FIXTURES/'manifest.json').read_text())
        self.assertNotIn('record_recursive_profile.my', manifest)
        self.assertEqual(manifest['record_recursive_lists.my']['result'], 7)
        self.assertTrue(manifest['record_recursive_lists.my']['typed'])
        self.assertEqual(manifest['record_invariant_unused.my']['status'], 2)
        self.assertEqual(manifest['record_invariant_imported.my']['status'], 2)
        self.assertNotIn('Box', (D.FIXTURES/'record_invariant_unused.input').read_text().split('func main', 1)[1])
        self.assertIn('@invariant', (D.FIXTURES/'record_invariant_dependency.input').read_text())

    def test_variant_match_propagation_transfer_and_tagged_recipe_attacks(self):
        rows=[]
        def add(kind, integer=0, data=b'', children=(), names=()):
            rows.append((kind,integer,data,children,names));return len(rows)-1
        def integer(value):return add(1,value)
        def record(**fields):return add(5,children=list(fields.values()),names=[key.encode() for key in fields])
        def sequence(values):return add(6,children=values)
        def tagged(tag,value):return add(7,data=tag,children=[value])
        span=record(start=integer(0),end=integer(1))
        scalar=record(ty=integer(0),span=span,data=tagged(b'integer',integer(7)))
        variant=record(ty=integer(19),span=span,data=tagged(b'variant',record(tag=integer(0),value=integer(2))))
        payload=record(ty=integer(20),span=span,data=tagged(b'record',sequence([])))
        propagation=record(ty=integer(0),span=span,data=tagged(b'propagate',record(value=integer(1),output=integer(21))))
        arms=[record(tag=integer(0),slot=integer(0),body=integer(0)),record(tag=integer(1),slot=add(0),body=integer(0))]
        match=record(span=span,data=tagged(b'match',record(value=integer(1),arms=sequence(arms))))
        ownership=record(transfer_span=span,transfer_available=add(2,0))
        local=record(ty=integer(0),ownership=ownership)
        function=record(scope=record(locals=sequence([local])))
        batch=record(nodes=sequence([scalar,variant,payload,propagation]),statements=sequence([match]),functions=sequence([function]))
        recipes=[tagged(b'result',record(id=integer(31),success=integer(0),failure=integer(19),span=span)),tagged(b'option',record(id=integer(32),element=integer(0),span=span))]
        root=tagged(b'success',record(batch=batch,recipes=sequence(recipes)))
        payload=bytearray(b'SLKBKR01'+struct.pack('<II',len(rows),root))
        for kind,value,data,children,names in rows:
            payload.extend(struct.pack('<BqI',kind,value,len(data))+data+struct.pack('<I',len(children)))
            for child in children:payload.extend(struct.pack('<I',child))
            payload.extend(struct.pack('<I',len(names)))
            for name in names:payload.extend(struct.pack('<I',len(name))+name)
        original=bytes(payload)
        groups=[D.mutate_variants(original),D.mutate_matches(original),D.mutate_propagation(original),D.mutate_transfer(original),D.mutate_catalog_recipes(original,b'result'),D.mutate_catalog_recipes(original,b'option')]
        self.assertEqual([len(group) for group in groups],[4,4,3,2,4,4])
        before,_=D.graph_rows(original)
        for changed in sum(groups,[]):
            after,actual_root=D.graph_rows(changed)
            self.assertEqual(len(changed),len(original))
            self.assertEqual(actual_root,root)
            differences=[index for index,(a,b) in enumerate(zip(before,after)) if a!=b]
            self.assertEqual(len(differences),1)
            index=differences[0]
            self.assertEqual(after[index],dict(before[index],integer=after[index]['integer']))

    def test_b5_manifest_preserves_every_proposal_case_and_promotes_union(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        inventory=json.loads((D.FIXTURES/'b5_inventory.json').read_text())
        cases,donors=set(inventory['cases']),set(inventory['donors'])
        names=cases|donors
        self.assertEqual(len(inventory['cases']),39)
        self.assertEqual(len(cases),39)
        self.assertEqual(donors,{'variant_import_dep.my'})
        self.assertEqual(len(names),40)
        self.assertEqual(names-set(manifest),donors)
        self.assertTrue(all((D.FIXTURES/Path(name).with_suffix('.input')).is_file() for name in names))
        self.assertEqual(inventory['historical_counts'],{'success':21,'diagnostic':14,'profile':4})
        self.assertEqual(inventory['counts'],{'success':23,'diagnostic':14,'profile':2})
        demand = (D.FIXTURES/'optional_parse_int_demand.input').read_text()
        self.assertNotIn('?', demand)
        self.assertNotIn('Option', demand)
        self.assertIn('parse_int', demand)
        self.assertEqual(manifest['record_union_profile.my']['result'],7)
        self.assertEqual(manifest['variant_recursive_lists.my']['result'],7)
        self.assertEqual(manifest['variant_boxed_recursive_profile.my']['status'],2)
        self.assertEqual(manifest['variant_generic_profile.my']['status'],2)
        self.assertEqual(sum(manifest[name]['status']==0 for name in names&set(manifest)),23)
        self.assertEqual(sum(manifest[name]['status']==1 for name in names&set(manifest)),14)
        self.assertEqual(sum(manifest[name]['status']==2 for name in names&set(manifest)),2)

    def test_b6_inventory_preserves_history_and_pins_native_diagnostics(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        inventory=json.loads((D.FIXTURES/'b6_inventory.json').read_text())
        self.assertEqual(len(manifest),169)
        self.assertEqual(len(set(inventory['cases'])),21)
        self.assertEqual(inventory['counts'],{'success':10,'diagnostic':9,'profile':2})
        self.assertTrue(all(name in manifest for name in inventory['cases']))
        self.assertEqual(sum(manifest[name]['status']==0 for name in inventory['cases']),10)
        self.assertEqual(sum(manifest[name]['status']==1 for name in inventory['cases']),9)
        self.assertTrue(all(manifest[name].get('diagnostics') for name in inventory['cases']
                            if manifest[name]['status']==1))
        self.assertEqual(manifest['bytes_buffer_arity_precedence_error.my']['diagnostics'][0]['code'],'E_ARITY')
        self.assertEqual(manifest['bytes_buffer_argument_precedence_error.my']['diagnostics'][0]['code'],'E_IMMUTABLE')
        self.assertEqual(manifest['bytes_buffer_function_shadow.my']['library_check_status'],0)
        self.assertEqual(D.SCHEMA,10)

    def test_buffer_forgeries_require_real_recipe_and_preserve_named_graph(self):
        rows=[]
        def add(kind,integer=0,data=b'',children=(),names=()):
            rows.append((kind,integer,data,list(children),list(names)))
            return len(rows)-1
        def integer(value):return add(1,value)
        def record(**fields):return add(5,children=fields.values(),names=[k.encode() for k in fields])
        def sequence(items):return add(6,children=items)
        def tagged(name,child):return add(7,data=name.encode(),children=[child])
        def node(ty,data):return record(ty=integer(ty),span=span,data=data)
        span=record(start=integer(0),end=integer(10))
        nodes=[node(20,tagged('list',sequence([]))),node(21,tagged('cast',integer(0))),
               node(19,tagged('cast',integer(1))),node(0,tagged('integer',integer(1)))]
        reserve=record(kind=add(3,data=b'buffer_reserve'),owner=integer(0),arguments=sequence([integer(3)]))
        append=record(kind=add(3,data=b'buffer_append_range'),owner=integer(0),
                      arguments=sequence([integer(2),integer(3),integer(3)]))
        nodes += [node(1,tagged('buffer_operation',reserve)),node(1,tagged('buffer_operation',append))]
        local=record(ty=integer(21),mutable=add(2,integer=1))
        function=record(scope=record(locals=sequence([local])))
        batch=record(nodes=sequence(nodes),statements=sequence([]),functions=sequence([function]))
        recipe=tagged('byte_buffer',record(id=integer(21),span=span))
        output=record(batch=batch,recipes=sequence([recipe]))
        root=tagged('success',output)
        payload=bytearray(b'SLKBKR01'+struct.pack('<II',len(rows),root))
        for kind,value,data,children,names in rows:
            payload.extend(struct.pack('<Bq',kind,value)+D.blob(data)+struct.pack('<I',len(children)))
            for child in children:payload.extend(struct.pack('<I',child))
            payload.extend(struct.pack('<I',len(names)))
            for name in names:payload.extend(D.blob(name))
        variants=D.mutate_buffers(bytes(payload))
        self.assertEqual(len(variants),13)
        self.assertEqual(len(set(variants)),13)
        self.assertTrue(all(value!=payload for value in variants))
        self.assertTrue(all(D.graph_rows(value)[1]==root for value in variants))
        no_recipe=D.rewrite_edges(bytes(payload),{D.CapturedGraph(payload).field(output,b'recipes'):[]})
        with self.assertRaisesRegex(RuntimeError,'no byte_buffer append'):D.mutate_buffers(no_recipe)

    def test_managed_measurement_edits_preserve_text_and_change_byte_length(self):
        import measure_managed_body_adoption as M
        self.assertIn('é😀ab'.encode(),M.HELPER)
        values=[M.edited(M.HELPER,index) for index in range(6)]
        self.assertEqual(len(set(values)),6)
        self.assertEqual(values[0],M.HELPER)
        for index,value in enumerate(values):
            self.assertIn(b'b"xyz'+b'!'*index+b'"',value)
            self.assertIn('é😀ab'.encode(),value)

    def test_profile_selection_is_explicit_and_nonempty(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        refusals=[n for n,v in manifest.items() if v['status']==2]
        self.assertEqual(set(refusals),{'profile_generic.my','profile_lambda.my','profile_range_stride.my','profile_text_method.my','record_generic_profile.my','record_invariant_profile.my','variant_generic_profile.my','variant_boxed_recursive_profile.my','record_invariant_unused.my','record_invariant_imported.my','bytes_encode_profile.my','bytes_decode_profile.my'})
        self.assertEqual(manifest['profile_managed.my']['result'], 1)
        self.assertEqual(manifest['profile_text_repeat.my'], {'status': 0, 'boundary': 'text-repetition-body', 'typed': True, 'library': False, 'result': 7})
        self.assertEqual(manifest['profile_chained_comparison.my'], {'status': 0, 'boundary': 'chained-comparison-body', 'typed': True, 'library': False, 'result': 7})
        self.assertTrue(all((D.FIXTURES/Path(n).with_suffix('.input')).is_file() for n in manifest))
        self.assertTrue(manifest['library.my']['library'])

if __name__=='__main__':unittest.main()
