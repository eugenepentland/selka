#!/usr/bin/env python3
"""Store session server: every verb positive and negative, batch rollback, delta diagnostics, budgets."""
import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import store  # noqa: E402  (the session server ships beside the other repository scripts)
import store_server as server  # noqa: E402

RUNTIME = ROOT / 'experiments/development_velocity/runtime/my'
STARTER = ROOT / 'experiments/development_velocity/starters/inventory-reservations/my'
# One exported test entry so `context` can report the tests that reach a declaration.
TEST_ENTRY = '''export test_reserve;
// A public smoke test that exercises the whole request path.
fn test_reserve(heap: allocator, doc: &[]i64, request: j::Node) -> b::Built {
    return run(heap,doc,request);
}
'''
TASK = b'# Task\nImplement reservation state transitions in ledger::apply.\n'
REQUEST = {'requests': [{'stock': [{'id': 'apple', 'quantity': 5}], 'operations': []}]}
EXPECTED = {'results': [{'results': [], 'available': [{'id': 'apple', 'quantity': 5}], 'active': []}]}
CASES = [{'name': 'stock-only', 'case': {'request': REQUEST, 'expected': EXPECTED}}]
WRONG_CASES = [{'name': 'stock-only', 'case': {'request': REQUEST, 'expected': {'results': []}}}]

STOCK_WITH_FIELD = 'struct Stock { quantity: i64, name: i64, reserved: i64 }'
INITIAL_WITH_FIELD = '''fn initial(heap: allocator, doc: &[]i64, accounts: j::Node) -> model::Open<model::Stock> {
    let mut state = try model::create::<model::Stock>(heap);
    borrow mut state as table {
        let mut cursor = try j::children(doc, accounts);
        while !cursor.done {
            let account = try j::current(doc, cursor);
            let name = try j::required(doc, account, "id");
            let key = try model::identifier(heap, doc, name);
            let value = try j::integer(doc, try j::required(doc, account, "quantity"));
            if h::put::<model::Stock>(table, key, new model::Stock {quantity: value, name: name.id, reserved: 0}) == new h::PutStatus.full {
                return new model::Open<model::Stock>.err(r::allocation_error(2));
            }
            cursor = try j::advance(doc, cursor);
        }
    }
    return new model::Open<model::Stock>.ok(state);
}'''
ROWS_WITH_FIELD = '''fn rows(heap: allocator) -> Rows {
    match c::filled::<model::Stock>(heap, 32u64, new model::Stock {quantity: 0, name: 0, reserved: 0}) {
        c::Created<model::Stock>.ok(value) => { return new Rows.ok(value); },
        c::Created<model::Stock>.err(code) => { return new Rows.err(r::allocation_error(code)); }
    }
}'''
TWO_DECLARATIONS = 'fn one() -> i64 { return 1; }\nfn two() -> i64 { return 2; }'


class Failures:
    def __init__(self):
        self.checked = 0
        self.failed = []
        self.maxima = {}

    def ok(self, condition, label):
        self.checked += 1
        if not condition:
            self.failed.append(label)
        return bool(condition)

    def error(self, response, label, marker=''):
        """A verb rejection is an error response, never a raised exception or a success."""
        self.checked += 1
        if not isinstance(response, dict) or response.get('verb') != 'error':
            self.failed.append(label + ': no rejection')
        elif marker and marker not in response.get('error', ''):
            self.failed.append(f'{label}: wrong message {response.get("error", "")[:120]}')

    def budget(self, session, response, verb, label, limit=None):
        size = server.sized(response)
        limit = session.budgets[verb] if limit is None else limit
        self.maxima[verb] = max(self.maxima.get(verb, 0), size)
        self.ok(size <= limit, f'{label}: {verb} response {size} bytes exceeds {limit}')
        return response


