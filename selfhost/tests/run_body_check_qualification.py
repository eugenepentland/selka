#!/usr/bin/env python3
"""Installed body-check workflow qualification; native coordinator only."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import run_frontend_qualification as F

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).with_name('fixtures') / 'body_check'
COMPONENT = 'body-check'
SCHEMA = 6
FORGED_CHECKS = 92
MALFORMED_CHECKS = 22


def frame(payload):
    identity = b'bodytest' + F.hashlib.sha256(payload).digest()
    return b'SLKBCK01' + struct.pack('<IIII', 1, SCHEMA, 0, len(payload)) + identity + payload


def blob(value):
    return struct.pack('<I', len(value)) + value


def coordinator_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(('MYLANG_', 'PILOT_', 'BODY_')) or key == 'MYLANG_COMPONENT_CACHE'}


def transport(binary, work, env, valid):
    F.require(valid[:8] == b'SLKBCK01' and valid[64:72] == b'SLKBKI01', 'missing native-projected body request')
    request = work / 'body-exchange.bin'
    request.write_bytes(valid)
    status, stdout, stderr = F.execute([binary, '--exchange', request], env, work, 30)
    F.require(status == 0 and not stderr and stdout[:8] == b'SLKBCK01' and stdout[24:64] == valid[24:64], 'valid body exchange failed')
    F.require(struct.unpack('<IIII', stdout[8:24]) == (1, SCHEMA, 1, len(stdout)-64) and stdout[64:72] == b'SLKBKR01', 'unbound body reply')
    malformed = [b'', valid[:63], valid[:-1], valid+b'X', b'BADMAGIC'+valid[8:]]
    for offset,value in ((8,2),(12,1),(12,2),(12,3),(12,4),(12,5),(16,1),(20,67108864)):
        changed=bytearray(valid);struct.pack_into('<I',changed,offset,value);malformed.append(bytes(changed))
    payload=valid[64:]
    malformed.extend([frame(b'BADMAGIC'+payload[8:]), frame(payload[:-1])])
    for offset,value in ((8,1048577),(12,1048576)):
        changed=bytearray(payload);struct.pack_into('<I',changed,offset,value);malformed.append(frame(changed))
    malformed.extend(frame(value) for value in mutate_input(payload))
    for index,value in enumerate(malformed):
        request.write_bytes(value)
        status,out,err=F.execute([binary,'--exchange',request],env,work,30)
        F.require(status==2 and not out and err, f'malformed body request {index} escaped refusal')
    F.require(len(malformed) == MALFORMED_CHECKS, 'incomplete malformed transport selection')
    return {'valid':1,'malformed':len(malformed),'request_sha256':F.hashlib.sha256(valid).hexdigest(),'request_bytes':len(valid),'failed':0,'skipped':0}


def graph_rows(payload, magic=b'SLKBKR01'):
    """Read bounded named rows for developer mutations, never production decoding."""
    F.require(len(payload)>=16 and payload[:8]==magic,'not a body outcome')
    count,root=struct.unpack_from('<II',payload,8)
    F.require(0<count<=1048576 and root<count,'bad captured outcome root')
    at=16;rows=[]
    def read_u32():
        nonlocal at
        F.require(at+4<=len(payload),'truncated captured row')
        value=struct.unpack_from('<I',payload,at)[0];at+=4;return value
    def read_blob():
        nonlocal at
        length=read_u32();F.require(length<=len(payload)-at,'truncated captured blob')
        data=payload[at:at+length];at+=length;return data
    for _ in range(count):
        F.require(at+9<=len(payload),'truncated captured kind')
        kind=payload[at];integer_at=at+1;value=struct.unpack_from('<q',payload,integer_at)[0];at+=9
        data=read_blob();n=read_u32();F.require(n<=4194304 and n*4<=len(payload)-at,'bad captured edges')
        children=[read_u32() for _ in range(n)]
        n=read_u32();F.require(n<=1048576,'bad captured names');names=[read_blob() for _ in range(n)]
        rows.append({'kind':kind,'integer':value,'integer_at':integer_at,'data':data,'children':children,'names':names})
    F.require(at==len(payload),'captured trailing rows')
    return rows,root


def mutate_input(payload):
    rows,root=graph_rows(payload,b'SLKBKI01')
    def field(node,name):
        row=rows[node]
        F.require(row['kind']==5 and name in row['names'],'missing projected input field')
        return row['children'][row['names'].index(name)]
    # Keep a complete, bounded graph while refusing wrong DTO kinds before typing.
    catalog = field(root, b'catalog')
    templates = field(catalog, b'templates')
    buffer = field(templates, b'byte_buffer')
    targets=[catalog,field(field(root,b'context'),b'source'),templates,buffer]
    variants=[]
    for target in targets:
        changed=bytearray(payload)
        changed[rows[target]['integer_at']-1]=1
        variants.append(bytes(changed))
    changed=bytearray(payload)
    struct.pack_into('<q', changed, rows[field(buffer,b'available')]['integer_at'], 2)
    variants.append(bytes(changed))
    return variants


def mutate_success(payload):
    rows,root=graph_rows(payload)
    F.require(rows[root]['kind']==7 and rows[root]['data']==b'success','capture is not success')
    def field(node,name):
        row=rows[node];F.require(row['kind']==5 and name in row['names'],'missing typed field '+repr(name))
        return row['children'][row['names'].index(name)]
    output=rows[root]['children'][0];batch=field(output,b'batch')
    nodes=rows[field(batch,b'nodes')]['children'];functions=rows[field(batch,b'functions')]['children']
    F.require(nodes and functions,'empty typed body capture')
    # Invalid identities/types/spans in otherwise authentic complete typed batches.
    statements=rows[field(batch,b'statements')]['children']
    ret=next((rows[field(item,b'data')]['children'][0] for item in statements
              if rows[field(item,b'data')]['data']==b'ret'),None)
    integer=next((item for item in nodes if rows[field(item,b'data')]['data']==b'integer'),None)
    F.require(ret is not None and integer is not None,'capture has no scalar return/literal')
    targets=[(field(field(nodes[0],b'span'),b'end'),2147483647),
             (field(field(functions[0],b'scope'),b'body'),2147483647),
             (ret,len(nodes)),(field(integer,b'ty'),1)]
    variants=[]
    for target,value in targets:
        F.require(rows[target]['kind']==1,'typed ID/span/type is not integer')
        changed=bytearray(payload);struct.pack_into('<q',changed,rows[target]['integer_at'],value);variants.append(bytes(changed))
    return variants


def environment(mode, components, empty):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('PILOT_', 'MYLANG_', 'BODY_'))}
    env.update(PATH=str(empty), MYLANG_COMPONENT_DIR=str(components),
               MYLANG_LEXER_MODE='reference', MYLANG_PARSER_MODE='reference',
               MYLANG_DECLARATION_MODE='reference', MYLANG_TYPE_INTERFACE_MODE='reference', MYLANG_BODY_CHECK_MODE=mode, MYLANG_TEST_INDEX_MODE='reference',
               MYLANG_CACHE_PLAN_MODE='reference', MYL_CORE_LEAKCHECK='1')
    return env


def mutate_lists(payload):
    rows, root = graph_rows(payload)
    F.require(rows[root]['kind'] == 7 and rows[root]['data'] == b'success', 'list capture is not success')
    def field(node, name):
        row = rows[node]
        F.require(row['kind'] == 5 and name in row['names'], 'missing list recipe field')
        return row['children'][row['names'].index(name)]
    output = rows[root]['children'][0]
    recipes = rows[field(output, b'recipes')]['children']
    F.require(len(recipes) == 1, 'capture must contain one inferred list recipe')
    recipe_tag = rows[recipes[0]]
    F.require(recipe_tag['kind'] == 7 and recipe_tag['data'] == b'list', 'capture recipe is not a tagged list')
    recipe = recipe_tag['children'][0]
    identity, element = field(recipe, b'id'), field(recipe, b'element')
    targets = [(identity, rows[identity]['integer'] + 1),
               (element, rows[identity]['integer']), (element, 7),
               (field(field(recipe, b'span'), b'end'), 2147483647)]
    variants = []
    for target, value in targets:
        F.require(rows[target]['kind'] == 1, 'list recipe field is not integer')
        changed = bytearray(payload)
        struct.pack_into('<q', changed, rows[target]['integer_at'], value)
        variants.append(bytes(changed))
    return variants


def mutate_records(payload):
    """Corrupt record-only structure in an otherwise authentic owned batch."""
    rows, root = graph_rows(payload)
    F.require(rows[root]['kind'] == 7 and rows[root]['data'] == b'success', 'record capture is not success')
    def field(node, name):
        row = rows[node]
        F.require(row['kind'] == 5 and name in row['names'], 'missing record field ' + repr(name))
        return row['children'][row['names'].index(name)]
    output = rows[root]['children'][0]
    batch = field(output, b'batch')
    nodes = rows[field(batch, b'nodes')]['children']
    constructors, projections, updates = [], [], []
    for node in nodes:
        data = rows[field(node, b'data')]
        if data['data'] == b'record':
            entries = rows[data['children'][0]]['children']
            if len(entries) >= 2:
                constructors.append(entries)
        elif data['data'] == b'field':
            projections.append(data['children'][0])
        elif data['data'] == b'update':
            updates.extend(rows[field(data['children'][0], b'fields')]['children'])
    F.require(constructors and projections and updates, 'record capture lacks constructor/read/update coverage')
    entries = constructors[0]
    first, second = field(entries[0], b'index'), field(entries[1], b'index')
    F.require(rows[first]['integer'] != rows[second]['integer'], 'authentic initializer indices duplicate')
    targets = [(first, rows[second]['integer']), (first, len(entries)),
               (field(projections[0], b'index'), 2147483647),
               (field(updates[0], b'index'), 2147483647)]
    variants = []
    for target, value in targets:
        F.require(rows[target]['kind'] == 1, 'record field index is not integer')
        changed = bytearray(payload)
        struct.pack_into('<q', changed, rows[target]['integer_at'], value)
        variants.append(bytes(changed))
    return variants


def packages(directory, body_schema=SCHEMA):
    result = {}
    versions = {'test-index': (1, 1), 'cache-plan': (2, 2),
                'lexer-pilot': (1, 2), 'parser-pilot': (1, 2), 'declaration-index': (1, 1), 'type-interface': (1, 1), COMPONENT: (1, body_schema)}
    for name, (protocol, schema) in versions.items():
        value = json.loads((directory / f'{name}.json').read_text())
        F.require(all(type(value.get(k)) is int for k in ('format', 'protocol', 'schema')), 'noninteger package identity')
        F.require(all(value.get(k) == v for k, v in
                      {'format': 1, 'component': name, 'protocol': protocol, 'schema': schema}.items()),
                  f'{name}: invalid qualified identity')
        artifact = value.get('artifact', '')
        F.require(artifact and Path(artifact).name == artifact and artifact not in ('.', '..'), 'unsafe artifact')
        F.require(F.digest(directory / artifact) == value.get('sha256'), 'artifact digest mismatch')
        result[name] = value
    return result


@contextmanager
def body_check_boundary():
    # Reuse the established same-path warm/live algorithms with one explicitly
    # selected boundary, restoring imported helpers even when a check fails.
    previous = F.FRONTENDS, F.environment, F.packages
    F.FRONTENDS, F.environment, F.packages = (COMPONENT,), environment, packages
    try:
        yield
    finally:
        F.FRONTENDS, F.environment, F.packages = previous



def diagnostic_contract(diagnostic):
    """Pin ordered source diagnostics and repair bytes independently of path."""
    return {
        'code': diagnostic['code'],
        'message': diagnostic['message'],
        'bytes': diagnostic['location']['bytes'],
        'notes': [{'role': note['role'], 'message': note['message'],
                   'bytes': note['location']['bytes']} for note in diagnostic.get('notes', [])],
        'edits': [{'bytes': edit['bytes'], 'text': edit['text']}
                  for edit in diagnostic.get('fix', {}).get('edits', [])],
    }


class Qualification(F.Qualification):
    mixed = False

    def run(self, mode, args, components=None, leakcheck=True):
        self.calls += 1
        env = environment(mode, components or self.components, self.empty_path)
        if self.mixed:
            env.update(MYLANG_LEXER_MODE=mode, MYLANG_PARSER_MODE=mode, MYLANG_DECLARATION_MODE=mode, MYLANG_TYPE_INTERFACE_MODE=mode)
        if not leakcheck:
            env['MYL_CORE_LEAKCHECK'] = '0'
        return F.execute([self.compiler, *args], env, self.work)

    def compare(self, name, args, expected=0):
        reference = super().compare(name, args, expected)
        for mode in ('reference', *self.modes):
            F.require(self.run(mode, args) == reference, f'{name}/{mode}: ordering or diagnostics are nondeterministic')
        return reference

    def live_sessions(self):
        private = self.work / 'session-deployment'
        manifests = packages(self.components)
        for mode in self.modes:
            for variant in ('missing', 'digest'):
                F.restore_deployment(self.components, private)
                with tempfile.TemporaryFile() as errors:
                    child = subprocess.Popen([str(self.compiler), 'check-session', str(self.source / 'main.my')],
                                             cwd=self.work, env=environment(mode, private, self.empty_path),
                                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
                                             bufsize=0, preexec_fn=F.process_limits)
                    self.calls += 1
                    try:
                        for _ in range(2):
                            F.require(F.session_command(child, 'check').get('status') == 0, 'warm live check failed')
                        if variant == 'missing':
                            (private / f'{COMPONENT}.json').unlink()
                        else:
                            artifact = private / manifests[COMPONENT]['artifact']
                            artifact.chmod(0o700)
                            with artifact.open('ab') as file:
                                file.write(b'corruption')
                        F.require(F.session_command(child, 'check').get('status') == 2, 'live body_check mutation hid host failure')
                        F.require(F.session_command(child, 'quit').get('status') == 0, 'session did not survive failure')
                        F.require(child.wait(timeout=30) == 0, 'session exit failed')
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait()
                        child.stdin.close()
                        child.stdout.close()
                self.sessions += 1
        return self.sessions

    def matrix(self):
        main = self.source / 'main.my'
        for command in ('check', 'check-project', 'list-declarations', 'list-modules',
                        'schema-project', 'list-interfaces', 'dump-typed', 'dump-ir'):
            self.compare(command, [command, main])
        manifest = json.loads((FIXTURES / 'manifest.json').read_text())
        F.require(len(manifest) >= 20, 'empty/incomplete body fixture selection')
        for name, spec in manifest.items():
            F.require(type(spec['status']) is int and spec['status'] in (0, 1, 2), 'unsupported fixture verdict')
            command = 'check' if spec.get('library') else 'check-project'
            args = [command, self.source / name, '--diagnostics=json']
            if spec['status'] == 2:
                reference = self.run('reference', args)
                F.require(reference[0] == 0, f'{name}: profile refusal is not native-valid')
                for mode in self.modes:
                    actual = self.run(mode, args)
                    F.require(actual[0] == 2 and not actual[1] and b'ComponentProfile' in actual[2], f'{name}/{mode}: unsupported profile did not fail host')
                    self.comparisons += 1
                self.records.append({'workflow':name,'phase':self.phase,'status':2,'boundary':'explicit-profile-refusal'})
            else:
                result = self.compare(name, args, spec['status'])
                diagnostics = [json.loads(line)['diagnostic'] for line in result[2].splitlines()]
                if 'diagnostics' in spec:
                    F.require([diagnostic_contract(d) for d in diagnostics] == spec['diagnostics'],
                              f'{name}: ordered diagnostic/repair contract changed')
                if 'code' in spec:
                    F.require(any(d['code'] == spec['code'] for d in diagnostics), f'{name}: required body diagnostic missing')
                if name == 'multi_body_errors.my':
                    F.require(len(diagnostics) == 2 and all(d['code'] == 'E_UNKNOWN_NAME' for d in diagnostics), 'independent body diagnostics were lost')
                if name == 'warning.my':
                    F.require(any(d['code'] == 'W_UNUSED_BINDING' and d['severity'] == 'warning' for d in diagnostics), 'native warning was lost')
            if 'library_check_status' in spec:
                self.compare(name+'-library-check', ['check', self.source/name, '--diagnostics=json'],
                             spec['library_check_status'])
            if spec.get('typed') and not spec.get('library'):
                self.compare(name+'-typed', ['dump-typed', self.source / name])
                self.compare(name+'-ir', ['dump-ir', self.source / name])
            if 'result' in spec:
                flags = ['--release', '--verify-facts'] if self.release else []
                self.compare(name+'-run', ['run-project', self.source / name, '--print-result',
                                          '--cache-dir', self.work / ('fixture-'+name),
                                          f'--zig={self.zig}', *flags], spec['result'])
        helper = self.source / 'helper.my'
        original = helper.read_bytes()
        try:
            helper.write_bytes(original.replace(b'return 7', b'return missing'))
            self.compare('body-source-edit', ['check-project', main, '--diagnostics=json'], 1)
        finally:
            helper.write_bytes(original)
        self.compare('body-source-restored', ['check-project', main])
        self.mixed = True
        try:
            for command in ('check-project', 'dump-typed', 'dump-ir'):
                self.compare('mixed-' + command, [command, main])
        finally:
            self.mixed = False
        for mode in ('reference', *self.modes):
            cache = self.work / f'application-{mode}'
            common = ['--cache-dir', cache, f'--zig={self.zig}']
            flags = ['--release', '--verify-facts'] if self.release else []
            output = self.work / 'program'
            F.require(self.run(mode, ['build', main, '--project', '-o', output, *common, *flags]) == (0, b'', b''), 'build failed')
            F.require(F.execute([output], environment(mode, self.components, self.empty_path), self.work) == (7, b'', b''), 'native artifact differs')
            F.require(self.run(mode, ['run-project', main, '--print-result', *common, *flags]) == (7, b'7\n', b''), 'run differs')
            F.test_counts(self.run(mode, ['test', main, '--json', '--force', '--no-cache', f'--zig={self.zig}', *flags]))
            self.comparisons += 3 if mode != 'reference' else 0
        return len(self.records) + 3


def coordinator_edit(args, q):
    source = q.work / 'coordinator-source'
    (source / 'selfhost').mkdir(parents=True)
    shutil.copyfile(ROOT / 'selfhost/component-seed.json', source / 'selfhost/component-seed.json')
    shutil.copytree(ROOT / 'selfhost/components', source / 'selfhost/components', symlinks=True)
    installation = q.work / 'coordinator-install'
    command = [args.builder, '--root', source, '--zig', args.zig, '--install-dir', installation]
    env = coordinator_environment()
    F.require(F.execute(command, env, q.work, 600)[0] == 0, 'private coordinator initial install failed')
    before = packages(installation)
    path = source / 'selfhost/components/body_check/checking.my'
    marker = 'if path.data == b"body_edit_marker":'
    text = path.read_text()
    F.require(text.count(marker) == 1, 'body implementation edit hook missing/ambiguous')
    path.write_text(text.replace(marker, 'if path.data == b"body_edit_marker_changed":'))
    F.require(F.execute(command, env, q.work, 600)[0] == 0, 'private body_check rebuild failed')
    after = packages(installation)
    F.require(before[COMPONENT]['key'] != after[COMPONENT]['key'] and
              before[COMPONENT]['sha256'] != after[COMPONENT]['sha256'], 'implementation edit did not rebuild body_check artifact')
    F.require(all(before[name] == after[name] for name in before if name != COMPONENT), 'unrelated packages changed')
    q.components, q.phase = installation, 'coordinator-edit'
    q.matrix()
    return {'before': before[COMPONENT], 'after': after[COMPONENT], 'other_packages_unchanged': 6}


class CapturedGraph:
    """Fail-closed developer view of a fully authenticated captured success."""
    def __init__(self, payload):
        self.payload = payload
        self.rows, root = graph_rows(payload)
        F.require(self.rows[root]['kind'] == 7 and self.rows[root]['data'] == b'success', 'capture is not success')
        self.output = self.rows[root]['children'][0]
        self.batch = self.field(self.output, b'batch')
        self.nodes = self.items(self.field(self.batch, b'nodes'))
        self.statements = self.items(self.field(self.batch, b'statements'))
        self.functions = self.items(self.field(self.batch, b'functions'))

    def field(self, node, name):
        row = self.rows[node]
        F.require(row['kind'] == 5 and name in row['names'], 'missing captured field ' + repr(name))
        return row['children'][row['names'].index(name)]

    def items(self, node):
        F.require(self.rows[node]['kind'] == 6, 'captured list expected')
        return self.rows[node]['children']

    def tagged(self, tables, tag):
        for item in tables:
            data = self.rows[self.field(item, b'data')]
            if data['kind'] == 7 and data['data'] == tag:
                return item, data['children'][0]
        raise RuntimeError('capture missing typed ' + repr(tag))

    def integer_node(self):
        return self.nodes.index(self.tagged(self.nodes, b'integer')[0])

    def mutations(self, targets):
        changed = []
        for target, value in targets:
            F.require(self.rows[target]['kind'] in (1, 2), 'mutation target is not integer/boolean')
            result = bytearray(self.payload)
            struct.pack_into('<q', result, self.rows[target]['integer_at'], value)
            F.require(bytes(result) != self.payload, 'mutation did not change authentic payload')
            changed.append(bytes(result))
        return changed


def mutate_variants(payload):
    graph = CapturedGraph(payload)
    node, variant = graph.tagged(graph.nodes, b'variant')
    tag = graph.field(variant, b'tag')
    value = graph.field(variant, b'value')
    F.require(graph.rows[value]['kind'] == 1, 'capture requires a payload-bearing variant')
    return graph.mutations([(tag, 2147483647), (value, graph.integer_node()),
                            (graph.field(node, b'ty'), 0), (tag, 1)])


def mutate_matches(payload):
    graph = CapturedGraph(payload)
    _, match = graph.tagged(graph.statements, b'match')
    arms = graph.items(graph.field(match, b'arms'))
    F.require(len(arms) >= 2, 'capture needs multiple match arms')
    tag = graph.field(arms[0], b'tag')
    other = graph.field(arms[1], b'tag')
    slot = graph.field(arms[0], b'slot')
    F.require(graph.rows[slot]['kind'] == 1, 'capture needs a bound payload')
    return graph.mutations([(tag, 2147483647), (other, graph.rows[tag]['integer']),
                            (slot, 2147483647), (graph.field(match, b'value'), graph.integer_node())])


def mutate_propagation(payload):
    graph = CapturedGraph(payload)
    node, propagation = graph.tagged(graph.nodes, b'propagate')
    return graph.mutations([(graph.field(propagation, b'value'), graph.integer_node()),
                            (graph.field(propagation, b'output'), 0), (graph.field(node, b'ty'), 1)])


def mutate_transfer(payload):
    graph = CapturedGraph(payload)
    end, available = None, None
    for function in graph.functions:
        scope = graph.field(function, b'scope')
        for local in graph.items(graph.field(scope, b'locals')):
            ownership = graph.field(local, b'ownership')
            span = graph.field(ownership, b'transfer_span')
            if graph.rows[span]['kind'] == 5:
                end = graph.field(span, b'end')
            if graph.rows[graph.field(local, b'ty')]['integer'] == 0:
                available = graph.field(ownership, b'transfer_available')
    F.require(end is not None and available is not None, 'capture lacks pending transfer/scalar metadata')
    return graph.mutations([(end, 2147483647), (available, 1)])


def mutate_catalog_recipes(payload, tag):
    graph = CapturedGraph(payload)
    recipes = graph.items(graph.field(graph.output, b'recipes'))
    recipe = next((graph.rows[row]['children'][0] for row in recipes
                   if graph.rows[row]['kind'] == 7 and graph.rows[row]['data'] == tag), None)
    F.require(recipe is not None, 'capture has no ' + repr(tag) + ' append recipe')
    identity = graph.field(recipe, b'id')
    argument = graph.field(recipe, b'success' if tag == b'result' else b'element')
    return graph.mutations([(identity, graph.rows[identity]['integer'] + 1),
                            (argument, graph.rows[identity]['integer']), (argument, 7),
                            (graph.field(graph.field(recipe, b'span'), b'end'), 2147483647)])

def rewrite_edges(payload, changes):
    """Re-encode bounded captured rows with explicit graph edge substitutions."""
    rows, root = graph_rows(payload)
    result = bytearray(payload[:16])
    for index, row in enumerate(rows):
        children = changes.get(index, row['children'])
        result.extend(bytes([row['kind']]) + struct.pack('<q', row['integer']) + blob(row['data']))
        result.extend(struct.pack('<I', len(children)))
        result.extend(b''.join(struct.pack('<I', child) for child in children))
        result.extend(struct.pack('<I', len(row['names'])))
        for name in row['names']:
            result.extend(blob(name))
    F.require(bytes(result) != payload, 'edge mutation did not change capture')
    return bytes(result)


def mutate_buffers(payload):
    """Thirteen authentic buffer recipe, cast, operation and ownership attacks."""
    graph = CapturedGraph(payload)
    recipes = graph.field(graph.output, b'recipes')
    tagged_recipe = next((row for row in graph.items(recipes)
                          if graph.rows[row]['data'] == b'byte_buffer'), None)
    F.require(tagged_recipe is not None, 'capture has no byte_buffer append recipe')
    recipe = graph.rows[tagged_recipe]['children'][0]
    identity = graph.field(recipe, b'id')
    buffer_type = graph.rows[identity]['integer']
    casts = []
    operations = {}
    for index, node in enumerate(graph.nodes):
        data = graph.rows[graph.field(node, b'data')]
        if data['data'] == b'cast':
            casts.append((node, data['children'][0]))
        if data['data'] == b'buffer_operation':
            operation = data['children'][0]
            kind = graph.rows[graph.field(operation, b'kind')]['data']
            operations.setdefault(kind, (node, operation))
    append, operation = operations[b'buffer_append_range']
    reserve, reserve_operation = operations[b'buffer_reserve']
    arguments = graph.field(operation, b'arguments')
    argument_rows = graph.items(arguments)
    F.require(len(argument_rows) == 3 and len(casts) >= 2, 'capture lacks buffer operations/casts')
    owner = graph.field(operation, b'owner')
    locals_ = graph.items(graph.field(graph.field(graph.functions[0], b'scope'), b'locals'))
    local = locals_[graph.rows[owner]['integer']]
    snapshot = next(node for node, value in casts
                    if graph.rows[graph.field(node, b'ty')]['integer'] != buffer_type
                    and graph.rows[graph.field(graph.nodes[graph.rows[value]['integer']], b'ty')]['integer'] == buffer_type)
    immutable_type = graph.rows[graph.field(snapshot, b'ty')]['integer']
    byte_node = graph.nodes.index(snapshot)
    targets = [(identity, buffer_type + 1),
               (graph.field(graph.field(recipe, b'span'), b'end'), 2147483647),
               (graph.field(casts[0][0], b'ty'), 0),
               (graph.field(snapshot, b'ty'), buffer_type),
               (graph.field(append, b'ty'), 0), (owner, len(locals_)),
               (argument_rows[1], byte_node), (argument_rows[0], graph.integer_node()),
               (graph.field(local, b'mutable'), 0),
               (graph.field(local, b'ty'), immutable_type)]
    changed = graph.mutations(targets)
    changed.append(rewrite_edges(payload, {recipes: graph.items(recipes) + [tagged_recipe]}))
    field_row = graph.rows[operation]
    edges = list(field_row['children'])
    edges[field_row['names'].index(b'arguments')] = graph.field(reserve_operation, b'arguments')
    changed.append(rewrite_edges(payload, {operation: edges}))
    # An otherwise valid byte constructor cannot read its operand from itself.
    changed.extend(graph.mutations([(casts[0][1], graph.nodes.index(casts[0][0]))]))
    F.require(len(changed) == 13, 'incomplete buffer mutation selection')
    return changed


def private_fixture(args,q):
    binary=q.work/'exchange-fixture'
    compiled=F.execute([args.zig,'cc',FIXTURES/'exchange_fixture.c','-O2','-o',binary],coordinator_environment(),q.work,180)
    F.require(compiled[0]==0,'native body fixture compilation failed')
    real=q.work/'authentic-body-check';original=packages(args.component_dir)[COMPONENT]
    shutil.copyfile(args.component_dir/original['artifact'],real);real.chmod(0o700)
    private=q.work/'fixture-deployment';F.restore_deployment(args.component_dir,private)
    manifest_path=private/f'{COMPONENT}.json';manifest=json.loads(manifest_path.read_text())
    artifact=private/manifest['artifact'];artifact.chmod(0o700);shutil.copyfile(binary,artifact)
    manifest['sha256']=F.digest(artifact);manifest_path.write_text(json.dumps(manifest));packages(private)
    return private,real


def capture_exchange(args,q,private,real,source,mode='component',mutate=False):
    env=environment(mode,private,q.empty_path)
    request=q.work/('capture-request-'+mode+'.bin');reply=q.work/('capture-reply-'+mode+'.bin')
    env.update(BODY_REAL=str(real),BODY_REQUEST=str(request),BODY_CAPTURE=str(reply))
    if mutate:
        env.update(MYLANG_LEXER_MODE='component',BODY_MUTATE=str(private/'lexer-pilot.json'))
    result=F.execute([q.compiler,'check-project',q.source/source,'--diagnostics=json'],env,q.work)
    return result,request.read_bytes(),reply.read_bytes()


def forged_replies(args,q,private,success,list_success,record_success,b5,b6):
    checked=0
    cases = [('main.my', payload) for payload in mutate_success(success[64:])]
    cases.extend(('profile_managed.my', payload) for payload in mutate_lists(list_success[64:]))
    cases.extend(('record_nested_snapshot.my', payload) for payload in mutate_records(record_success[64:]))
    cases.extend(('variant_named_order.my', payload) for payload in mutate_variants(b5['variant_named_order.my'][64:]))
    cases.extend(('variant_named_order.my', payload) for payload in mutate_matches(b5['variant_named_order.my'][64:]))
    cases.extend(('checked_try_fail.my', payload) for payload in mutate_propagation(b5['checked_try_fail.my'][64:]))
    cases.extend(('checked_loop_consumption.my', payload) for payload in mutate_transfer(b5['checked_loop_consumption.my'][64:]))
    cases.extend(('checked_try_fail.my', payload) for payload in mutate_catalog_recipes(b5['checked_try_fail.my'][64:], b'result'))
    cases.extend(('optional_parse_int_demand.my', payload) for payload in mutate_catalog_recipes(b5['optional_parse_int_demand.my'][64:], b'option'))
    cases.extend(('bytes_buffer_operations.my', payload) for payload in mutate_buffers(b6[64:]))
    F.require(len(cases) * len(q.modes) == FORGED_CHECKS, 'incomplete forged body selection')
    for case,(source,payload) in enumerate(cases):
        path=q.work/f'forged-body-{case}.bin';path.write_bytes(payload)
        for mode in q.modes:
            env=environment(mode,private,q.empty_path);env['BODY_REPLY']=str(path)
            result=F.execute([q.compiler,'check-project',q.source/source],env,q.work)
            F.require(result[0]==2 and not result[1] and result[2],f'{mode}: forged typed body {case} escaped rejection: {result!r}')
            checked+=1
    return checked


def publication_checks(args,q):
    records=[]
    for mode in q.modes:
        private,real=private_fixture(args,q)
        result,request,reply=capture_exchange(args,q,private,real,'unknown_name.my',mode,True)
        rows,root=graph_rows(reply[64:])
        F.require(rows[root]['kind']==7 and rows[root]['data']==b'failure' and b'E_UNKNOWN_NAME' in reply,'wrapper did not capture authentic body diagnostic')
        F.require(result[0]==2 and not result[1] and result[2] and not (private/'lexer-pilot.json').exists(),f'{mode}: diagnostic body publication survived selected artifact mutation: {result!r}')
        records.append({'mode':mode,'status':2,'reply_sha256':F.hashlib.sha256(reply).hexdigest(),'reply_bytes':len(reply),'stderr':result[2].decode()})
    return records


def main():
    ap = argparse.ArgumentParser()
    for name in ('compiler', 'builder', 'component-dir', 'zig'):
        ap.add_argument('--' + name, type=Path, required=True)
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--edit-check', action='store_true')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    for name in ('compiler', 'builder', 'component_dir', 'zig'):
        setattr(args, name, getattr(args, name).resolve())
    manifests = packages(args.component_dir)
    seed_check = F.execute([args.builder, '--root', ROOT, '--zig', args.zig, '--seed-only'], coordinator_environment(), ROOT, 600)
    F.require(seed_check[0] == 0, 'qualified seed receipt verification failed')
    seed_lines = seed_check[1].decode().strip().splitlines()
    F.require(len(seed_lines) == 1 and Path(seed_lines[0]).is_file(), 'missing/ambiguous qualified seed executable')
    seed_sha256 = F.digest(Path(seed_lines[0]))
    host = F.digest(args.compiler)
    with tempfile.TemporaryDirectory(prefix='body_check-qualification-') as temporary, body_check_boundary():
        q = Qualification(args.compiler, args.zig, args.component_dir, Path(temporary), ['shadow', 'component'], args.release)
        for source in FIXTURES.rglob('*.input'):
            target = q.source / source.relative_to(FIXTURES).with_suffix('.my')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        workflows = q.matrix()
        q.warm_deployments()
        q.live_sessions()
        private,real=private_fixture(args,q)
        captured,request,reply=capture_exchange(args,q,private,real,'main.my')
        F.require(captured==(0,b'',b''),'authentic body capture failed')
        protocol = transport(args.component_dir / manifests[COMPONENT]['artifact'], q.work,
                             environment('component', args.component_dir, q.empty_path),request)
        list_captured, _, list_reply = capture_exchange(args, q, private, real, 'profile_managed.my')
        F.require(list_captured == (0, b'', b''), 'authentic inferred list capture failed')
        record_captured, _, record_reply = capture_exchange(args, q, private, real, 'record_nested_snapshot.my')
        F.require(record_captured == (0, b'', b''), 'authentic nested record capture failed')
        b5 = {}
        for source in ('variant_named_order.my', 'checked_try_fail.my', 'checked_loop_consumption.my', 'optional_parse_int_demand.my'):
            captured, _, body_reply = capture_exchange(args, q, private, real, source)
            F.require(captured == (0, b'', b''), 'authentic B5 capture failed: ' + source)
            b5[source] = body_reply
        buffer_captured, _, buffer_reply = capture_exchange(args, q, private, real, 'bytes_buffer_operations.my')
        F.require(buffer_captured == (0, b'', b''), 'authentic B6 buffer capture failed')
        forged = forged_replies(args, q,private,reply,list_reply,record_reply,b5,buffer_reply)
        publication = publication_checks(args, q)
        edit = coordinator_edit(args, q) if args.edit_check else None
        report = {'host_sha256': host, 'packages': manifests, 'workflows': workflows,
                  'verified_seed_sha256': seed_sha256, 'release_facts_leaks': args.release,
                  'comparisons': q.comparisons, 'warm_deployment_checks': q.deployment,
                  'live_session_checks': q.sessions, 'cache_enabled_test_receipts': q.receipt_warm,
                  'records': q.records, 'failed': 0, 'skipped': 0}
        report['transport'] = protocol
        report['forged_reply_checks'] = forged
        report['publication_checks'] = publication
        report['coordinator_edit'] = edit
    F.require(F.digest(args.compiler) == host and packages(args.component_dir) == manifests, 'installed inputs changed')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'body_check qualification: {workflows} workflows, {q.comparisons} comparisons, {q.deployment} warm deployment checks, {q.sessions} live session checks; 0 failed, 0 skipped')
    print(f'body_check transport: {protocol["valid"]} valid, {protocol["malformed"]} malformed; 0 failed, 0 skipped')
    print(f'body_check forged replies: {forged} rejected; 0 failed, 0 skipped')
    print(f'body_check publication: {len(publication)} host failures; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
