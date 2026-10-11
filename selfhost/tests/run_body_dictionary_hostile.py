#!/usr/bin/env python3
"""Authentic schema11 collection/Option reply mutations; installed proof only."""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import struct
from types import SimpleNamespace
import run_body_check_qualification as D
import run_body_library_join as J

F = D.F
SCHEMA = 11
BASE_PACKAGES = D.packages
SOURCE = Path(__file__).with_name('fixtures') / 'body_dictionary_hostile/main.input'
NAMES = ('recipe_gap', 'recipe_duplicate', 'recipe_reorder', 'recipe_unhashable_key',
         'recipe_site', 'view_missing_mapping', 'view_forward_mapping', 'dict_set_distinction',
         'dictionary_odd', 'dictionary_key_type', 'dictionary_value_type',
         'set_nonunit_write', 'read_result', 'get_fallback_type', 'get_arity',
         'contains_result', 'length_result', 'write_key_type', 'write_value_type',
         'write_readonly_owner', 'foreign_operand', 'view_mapping',
         'item_field_index', 'item_field_value', 'option_some_type',
         'option_some_missing', 'option_none_payload')


def require_inventory():
    inventory = json.loads((SOURCE.parent / 'inventory.json').read_text())
    F.require(inventory['schema'] == SCHEMA and tuple(inventory['hostile_names']) == NAMES,
              'hostile collection inventory changed')
    F.require(inventory['source_sha256'] == F.digest(SOURCE), 'hostile source changed')
    F.require({p.name for p in SOURCE.parent.glob('*.input')} == {'main.input'},
              'unselected/missing hostile collection source')
    return inventory


def packages(directory):
    return BASE_PACKAGES(directory, body_schema=SCHEMA)


@contextmanager
def capture_boundary():
    # Existing authenticated native C capture helper resolves package versions
    # through this hook. Only this developer process changes; no deployment does.
    previous = D.packages
    D.packages = packages
    try:
        yield
    finally:
        D.packages = previous


def bound_capture(request, reply):
    F.require(len(request) >= 64 and len(reply) >= 64, 'truncated schema11 capture')
    F.require(request[:8] == reply[:8] == b'SLKBCK01', 'wrong schema11 capture magic')
    F.require(struct.unpack_from('<IIII', request, 8) == (1, SCHEMA, 0, len(request) - 64)
              and struct.unpack_from('<IIII', reply, 8) == (1, SCHEMA, 1, len(reply) - 64),
              'wrong schema11 capture framing')
    F.require(request[64:72] == b'SLKBKI01' and reply[64:72] == b'SLKBKR01'
              and request[24:64] == reply[24:64]
              and request[32:64] == hashlib.sha256(request[64:]).digest(),
              'schema11 capture is not request-bound')
    return {'request_sha256': hashlib.sha256(request).hexdigest(),
            'reply_sha256': hashlib.sha256(reply).hexdigest(),
            'request_bytes': len(request), 'reply_bytes': len(reply)}


def duplicate_recipe(payload, recipe_outer, recipes_id):
    # Append the same role/arguments at the correct next global ID. A repeated
    # old ID would test only contiguity, not duplicate semantic authority.
    rows, root = D.graph_rows(payload)
    F.require(len(rows) + 4 <= D.BODY_VALUE_LIMIT, 'duplicate recipe exceeds capture row budget')
    rows = [dict(row, children=list(row['children']), names=list(row['names'])) for row in rows]
    recipe_tags = rows[recipes_id]['children']
    identities = []
    for tagged in recipe_tags:
        record = rows[tagged]['children'][0]
        if rows[tagged]['data'] == b'collection':
            record = rows[record]['children'][0]
        value = rows[record]
        F.require(b'id' in value['names'], 'append recipe lacks global ID')
        identities.append(rows[value['children'][value['names'].index(b'id')]]['integer'])
    F.require(identities, 'empty append sequence')
    mapping = rows[rows[recipe_outer]['children'][0]]['children'][0]
    record = dict(rows[mapping], children=list(rows[mapping]['children']))
    record['children'][record['names'].index(b'id')] = len(rows)
    rows.append({'kind': 1, 'integer': max(identities) + 1, 'data': b'', 'children': [], 'names': []})
    record_id = len(rows); rows.append(record)
    inner_id = len(rows)
    rows.append({'kind': 7, 'integer': 0, 'data': b'dict', 'children': [record_id], 'names': []})
    outer_id = len(rows)
    rows.append({'kind': 7, 'integer': 0, 'data': b'collection', 'children': [inner_id], 'names': []})
    rows[recipes_id]['children'].append(outer_id)
    result = bytearray(b'SLKBKR01' + struct.pack('<II', len(rows), root))
    for row in rows:
        result.extend(bytes([row['kind']]) + struct.pack('<q', row['integer']) + D.blob(row['data']))
        result.extend(struct.pack('<I', len(row['children'])))
        result.extend(b''.join(struct.pack('<I', child) for child in row['children']))
        result.extend(struct.pack('<I', len(row['names'])))
        for name in row['names']:
            result.extend(D.blob(name))
    return bytes(result)


