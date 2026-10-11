"""Four named hostile join replies, independent of source-operation accounting."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
from types import SimpleNamespace
import run_body_check_qualification as D

F = D.F
NAMES = ('wrong_result', 'foreign_list_element', 'wrong_arity', 'mutable_buffer_owner')
SOURCE = Path(__file__).with_name('fixtures') / 'body_library_followup/join_capture/main.input'


def mutations(payload):
    graph = D.CapturedGraph(payload)
    joins = []
    for node in graph.nodes:
        data = graph.rows[graph.field(node, b'data')]
        if data['data'] == b'buffer_operation':
            operation = data['children'][0]
            if graph.rows[graph.field(operation, b'kind')]['data'] == b'join':
                joins.append((node, operation))
    F.require(len(joins) >= 2, 'capture needs text and bytes join')
    text_node, text = joins[0]
    byte_node, octets = joins[1]
    F.require(graph.rows[graph.field(text_node, b'ty')]['integer'] !=
              graph.rows[graph.field(byte_node, b'ty')]['integer'], 'join element families are not distinct')
    text_arguments = graph.items(graph.field(text, b'arguments'))
    arguments = graph.field(octets, b'arguments')
    byte_arguments = graph.items(arguments)
    F.require(len(text_arguments) == len(byte_arguments) == 1, 'join requires one list argument')
    locals_ = graph.items(graph.field(graph.field(graph.functions[0], b'scope'), b'locals'))
    recipes = graph.items(graph.field(graph.output, b'recipes'))
    buffer_recipe = next((graph.rows[row]['children'][0] for row in recipes
                          if graph.rows[row]['data'] == b'byte_buffer'), None)
    F.require(buffer_recipe is not None, 'capture needs canonical buffer append recipe')
    buffer_type = graph.rows[graph.field(buffer_recipe, b'id')]['integer']
    owner = next((index for index, local in enumerate(locals_)
                  if graph.rows[graph.field(local, b'ty')]['integer'] == buffer_type
                  and graph.rows[graph.field(local, b'mutable')]['integer'] == 1), None)
    F.require(owner is not None, 'capture needs mutable buffer local')
    changed = graph.mutations([(graph.field(byte_node, b'ty'), 0),
                               (byte_arguments[0], graph.rows[text_arguments[0]]['integer'])])
    changed.append(D.rewrite_edges(payload, {arguments: []}))
    mutable = bytearray(payload)
    for row, value in ((graph.field(octets, b'owner'), owner), (graph.field(byte_node, b'ty'), buffer_type)):
        struct.pack_into('<q', mutable, graph.rows[row]['integer_at'], value)
    changed.append(bytes(mutable))
    F.require(len(changed) == 4 and all(value != payload for value in changed), 'incomplete join mutations')
    return dict(zip(NAMES, changed))



def require_rejection(result):
    # ComponentProtocol's established CLI renderer still uses a test-index label.
    # Require that exact diagnostic, rather than treating every host failure as proof.
    F.require(result[0] == 2 and not result[1], 'join reply was not a host rejection')
    try:
        record = json.loads(result[2])
    except (ValueError, TypeError) as error:
        raise RuntimeError('join rejection is not diagnostic-v1') from error
    F.require(record == {'version': 'diagnostic-v1', 'kind': 'message',
        'message': 'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'},
        'join rejection is not ComponentProtocol')


def run(args, work, empty, checkpoint):
    """Persist every request/reply and partial verdict before checking status."""
    work.mkdir(parents=True, exist_ok=False)
    source = work / 'join_capture.my'
    shutil.copyfile(SOURCE, source)
    q = SimpleNamespace(work=work, source=work, empty_path=empty, compiler=args.compiler)
    private, real = D.private_fixture(args, q)
    native = F.execute([args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json'],
                       D.environment('reference', args.component_dir, empty), work)
    F.require(native == (0, b'', b''), 'native join capture source failed')
    result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    capture = {'source_sha256': F.digest(SOURCE), 'request_sha256': hashlib.sha256(request).hexdigest(),
               'reply_sha256': hashlib.sha256(reply).hexdigest(), 'status': result[0],
               'stdout': result[1].decode('utf8', 'replace'), 'stderr': result[2].decode('utf8', 'replace')}
    checkpoint([], capture)
    F.require(result == native and reply[:8] == b'SLKBCK01' and len(reply) >= 64,
              'authentic selected join capture failed')
    F.require(request[:8] == b'SLKBCK01' and len(request) >= 64
              and struct.unpack_from('<IIII', request, 8) == (1, 6, 0, len(request)-64)
              and struct.unpack_from('<IIII', reply, 8) == (1, 6, 1, len(reply)-64)
              and request[24:32] == reply[24:32]
              and hashlib.sha256(request[64:]).digest() == reply[32:64],
              'join capture frame correlation failed')
    cases = mutations(reply[64:])
    F.require(tuple(cases) == NAMES, 'join forged inventory changed')
    records = []
    for name, payload in cases.items():
        path = work / (name + '.bin'); path.write_bytes(payload)
        env = D.environment('component', private, empty); env['BODY_REPLY'] = str(path)
        command = [args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json']
        result = F.execute(command, env, work)
        records.append({'name': name, 'mode': 'component', 'command': list(map(str, command)),
                        'payload_sha256': F.digest(path), 'payload_path': str(path), 'status': result[0],
                        'stdout': result[1].decode('utf8', 'replace'), 'stderr': result[2].decode('utf8', 'replace')})
        checkpoint(records, capture)
        require_rejection(result)
    F.require(len(records) == 4, 'incomplete join forged checks')
    return records, capture