def project(directory):
    """The velocity runtime plus the inventory-reservations starter: a real main/io pair."""
    directory.mkdir(parents=True)
    for source in list(RUNTIME.glob('*.my')) + list(STARTER.glob('*.my')):
        shutil.copy2(source, directory / source.name)
    with (directory / 'app.my').open('a') as stream:
        stream.write(TEST_ENTRY)
    public = directory / '.trial-public'
    public.mkdir()
    (public / 'TASK.md').write_bytes(TASK)
    (public / 'cases.json').write_bytes(json.dumps(CASES).encode() + b'\n')
    (directory / 'private-notes.txt').write_bytes(b'coordinator only\n')
    return directory


def session_for(work, compiler, name, *, cases=CASES, runner=None):
    database = work / f'{name}.sqlite'
    if not database.exists():
        with store.Compiler(compiler) as tool:
            with store.Store(database, create=True, compiler=tool) as database_handle:
                store.import_directory(database_handle, tool, work / 'source', 'base')
                database_handle.create_branch('base', 'work')
    return server.StoreSession(database, 'work', compiler,
                               [str(Path(compiler).with_name('mylang-io')), '--project', '{work}'],
                               work / f'{name}-session', cases=cases, check=runner)


def read_verbs(session, results):
    """open, context, search and asset: one accepted and one refused request each."""
    opened = results.budget(session, session.open(), 'open', 'open')
    ids = {row['id'] for row in opened['declarations']}
    results.ok(opened['version'] == server.VERSION, 'open reports the protocol version')
    results.ok({'app::run', 'ledger::apply', 'model::Stock'} <= ids, 'open lists branch declarations')
    results.ok(all(row['protected'] for row in opened['declarations']
                   if row['id'].split('::')[0] in ('main', 'io')), 'open marks protected declarations')
    results.ok([row['name'] for row in opened['assets']] == ['.trial-public/TASK.md',
               '.trial-public/cases.json'], 'open lists only assets under the asset root')
    results.ok(opened['receipt']['id'] >= 1 and len(opened['receipt']['sha256']) == 64,
               'open reports the branch head receipt')
    results.ok(opened['budgets']['context_max'] == 32768, 'open publishes the budget table')
    results.error(session.dispatch('open', {'module': 'app'}), 'open rejects arguments', 'unexpected')

    context = results.budget(session, session.context(['ledger::apply', 'model::Stock']), 'context', 'context')
    entries = {row['id']: row for row in context['entries']}
    results.ok(context['checked'] and context['signature_source'] == 'index-project',
               'context uses index signatures when the branch checks')
    results.ok(entries['ledger::apply']['source'].startswith('// Existing inventory'),
               'context returns canonical source with attached comments')
    results.ok(len(entries['ledger::apply']['hash']) == 64, 'context returns the if_match hash')
    results.ok([row['id'] for row in entries['ledger::apply']['callers']] == ['app::run'],
               'context reports callers from the index')
    results.ok(entries['ledger::apply']['tests'] == ['app::test_reserve'],
               'context reports the exported tests reaching a declaration')
    results.ok(any(row['id'] == 'std_hash_bytes::Map' for row in entries['ledger::apply']['types']),
               'context reports the types a declaration uses')
    results.ok(entries['model::Stock']['omitted']['callers'] >= 0, 'context reports omitted counts')
    results.error(session.dispatch('context', {'ids': ['model::Missing']}), 'context unknown id', 'no such')
    results.error(session.dispatch('context', {'ids': ['model::Stock'], 'budget': 64}),
                  'context budget floor', 'budget')

    tight = results.budget(session, session.context(
        ['app::run', 'model::validate', 'ledger::initial', 'ledger::apply'], 1024),
        'context', 'context tight', limit=1024)
    results.ok(tight['response_truncated'] is True, 'an over-budget response is marked truncated')
    results.ok(any(row['omitted'] for row in tight['entries']) or tight['omitted'].get('entries'),
               'a trimmed context reports omitted counts')
    wide = results.budget(session, session.context(['app::run', 'model::validate'], 32768),
                          'context', 'context wide', limit=32768)
    results.ok('response_truncated' not in wide and server.sized(wide) > session.budgets['context'],
               'the maximum context budget returns more than the default')
    retained = session._retained(tight['record'])['response']
    results.ok(sum(len(row['source']) for row in retained['entries'])
               > sum(len(row['source']) for row in tight['entries']),
               'the retained record holds everything the budget trimmed away')

    text = results.budget(session, session.search(text='reserv'), 'search', 'search text')
    results.ok(any(row['kind'] == 'declaration' and row['id'] == 'model::validate' for row in text['hits']),
               'text search finds declarations')
    results.ok(any(row['kind'] == 'asset' and row['name'] == '.trial-public/TASK.md' for row in text['hits']),
               'text search finds assets with a page offset')
    results.ok(all(len(row['snippet'].encode()) <= server.SNIPPET_BYTES for row in text['hits']),
               'search snippets stay within 200 bytes')
    typed = results.budget(session, session.search(type_name='model::Stock'), 'search', 'search type')
    results.ok('ledger::initial' in {row['id'] for row in typed['hits']}, 'type search finds users of a type')
    calls = results.budget(session, session.search(calls='ledger::apply'), 'search', 'search calls')
    results.ok({row['id'] for row in calls['hits']} == {'app::run'}, 'calls search finds callers')
    effect = results.budget(session, session.search(effect='allocation'), 'search', 'search effect')
    results.ok('app::run' in {row['id'] for row in effect['hits']}, 'effect search uses index effects')
    results.ok(len(effect['hits']) <= server.MAX_HITS, 'search returns at most twenty hits')
    results.error(session.dispatch('search', {'text': 'a', 'calls': 'b'}), 'search one mode', 'exactly one')
    results.error(session.dispatch('search', {}), 'search needs a mode', 'exactly one')

    page = results.budget(session, session.asset('.trial-public/TASK.md', 0, 20), 'asset', 'asset')
    rest = results.budget(session, session.asset('.trial-public/TASK.md', page['next_offset'], 4096),
                          'asset', 'asset rest')
    results.ok(page['text'] + rest['text'] == TASK.decode(), 'asset pages concatenate to the whole file')
    results.ok(rest['complete'] and rest['omitted']['bytes'] == 0, 'asset reports completion')
    results.error(session.dispatch('asset', {'name': 'private-notes.txt', 'offset': 0, 'limit': 10}),
                  'asset refuses files outside the asset root', 'no such readable asset')
    results.error(session.dispatch('asset', {'name': '.trial-public/TASK.md', 'offset': 0, 'limit': 0}),
                  'asset page cap', 'limit')