def mutations(payload):
    g = D.CapturedGraph(payload)
    def number(row, name):
        target = g.field(row, name)
        F.require(g.rows[target]['kind'] == 1, 'capture integer field expected')
        return g.rows[target]['integer']
    def ty(node):
        return number(node, b'ty')
    recipes_id = g.field(g.output, b'recipes')
    recipes = g.items(recipes_id)
    collections = {}
    for outer in recipes:
        value = g.rows[outer]
        if value['kind'] == 7 and value['data'] == b'collection':
            inner = g.rows[value['children'][0]]
            F.require(inner['kind'] == 7 and len(inner['children']) == 1, 'bad collection wrapper')
            collections.setdefault(inner['data'], []).append((outer, inner['children'][0]))
    required = (b'dict', b'set', b'dict_item', b'dict_keys', b'dict_values', b'dict_items')
    F.require(all(tag in collections for tag in required) and len(collections[b'dict']) >= 2,
              'authentic fixture must demand all six collection recipe roles')
    mapping = collections[b'dict'][0][1]
    dict_type = number(mapping, b'id')
    prior_list = next((g.rows[row]['children'][0] for row in recipes
                       if g.rows[row]['data'] == b'list'
                       and number(g.rows[row]['children'][0], b'id') < dict_type), None)
    F.require(prior_list is not None, 'capture lacks prior canonical nonhashable list')
    numeric = next(row for _, row in collections[b'dict'] if number(row, b'key') == 0)
    numeric_type = number(numeric, b'id')
    set_recipe = collections[b'set'][0][1]; set_type = number(set_recipe, b'id')
    item_recipe = collections[b'dict_item'][0][1]; item_type = number(item_recipe, b'id')
    view_outer, view_recipe = collections[b'dict_keys'][0]
    view_type = number(view_recipe, b'id')
    # Functions own disjoint node ranges; select locals in the operation's scope.
    ranges = g.items(g.field(g.batch, b'ranges'))
    F.require(len(ranges) == len(g.functions), 'missing function ownership ranges')
    def owner_function(node):
        position = g.nodes.index(node)
        owners = []
        for index, row in enumerate(ranges):
            span = g.field(row, b'nodes')
            if number(span, b'start') <= position < number(span, b'end'):
                owners.append(index)
        F.require(len(owners) == 1, 'ambiguous function node ownership')
        return owners[0]
    def local_rows(node):
        function = g.functions[owner_function(node)]
        return g.items(g.field(g.field(function, b'scope'), b'locals'))
    def operation(kind, owner_type):
        for node in g.nodes:
            data = g.rows[g.field(node, b'data')]
            if data['data'] != b'buffer_operation':
                continue
            op = data['children'][0]
            if g.rows[g.field(op, b'kind')]['data'] != kind:
                continue
            locals_ = local_rows(node)
            slot = number(op, b'owner')
            if 0 <= slot < len(locals_) and number(locals_[slot], b'ty') == owner_type:
                return node, op
        raise RuntimeError('capture missing canonical operation ' + repr(kind))
    def tagged_of_type(tag, type_id):
        for node in g.nodes:
            data = g.rows[g.field(node, b'data')]
            if ty(node) == type_id and data['data'] == tag:
                return node, data['children'][0]
        raise RuntimeError('capture missing canonical node ' + repr(tag))
    def indexed_owner(owner_type):
        for node in g.nodes:
            data = g.rows[g.field(node, b'data')]
            if data['data'] != b'index':
                continue
            base = number(data['children'][0], b'base')
            F.require(0 <= base < len(g.nodes), 'capture index base outside node graph')
            if ty(g.nodes[base]) == owner_type:
                F.require(owner_function(node) == owner_function(g.nodes[base]),
                          'capture index base belongs to another function')
                return node
        raise RuntimeError('capture missing canonical dictionary index')
    dict_array, array = tagged_of_type(b'array', dict_type)
    numeric_array, _ = tagged_of_type(b'array', numeric_type)
    array_items = g.items(array)
    F.require(len(array_items) >= 2 and len(array_items) % 2 == 0, 'dictionary array is not alternating')
    boolean, _ = g.tagged(g.nodes, b'boolean')
    boolean_id = g.nodes.index(boolean)
    integer_id = next(index for index, node in enumerate(g.nodes)
                      if ty(node) == 0 and owner_function(node) == owner_function(dict_array)
                      and g.rows[g.field(node, b'data')]['data'] == b'integer')
    write_node, write = operation(b'write', dict_type)
    numeric_write_node, numeric_write = operation(b'write', numeric_type)
    _, set_write = operation(b'write', set_type)
    read_node = indexed_owner(dict_type)
    _, get = operation(b'get', dict_type)
    contains_node, _ = operation(b'contains', dict_type)
    length_node, _ = operation(b'length', dict_type)
    F.require(ty(read_node) == number(mapping, b'value') and ty(length_node) == 0,
              'capture dictionary read/length types are not canonical')
    write_args = g.items(g.field(write, b'arguments'))
    set_args = g.items(g.field(set_write, b'arguments'))
    get_args_id = g.field(get, b'arguments'); get_args = g.items(get_args_id)
    numeric_args = g.items(g.field(numeric_write, b'arguments'))
    F.require(len(write_args) == len(set_args) == len(get_args) == len(numeric_args) == 2,
              'capture lacks exact operation argument shapes')
    readonly = next((index for index, local in enumerate(local_rows(write_node))
                     if number(local, b'ty') == dict_type
                     and g.rows[g.field(local, b'mutable')]['integer'] == 0), None)
    F.require(readonly is not None, 'capture lacks same-type readonly dictionary owner')
    foreign_id = next((index for index, node in enumerate(g.nodes)
                       if ty(node) == 0 and owner_function(node) != owner_function(numeric_write_node)
                       and g.rows[g.field(node, b'data')]['data'] == b'integer'), None)
    F.require(foreign_id is not None, 'capture lacks same-type foreign function operand')
    _, view = tagged_of_type(b'record', view_type)
    view_fields = g.items(view)
    _, item = tagged_of_type(b'record', item_type)
    item_fields = g.items(item)
    F.require(len(view_fields) == 1 and len(item_fields) == 2, 'capture lacks canonical view/item initializers')
    some, none = None, None
    for node in g.nodes:
        data = g.rows[g.field(node, b'data')]
        if data['data'] == b'variant':
            variant = data['children'][0]
            value = g.field(variant, b'value')
            if g.rows[value]['kind'] == 1:
                some = value
            elif g.rows[value]['kind'] == 0:
                none = value
    F.require(some is not None and none is not None, 'capture lacks actual Some/None payload shapes')
    result = {}
    def scalar(name, target, value):
        F.require(name not in result, 'duplicate mutation name')
        result[name] = g.mutations([(target, value)])[0]
    def edges(name, row, children):
        F.require(name not in result, 'duplicate mutation name')
        result[name] = D.rewrite_edges(payload, {row: children})
    scalar('recipe_gap', g.field(mapping, b'id'), dict_type + 1)
    result['recipe_duplicate'] = duplicate_recipe(payload, collections[b'dict'][0][0], recipes_id)
    order = list(recipes)
    first, later = order.index(collections[b'dict'][0][0]), order.index(view_outer)
    order[first], order[later] = order[later], order[first]
    edges('recipe_reorder', recipes_id, order)
    scalar('recipe_unhashable_key', g.field(mapping, b'key'), number(prior_list, b'id'))
    invalid_site = bytearray(payload)
    for field, value in ((b'start', 1), (b'end', 2)):
        row = g.field(g.field(mapping, b'span'), field)
        struct.pack_into('<q', invalid_site, g.rows[row]['integer_at'], value)
    result['recipe_site'] = bytes(invalid_site)  # Bounded interior of `func`, not an AST site.
    scalar('view_missing_mapping', g.field(view_recipe, b'key'), 1)
    scalar('view_forward_mapping', g.field(view_recipe, b'key'), view_type)
    scalar('dict_set_distinction', g.field(numeric_array, b'ty'), set_type)
    edges('dictionary_odd', array, array_items[:-1])
    scalar('dictionary_key_type', array_items[0], integer_id)
    scalar('dictionary_value_type', array_items[1], boolean_id)
    scalar('set_nonunit_write', set_args[1], integer_id)
    scalar('read_result', g.field(read_node, b'ty'), 1)
    scalar('get_fallback_type', get_args[1], boolean_id)
    edges('get_arity', get_args_id, get_args[:-1])
    scalar('contains_result', g.field(contains_node, b'ty'), 0)
    scalar('length_result', g.field(length_node, b'ty'), 8)
    scalar('write_key_type', write_args[0], integer_id)
    scalar('write_value_type', write_args[1], boolean_id)
    scalar('write_readonly_owner', g.field(write, b'owner'), readonly)
    scalar('foreign_operand', numeric_args[1], foreign_id)
    scalar('view_mapping', g.field(view_fields[0], b'value'), boolean_id)
    scalar('item_field_index', g.field(item_fields[1], b'index'), 0)
    scalar('item_field_value', g.field(item_fields[0], b'value'), integer_id)
    scalar('option_some_type', some, boolean_id)
    for name, row, kind, value in (('option_some_missing', some, 0, 0),
                                   ('option_none_payload', none, 1, integer_id)):
        changed = bytearray(payload)
        changed[g.rows[row]['integer_at'] - 1] = kind
        struct.pack_into('<q', changed, g.rows[row]['integer_at'], value)
        result[name] = bytes(changed)
    F.require(tuple(result) == NAMES and all(value != payload for value in result.values())
              and len(set(result.values())) == len(NAMES), 'incomplete/duplicate hostile collection inventory')
    return result


