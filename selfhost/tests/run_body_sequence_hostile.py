#!/usr/bin/env python3
"""Mutate authentic keyless sort replies under their original request binding."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from types import SimpleNamespace
import run_body_check_qualification as D
import run_body_dictionary_hostile as H
import run_body_library_join as J

F = D.F
SCHEMA = D.SCHEMA
SOURCE = Path(__file__).with_name('fixtures') / 'body_sequence_hostile/main.input'
NAMES = ('copy_readonly_receiver', 'second_readonly_receiver', 'nonunit_result',
         'short_arity', 'long_arity', 'source_type', 'keys_type', 'reverse_type',
         'distinct_keys_local', 'nonlocal_source', 'nonlocal_keys', 'foreign_receiver')


def require_inventory():
    inventory = json.loads((SOURCE.parent / 'inventory.json').read_text())
    F.require(inventory['schema'] == SCHEMA and tuple(inventory['hostile_names']) == NAMES,
              'keyless hostile inventory changed')
    F.require(inventory['source_sha256'] == F.digest(SOURCE), 'keyless hostile source changed')
    F.require({p.name for p in SOURCE.parent.glob('*.input')} == {'main.input'},
              'unselected keyless hostile fixture')
    return inventory


def mutations(payload):
    graph = D.CapturedGraph(payload)
    locals_ = graph.items(graph.field(graph.field(graph.functions[0], b'scope'), b'locals'))
    def number(row, name):
        return graph.rows[graph.field(row, name)]['integer']
    operations = []
    for node in graph.nodes:
        data = graph.rows[graph.field(node, b'data')]
        if data['data'] == b'buffer_operation':
            operation = data['children'][0]
            if graph.rows[graph.field(operation, b'kind')]['data'] == b'sort_keyed':
                operations.append((node, operation))
    F.require(len(operations) == 2, 'authentic source must contain two keyless sorted copies')
    node, copy = operations[0]
    _, second = operations[1]
    arguments_id = graph.field(copy, b'arguments')
    arguments = graph.items(arguments_id)
    F.require(len(arguments) == 3, 'authentic keyless arity differs')
    source_index = graph.rows[arguments[0]]['integer']
    keys_index = graph.rows[arguments[1]]['integer']
    source_data = graph.rows[graph.field(graph.nodes[source_index], b'data')]
    keys_data = graph.rows[graph.field(graph.nodes[keys_index], b'data')]
    F.require(source_data['data'] == keys_data['data'] == b'local', 'authentic keys are not local reads')
    source_slot = source_data['children'][0]
    keys_slot = keys_data['children'][0]
    F.require(graph.rows[source_slot]['integer'] == graph.rows[keys_slot]['integer'],
              'authentic keyless source and keys differ')
    owner = number(copy, b'owner')
    second_owner = number(second, b'owner')
    F.require(owner != graph.rows[source_slot]['integer']
              and 0 <= owner < len(locals_) and 0 <= second_owner < len(locals_),
              'capture lacks independent writable copy receiver')
    literal = next(index for index, row in enumerate(graph.nodes)
                   if number(row, b'ty') == number(graph.nodes[source_index], b'ty')
                   and graph.rows[graph.field(row, b'data')]['data'] == b'acquire_buffer')
    targets = [(graph.field(locals_[owner], b'mutable'), 0),
               (graph.field(locals_[second_owner], b'mutable'), 0),
               (graph.field(node, b'ty'), 0)]
    changed = graph.mutations(targets)
    changed += [D.rewrite_edges(payload, {arguments_id: arguments[:2]}),
                D.rewrite_edges(payload, {arguments_id: arguments + arguments[:1]})]
    changed += graph.mutations([(arguments[0], graph.integer_node()),
                                (arguments[1], graph.integer_node()),
                                (arguments[2], source_index),
                                (keys_slot, owner),
                                (arguments[0], literal),
                                (arguments[1], literal),
                                (graph.field(copy, b'owner'), len(locals_))])
    F.require(len(changed) == len(NAMES), 'incomplete keyless hostile selection')
    return dict(zip(NAMES, changed))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'component_dir', 'zig', 'evidence_dir', 'report'):
        setattr(args, name, getattr(args, name).resolve())
    inventory = require_inventory()
    before = {'compiler_sha256': F.digest(args.compiler),
              'packages': D.packages(args.component_dir, body_schema=SCHEMA)}
    report = {'complete': False, 'schema': SCHEMA, 'expected_hostile': len(NAMES),
              'names': list(NAMES), 'identity': before, 'source_sha256': F.digest(SOURCE), 'records': []}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint():
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    checkpoint()
    args.evidence_dir.mkdir(parents=True, exist_ok=False)
    work = args.evidence_dir
    empty = work / 'empty-path'; empty.mkdir()
    source = work / 'main.my'; shutil.copyfile(SOURCE, source)
    q = SimpleNamespace(work=work, source=work, compiler=args.compiler, empty_path=empty)
    command = [args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json']
    native = F.execute(command, D.environment('reference', args.component_dir, empty), work)
    report['native'] = {'status': native[0], 'stdout_hex': native[1].hex(), 'stderr_hex': native[2].hex()}
    checkpoint()
    F.require(native == (0, b'', b''), 'native keyless hostile source failed')
    with H.capture_boundary():
        private, real = D.private_fixture(args, q)
        result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    report['capture'] = {'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex(),
                         **H.bound_capture(request, reply)}
    checkpoint()
    F.require(result == native, 'authentic keyless capture differs')
    for name, payload in mutations(reply[64:]).items():
        path = work / (name + '.bin'); path.write_bytes(payload)
        environment = D.environment('component', private, empty)
        environment['BODY_REPLY'] = str(path)
        result = F.execute(command, environment, work, 600)
        report['records'].append({'name': name, 'payload_sha256': hashlib.sha256(payload).hexdigest(),
                                 'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
        checkpoint()
        J.require_rejection(result)
    F.require(len(report['records']) == len(NAMES), 'incomplete installed keyless hostile replay')
    F.require(before == {'compiler_sha256': F.digest(args.compiler),
                        'packages': D.packages(args.component_dir, body_schema=SCHEMA)},
              'keyless hostile deployment changed')
    F.require(require_inventory() == inventory, 'keyless hostile selection changed')
    report.update(complete=True, operations=len(NAMES), failed=0, skipped=0)
    checkpoint()
    print('keyless sort:', len(NAMES), 'authentic mutations refused; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