def rejection_details(session, results, stock):
    """A rejection has to teach the shape: exact fields for the op, kinds for a bad keyword."""
    for kind, operation in (('add', {'op': 'add', 'id': 'model::Stock', 'source': STOCK_WITH_FIELD}),
                            ('replace', {'op': 'replace', 'id': 'model::Stock'}),
                            ('remove', {'op': 'remove', 'id': 'model::Stock', 'source': ''})):
        response = results.budget(session, session.batch([operation], {'model::Stock': stock['hash']}),
                                  'batch', kind + ' field rejection')
        row = response['rejections'][0]
        accepted, example = server.OPERATION_SHAPES[kind]
        results.ok(row['reason'] == 'invalid-operation' and row['operation'] == 0,
                   f'a malformed {kind} is an invalid-operation rejection')
        results.ok(accepted in row['detail'] and example in row['detail'],
                   f'the {kind} rejection states its exact fields and a copy-ready example')
        results.ok(', '.join(sorted(operation)) in row['detail'],
                   f'the {kind} rejection names the fields the operation actually had')

    invented = results.budget(session, session.batch(
        [{'op': 'add', 'module': 'model', 'source': 'record Entry {\n    id: i64\n}'}], {}),
        'batch', 'invented keyword rejection')
    row = invented['rejections'][0]
    results.ok(invented['reason'] == 'parse-failure' and 'E_SYNTAX' in row['detail'],
               'an invented declaration keyword keeps the compiler diagnostic')
    results.ok(row['detail'].endswith(server.SYNTAX_HELP),
               'a syntax error at a declaration header appends the kinds and the reminder')
    results.ok(all(kind in server.SYNTAX_HELP for kind in server.DECLARATION_KINDS) and
               'record' in server.SYNTAX_HELP and 'i64(x)' in server.SYNTAX_HELP,
               'the reminder lists every accepted kind and the known guesses')

    deep = session.batch([{'op': 'replace', 'id': 'model::Stock', 'source': stock['source']},
                          {'op': 'add', 'module': 'model',
                           'source': 'fn widen(value: i64) -> i64 {\n    return value as i64;\n}'}],
                         {'model::Stock': stock['hash']})
    row = deep['rejections'][0]
    results.ok(deep['reason'] == 'parse-failure' and 'E_SYNTAX' in row['detail'],
               'a syntax error inside a body is still a parse failure')
    results.ok(server.SYNTAX_HELP not in row['detail'],
               'a body syntax error does not append the declaration-kind reminder')


