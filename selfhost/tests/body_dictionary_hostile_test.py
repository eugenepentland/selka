"""Negative mutation construction tests, not installed schema10 qualification."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import run_body_dictionary_hostile as H


def sample_graph():
    rows = []
    def add(kind, value=0, data=b'', children=(), names=()):
        rows.append((kind, value, data, list(children), list(names))); return len(rows) - 1
    def integer(value): return add(1, value)
    def flag(value): return add(2, value)
    def obj(**fields): return add(5, children=fields.values(), names=[k.encode() for k in fields])
    def seq(items): return add(6, children=items)
    def tag(name, payload): return add(7, data=name, children=[payload])
    def span(start, end): return obj(start=integer(start), end=integer(end))
    def node(ty, name, payload): return obj(ty=integer(ty), data=tag(name, payload))
    nodes = [node(0, b'integer', integer(91)), node(1, b'boolean', flag(1)),
             node(20, b'array', seq([])), node(0, b'integer', integer(7)), node(15, b'unit', add(0))]
    nodes += [node(40, b'array', seq([integer(2), integer(3), integer(2), integer(3)])),
              node(41, b'array', seq([integer(3), integer(3)])), node(42, b'array', seq([]))]
    def operation(ty, kind, owner, arguments):
        payload = obj(owner=integer(owner), kind=add(4, data=kind), arguments=seq([integer(i) for i in arguments]))
        nodes.append(node(ty, b'buffer_operation', payload))
    operation(15, b'write', 0, [2, 3])
    operation(15, b'write', 2, [3, 3])
    operation(15, b'write', 3, [3, 4])
    nodes.append(node(0, b'index', obj(base=integer(2), index=integer(3), from_end=flag(0))))
    nodes.append(node(0, b'index', obj(base=integer(5), index=integer(2), from_end=flag(0))))
    operation(0, b'get', 0, [2, 3])
    operation(1, b'contains', 0, [2])
    operation(0, b'length', 0, [])
    nodes.append(node(44, b'record', seq([obj(index=integer(0), value=integer(5))])))
    nodes.append(node(43, b'record', seq([obj(index=integer(0), value=integer(2)), obj(index=integer(1), value=integer(3))])))
    nodes.append(node(30, b'variant', obj(tag=integer(1), value=integer(3))))
    nodes.append(node(30, b'variant', obj(tag=integer(0), value=add(0))))
    def local(ty, mutable): return obj(ty=integer(ty), mutable=flag(mutable))
    functions = [obj(scope=obj(locals=seq([]))), obj(scope=obj(locals=seq([local(40, 1), local(40, 0), local(41, 1), local(42, 1)])))]
    ranges = [obj(nodes=span(0, 1)), obj(nodes=span(1, len(nodes)))]
    recipes = [tag(b'list', obj(id=integer(39), element=integer(0), span=span(0, 1)))]
    def recipe(name, identity, **arguments):
        record = obj(id=integer(identity), span=span(0, 1), **{k: integer(v) for k, v in arguments.items()})
        recipes.append(tag(b'collection', tag(name, record)))
    recipe(b'dict', 40, key=20, value=0)
    recipe(b'dict', 41, key=0, value=0)
    recipe(b'set', 42, element=0)
    recipe(b'dict_item', 43, key=20, value=0)
    recipe(b'dict_keys', 44, key=20, value=0)
    recipe(b'dict_values', 45, key=20, value=0)
    recipe(b'dict_items', 46, key=20, value=0)
    batch = obj(nodes=seq(nodes), statements=seq([]), functions=seq(functions), ranges=seq(ranges))
    root = tag(b'success', obj(batch=batch, recipes=seq(recipes)))
    payload = bytearray(b'SLKBKR01' + struct.pack('<II', len(rows), root))
    for kind, value, data, children, names in rows:
        payload.extend(bytes([kind]) + struct.pack('<q', value) + H.D.blob(data) + struct.pack('<I', len(children)))
        payload.extend(b''.join(struct.pack('<I', child) for child in children))
        payload.extend(struct.pack('<I', len(names)))
        for name in names: payload.extend(H.D.blob(name))
    return bytes(payload)


def frames(payload):
    raw = b'SLKBKI01test-input'
    digest = hashlib.sha256(raw).digest()
    identity = b'bodytest' + digest
    request = b'SLKBCK01' + struct.pack('<IIII', 1, 10, 0, len(raw)) + identity + raw
    reply = b'SLKBCK01' + struct.pack('<IIII', 1, 10, 1, len(payload)) + identity + payload
    return request, reply


class DictionaryHostileTests(unittest.TestCase):
    def test_closed_inventory_and_native_control_are_pinned(self):
        inventory = H.require_inventory()
        self.assertEqual(len(H.NAMES), 27)
        self.assertEqual(len(set(H.NAMES)), 27)
        self.assertEqual(inventory['native_control']['check_status'], 0)
        self.assertEqual(inventory['native_control']['release_verify_facts_leakcheck_status'], 7)
        self.assertNotIn('option_unwrap', H.NAMES)
        self.assertIn('foreign_operand', H.NAMES)

    def test_all_27_distinct_mutations_follow_nested_collection_roles(self):
        original = sample_graph()
        attacks = H.mutations(original)
        self.assertEqual(tuple(attacks), H.NAMES)
        self.assertEqual(len(set(attacks.values())), 27)
        self.assertTrue(all(payload != original for payload in attacks.values()))
        duplicate = H.D.CapturedGraph(attacks['recipe_duplicate'])
        recipes = duplicate.items(duplicate.field(duplicate.output, b'recipes'))
        ids = []
        for outer in recipes:
            inner = duplicate.rows[outer]['children'][0]
            record = duplicate.rows[inner]['children'][0] if duplicate.rows[outer]['data'] == b'collection' else inner
            ids.append(duplicate.rows[duplicate.field(record, b'id')]['integer'])
        self.assertEqual(ids, list(range(39, 48)))
        odd = H.D.CapturedGraph(attacks['dictionary_odd'])
        array = next(odd.rows[odd.field(n, b'data')]['children'][0] for n in odd.nodes
                     if odd.rows[odd.field(n, b'ty')]['integer'] == 40
                     and odd.rows[odd.field(n, b'data')]['data'] == b'array')
        self.assertEqual(len(odd.items(array)) % 2, 1)
        altered = H.D.CapturedGraph(attacks['option_none_payload'])
        variants = [altered.rows[altered.field(n, b'data')]['children'][0] for n in altered.nodes
                    if altered.rows[altered.field(n, b'data')]['data'] == b'variant']
        self.assertTrue(all(altered.rows[altered.field(v, b'value')]['kind'] == 1 for v in variants))
        missing = H.D.CapturedGraph(attacks['option_some_missing'])
        self.assertTrue(any(missing.rows[missing.field(v, b'value')]['kind'] == 0 for v in variants))

    def test_missing_authentic_roles_cannot_be_skipped(self):
        with patch.object(H.D, 'CapturedGraph', side_effect=RuntimeError('no authentic success')):
            with self.assertRaisesRegex(RuntimeError, 'no authentic success'):
                H.mutations(b'not a captured reply')
        payload = sample_graph().replace(b'dict_keys', b'fake_keys')
        with self.assertRaisesRegex(RuntimeError, 'all six collection'):
            H.mutations(payload)

    def test_read_and_length_mutations_follow_native_dictionary_shapes(self):
        original = sample_graph()
        graph = H.D.CapturedGraph(original)
        attacks = H.mutations(original)
        for name, expected_tag, expected_type in (("read_result", b'index', 1),
                                                   ("length_result", b'buffer_operation', 8)):
            changed = H.D.CapturedGraph(attacks[name])
            altered = [node for node in graph.nodes
                       if graph.rows[graph.field(node, b'ty')]['integer']
                       != changed.rows[changed.field(node, b'ty')]['integer']]
            self.assertEqual(len(altered), 1)
            node = altered[0]
            self.assertEqual(graph.rows[graph.field(node, b'ty')]['integer'], 0)
            self.assertEqual(changed.rows[changed.field(node, b'ty')]['integer'], expected_type)
            data = graph.rows[graph.field(node, b'data')]
            self.assertEqual(data['data'], expected_tag)
            operation = data['children'][0]
            if name == 'read_result':
                base = graph.rows[graph.field(operation, b'base')]['integer']
                self.assertEqual(graph.rows[graph.field(graph.nodes[base], b'ty')]['integer'], 40)
            else:
                self.assertEqual(graph.rows[graph.field(operation, b'kind')]['data'], b'length')

    def test_frame_correlation_rejects_old_schema_nonce_digest_and_trailing_bytes(self):
        request, reply = frames(sample_graph())
        H.bound_capture(request, reply)
        for offset, value in ((8, 2), (12, 7), (16, 0)):
            changed = bytearray(reply); struct.pack_into('<I', changed, offset, value)
            with self.assertRaises(RuntimeError): H.bound_capture(request, bytes(changed))
        for offset in (24, 32):
            changed = bytearray(reply); changed[offset] ^= 1
            with self.assertRaises(RuntimeError): H.bound_capture(request, bytes(changed))
        with self.assertRaises(RuntimeError): H.bound_capture(request, reply + b'X')

    def test_exact_refusal_cannot_be_replaced_by_unrelated_host_error(self):
        protocol = json.dumps({'version': 'diagnostic-v1', 'kind': 'message', 'message':
            'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}).encode()
        H.J.require_rejection((2, b'', protocol))
        for result in ((1, b'', protocol), (2, b'escaped', protocol), (2, b'', b'ComponentMissing'),
                       (2, b'', protocol.replace(b'frame malformed', b'artifact missing'))):
            with self.assertRaises(RuntimeError): H.J.require_rejection(result)

    def test_schema10_package_hook_restores_even_after_capture_failure(self):
        original = H.D.packages
        with self.assertRaisesRegex(RuntimeError, 'stop'):
            with H.capture_boundary():
                self.assertIs(H.D.packages, H.packages)
                raise RuntimeError('stop')
        self.assertIs(H.D.packages, original)

    def test_first_bad_hostile_verdict_is_persisted_before_failure_and_uncached(self):
        request, reply = frames(sample_graph())
        args = SimpleNamespace(compiler=Path('/host'), component_dir=Path('/packages'), zig=Path('/zig'))
        checkpoints = []
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary) / 'evidence'
            with patch.object(H, 'require_inventory'), patch.object(H, 'packages', return_value={'body-check': 'schema10'}), \
                 patch.object(H.F, 'digest', return_value='identity'), \
                 patch.object(H.D, 'private_fixture', return_value=(Path('/private'), Path('/real'))), \
                 patch.object(H.D, 'capture_exchange', return_value=((0, b'', b''), request, reply)), \
                 patch.object(H.F, 'execute', side_effect=[(0, b'', b''), (2, b'', b'ComponentMissing')]) as execute:
                with self.assertRaises(RuntimeError):
                    H.run(args, work, Path('/empty'), lambda records, capture: checkpoints.append((list(records), dict(capture))))
            self.assertEqual(checkpoints[-1][0][0]['name'], H.NAMES[0])
            self.assertEqual(checkpoints[-1][0][0]['stderr_hex'], b'ComponentMissing'.hex())
            self.assertTrue((work / (H.NAMES[0] + '.bin')).is_file())
            self.assertIn('--no-cache', execute.call_args.args[0])
            self.assertIn('BODY_REPLY', execute.call_args.args[1])


if __name__ == '__main__':
    unittest.main()
