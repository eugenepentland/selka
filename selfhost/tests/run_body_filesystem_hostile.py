"""Authenticated filesystem reply validation using unchanged source fixtures."""
from pathlib import Path
import hashlib
import shutil
from types import SimpleNamespace
import run_body_entry_qualification as E
import run_body_library_join as J

D, F = E.D, E.F
FIXTURES = Path(__file__).with_name('fixtures') / 'body_filesystem_candidate'
SOURCES = ('whole_path_method', 'scoped_binary', 'scoped_text_explicit', 'text_open_failure')
COUNTS = {'whole_path_method': 83, 'scoped_binary': 66,
          'scoped_text_explicit': 65, 'text_open_failure': 21}
ACCESS = {'whole_path_method': ['exists', 'listdir', 'mkdir', 'read_file', 'read_text',
                               'remove', 'write_file', 'write_text'],
          'scoped_binary': ['open', 'remove'], 'scoped_text_explicit': ['open', 'remove'],
          'text_open_failure': ['open']}
METHODS = {'whole_path_method': [], 'scoped_binary': ['close', 'flush', 'read', 'readline', 'readlines', 'write'],
           'scoped_text_explicit': ['close', 'flush', 'read', 'readline', 'readlines', 'write'],
           'text_open_failure': ['read']}
MODES = ('shadow', 'component')
EXPECTED = {'captures': 4, 'mutations': 235, 'rejections': 470, 'authentic_replays': 8}


def operations(g, tag):
    result = {}
    for index, node in enumerate(g.nodes):
        data = g.rows[g.field(node, b'data')]
        if data['data'] == tag:
            operation = data['children'][0]
            name = g.rows[g.field(operation, b'kind')]['data'].decode()
            result.setdefault(name, (index, node, operation))
    return result


def mutations(payload):
    g = D.CapturedGraph(payload)
    result = {}
    def scalar(name, row, value):
        D.F.require(name not in result, 'duplicate filesystem mutation')
        result[name] = g.mutations([(row, value)])[0]
    def edge(name, row, children):
        D.F.require(name not in result, 'duplicate filesystem mutation')
        result[name] = D.rewrite_edges(payload, {row: children})
    def field_edge(name, row, field, target):
        data = g.rows[row]
        children = list(data['children'])
        children[data['names'].index(field)] = target
        edge(name, row, children)
    accesses = operations(g, b'file_access')
    methods = operations(g, b'file_method')
    for name, (_, node, op) in accesses.items():
        prefix = 'access_' + name + '_'
        arguments = g.field(op, b'arguments')
        args = g.items(arguments)
        scalar(prefix+'receiver', args[0], g.rows[args[1]]['integer'])
        scalar(prefix+'path', args[1], g.rows[args[0]]['integer'])
        edge(prefix+'arity', arguments, args[:-1])
        scalar(prefix+'result', g.field(node, b'ty'), 0)
        text = g.field(op, b'text')
        scalar(prefix+'text', text, 1-g.rows[text]['integer'])
        mode = g.field(op, b'mode')
        scalar(prefix+'mode', mode, ord('w') if g.rows[mode]['integer'] != ord('w') else ord('r'))
        for field in [b'text', b'bytes', b'list']:
            scalar(prefix+'shape_'+field.decode(), g.field(g.field(op, b'shapes'), field), 0)
        if len(args) == 3:
            scalar(prefix+'data', args[2], g.rows[args[0]]['integer'])
    for name, (_, node, op) in methods.items():
        prefix = 'method_' + name + '_'
        ty = g.field(node, b'ty')
        scalar(prefix+'result', ty, 1)
        scalar(prefix+'owner', g.field(op, b'owner'), 0)
        text = g.field(op, b'text')
        scalar(prefix+'text', text, 1-g.rows[text]['integer'])
        for field in [b'text', b'bytes', b'list']:
            scalar(prefix+'shape_'+field.decode(), g.field(g.field(op, b'shapes'), field), 0)
        argument = g.field(op, b'argument')
        if g.rows[argument]['kind'] == 1:
            scalar(prefix+'argument', argument, 0)
        if name == 'write':
            absent = next(g.field(other, b'argument') for _, _, other in methods.values()
                          if g.rows[g.field(other, b'argument')]['kind'] == 0)
            field_edge(prefix+'missing_argument', op, b'argument', absent)
        if name in ('readline', 'readlines', 'flush', 'close'):
            supplied = g.field(methods['write'][2], b'argument')
            field_edge(prefix+'extra_argument', op, b'argument', supplied)
    recipes = g.items(g.field(g.output, b'recipes'))
    for index, tagged in enumerate(recipes):
        row = g.rows[tagged]
        recipe = row['children'][0]
        prefix = 'recipe_' + str(index) + '_'
        if row['data'] == b'result':
            scalar(prefix+'success', g.field(recipe, b'success'), 1)
            scalar(prefix+'failure', g.field(recipe, b'failure'), 0)
        elif row['data'] == b'list':
            scalar(prefix+'element', g.field(recipe, b'element'), 0)
    D.F.require(len(result) == len(set(result.values())), 'duplicate filesystem mutation payload')
    return result, sorted(accesses), sorted(methods)