def batch_rejections(session, results):
    """Every rejection leaves the branch, the receipt head and the rendered snapshot untouched."""
    before_branch, before_head = session.branch_digest(), session.store.head()['id']
    stock = session.context(['model::Stock'])['entries'][0]

    protected = results.budget(session, session.batch(
        [{'op': 'replace', 'id': 'io::put', 'source': 'host fn put(value: u8) -> i64 effects(host);'}],
        {'io::put': stock['hash']}), 'batch', 'protected rejection')
    results.ok(protected['status'] == 'rejected' and protected['passed'] is False,
               'a protected touch is rejected')
    results.ok(protected['scope_violations'] == ['io::put'],
               'protected rejection carries the gateway scope_violations field')
    results.ok(protected['committed'] is False and protected['reason'] == 'protected-declaration',
               'protected rejection names its reason')
    results.ok(protected['receipt']['id'] == before_head, 'protected rejection keeps the receipt head')

    conflict = results.budget(session, session.batch(
        [{'op': 'replace', 'id': 'model::Stock', 'source': STOCK_WITH_FIELD}],
        {'model::Stock': '0' * 64}), 'batch', 'if-match rejection')
    results.ok(conflict['reason'] == 'if-match-mismatch' and conflict['scope_violations'] == [],
               'a stale if_match is an if-match-mismatch rejection')

    missing = session.batch([{'op': 'remove', 'id': 'model::Stock'}], {})
    results.ok(missing['reason'] == 'if-match-missing', 'remove requires an if_match entry')
    unknown = session.batch([{'op': 'replace', 'id': 'model::Missing', 'source': STOCK_WITH_FIELD}], {})
    results.ok(unknown['reason'] == 'unknown-declaration', 'an unknown id is rejected')
    broken = session.batch([{'op': 'replace', 'id': 'model::Stock', 'source': 'struct Stock {'}],
                           {'model::Stock': stock['hash']})
    results.ok(broken['reason'] == 'parse-failure', 'a parse failure is rejected')
    multiple = session.batch([{'op': 'add', 'module': 'model', 'source': TWO_DECLARATIONS}], {})
    results.ok(multiple['reason'] == 'parse-failure', 'a multi-declaration source is rejected')
    shaped = session.dispatch('batch', {'ops': [{'op': 'rename', 'id': 'model::Stock'}], 'if_match': {}})
    results.ok(shaped.get('reason') == 'invalid-operation', 'an unknown operation is rejected')
    results.error(session.dispatch('batch', {'ops': [], 'if_match': {}}), 'batch needs operations', '1..')
    rejection_details(session, results, stock)

    results.ok(session.branch_digest() == before_branch, 'rejections leave the branch unchanged')
    results.ok(session.store.head()['id'] == before_head, 'rejections leave the receipt head unchanged')
    results.ok(session.context(['model::Stock'])['entries'][0]['hash'] == stock['hash'],
               'rejections leave the declaration hash unchanged')


