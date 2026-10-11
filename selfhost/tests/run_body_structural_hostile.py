#!/usr/bin/env python3
"""Authentic schema10 tuple/fixed-array reply mutations; installed proof only."""
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
SCHEMA = 10
BASE_PACKAGES = D.packages
SOURCE = Path(__file__).with_name('fixtures') / 'body_structural_hostile/main.input'
NAMES = ('tuple_recipe_gap', 'tuple_recipe_forward', 'tuple_field_index', 'tuple_field_value', 'tuple_field_arity', 'array_literal_length', 'array_literal_element', 'array_index_result', 'array_index_type', 'array_write_value', 'array_write_readonly', 'array_replace_result', 'foreign_operand')


def require_inventory():
    inventory = json.loads((SOURCE.parent / 'inventory.json').read_text())
    F.require(inventory['schema'] == SCHEMA and tuple(inventory['hostile_names']) == NAMES,
              'hostile structural inventory changed')
    F.require(inventory['source_sha256'] == F.digest(SOURCE), 'hostile source changed')
    F.require({p.name for p in SOURCE.parent.glob('*.input')} == {'main.input'},
              'unselected/missing hostile structural source')
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
    F.require(len(request) >= 64 and len(reply) >= 64, 'truncated schema10 capture')
    F.require(request[:8] == reply[:8] == b'SLKBCK01', 'wrong schema10 capture magic')
    F.require(struct.unpack_from('<IIII', request, 8) == (1, SCHEMA, 0, len(request) - 64)
              and struct.unpack_from('<IIII', reply, 8) == (1, SCHEMA, 1, len(reply) - 64),
              'wrong schema10 capture framing')
    F.require(request[64:72] == b'SLKBKI01' and reply[64:72] == b'SLKBKR01'
              and request[24:64] == reply[24:64]
              and request[32:64] == hashlib.sha256(request[64:]).digest(),
              'schema10 capture is not request-bound')
    return {'request_sha256': hashlib.sha256(request).hexdigest(),
            'reply_sha256': hashlib.sha256(reply).hexdigest(),
            'request_bytes': len(request), 'reply_bytes': len(reply)}


