"""Closed authenticated B7 resource-reply attacks, separate from source counts."""
import hashlib
from pathlib import Path
import shutil
from types import SimpleNamespace
import run_body_entry_qualification as E
import run_body_library_join as J

D, F = E.D, E.F
SOURCE = Path(__file__).with_name('fixtures')/'body_entry_hostile/main.input'
NAMES = ('open_receiver', 'open_result', 'open_mode', 'file_shapes_list',
         'missing_scoped_file', 'scoped_type', 'scoped_mutable', 'sibling_owner',
         'with_resource', 'with_slot', 'write_stream', 'write_text', 'write_result',
         'print_stream', 'print_result')


def mutations(payload):
    g = D.CapturedGraph(payload)
    access_node, access = g.tagged(g.nodes, b'file_access')
    read_node, read = g.tagged(g.nodes, b'file_method')
    write_node, write = g.tagged(g.nodes, b'stream_write')
    print_node, print_ = g.tagged(g.nodes, b'print')
    _, scope = g.tagged(g.statements, b'with_scope')
    owner = g.rows[g.field(read, b'owner')]['integer']
    local_lists = [g.items(g.field(g.field(fn, b'scope'), b'locals')) for fn in g.functions]
    candidates = [ls for ls in local_lists if owner < len(ls) and
                  g.rows[g.field(g.field(ls[owner], b'ownership'), b'scoped_file')]['integer']]
    F.require(len(candidates) == 1, 'ambiguous scoped owner capture')
    locals_ = candidates[0]; local = locals_[owner]
    sibling = next(i for i, row in enumerate(locals_) if i != owner and
                   g.rows[g.field(g.field(row, b'ownership'), b'scoped_file')]['integer'])
    args = g.items(g.field(access, b'arguments'))
    integer = g.integer_node()
    # Mutate only authentic scalar fields: no invented catalog/type authority.
    targets = [(args[0], integer), (g.field(access_node, b'ty'), 0),
               (g.field(access, b'mode'), ord('w')),
               (g.field(g.field(access, b'shapes'), b'list'), 0),
               (g.field(g.field(local, b'ownership'), b'scoped_file'), 0),
               (g.field(local, b'ty'), 0), (g.field(local, b'mutable'), 1),
               (g.field(read, b'owner'), sibling),
               (g.field(scope, b'resource'), integer), (g.field(scope, b'slot'), 65536),
               (g.field(write, b'stream'), integer), (g.field(write, b'text'), integer),
               (g.field(write_node, b'ty'), 1), (g.field(print_, b'stream'), integer),
               (g.field(print_node, b'ty'), 0)]
    result = dict(zip(NAMES, g.mutations(targets)))
    F.require(len(result) == len(NAMES), 'incomplete resource attack inventory')
    return result


def run(args, work, empty, checkpoint):
    work.mkdir(parents=True, exist_ok=False)
    source = work/'main.my'; shutil.copyfile(SOURCE, source)
    (work/'blob.bin').write_bytes(b'\x00\xff')
    q = SimpleNamespace(work=work, source=work, empty_path=empty, compiler=args.compiler)
    private, real = D.private_fixture(args, q)
    command = [args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json']
    native = F.execute(command, D.environment('reference', args.component_dir, empty), work)
    F.require(native == (0, b'', b''), 'native resource attack source failed')
    result, request, reply = D.capture_exchange(args, q, private, real, source.name)
    capture = {'source_sha256': F.digest(SOURCE), **E.bound_capture(request, reply),
               'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()}
    checkpoint([], capture)
    F.require(result == native, 'authentic selected resource capture failed')
    cases = mutations(reply[64:])
    F.require(tuple(cases) == NAMES, 'resource forged selection changed')
    records = []
    for name, payload in cases.items():
        path = work/(name+'.bin'); path.write_bytes(payload)
        env = D.environment('component', private, empty); env['BODY_REPLY'] = str(path)
        result = F.execute(command, env, work)
        records.append({'name': name, 'command': list(map(str, command)), 'payload_path': str(path),
                        'payload_sha256': hashlib.sha256(payload).hexdigest(), 'status': result[0],
                        'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
        checkpoint(records, capture)
        J.require_rejection(result)
    F.require(len(records) == len(NAMES), 'incomplete resource forged checks')
    return records, capture