def migration(session, results):
    """A record migration: one constructor replaced, one left, then the follow-up repair."""
    before = session.context(['model::Stock', 'ledger::initial'])
    hashes = {row['id']: row['hash'] for row in before['entries']}
    head = session.store.head()['id']
    first = results.budget(session, session.batch(
        [{'op': 'replace', 'id': 'model::Stock', 'source': STOCK_WITH_FIELD},
         {'op': 'replace', 'id': 'ledger::initial', 'source': INITIAL_WITH_FIELD}],
        {'model::Stock': hashes['model::Stock'], 'ledger::initial': hashes['ledger::initial']}),
        'batch', 'migration batch')
    results.ok(first['status'] == 'committed' and first['checked'] is False,
               'the migration commits on parse while the check fails')
    results.ok(first['receipt']['id'] == head + 1, 'a committed batch appends one receipt')
    incomplete = [row for row in first['delta']['new'] if row['code'] == 'E_INCOMPLETE_CONSTRUCTION']
    results.ok([row['id'] for row in incomplete] == ['app::rows'],
               'the delta points at the one unreplaced constructor')
    results.ok(any(note['id'] == 'model::Stock' for row in incomplete for note in row['notes']),
               'the mechanical note names the declaration that gained the field')
    results.ok([row['id'] for row in first['signature_changes']] == ['model::Stock']
               and first['signature_changes'][0]['after'].endswith('reserved: i64 }'),
               'signature changes report the touched declarations whose shape changed')
    results.ok('app::rows' in {row['id'] for row in first['affected']},
               'affected declarations come from the index of the previous snapshot')

    rows = session.context(['app::rows'])['entries'][0]
    second = results.budget(session, session.batch(
        [{'op': 'replace', 'id': 'app::rows', 'source': ROWS_WITH_FIELD}],
        {'app::rows': rows['hash']}), 'batch', 'repair batch')
    results.ok(second['status'] == 'committed' and second['checked'] is True,
               'the follow-up batch restores a checking branch')
    results.ok([(row['code'], row['id']) for row in second['delta']['resolved']]
               == [('E_INCOMPLETE_CONSTRUCTION', 'app::rows')], 'the repair resolves the reported diagnostic')
    results.ok(all(row['severity'] == 'warning' for row in second['delta']['new']),
               'the repaired branch reports no new errors')
    results.ok(second['receipt']['parent_id'] == first['receipt']['id'],
               'delta diagnostics chain across three receipts')

    added = results.budget(session, session.batch(
        [{'op': 'add', 'module': 'model', 'source': 'fn reserved_total(item: Stock) -> i64 { return item.reserved; }',
          'after': 'Stock', 'exported': True}], {}), 'batch', 'add batch')
    results.ok(added['status'] == 'committed'
               and [row['id'] for row in added['applied']] == ['model::reserved_total'],
               'add places one new declaration')
    removed = session.batch([{'op': 'remove', 'id': 'model::reserved_total'}],
                            {'model::reserved_total': added['applied'][0]['hash']})
    results.ok(removed['status'] == 'committed' and removed['delta']['unchanged_count'] >= 0,
               'remove commits and reports its delta')
    results.ok('model::reserved_total' not in {row['id'] for row in session.open()['declarations']},
               'a removed declaration leaves the branch')