def run(args, work, empty, checkpoint):
    identity = {'compiler_sha256': F.digest(args.compiler), 'packages': D.packages(args.component_dir)}
    records, captures = [], []
    work.mkdir(parents=True, exist_ok=False)
    checkpoint(records, captures)
    for name in SOURCES:
        directory = work / name; directory.mkdir()
        source = directory / 'main.my'
        original = FIXTURES / (name + '.input')
        shutil.copyfile(original, source)
        q = SimpleNamespace(work=directory, source=directory, empty_path=empty, compiler=args.compiler)
        private, real = D.private_fixture(args, q)
        command = [args.compiler, 'check-project', source, '--no-cache', '--diagnostics=json']
        native = F.execute(command, D.environment('reference', args.component_dir, empty), directory)
        F.require(native == (0, b'', b''), 'native filesystem hostile source failed: ' + name)
        selected, request, reply = D.capture_exchange(args, q, private, real, source.name)
        F.require(selected == native, 'selected filesystem hostile capture failed: ' + name)
        cases, accesses, methods = mutations(reply[64:])
        F.require(len(cases) == COUNTS[name] and accesses == ACCESS[name] and methods == METHODS[name],
                  'filesystem hostile operation inventory changed: ' + name)
        captures.append({'name': name, 'identity': identity, 'source_sha256': F.digest(original),
            'request_path': str(directory / 'capture-request-component.bin'),
            'reply_path': str(directory / 'capture-reply-component.bin'),
            **E.bound_capture(request, reply), 'mutations': list(cases),
            'access': accesses, 'methods': methods,
            'native_status': native[0], 'selected_status': selected[0]})
        checkpoint(records, captures)
        for label, payload in {'authentic': reply[64:], **cases}.items():
            path = directory / (label + '.bin'); path.write_bytes(payload)
            for mode in MODES:
                env = D.environment(mode, private, empty); env['BODY_REPLY'] = str(path)
                result = F.execute(command, env, directory)
                records.append({'capture': name, 'name': label, 'mode': mode,
                    'command': list(map(str, command)), 'payload_path': str(path),
                    'payload_sha256': hashlib.sha256(payload).hexdigest(),
                    'status': result[0], 'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
                checkpoint(records, captures)
                if label == 'authentic':
                    F.require(result == native, 'authentic filesystem reply replay failed')
                else:
                    J.require_rejection(result)
    F.require(len(captures) == EXPECTED['captures'] and
              sum(len(c['mutations']) for c in captures) == EXPECTED['mutations'] and
              sum(r['name'] == 'authentic' for r in records) == EXPECTED['authentic_replays'] and
              sum(r['name'] != 'authentic' for r in records) == EXPECTED['rejections'],
              'incomplete filesystem hostile verification')
    F.require(identity == {'compiler_sha256': F.digest(args.compiler), 'packages': D.packages(args.component_dir)},
              'filesystem hostile deployment changed')
    F.require(all(F.digest(FIXTURES / (c['name'] + '.input')) == c['source_sha256'] for c in captures),
              'filesystem hostile source changed')
    return records, captures