def mutations(payload):
    g = D.CapturedGraph(payload)
    def number(row, name):
        target = g.field(row, name)
        F.require(g.rows[target]['kind'] == 1, 'capture integer field expected')
        return g.rows[target]['integer']
    def ty(node):
        return number(node, b'ty')
    recipes = g.items(g.field(g.output, b'recipes'))
    structural = {}
    for outer in recipes:
        tagged = g.rows[outer]
        if tagged['data'] == b'structural':
            inner = g.rows[tagged['children'][0]]
            F.require(inner['kind'] == 7 and len(inner['children']) == 1,
                      'invalid structural wrapper')
            structural.setdefault(inner['data'], []).append(inner['children'][0])
    F.require(b'tuple' in structural, 'capture lacks authentic inferred tuple recipe')
    pair = structural[b'tuple'][0]
    pair_type = number(pair, b'id')
    fixed_types = set()
    for node in g.nodes:
        data = g.rows[g.field(node, b'data')]
        if data['data'] == b'replace':
            fixed_types.add(ty(node))
    F.require(len(fixed_types) == 1, 'capture must have one numeric fixed array replacement type')
    fixed_type = fixed_types.pop()
    def tagged(tag, type_id):
        for node in g.nodes:
            data = g.rows[g.field(node, b'data')]
            if ty(node) == type_id and data['data'] == tag:
                return node, data['children'][0]
        raise RuntimeError('capture missing structural node ' + repr(tag))
    pair_node, pair_fields = tagged(b'record', pair_type)
    fields = g.items(pair_fields)
    F.require(len(fields) == 2, 'capture tuple must have two canonical fields')
    fixed_node, elements_id = tagged(b'array', fixed_type)
    elements = g.items(elements_id)
    F.require(len(elements) == 2, 'capture fixed array must have two elements')
    boolean_node, _ = tagged(b'boolean', 1)
    boolean_id = g.nodes.index(boolean_node)
    index_node = index = write_node = write = None
    for node in g.nodes:
        data = g.rows[g.field(node, b'data')]
        if data['data'] == b'index':
            operation = data['children'][0]
            base = number(operation, b'base')
            if ty(g.nodes[base]) == fixed_type:
                index_node, index = node, operation
        if data['data'] == b'replace' and ty(node) == fixed_type:
            write_node, write = node, data['children'][0]
    F.require(index is not None and write is not None, 'missing authentic fixed array read/write')
    ranges = g.items(g.field(g.batch, b'ranges'))
    def owner(node):
        position = g.nodes.index(node)
        owners = [i for i, row in enumerate(ranges)
                  if number(g.field(row, b'nodes'), b'start') <= position
                  < number(g.field(row, b'nodes'), b'end')]
        F.require(len(owners) == 1, 'ambiguous node ownership')
        return owners[0]
    locals_ = g.items(g.field(g.field(g.functions[owner(write_node)], b'scope'), b'locals'))
    statements = g.items(g.field(g.batch, b'statements'))
    stores = []
    for statement in statements:
        data = g.rows[g.field(statement, b'data')]
        if data['data'] == b'assign':
            store = data['children'][0]
            if number(store, b'value') == g.nodes.index(write_node):
                stores.append(store)
    F.require(len(stores) == 1, 'replace must have one authentic assignment')
    store = stores[0]
    F.require(number(locals_[number(store, b'slot')], b'ty') == fixed_type
              and g.rows[g.field(store, b'element')]['integer'] == 1,
              'replace must mutate its fixed array binding')
    readonly = next(i for i, local in enumerate(locals_)
                    if number(local, b'ty') == fixed_type
                    and g.rows[g.field(local, b'mutable')]['integer'] == 0)
    foreign = next(i for i, node in enumerate(g.nodes)
                   if ty(node) == 0 and owner(node) != owner(write_node)
                   and g.rows[g.field(node, b'data')]['data'] == b'integer')
    result = {}
    def scalar(name, target, value):
        result[name] = g.mutations([(target, value)])[0]
    def edges(name, row, children):
        result[name] = D.rewrite_edges(payload, {row: children})
    scalar('tuple_recipe_gap', g.field(pair, b'id'), pair_type + 1)
    tuple_elements = g.items(g.field(pair, b'elements'))
    F.require(len(tuple_elements) == 2, 'tuple recipe element shape changed')
    scalar('tuple_recipe_forward', tuple_elements[0], pair_type)
    scalar('tuple_field_index', g.field(fields[1], b'index'), 0)
    scalar('tuple_field_value', g.field(fields[0], b'value'), boolean_id)
    edges('tuple_field_arity', pair_fields, fields[:-1])
    edges('array_literal_length', elements_id, elements[:-1])
    scalar('array_literal_element', elements[0], boolean_id)
    scalar('array_index_result', g.field(index_node, b'ty'), 1)
    scalar('array_index_type', g.field(index, b'index'), boolean_id)
    scalar('array_write_value', g.field(write, b'value'), boolean_id)
    scalar('array_write_readonly', g.field(store, b'slot'), readonly)
    scalar('array_replace_result', g.field(write_node, b'ty'), 1)
    scalar('foreign_operand', g.field(write, b'value'), foreign)
    F.require(tuple(result) == NAMES and all(value != payload for value in result.values())
              and len(set(result.values())) == len(NAMES), 'incomplete/duplicate structural mutations')
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
        F.require(native == (0, b'', b''), 'native structural capture source failed')
        result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    capture = {'source_sha256': F.digest(SOURCE), 'identity': before,
               'request_path': str(work / 'capture-request-component.bin'),
               'reply_path': str(work / 'capture-reply-component.bin'),
               'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()}
    checkpoint([], capture)
    F.require(result == native, 'authentic selected structural capture failed')
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
    F.require(len(records) == len(NAMES), 'incomplete schema10 hostile verdicts')
    F.require(before == {'host': F.digest(args.compiler), 'packages': packages(args.component_dir)},
              'structural hostile deployment changed')
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
    print(f'B10 hostile: {len(records)} exact ComponentProtocol refusals; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