def execution(session, results, work, compiler):
    """probe, check, output and finish, plus the private snapshot the gateway checks."""
    probe = results.budget(session, session.probe(REQUEST), 'probe', 'probe')
    results.ok(probe['outcome'] == 'exited' and probe['returncode'] == 0, 'probe runs the adapter')
    results.ok(json.loads(probe['stdout']) == EXPECTED, 'probe round-trips one request')
    results.ok(isinstance(probe['elapsed_seconds'], float), 'probe reports timing')
    results.error(session.dispatch('probe', {}), 'probe needs a request', 'exactly one request')

    checked = results.budget(session, session.check(), 'check', 'check')
    results.ok(checked['passed'] is True and checked['cases'][0]['name'] == 'stock-only',
               'the standalone check runs the public cases')
    results.ok(checked['scope_violations'] == [], 'the check receipt carries the gateway fields')
    results.error(session.dispatch('check', {'case': 'stock-only'}), 'check takes no arguments', 'unexpected')
    session.cases = WRONG_CASES
    failed = results.budget(session, session.check(), 'check', 'failing check')
    session.cases = CASES
    results.ok(failed['passed'] is False and failed['diagnostics'][0]['case'] == 'stock-only',
               'a wrong expected answer fails the check with bounded diagnostics')

    injected = session_for(work, compiler, 'injected', runner=lambda snapshot: {
        'passed': True, 'cases': [], 'scope_violations': [], 'inventory': snapshot['inventory_sha256']})
    try:
        hooked = injected.check()
        results.ok(hooked['inventory'] == injected.snapshot()['inventory_sha256'],
                   'an injected check hook receives the private snapshot record')
    finally:
        injected.close()

    page = results.budget(session, session.output(0, 0, 200), 'output', 'output')
    total = page['total_characters']
    joined = page['text']
    while page['next_offset'] < total:
        page = results.budget(session, session.output(0, page['next_offset'], 4096), 'output', 'output')
        joined += page['text']
    results.ok(json.loads(joined) == session._retained(0)['response'],
               'output pages the retained response in full')
    results.error(session.dispatch('output', {'record': 9999, 'offset': 0, 'limit': 10}),
                  'output range', 'within the session')
    results.error(session.dispatch('output', {'record': 0, 'offset': 0, 'limit': 0}),
                  'output limit', 'within the session')

    snapshot = session.snapshot()
    results.ok(Path(snapshot['path']).is_dir() and len(snapshot['inventory_sha256']) == 64,
               'snapshot renders a private directory with an inventory hash')
    results.ok('main.my' in snapshot['inventory'] and '.trial-public/TASK.md' in snapshot['inventory'],
               'the snapshot inventory is a drop-in project tree')

    done = results.budget(session, session.finish('completed'), 'finish', 'finish')
    results.ok(done['reason'] == 'completed' and done['receipt']['sha256'] == session.store.head()['sha256'],
               'finish reports the receipt head')
    results.ok(done['inventory_sha256'] == snapshot['inventory_sha256'], 'finish reports the final snapshot')
    results.ok(session.final_snapshot['path'] == snapshot['path'],
               'the gateway reads the final snapshot path from the session, never from a response')
    results.error(session.dispatch('finish', {'reason': 'later'}), 'finish reason', 'completed or abandoned')


def confinement(session, results):
    """No participant response ever carries a private path, and every response is retained whole."""
    records = sorted((session.session_dir / 'records').glob('[0-9]' * 6 + '.json'))
    results.ok(len(records) == session.records, 'every response is retained with a record number')
    private = session.private_root
    leaked = [path.name for path in records
              if private in json.dumps(json.loads(path.read_text())['returned'])]
    results.ok(not leaked, 'no returned response contains a private snapshot path: ' + ', '.join(leaked))
    results.ok(any(json.loads(path.read_text())['private'].get('snapshot_path') for path in records),
               'the retained record keeps the snapshot path for the coordinator')


