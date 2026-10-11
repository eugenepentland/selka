"""Synthetic construction checks only; not authentic schema10 qualification."""
import struct
import unittest
import run_body_structural_hostile as H


def synthetic_graph():
    rows = []
    def add(kind, integer=0, data=b'', children=(), names=()):
        rows.append({'kind': kind, 'integer': integer, 'data': data,
                     'children': list(children), 'names': list(names)})
        return len(rows) - 1
    def integer(value): return add(1, value)
    def boolean(value): return add(2, value)
    def obj(**fields): return add(5, children=fields.values(), names=[k.encode() for k in fields])
    def seq(children): return add(6, children=children)
    def tag(name, payload): return add(7, data=name, children=[payload])
    def node(ty, name, payload): return obj(ty=integer(ty), data=tag(name, payload))
    def span(start, end): return obj(start=integer(start), end=integer(end))
    # Function0 owns the foreign int; Function1 owns every structural operand.
    nodes = [node(0, b'integer', integer(99)), node(0, b'integer', integer(3)),
             node(1, b'boolean', boolean(1)), node(0, b'integer', integer(4)),
             node(0, b'integer', integer(0))]
    fields = [obj(index=integer(0), value=integer(1)),
              obj(index=integer(1), value=integer(2))]
    pair_fields = seq(fields); nodes.append(node(30, b'record', pair_fields))
    elements = [integer(1), integer(3)]; elements_id = seq(elements)
    nodes.append(node(22, b'array', elements_id))
    index = obj(base=integer(6), index=integer(4), from_end=boolean(0))
    index_node = node(0, b'index', index); nodes.append(index_node)
    replacement = obj(base=integer(6), index=integer(4), value=integer(1), from_end=boolean(0))
    replace_node = node(22, b'replace', replacement); nodes.append(replace_node)
    store = obj(slot=integer(0), value=integer(8), element=boolean(1))
    statements = [obj(data=tag(b'assign', store))]
    def local(ty, mutable): return obj(ty=integer(ty), mutable=boolean(mutable))
    functions = [obj(scope=obj(locals=seq([]))),
                 obj(scope=obj(locals=seq([local(22, 1), local(22, 0)])))]
    ranges = [obj(nodes=span(0, 1)), obj(nodes=span(1, len(nodes)))]
    tuple_elements = [integer(0), integer(1)]
    pair = obj(id=integer(30), elements=seq(tuple_elements))
    recipes = [tag(b'structural', tag(b'tuple', pair))]
    batch = obj(nodes=seq(nodes), statements=seq(statements), functions=seq(functions), ranges=seq(ranges))
    root = tag(b'success', obj(batch=batch, recipes=seq(recipes)))
    payload = bytearray(b'SLKBKR01' + struct.pack('<II', len(rows), root))
    for row in rows:
        payload.extend(bytes([row['kind']]) + struct.pack('<q', row['integer']) + H.D.blob(row['data']))
        payload.extend(struct.pack('<I', len(row['children'])))
        payload.extend(b''.join(struct.pack('<I', child) for child in row['children']))
        payload.extend(struct.pack('<I', len(row['names'])))
        for name in row['names']: payload.extend(H.D.blob(name))
    graph = H.D.CapturedGraph(bytes(payload))
    targets = {
        'tuple_recipe_gap': (graph.field(pair, b'id'), 'integer', 31),
        'tuple_recipe_forward': (tuple_elements[0], 'integer', 30),
        'tuple_field_index': (graph.field(fields[1], b'index'), 'integer', 0),
        'tuple_field_value': (graph.field(fields[0], b'value'), 'integer', 2),
        'tuple_field_arity': (pair_fields, 'children', fields[:1]),
        'array_literal_length': (elements_id, 'children', elements[:1]),
        'array_literal_element': (elements[0], 'integer', 2),
        'array_index_result': (graph.field(index_node, b'ty'), 'integer', 1),
        'array_index_type': (graph.field(index, b'index'), 'integer', 2),
        'array_write_value': (graph.field(replacement, b'value'), 'integer', 2),
        'array_write_readonly': (graph.field(store, b'slot'), 'integer', 1),
        'array_replace_result': (graph.field(replace_node, b'ty'), 'integer', 1),
        'foreign_operand': (graph.field(replacement, b'value'), 'integer', 0),
    }
    return bytes(payload), targets


def comparable(rows):
    return [{k: v for k, v in row.items() if k != 'integer_at'} for row in rows]


class Construction(unittest.TestCase):
    def test_all_thirteen_change_only_the_intended_row_field(self):
        payload, targets = synthetic_graph()
        original = H.D.CapturedGraph(payload)
        attacks = H.mutations(payload)
        self.assertEqual(tuple(attacks), H.NAMES)
        self.assertEqual(set(attacks), set(targets))
        self.assertEqual(len(set(attacks.values())), 13)
        for name, altered in attacks.items():
            with self.subTest(name=name):
                rows = comparable(original.rows)
                row, field, expected = targets[name]
                rows[row][field] = expected
                changed = H.D.CapturedGraph(altered)
                self.assertEqual(comparable(changed.rows), rows)
                self.assertEqual(changed.nodes, original.nodes)
                self.assertEqual(changed.functions, original.functions)

    def test_missing_tuple_role_is_fail_closed(self):
        payload, _ = synthetic_graph()
        with self.assertRaisesRegex(RuntimeError, 'authentic inferred tuple'):
            H.mutations(payload.replace(b'tuple', b'other'))

    def test_readonly_target_must_have_the_same_array_type(self):
        payload, _ = synthetic_graph()
        graph = H.D.CapturedGraph(payload)
        scope = graph.field(graph.functions[1], b'scope')
        locals_ = graph.items(graph.field(scope, b'locals'))
        changed = graph.mutations([(graph.field(locals_[1], b'ty'), 0)])[0]
        with self.assertRaises((RuntimeError, StopIteration)):
            H.mutations(changed)

    def test_replacement_must_be_owned_by_an_element_assignment(self):
        payload, targets = synthetic_graph()
        graph = H.D.CapturedGraph(payload)
        statement = graph.statements[0]
        store = graph.rows[graph.field(statement, b'data')]['children'][0]
        changed = graph.mutations([(graph.field(store, b'element'), 0)])[0]
        with self.assertRaisesRegex(RuntimeError, 'mutate its fixed array'):
            H.mutations(changed)


if __name__ == '__main__':
    unittest.main()
