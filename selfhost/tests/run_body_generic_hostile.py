#!/usr/bin/env python3
"""Authentic schema11 generic instance reply mutations; installed proof only."""
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
SOURCE = Path(__file__).with_name('fixtures') / 'body_generic_hostile/main.input'
NAMES = ('duplicate_instance', 'foreign_declaration', 'wrong_argument', 'excess_constant_length', 'wrong_parameter_signature', 'wrong_return_signature', 'raw_declaration_call')


def require_inventory():
    inventory = json.loads((SOURCE.parent / 'inventory.json').read_text())
    F.require(inventory['schema'] == SCHEMA and tuple(inventory['hostile_names']) == NAMES,
              'hostile generic inventory changed')
    F.require(inventory['source_sha256'] == F.digest(SOURCE), 'hostile source changed')
    F.require({p.name for p in SOURCE.parent.glob('*.input')} == {'main.input'},
              'unselected/missing hostile generic source')
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


def mutations(payload):
    g = D.CapturedGraph(payload)
    def integer(row, field):
        return g.rows[g.field(row, field)]['integer']
    generic = [f for f in g.functions if g.items(g.field(f, b'type_arguments'))]
    F.require(len(generic) >= 3, 'capture lacks independent generic instances')
    scalar = next(f for f in generic if len(g.items(g.field(f, b'type_arguments'))) == 1
                  and integer(g.field(f, b'signature'), b'return_type') == 0)
    array = next(f for f in generic if len(g.items(g.field(f, b'type_arguments'))) == 2)
    arguments = g.items(g.field(scalar, b'type_arguments'))
    lengths = g.items(g.field(g.field(array, b'signature'), b'constant_arguments'))
    F.require(g.rows[lengths[1]]['kind'] == 1 and g.rows[lengths[1]]['integer'] == 2,
              'capture lacks authentic unsigned constant length')
    locals_ = g.items(g.field(g.field(scalar, b'scope'), b'locals'))
    result = {}
    def number(name, row, value): result[name] = g.mutations([(row, value)])[0]
    functions = list(g.functions)
    functions[functions.index(array)] = scalar
    result['duplicate_instance'] = D.rewrite_edges(payload, {g.field(g.batch, b'functions'): functions})
    number('foreign_declaration', g.field(g.field(scalar, b'declaration'), b'start'), 0)
    number('wrong_argument', arguments[0], 1)
    number('excess_constant_length', lengths[1], 1048577)
    number('wrong_parameter_signature', g.field(locals_[0], b'ty'), 1)
    number('wrong_return_signature', g.field(g.field(scalar, b'signature'), b'return_type'), 1)
    call_node, call = g.tagged(g.nodes, b'call')
    number('raw_declaration_call', g.field(call, b'function'), 0)
    F.require(tuple(result) == NAMES and len(set(result.values())) == len(NAMES),
              'incomplete or duplicate generic mutations')
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
        F.require(native == (0, b'', b''), 'native generic capture source failed')
        result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    capture = {'source_sha256': F.digest(SOURCE), 'identity': before,
               'request_path': str(work / 'capture-request-component.bin'),
               'reply_path': str(work / 'capture-reply-component.bin'),
               'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()}
    checkpoint([], capture)
    F.require(result == native, 'authentic selected generic capture failed')
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
              'generic hostile deployment changed')
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
    print(f'B11 hostile: {len(records)} exact ComponentProtocol refusals; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