def command_line(work, compiler, results):
    """The line protocol: one response per request, unknown verbs continue, malformed lines exit 2."""
    session_dir = work / 'cli-session'
    database = work / 'cli.sqlite'
    with store.Compiler(compiler) as tool:
        with store.Store(database, create=True, compiler=tool) as handle:
            store.import_directory(handle, tool, work / 'source', 'base')
            handle.create_branch('base', 'work')
    cases = work / 'cases.json'
    cases.write_bytes(json.dumps(CASES).encode())
    argv = [sys.executable, '-B', str(ROOT / 'scripts/store_server.py'), '--db', str(database),
            '--branch', 'work', '--compiler', str(compiler), '--session-dir', str(session_dir),
            '--cases', str(cases), '--adapter', str(Path(compiler).with_name('mylang-io')),
            '--project', '{work}']
    requests = '\n'.join(json.dumps(row) for row in [
        {'verb': 'open', 'arguments': {}},
        {'verb': 'teleport', 'arguments': {}},
        {'verb': 'asset', 'arguments': {'name': '.trial-public/TASK.md', 'offset': 0, 'limit': 4096}},
        {'verb': 'output', 'arguments': {'record': 0, 'offset': 0, 'limit': 100}},
        {'verb': 'finish', 'arguments': {'reason': 'abandoned'}}]) + '\n'
    result = subprocess.run(argv, input=requests.encode(), capture_output=True, timeout=600)
    lines = [json.loads(line) for line in result.stdout.decode().splitlines()]
    results.ok(result.returncode == 0, 'the line protocol exits 0 on a clean stream')
    results.ok(len(lines) == 5 and [row['record'] for row in lines] == [0, 1, 2, 3, 4],
               'one response per request with increasing record numbers')
    results.ok([row['verb'] for row in lines] == ['open', 'error', 'asset', 'output', 'finish'],
               'an unknown verb answers with an error and the session continues')
    results.ok(all(row['version'] == server.VERSION for row in lines), 'every response carries the version')
    results.ok(lines[3]['source_record'] == 0 and lines[3]['total_characters'] > 0,
               'output pages a prior record over the line protocol')
    broken = subprocess.run(argv, input=b'{"verb": "open"\n', capture_output=True, timeout=600)
    results.ok(broken.returncode == 2, 'a malformed line exits 2')
    unshaped = subprocess.run(argv, input=b'["open"]\n', capture_output=True, timeout=600)
    results.ok(unshaped.returncode == 2, 'a request that is not a verb object exits 2')


def feedback_parity(results):
    """The local bounded-feedback copy must equal the harness policy the files arm applies."""
    try:
        sys.path.insert(0, str(ROOT))
        from experiments.development_velocity.runner import bounded_feedback
    except (ImportError, ValueError):
        results.ok(True, 'bounded feedback parity skipped; the harness package is not importable')
        return
    samples = [{'passed': False, 'stdout': 'x' * 40000, 'stderr': 'y' * 40000},
               {'passed': False, 'cases': [{'name': 'a', 'passed': False}],
                'diagnostics': [{'case': 'a', 'stderr': 'z' * 50000}, {'case': 'b', 'stderr': 'w'}]},
               {'nested': [{'value': 'q' * 500} for _ in range(200)]}]
    for index, sample in enumerate(samples):
        results.ok(server.bounded(json.loads(json.dumps(sample)), 16384)
                   == bounded_feedback(json.loads(json.dumps(sample)), 16384),
                   f'bounded feedback matches the harness policy on sample {index}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--runner', required=True, help='mylang-io, the frozen application adapter')
    parser.add_argument('--work-dir', type=Path, default=ROOT / '.zig-cache/tmp/store-server')
    arguments = parser.parse_args()
    if Path(arguments.runner).resolve() != Path(arguments.compiler).resolve().with_name('mylang-io'):
        raise SystemExit('the adapter must be mylang-io beside the compiler')
    arguments.work_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(dir=arguments.work_dir, prefix='session-'))
    results = Failures()
    try:
        project(work / 'source')
        session = session_for(work, arguments.compiler, 'store')
        try:
            read_verbs(session, results)
            batch_rejections(session, results)
            migration(session, results)
            execution(session, results, work, arguments.compiler)
            confinement(session, results)
        finally:
            session.close()
        command_line(work, arguments.compiler, results)
        feedback_parity(results)
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        results.failed.append(f'unhandled {type(error).__name__}: {error}')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for label in results.failed:
        print('FAIL ' + label)
    print(f'store-server: {results.checked - len(results.failed)}/{results.checked} checks passed; '
          'maximum response bytes ' + json.dumps(dict(sorted(results.maxima.items()))))
    return 1 if results.failed else 0


if __name__ == '__main__':
    sys.exit(main())