def run(args, work, empty, checkpoint):
    require_inventory()
    before = {'host': F.digest(args.compiler), 'packages': packages(args.component_dir)}
    work.mkdir(parents=True, exist_ok=False)
    source = work / 'main.my'; shutil.copyfile(SOURCE, source)
    q = SimpleNamespace(work=work, source=work, empty_path=empty, compiler=args.compiler)
    with capture_boundary():
        private, real = D.private_fixture(args, q)
        command = [args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json']
        native = F.execute(command, D.environment('reference', args.component_dir, empty), work)
        checkpoint([], {'identity': before, 'native_status': native[0],
                    'native_stdout_hex': native[1].hex(), 'native_stderr_hex': native[2].hex()})
        F.require(native == (0, b'', b''), 'native collection capture source failed')
        result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    capture = {'source_sha256': F.digest(SOURCE), 'identity': before,
               'request_path': str(work / 'capture-request-component.bin'),
               'reply_path': str(work / 'capture-reply-component.bin'),
               'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()}
    checkpoint([], capture)
    F.require(result == native, 'authentic selected collection capture failed')
    capture.update(bound_capture(request, reply))
    checkpoint([], capture)
    cases = mutations(reply[64:])
    records = []
    for name, payload in cases.items():
        path = work / (name + '.bin'); path.write_bytes(payload)
        env = D.environment('component', private, empty); env['BODY_REPLY'] = str(path)
        result = F.execute(command, env, work)
        records.append({'name': name, 'command': list(map(str, command)), 'payload_path': str(path),
                        'payload_sha256': F.digest(path), 'status': result[0],
                        'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
        checkpoint(records, capture)
        J.require_rejection(result)
    F.require(len(records) == len(NAMES), 'incomplete schema11 hostile verdicts')
    F.require(before == {'host': F.digest(args.compiler), 'packages': packages(args.component_dir)},
              'collection hostile deployment changed')
    return records, capture


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--component-dir', type=Path, required=True)
    ap.add_argument('--zig', type=Path, required=True)
    ap.add_argument('--report', type=Path, required=True)
    ap.add_argument('--evidence-dir', type=Path, required=True)
    args = ap.parse_args()
    for name in ('compiler', 'component_dir', 'zig', 'report', 'evidence_dir'):
        setattr(args, name, getattr(args, name).resolve())
    report = {'complete': False, 'selected_admission': 'pending', 'schema': SCHEMA,
              'expected_hostile': len(NAMES), 'names': list(NAMES), 'records': [], 'capture': None}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint(records, capture):
        report.update(records=list(records), capture=capture)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    checkpoint([], None)
    empty = args.evidence_dir.parent / (args.evidence_dir.name + '-empty-path')
    empty.mkdir(parents=True, exist_ok=False)
    try:
        records, capture = run(args, args.evidence_dir, empty, checkpoint)
    except Exception as error:
        report['error'] = str(error)
        checkpoint(report['records'], report['capture'])
        raise
    report.update(complete=True, selected_admission='passed', hostile=len(records), failed=0, skipped=0)
    checkpoint(records, capture)
    print(f'B8 hostile: {len(records)} exact ComponentProtocol refusals; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
