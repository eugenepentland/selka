#!/usr/bin/env python3
"""Declaration-store session server: name-addressed source behind bounded verbs, no paths."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import resource
import shutil
import sqlite3
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import navigate  # noqa: E402  (the navigation client ships beside this server)
import store  # noqa: E402  (the declaration store ships beside this server)

VERSION = 'store-session-v1'
VERBS = ('open', 'context', 'search', 'asset', 'batch', 'probe', 'check', 'output', 'finish')
# The plan's budget table, in bytes of the serialized participant response.
BUDGETS = {'open': 8192, 'context': 8192, 'context_max': 32768, 'search': 8192, 'asset': 8192,
           'batch': 16384, 'probe': 16384, 'check': 16384, 'output': 8192, 'finish': 4096}
PROTECTED_MODULES = ('main', 'io')
DEFAULT_ASSET_ROOT = '.trial-public'
DEFAULT_LIMITS = {'wall_seconds': 90, 'cpu_seconds': 90, 'memory_bytes': 4 * 1024 ** 3,
                  'output_bytes': 16 * 1024 ** 2}
MIN_BUDGET = 1024
MAX_IDS = 16
MAX_OPS = 32
MAX_HITS = 20
MAX_RELATED = 8
SNIPPET_BYTES = 200
TYPE_SOURCE_BYTES = 512
MAX_SOURCE_BYTES = 64 * 1024
MAX_PAGE = 8192
MAX_REQUEST_BYTES = 2 * 1024 * 1024
MAX_RECORDS = 10000
CHECK_TIMEOUT = 600
ARGUMENTS = {'open': set(), 'context': {'ids', 'budget'}, 'search': {'text', 'type', 'calls', 'effect', 'limit'},
             'asset': {'name', 'offset', 'limit'}, 'batch': {'ops', 'if_match'}, 'probe': {'request'},
             'check': set(), 'output': {'record', 'offset', 'limit'}, 'finish': {'reason'}}
TYPE_EDGE_KINDS = ('uses_type', 'contains_type', 'returns', 'accepts', 'field_initialize', 'field_read')
# Every accepted top-level declaration kind, in the order the participant documents
# list them. `store.KINDS` is the authority; drift fails closed at import.
DECLARATION_KINDS = ('alias', 'const', 'resource', 'result', 'enum',
                     'union', 'domain', 'struct', 'fn', 'host_fn', 'extern_fn')
if frozenset(DECLARATION_KINDS) != frozenset(store.KINDS):
    raise ValueError('the documented declaration kinds no longer match the store')
# Appended to a parse failure that lands on a declaration's own header line. The
# pilot lost ten batches there to invented syntax, so the reminder names what exists.
SYNTAX_HELP = ('A top-level declaration is one of these kinds: ' + ', '.join(DECLARATION_KINDS) +
               '. There is no record keyword; a product type is written class Name: with one '
               'annotated field per indented line. A function is def name(x: i64) -> i64: with '
               'an indented suite; indentation is the block syntax and braces are only a dict '
               'literal. Casts are i64(x), never cast<i64>(x) or x as i64. Qualified references '
               'derive imports, so no import statement is ever written.')
# The exact accepted fields of each batch operation, with a copy-ready example.
OPERATION_SHAPES = {
    'replace': ('op, id, source',
                '{"op":"replace","id":"MODULE::NAME","source":"<one top-level declaration>"}'),
    'add': ('op, module, source and the optional after, exported',
            '{"op":"add","module":"MODULE","source":"<one top-level declaration>",'
            '"after":"SIBLING_NAME","exported":false}'),
    'remove': ('op, id', '{"op":"remove","id":"MODULE::NAME"}'),
}
SYNTAX_LOCATION = re.compile(r':(\d+):\d+: error\[E_SYNTAX\]')
# Compiler scratch module paths in diagnostics, e.g. /tmp/mylang-store-abc123/source.my
SCRATCH_PATH = re.compile(r'\S*mylang-store-[^/\s]+/source\.my')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def sized(value):
    """Serialized response size in bytes; budgets are stated over exactly this number."""
    return len(json.dumps(value, ensure_ascii=False, allow_nan=False).encode('utf-8'))


def bounded(result, limit):
    """Shape one response to a character budget; the retained record still holds everything.

    This mirrors `experiments/development_velocity/runner.bounded_feedback`, which the files
    arm applies to its check receipts. The two must agree; `tests/store_server.py` compares
    them whenever the harness package is importable.
    """
    if type(limit) is not int or limit < 256:
        raise ValueError('feedback limit must be at least 256 characters')
    if len(json.dumps(result, ensure_ascii=False)) <= limit:
        return result
    result = dict(result)
    if 'diagnostics' in result:
        failures = {row['name'] for row in result.get('cases', []) if not row['passed']}
        result['diagnostics'] = [row for row in result['diagnostics'] if row.get('case') in failures]
    for key in ('stdout', 'stderr'):
        if len(result.get(key, '')) > limit // 4:
            value = result[key]
            result[key] = value[:limit // 8] + '\n... [middle omitted; full output retained] ...\n' + value[-limit // 8:]
            result[key + '_characters'] = len(value)
    encoded = json.dumps(result, ensure_ascii=False)
    if len(encoded) > limit:
        result = {'feedback_truncated': True, 'summary': '', 'full_evidence_retained': True}
        low, high = 0, min(len(encoded), limit)
        while low < high:
            middle = (low + high + 1) // 2
            result['summary'] = encoded[:middle]
            if len(json.dumps(result, ensure_ascii=False)) <= limit:
                low = middle
            else:
                high = middle - 1
        result['summary'] = encoded[:low]
        return result
    result = dict(result, feedback_truncated=True, full_evidence_retained=True)
    if len(json.dumps(result, ensure_ascii=False)) > limit:
        return bounded({'stdout': encoded}, limit)
    return result


def trimmed(body, budget, keys):
    """Drop trailing rows of the named list fields, `a.b` included, until the body fits its budget."""
    omitted = body.setdefault('omitted', {})
    for key in keys:
        path, _, field = key.rpartition('.')
        container = body
        for part in path.split('.') if path else ():
            container = container.get(part) or {}
        while sized(body) > budget and container.get(field):
            container[field].pop()
            omitted[key] = omitted.get(key, 0) + 1
    return body


def clip(text, limit):
    """UTF-8 safe prefix of at most `limit` bytes."""
    data = text.encode('utf-8')
    return (data[:max(0, limit)].decode('utf-8', errors='ignore'), len(data)) if len(data) > limit else (text, len(data))


def shape(row):
    """What a participant compares across an edit: a function header, or a whole type body."""
    if row is None:
        return None
    if row['kind'] in ('fn', 'host_fn'):
        return row['signature']
    text = row['canonical_source'].decode('utf-8', errors='replace')
    return clip(' '.join(text[store.body_start(text):].split()), store.MAX_SIGNATURE_BYTES)[0]


def owner(identifier):
    """The top-level declaration owning an index symbol id; locals carry a byte suffix."""
    return identifier.split('/local:', 1)[0] if isinstance(identifier, str) else identifier


def decode_case(case):
    """The coordinator case form, without importing the harness package into a frozen tool."""
    if not isinstance(case, dict) or 'expected' not in case:
        raise ValueError('case requires expected output')
    if set(case) == {'request', 'expected'}:
        return canonical(case['request']), case['expected']
    if set(case) != {'request_base64', 'expected'}:
        raise ValueError('case requires exactly one JSON or base64 input')
    raw = base64.b64decode(case['request_base64'], validate=True)
    if base64.b64encode(raw).decode('ascii') != case['request_base64']:
        raise ValueError('noncanonical base64 input')
    return raw, case['expected']


def inventory(directory):
    """Every rendered regular file as relative path to SHA-256; the gateway's public-check input."""
    directory = Path(directory)
    rows = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        rows[path.relative_to(directory).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return rows


class Adapter:
    """The frozen application adapter: an injected callable, or an argv template with `{work}`."""

    def __init__(self, spec, limits=None):
        self.limits = dict(DEFAULT_LIMITS, **(limits or {}))
        if callable(spec):
            self.callable, self.argv = spec, None
        else:
            argv = list(spec or ())
            if not argv or any(not isinstance(item, str) or '\x00' in item for item in argv):
                raise ValueError('an adapter is a callable or a nonempty argv template')
            if not any('{work}' in item for item in argv):
                raise ValueError('an adapter argv template must place the snapshot with {work}')
            if Path(argv[0]).exists():  # The snapshot is the working directory; resolve now.
                argv[0] = str(Path(argv[0]).resolve(strict=True))
            self.callable, self.argv = None, argv

    def _rlimits(self):
        resource.setrlimit(resource.RLIMIT_CPU, (self.limits['cpu_seconds'], self.limits['cpu_seconds']))
        resource.setrlimit(resource.RLIMIT_AS, (self.limits['memory_bytes'], self.limits['memory_bytes']))

    def run(self, work, input_bytes):
        """One adapter execution against a rendered snapshot; bounded streams and status."""
        if self.callable is not None:
            return self.callable(str(work), input_bytes)
        argv = [item.replace('{work}', str(work)) for item in self.argv]
        started = datetime.now(timezone.utc)
        try:
            result = subprocess.run(argv, input=input_bytes, capture_output=True,
                                    timeout=self.limits['wall_seconds'], preexec_fn=self._rlimits,
                                    cwd=str(work), env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'})
            outcome, code, out, err = 'exited', result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as expired:
            outcome, code = 'timeout', None
            out, err = expired.stdout or b'', expired.stderr or b''
        cap = self.limits['output_bytes']
        return {'outcome': outcome, 'returncode': code, 'stdout': out[:cap], 'stderr': err[:cap],
                'stdout_bytes': len(out), 'stderr_bytes': len(err),
                'elapsed_seconds': (datetime.now(timezone.utc) - started).total_seconds()}


class StoreSession:
    """One attempt's session over a declaration store; every verb returns a bounded JSON dict."""

    def __init__(self, database, branch, compiler, adapter, session_dir, *,
                 asset_root=DEFAULT_ASSET_ROOT, budgets=None, protected_modules=PROTECTED_MODULES,
                 check=None, cases=None, limits=None):
        self.branch = branch
        self.budgets = dict(BUDGETS, **(budgets or {}))
        if any(type(value) is not int or value < MIN_BUDGET for value in self.budgets.values()):
            raise ValueError('every budget is an integer of at least 1024 bytes')
        self.asset_root = (asset_root or '').strip('/')
        self.protected_modules = frozenset(protected_modules)
        self.compiler = store.Compiler(compiler)
        self.store = store.Store(database, compiler=self.compiler)
        if branch not in self.store.branches():
            raise ValueError('no such branch in this store: ' + branch)
        self.store.verify_chain()
        self.adapter = adapter if isinstance(adapter, Adapter) else Adapter(adapter, limits)
        self.check_runner = check
        self.cases = cases
        if check is not None and not callable(check):
            raise ValueError('the check hook is a callable taking the snapshot record')
        self.session_dir = Path(session_dir)
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.private_root = str(self.session_dir.resolve())
        for name in ('snapshots', 'records', 'candidates'):
            (self.session_dir / name).mkdir(parents=True, exist_ok=True)
        self.records = len(list((self.session_dir / 'records').glob('[0-9]' * 6 + '.json')))
        self.final_snapshot = None
        self._snapshot = None
        self._index_cache = {}
        self._declarations_cache = {}
        self._diagnostic_cache = {}

    # Lifetime ---------------------------------------------------------------
    def close(self):
        self.store.close()
        self.compiler.close()

    def __enter__(self):
        return self

    def __exit__(self, *details):
        self.close()

    # Retention --------------------------------------------------------------
    def _respond(self, verb, arguments, body, *, private=None, keys=(), view=None, budget=None):
        """Retain the full response, then return the participant's budgeted view of it."""
        if self.records >= MAX_RECORDS:
            raise ValueError('session response budget exhausted')
        record = self.records
        self.records += 1
        full = dict(body, version=VERSION, verb=verb, record=record)
        budget = self.budgets.get(verb, self.budgets['open']) if budget is None else budget
        view = full if view is None else dict(view, version=VERSION, verb=verb, record=record)
        if view is not full or sized(view) > budget:
            if view is full:
                view = json.loads(json.dumps(full, ensure_ascii=False))
            envelope = {'version': VERSION, 'verb': verb, 'record': record, 'response_truncated': True,
                        'hint': f'output {{"record": {record}, "offset": 0, "limit": 4096}} pages the '
                                'retained response'}
            view.update(envelope)
            if sized(view) > budget and keys:
                trimmed(view, budget, keys)
            room = budget - sized(envelope)
            while sized(view) > budget:
                rest = {key: value for key, value in view.items() if key not in envelope}
                view = dict(bounded(rest, room), **envelope)
                if room <= 256:
                    break
                room -= 128
        text = json.dumps(view, ensure_ascii=False, allow_nan=False)
        if self.private_root in text:
            # Fail closed: no private snapshot or session path ever reaches the participant.
            view = json.loads(text.replace(self.private_root, '<private-snapshot>'))
        path = self.session_dir / 'records' / f'{record:06}.json'
        path.write_bytes(canonical({'version': VERSION, 'record': record, 'verb': verb,
                                    'arguments': arguments, 'utc': datetime.now(timezone.utc).isoformat(),
                                    'response': full, 'returned': view,
                                    'private': private or {}}) + b'\n')
        return view

    def _retained(self, record):
        path = self.session_dir / 'records' / f'{record:06}.json'
        if not path.exists():
            raise ValueError('no such retained record: ' + str(record))
        return json.loads(path.read_text())

    # Snapshots and compiler facts -------------------------------------------
    def branch_digest(self):
        return self.store.snapshot(self.branch)

    def entry(self):
        """The rendered module the compiler is pointed at; `main` when the branch has one."""
        entries = [module for module in self.store.modules(self.branch)
                   if self.store.module_meta(self.branch, module).get('entry')]
        if not entries:
            raise ValueError('the branch records no project entry module')
        chosen = 'main' if 'main' in entries else sorted(entries)[0]
        return chosen, self.store.module_meta(self.branch, chosen)['path']

    def snapshot(self):
        """Render the branch into a fresh private directory; the gateway's public-check input."""
        current = self.branch_digest()
        if self._snapshot is not None and self._snapshot['branch_sha256'] == current:
            return self._snapshot
        index = len(list((self.session_dir / 'snapshots').glob('[0-9]' * 3)))
        directory = self.session_dir / 'snapshots' / f'{index:03}'
        report = self.store.render_branch(self.branch, directory, compiler=self.compiler)
        self._snapshot = self._describe(directory, current, index, report)
        return self._snapshot

    def cached_snapshot(self, record=None):
        """Read, or adopt, this branch's rendered snapshot: the coordinator's cross-process cache.

        A gateway that opens one session per request would otherwise re-render an
        unchanged branch every time. Adoption is refused unless the record names this
        branch, matches its current digest and still exists on disk.
        """
        if isinstance(record, dict) and record.get('branch') == self.branch and (
                record.get('branch_sha256') == self.branch_digest()
                and isinstance(record.get('path'), str) and Path(record['path']).is_dir()):
            self._snapshot = record
        return self._snapshot

    def _describe(self, directory, branch_sha256, index, report):
        rows = inventory(directory)
        return {'index': index, 'path': str(directory.resolve()), 'branch': self.branch,
                'branch_sha256': branch_sha256, 'inventory': rows, 'inventory_sha256': digest(rows),
                'modules': report['modules'], 'assets': report['assets'], 'entries': report['entries']}

    def _index(self):
        """The checked project index of the current snapshot, or None when it cannot be built."""
        snapshot = self.snapshot()
        key = snapshot['branch_sha256']
        if key not in self._index_cache:
            _, path = self.entry()
            try:
                index, _ = navigate.load(Path(self.compiler.path), Path(snapshot['path']) / path, None)
            except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
                index = None  # An unbuildable index degrades context, never the session.
            self._index_cache = {key: index if index and index.get('checked') else None}
        return self._index_cache[key]

    def _module_declarations(self, snapshot, module):
        """`list-declarations` byte ranges on the rendered snapshot, for locating diagnostics."""
        key = (snapshot['branch_sha256'], module)
        if key not in self._declarations_cache:
            path = Path(snapshot['path']) / self.store.module_meta(self.branch, module)['path']
            data = path.read_bytes()
            document = self.compiler.declarations(data)
            self._declarations_cache[key] = (data, document['declarations'])
        return self._declarations_cache[key]

    def _locate(self, snapshot, paths, location):
        """A qualified declaration id for one diagnostic location, or None outside the branch."""
        if not isinstance(location, dict):
            return None
        module = paths.get(location.get('path'))
        if module is None:
            return None
        data, rows = self._module_declarations(snapshot, module)
        span = location.get('bytes')
        if isinstance(span, dict) and isinstance(span.get('start'), int):
            offset = span['start']
        else:
            start = location.get('start') or {}
            if not isinstance(start.get('line'), int):
                return None
            lines = data.split(b'\n')[:start['line'] - 1]
            offset = sum(len(line) + 1 for line in lines) + max(0, start.get('column', 1) - 1)
        for entry in rows:
            if entry['comment_start'] <= offset < entry['bytes']['end']:
                return module + '::' + entry['name']
        return None

    def diagnostics(self, snapshot):
        """`check-project --diagnostics=json` on a snapshot, keyed by code, declaration and message."""
        key = snapshot['branch_sha256']
        if key in self._diagnostic_cache:
            return self._diagnostic_cache[key]
        _, path = self.entry()
        result = subprocess.run([str(self.compiler.path), 'check-project', str(Path(snapshot['path']) / path),
                                 '--diagnostics=json'], capture_output=True, timeout=CHECK_TIMEOUT,
                                cwd=str(snapshot['path']))
        paths = {self.store.module_meta(self.branch, module)['path']: module
                 for module in self.store.modules(self.branch)}
        rows, messages = [], []
        for line in result.stderr.decode('utf-8', errors='replace').splitlines():
            if not line.startswith('{'):
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get('version') != 'diagnostic-v1':
                continue
            if record.get('kind') != 'diagnostic':
                messages.append(str(record.get('message', ''))[:512])
                continue
            item = record['diagnostic']
            rows.append({'code': item['code'], 'severity': item['severity'], 'message': item['message'],
                         'id': self._locate(snapshot, paths, item.get('location')),
                         'notes': [{'role': note.get('role'), 'message': note.get('message'),
                                    'id': self._locate(snapshot, paths, note.get('location'))}
                                   for note in item.get('notes', [])]})
        report = {'checked': result.returncode == 0, 'diagnostics': rows, 'messages': messages}
        self._diagnostic_cache = {key: report}
        return report

    @staticmethod
    def diagnostic_key(row):
        return (row['code'], row['id'], row['message'])

    def previous_diagnostics(self):
        """The head receipt's recorded diagnostic set, or a fresh check of the current snapshot."""
        head = self.store.head()
        if head is not None:
            delta = json.loads(head['delta_json'])
            recorded = delta.get('diagnostics') if isinstance(delta, dict) else None
            if isinstance(recorded, list) and head['snapshot_sha256'] == self.branch_digest():
                return recorded
        return self.diagnostics(self.snapshot())['diagnostics']

    # Declaration views ------------------------------------------------------
    def protected(self, module):
        return module in self.protected_modules

    def visible_assets(self):
        root = self.asset_root
        return [row for row in self.store.assets()
                if not root or row['name'] == root or row['name'].startswith(root + '/')]

    def signatures(self, index):
        """Checked signatures by declaration id when the branch checks; empty otherwise."""
        if index is None:
            return {}
        return {item['id']: item['signature'] for item in index['symbols']
                if '/local:' not in item['id'] and item.get('signature')}

    def _relations(self, index):
        """Forward and reverse index references touching a set of declaration ids."""
        forward, reverse = {}, {}
        if index is None:
            for row in self.store.connection.execute(
                    'SELECT n.module, n.name, e.to_id, e.kind FROM edges e JOIN names n ON n.hash = e.from_hash '
                    'AND n.branch = e.branch WHERE e.branch = ?', (self.branch,)).fetchall():
                source, target = row['module'] + '::' + row['name'], row['to_id']
                forward.setdefault(source, {}).setdefault(target, set()).add(row['kind'])
                reverse.setdefault(target, {}).setdefault(source, set()).add(row['kind'])
            return forward, reverse
        for edge in index['references']:
            source, target = owner(edge['from']), owner(edge['to'])
            if source == target:
                continue
            forward.setdefault(source, {}).setdefault(target, set()).add(edge['kind'])
            reverse.setdefault(target, {}).setdefault(source, set()).add(edge['kind'])
        return forward, reverse

    def _tests(self, index, forward, target):
        """Exported `test_` declarations whose call graph reaches one declaration."""
        if index is None:
            return []
        seeds = [item['id'] for item in index['symbols'] if item.get('exported')
                 and '/local:' not in item['id'] and item['id'].split('::')[-1].startswith('test_')]
        found = []
        for seed in sorted(seeds):
            seen, queue = {seed}, [seed]
            while queue:
                current = queue.pop()
                if current == target:
                    found.append(seed)
                    break
                for following, kinds in forward.get(current, {}).items():
                    if 'call' in kinds and following not in seen:
                        seen.add(following)
                        queue.append(following)
        return found

    # Verbs ------------------------------------------------------------------
    def open(self):
        """Modules, declaration inventory, readable assets, budgets and the receipt head."""
        rows = self.store.list_branch(self.branch)
        head = self.store.head()
        modules = {}
        for row in rows:
            modules.setdefault(row['module'], 0)
            modules[row['module']] += 1
        body = {'branch': self.branch,
                'modules': [{'module': module, 'declarations': count, 'protected': self.protected(module)}
                            for module, count in sorted(modules.items())],
                'declarations': [{'id': row['id'], 'kind': row['kind'], 'exported': row['exported'],
                                  'signature': clip(row['signature'], 160)[0],
                                  'bytes': len(row['canonical_source']),
                                  'protected': self.protected(row['module'])}
                                 for row in rows],
                'assets': [{'name': row['name'], 'kind': row['kind'], 'bytes': row['size']}
                           for row in self.visible_assets()],
                'budgets': {key: value for key, value in sorted(self.budgets.items())},
                'receipt': None if head is None else {'id': head['id'], 'parent_id': head['parent_id'],
                                                      'branch': head['branch'], 'utc': head['utc'],
                                                      'sha256': head['sha256']},
                'omitted': {},
                'hints': ['context {"ids":["module::name"]} returns source and the hash if_match needs',
                          'batch never touches a protected declaration or an asset']}
        return self._respond('open', {}, body, keys=('declarations', 'assets'))

    def context(self, ids, budget=None):
        """Canonical source plus checked neighbours for each qualified id, under one byte budget."""
        if not isinstance(ids, list) or not ids or len(ids) > MAX_IDS:
            raise ValueError(f'context takes 1..{MAX_IDS} qualified declaration ids')
        budget = self.budgets['context'] if budget is None else budget
        if type(budget) is not int or not MIN_BUDGET <= budget <= self.budgets['context_max']:
            raise ValueError(f'context budget is 1024..{self.budgets["context_max"]} bytes')
        index = self._index()
        checked = index is not None
        signatures = self.signatures(index)
        kinds = {} if index is None else {item['id']: item['kind'] for item in index['symbols']
                                          if '/local:' not in item['id']}
        forward, reverse = self._relations(index)
        known = {row['id']: row for row in self.store.list_branch(self.branch)}

        def described(identifier):
            row = known.get(identifier)
            return {'id': identifier, 'external': row is None,
                    'signature': signatures.get(identifier, row['signature'] if row else '')}

        entries, share = [], max(256, budget // (2 * len(ids)))
        for identifier in ids:
            if not isinstance(identifier, str) or identifier not in known:
                raise ValueError('no such declaration on this branch: ' + str(identifier))
            row = known[identifier]
            source, total = clip(row['canonical_source'].decode('utf-8'), MAX_SOURCE_BYTES)
            entry = {'id': identifier, 'hash': row['hash'], 'kind': row['kind'], 'module': row['module'],
                     'exported': row['exported'], 'protected': self.protected(row['module']),
                     'signature': signatures.get(identifier, row['signature']),
                     'source': source, 'source_bytes': total, 'omitted': {}}
            callees = sorted(target for target, edges in forward.get(identifier, {}).items() if 'call' in edges)
            callers = sorted(item for item, edges in reverse.get(identifier, {}).items() if 'call' in edges)
            types = sorted(target for target, edges in forward.get(identifier, {}).items()
                           if edges & set(TYPE_EDGE_KINDS)
                           and (kinds.get(target) == 'type' if target in kinds
                                else target in known and known[target]['kind'] != 'fn'))
            tests = self._tests(index, forward, identifier)
            entry['callees'] = [described(item) for item in callees[:MAX_RELATED]]
            entry['callers'] = [described(item) for item in callers[:MAX_RELATED]]
            entry['types'] = [dict(described(item), source=clip(
                known[item]['canonical_source'].decode('utf-8'), TYPE_SOURCE_BYTES)[0] if item in known else None)
                for item in types[:MAX_RELATED]]
            entry['tests'] = tests[:MAX_RELATED]
            for key, values in (('callees', callees), ('callers', callers), ('types', types), ('tests', tests)):
                entry['omitted'][key] = max(0, len(values) - MAX_RELATED)
            entries.append(entry)
        body = {'checked': checked,
                'signature_source': 'index-project' if checked else 'declaration-header',
                'relation_source': 'index-project' if checked else 'imported index edges',
                'budget': budget, 'entries': entries, 'omitted': {},
                'hints': [] if checked else
                ['the branch does not check; signatures are declaration headers, not resolved types']}
        view = body
        if sized(body) > budget:
            view = json.loads(json.dumps(body, ensure_ascii=False))
            for stage in ('source', 'types', 'callers', 'callees'):
                if sized(view) <= budget:
                    break
                for entry in view['entries']:
                    if stage == 'source' and len(entry['source'].encode()) > share:
                        entry['source'], _ = clip(entry['source'], share)
                        entry['omitted']['source_bytes'] = entry['source_bytes'] - len(entry['source'].encode())
                    elif stage != 'source' and entry[stage]:
                        entry['omitted'][stage] = entry['omitted'].get(stage, 0) + len(entry[stage])
                        entry[stage] = []
            view['hints'] = view['hints'] + ['request fewer ids, page the record, or raise budget up to '
                                             + str(self.budgets['context_max'])]
        return self._respond('context', {'ids': ids, 'budget': budget}, body, budget=budget,
                             keys=('entries',), view=None if view is body else view)

    def search(self, *, text=None, type_name=None, calls=None, effect=None, limit=MAX_HITS):
        """One query mode over the branch: declaration text, type use, callers or declared effects."""
        selectors = {'text': text, 'type': type_name, 'calls': calls, 'effect': effect}
        chosen = [name for name, value in selectors.items() if value is not None]
        if len(chosen) != 1 or not isinstance(selectors[chosen[0]], str) or not selectors[chosen[0]]:
            raise ValueError('search takes exactly one of text, type, calls or effect')
        mode, needle = chosen[0], selectors[chosen[0]]
        if type(limit) is not int or not 1 <= limit <= MAX_HITS:
            raise ValueError(f'search returns 1..{MAX_HITS} hits')
        rows = self.store.list_branch(self.branch)
        index = self._index()
        hits = []
        if mode == 'text':
            folded = needle.casefold()
            for row in rows:
                body = row['canonical_source'].decode('utf-8', errors='replace')
                at = body.casefold().find(folded)
                if at < 0:
                    continue
                start = max(0, at - SNIPPET_BYTES // 4)
                hits.append({'kind': 'declaration', 'id': row['id'], 'offset': at,
                             'protected': self.protected(row['module']),
                             'snippet': clip(body[start:start + SNIPPET_BYTES], SNIPPET_BYTES)[0]})
            for asset in self.visible_assets():
                data = self.store.asset(asset['name'])['bytes'].decode('utf-8', errors='replace')
                at = data.casefold().find(folded)
                if at < 0:
                    continue
                start = max(0, at - SNIPPET_BYTES // 4)
                hits.append({'kind': 'asset', 'name': asset['name'], 'offset': start,
                             'snippet': clip(data[start:start + SNIPPET_BYTES], SNIPPET_BYTES)[0],
                             'total_bytes': asset['size']})
        else:
            known = {row['id']: row for row in rows}
            forward, reverse = self._relations(index)
            if mode == 'calls':
                matches = {item for item, kinds in reverse.get(needle, {}).items() if 'call' in kinds}
            elif mode == 'type':
                matches = {item for item, kinds in reverse.get(needle, {}).items()
                           if kinds & set(TYPE_EDGE_KINDS)}
                if needle in known:
                    matches.add(needle)
            else:
                matches = set()
                if index is not None:
                    matches = {owner(item['id']) for item in index['symbols']
                               if needle in (item.get('effects') or [])}
                else:
                    for row in rows:
                        if needle in row['effects']:
                            matches.add(row['id'])
            for identifier in sorted(matches):
                row = known.get(identifier)
                if row is None:
                    continue
                hits.append({'kind': 'declaration', 'id': identifier, 'offset': 0,
                             'protected': self.protected(row['module']),
                             'snippet': clip(row['canonical_source'].decode('utf-8', errors='replace'),
                                             SNIPPET_BYTES)[0]})
        found = len(hits)
        hits = hits[:limit]
        body = {'mode': mode, 'query': needle, 'checked': index is not None, 'hits': hits,
                'omitted': {'hits': max(0, found - len(hits))},
                'hints': [] if index is not None or mode == 'text' else
                ['the branch does not check; index-backed search uses the last imported edges']}
        return self._respond('search', {'mode': mode, 'query': needle, 'limit': limit}, body,
                             keys=('hits',))

    def asset(self, name, offset=0, limit=MAX_PAGE):
        """One page of one readable asset; unknown or out-of-root names are refused."""
        if not isinstance(name, str) or type(offset) is not int or type(limit) is not int:
            raise ValueError('asset takes a name with integer offset and limit')
        if offset < 0 or not 1 <= limit <= MAX_PAGE:
            raise ValueError(f'asset offset is non-negative and limit is 1..{MAX_PAGE}')
        if name not in {row['name'] for row in self.visible_assets()}:
            raise ValueError('no such readable asset: ' + name)
        data = self.store.asset(name)['bytes']
        budget = self.budgets['asset']
        served = min(limit, len(data) - min(offset, len(data)))
        while True:
            page = data[offset:offset + served]
            body = {'name': name, 'offset': offset, 'bytes': len(page), 'total_bytes': len(data),
                    'text': page.decode('utf-8', errors='replace'),
                    'next_offset': min(len(data), offset + len(page)),
                    'complete': offset + len(page) >= len(data), 'omitted': {}}
            if served <= 0 or sized(body) <= budget:
                break
            served = served * 3 // 4
        body['omitted']['bytes'] = max(0, len(data) - body['next_offset'])
        return self._respond('asset', {'name': name, 'offset': offset, 'limit': limit}, body)

    # Batch ------------------------------------------------------------------
    def _validate_ops(self, ops, if_match):
        """Shape, protection and if-match checks against the branch head; no branch is touched."""
        if not isinstance(ops, list) or not ops or len(ops) > MAX_OPS:
            raise ValueError(f'batch takes 1..{MAX_OPS} operations')
        if not isinstance(if_match, dict):
            raise ValueError('if_match maps declaration ids to their current hashes')
        known = {row['id']: row for row in self.store.list_branch(self.branch)}
        violations, rejections, touched = [], [], []
        for position, operation in enumerate(ops):
            if not isinstance(operation, dict) or operation.get('op') not in ('replace', 'add', 'remove'):
                rejections.append({'operation': position, 'reason': 'invalid-operation',
                                   'detail': 'each operation is replace, add or remove'})
                continue
            kind = operation['op']
            fields = {'replace': {'op', 'id', 'source'}, 'remove': {'op', 'id'},
                      'add': {'op', 'module', 'source'}}[kind]
            extra = set(operation) - fields - ({'after', 'exported'} if kind == 'add' else set())
            if extra or not fields <= set(operation):
                accepted, example = OPERATION_SHAPES[kind]
                given = ', '.join(sorted(str(key) for key in operation)) or 'no fields'
                rejections.append({'operation': position, 'reason': 'invalid-operation',
                                   'detail': f'unexpected or missing fields for {kind}: {kind} takes '
                                             f'exactly {accepted}; this operation has {given}. '
                                             f'Example: {example}'})
                continue
            if kind == 'add':
                module = operation['module']
                if not isinstance(module, str) or module not in self.store.modules(self.branch):
                    rejections.append({'operation': position, 'reason': 'unknown-module',
                                       'detail': str(module)})
                    continue
            else:
                identifier = operation['id']
                if not isinstance(identifier, str) or identifier not in known:
                    rejections.append({'operation': position, 'reason': 'unknown-declaration',
                                       'detail': str(identifier)})
                    continue
                module = known[identifier]['module']
                touched.append(identifier)
            if self.protected(module):
                target = operation.get('id', module)
                violations.append(target)
                rejections.append({'operation': position, 'reason': 'protected-declaration',
                                   'detail': str(target)})
                continue
            if kind in ('replace', 'remove'):
                expected = if_match.get(operation['id'])
                if expected is None:
                    rejections.append({'operation': position, 'reason': 'if-match-missing',
                                       'detail': operation['id']})
                elif expected != known[operation['id']]['hash']:
                    rejections.append({'operation': position, 'reason': 'if-match-mismatch',
                                       'detail': operation['id']})
            if kind in ('replace', 'add'):
                source = operation['source']
                if not isinstance(source, str) or not source.strip() or len(source.encode()) > MAX_SOURCE_BYTES:
                    rejections.append({'operation': position, 'reason': 'invalid-source',
                                       'detail': 'source is nonempty text under 64 KiB'})
        for identifier, expected in sorted(if_match.items()):
            if identifier not in known:
                rejections.append({'operation': None, 'reason': 'unknown-declaration', 'detail': identifier})
            elif known[identifier]['hash'] != expected:
                rejections.append({'operation': None, 'reason': 'if-match-mismatch', 'detail': identifier})
        return violations, rejections, touched

    def _drop_branch(self, label):
        with self.store.connection:
            for table in ('names', 'module_meta', 'edges'):
                self.store.connection.execute(f'DELETE FROM {table} WHERE branch = ?', (label,))

    def _promote(self, label):
        """Replace the working branch with a validated candidate in one transaction."""
        with self.store.connection:
            for table in ('names', 'module_meta', 'edges'):
                self.store.connection.execute(f'DELETE FROM {table} WHERE branch = ?', (self.branch,))
                self.store.connection.execute(f'UPDATE {table} SET branch = ? WHERE branch = ?',
                                              (self.branch, label))

    def _apply(self, label, ops):
        """Apply one batch to a candidate branch; the raised message classifies the rejection."""
        applied, modules = [], set()
        for position, operation in enumerate(ops):
            kind = operation['op']
            if kind == 'replace':
                module = operation['id'].split('::')[0]
                hash_value = self.store.replace(label, operation['id'], operation['source'],
                                                self.store.declaration(label, operation['id'])['hash'],
                                                compiler=self.compiler)
                applied.append({'operation': position, 'op': kind, 'id': operation['id'], 'hash': hash_value})
            elif kind == 'add':
                module = operation['module']
                before = {row['name'] for row in self.store.list_branch(label, module)}
                hash_value = self.store.add(label, module, operation['source'], compiler=self.compiler,
                                            after=operation.get('after'),
                                            exported=bool(operation.get('exported', False)))
                name = ({row['name'] for row in self.store.list_branch(label, module)} - before).pop()
                applied.append({'operation': position, 'op': kind, 'id': module + '::' + name,
                                'hash': hash_value})
            else:
                module = operation['id'].split('::')[0]
                self.store.remove(label, operation['id'], self.store.declaration(label, operation['id'])['hash'])
                applied.append({'operation': position, 'op': kind, 'id': operation['id'], 'hash': None})
            modules.add(module)
        return applied, sorted(modules)

    def batch(self, ops, if_match=None):
        """One transactional edit: reject wholly, or commit on parse and report the check delta."""
        if_match = {} if if_match is None else if_match
        arguments = {'ops': ops, 'if_match': if_match}
        violations, rejections, touched = self._validate_ops(ops, if_match)
        if rejections:
            return self._reject(arguments, violations, rejections)
        before_rows = {row['id']: row for row in self.store.list_branch(self.branch)}
        before_diagnostics = self.previous_diagnostics()
        index = self._index()
        _, reverse = self._relations(index)
        affected_source = 'index-project' if index is not None else 'imported index edges'
        label = self.branch + '~candidate'
        self._drop_branch(label)
        candidate = self.session_dir / 'candidates' / f'{self.records:06}'
        shutil.rmtree(candidate, ignore_errors=True)
        try:
            self.store.create_branch(self.branch, label)
            applied, modules = self._apply(label, ops)
            report = self.store.render_branch(label, candidate, compiler=self.compiler)
            for module in modules:
                path = candidate / self.store.module_meta(label, module)['path']
                listing = self.compiler.declarations(path.read_bytes())
                expected = [row['name'] for row in self.store.list_branch(label, module)]
                if [row['name'] for row in listing['declarations']] != expected:
                    raise ValueError('candidate module listing does not match the branch: ' + module)
        except (OSError, ValueError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
            self._drop_branch(label)
            shutil.rmtree(candidate, ignore_errors=True)
            return self._reject(arguments, violations,
                                [{'operation': None, 'reason': self._reason(str(error)),
                                  'detail': self._detail(str(error), ops)}])
        self._promote(label)
        index_number = len(list((self.session_dir / 'snapshots').glob('[0-9]' * 3)))
        directory = self.session_dir / 'snapshots' / f'{index_number:03}'
        shutil.move(str(candidate), str(directory))
        self._snapshot = self._describe(directory, self.branch_digest(), index_number, report)
        self._index_cache, self._declarations_cache, self._diagnostic_cache = {}, {}, {}
        after = self.diagnostics(self._snapshot)
        previous = {self.diagnostic_key(row): row for row in before_diagnostics}
        current = {self.diagnostic_key(row): row for row in after['diagnostics']}
        new = [current[key] for key in sorted(set(current) - set(previous), key=lambda item: tuple(map(str, item)))]
        resolved = [previous[key] for key in sorted(set(previous) - set(current), key=lambda item: tuple(map(str, item)))]
        touched_ids = sorted({row['id'] for row in applied} | set(touched))
        after_rows = {row['id']: row for row in self.store.list_branch(self.branch)}
        changes = [{'id': identifier, 'before': shape(before_rows.get(identifier)),
                    'after': shape(after_rows.get(identifier))} for identifier in touched_ids]
        affected = [{'id': item, 'kinds': sorted(kinds)}
                    for identifier in touched_ids
                    for item, kinds in sorted(reverse.get(identifier, {}).items())
                    if item in after_rows and item not in touched_ids]
        merged = {}
        for row in affected:
            merged.setdefault(row['id'], set()).update(row['kinds'])
        affected = [{'id': key, 'kinds': sorted(value)} for key, value in sorted(merged.items())]
        delta = {'new': new, 'resolved': resolved, 'unchanged_count': len(set(current) & set(previous)),
                 'diagnostics': after['diagnostics']}
        receipt = self.store.commit(self.branch, {'operation': 'batch', 'ops': ops, 'if_match': if_match,
                                                  'applied': applied}, delta)
        body = {'status': 'committed', 'passed': True, 'scope_violations': [], 'checked': after['checked'],
                'applied': applied,
                'delta': {'new': [self._diagnostic_view(row) for row in new],
                          'resolved': [self._diagnostic_view(row) for row in resolved],
                          'unchanged_count': delta['unchanged_count']},
                'signature_changes': [row for row in changes if row['before'] != row['after']],
                'affected': affected, 'affected_source': affected_source,
                'receipt': {'id': receipt['id'], 'parent_id': receipt['parent_id'],
                            'sha256': receipt['sha256'], 'utc': receipt['utc']},
                'omitted': {},
                'hints': ['the batch is committed; a failing check does not lose the edit']}
        return self._respond('batch', arguments, body,
                             keys=('affected', 'signature_changes', 'delta.new', 'delta.resolved'),
                             private={'snapshot_path': self._snapshot['path'],
                                      'inventory_sha256': self._snapshot['inventory_sha256']})

    @staticmethod
    def _diagnostic_view(row):
        return {'code': row['code'], 'severity': row['severity'], 'id': row['id'],
                'message': clip(row['message'], 512)[0],
                'notes': [{'role': note['role'], 'id': note['id'], 'message': clip(note['message'], 256)[0]}
                          for note in row.get('notes', [])][:MAX_RELATED]}

    @staticmethod
    def _header_line(text):
        """1-based line of a declaration's own header: the first non-blank, non-comment line."""
        for number, line in enumerate(str(text).splitlines(), start=1):
            stripped = line.strip()
            if stripped and not stripped.startswith('//'):
                return number
        return 1

    @classmethod
    def _detail(cls, message, ops):
        """The compiler's own diagnostic, plus the kinds and syntax reminder when it can help.

        A declaration is parsed inside a synthetic `module NAME;` line, so a diagnostic
        line of N lands on line N-1 of the participant's source. Only an E_SYNTAX at or
        before the declaration's header line means the keyword itself was not accepted;
        a syntax error deeper in a body is not a question about declaration kinds.
        """
        # The compiler names its scratch module by path; participants never see paths.
        message = SCRATCH_PATH.sub('<declaration>', message)
        detail = message[:512]
        match = SYNTAX_LOCATION.search(message)
        if cls._reason(message) != 'parse-failure' or match is None:
            return detail
        line = int(match.group(1)) - 1
        sources = [row['source'] for row in ops
                   if isinstance(row, dict) and isinstance(row.get('source'), str)]
        if any(line <= cls._header_line(text) for text in sources):
            return detail + ' ' + SYNTAX_HELP
        return detail

    @staticmethod
    def _reason(message):
        text = message.lower()
        if 'if-match' in text:
            return 'if-match-mismatch'
        if 'already exists' in text:
            return 'duplicate-declaration'
        if 'no declaration' in text or 'no such' in text:
            return 'unknown-declaration'
        return 'parse-failure'

    def _reject(self, arguments, violations, rejections):
        """The gateway's scope-violation receipt shape; the branch and receipt head are untouched."""
        head = self.store.head()
        body = {'status': 'rejected', 'passed': False, 'committed': False,
                'scope_violations': sorted(set(violations)),
                'reason': rejections[0]['reason'], 'rejections': rejections[:MAX_OPS],
                'branch_sha256': self.branch_digest(),
                'receipt': None if head is None else {'id': head['id'], 'parent_id': head['parent_id'],
                                                      'sha256': head['sha256'], 'utc': head['utc']},
                'omitted': {},
                'hints': ['the branch is unchanged; context returns the current hash for if_match']}
        return self._respond('batch', arguments, body, keys=('rejections',))

    # Execution --------------------------------------------------------------
    def probe(self, request):
        """Run the frozen adapter on the current snapshot with one request on stdin."""
        raw = canonical(request)
        if len(raw) > MAX_REQUEST_BYTES:
            raise ValueError('probe request exceeds the coordinator byte limit')
        snapshot = self.snapshot()
        result = self.adapter.run(snapshot['path'], raw)
        stdout = result.get('stdout', b'')
        stderr = result.get('stderr', b'')
        body = {'outcome': result.get('outcome'), 'returncode': result.get('returncode'),
                'request_sha256': hashlib.sha256(raw).hexdigest(), 'request_bytes': len(raw),
                'elapsed_seconds': result.get('elapsed_seconds'),
                'stdout': stdout.decode('utf-8', errors='replace') if isinstance(stdout, bytes) else str(stdout),
                'stderr': stderr.decode('utf-8', errors='replace') if isinstance(stderr, bytes) else str(stderr),
                'stdout_bytes': result.get('stdout_bytes', len(stdout)),
                'stderr_bytes': result.get('stderr_bytes', len(stderr)),
                'omitted': {}}
        return self._respond('probe', {'request_sha256': body['request_sha256']}, body,
                             private={'snapshot_path': snapshot['path']})

    def check(self):
        """The public check: the injected coordinator runner, or the standalone case file."""
        snapshot = self.snapshot()
        if self.check_runner is not None:
            report = self.check_runner(snapshot)
            if not isinstance(report, dict):
                raise ValueError('the check hook returns one JSON object')
        elif self.cases is not None:
            report = self._run_cases(snapshot)
        else:
            raise ValueError('public checking is not configured for this session')
        return self._respond('check', {}, dict(report),
                             private={'snapshot_path': snapshot['path'],
                                      'inventory_sha256': snapshot['inventory_sha256']})

    def _run_cases(self, snapshot):
        """Standalone public check: every case through the adapter, canonical output comparison."""
        results, diagnostics = [], []
        for item in self.cases:
            raw, expected = decode_case(item['case'])
            result = self.adapter.run(snapshot['path'], raw)
            stdout = result.get('stdout', b'')
            try:
                passed = (result.get('returncode') == 0
                          and canonical(json.loads(stdout.decode('utf-8'))) == canonical(expected))
            except (ValueError, UnicodeError):
                passed = False
            results.append({'name': item['name'], 'passed': passed, 'status': 'executed'})
            if not passed:
                diagnostics.append({'case': item['name'], 'returncode': result.get('returncode'),
                                    'stdout': clip(stdout.decode('utf-8', errors='replace'), 4096)[0],
                                    'stderr': clip(result.get('stderr', b'').decode('utf-8', errors='replace'),
                                                   4096)[0]})
        return {'submission': None, 'passed': all(row['passed'] for row in results) and bool(results),
                'cases': results, 'scope_violations': [], 'diagnostics': diagnostics}

    # Paging and completion --------------------------------------------------
    def output(self, record, offset, limit):
        """Page one retained response in full, including anything a budget trimmed away."""
        if (type(record) is not int or not 0 <= record < self.records or type(offset) is not int
                or offset < 0 or type(limit) is not int or not 1 <= limit <= MAX_PAGE):
            raise ValueError('output requires record, offset and limit within the session')
        raw = json.dumps(self._retained(record)['response'], ensure_ascii=False)
        budget, served = self.budgets['output'], min(limit, max(0, len(raw) - min(offset, len(raw))))
        while True:
            text = raw[offset:offset + served]
            body = {'source_record': record, 'offset': offset, 'text': text, 'total_characters': len(raw),
                    'next_offset': min(len(raw), offset + len(text)), 'omitted': {}}
            if served <= 0 or sized(body) <= budget:
                break
            served = served * 3 // 4
        body['omitted']['characters'] = max(0, len(raw) - body['next_offset'])
        return self._respond('output', {'record': record, 'offset': offset, 'limit': limit}, body)

    def finish(self, reason):
        """Render the final branch and report the receipt head; the gateway performs sealing."""
        if reason not in ('completed', 'abandoned'):
            raise ValueError('finish takes reason completed or abandoned')
        snapshot = self.snapshot()
        self.final_snapshot = snapshot
        head = self.store.verify_chain()
        body = {'reason': reason, 'branch': self.branch, 'modules': snapshot['modules'],
                'assets': snapshot['assets'], 'declarations': len(self.store.list_branch(self.branch)),
                'snapshot_sha256': snapshot['branch_sha256'],
                'inventory_sha256': snapshot['inventory_sha256'],
                'receipt': None if head is None else {'id': head['id'], 'parent_id': head['parent_id'],
                                                      'sha256': head['sha256'], 'utc': head['utc']},
                'omitted': {},
                'hints': ['sealing is the coordinator gateway`s step; nothing further is submitted here']}
        return self._respond('finish', {'reason': reason}, body,
                             private={'snapshot_path': snapshot['path'],
                                      'inventory': snapshot['inventory']})

    # Dispatch ---------------------------------------------------------------
    def dispatch(self, verb, arguments):
        """One request in, one response out; unknown verbs and bad arguments answer with an error."""
        arguments = {} if arguments is None else arguments
        try:
            if not isinstance(arguments, dict) or any(not isinstance(key, str) for key in arguments):
                raise ValueError('verb arguments are a JSON object')
            if verb not in VERBS:
                raise ValueError('unknown verb: ' + str(verb))
            unexpected = sorted(set(arguments) - ARGUMENTS[verb])
            if unexpected:
                raise ValueError('unexpected arguments for ' + verb + ': ' + ', '.join(unexpected))
            if verb == 'open':
                return self.open()
            if verb == 'context':
                return self.context(arguments.get('ids'), arguments.get('budget'))
            if verb == 'search':
                return self.search(text=arguments.get('text'), type_name=arguments.get('type'),
                                   calls=arguments.get('calls'), effect=arguments.get('effect'),
                                   limit=arguments.get('limit', MAX_HITS))
            if verb == 'asset':
                return self.asset(arguments.get('name'), arguments.get('offset', 0),
                                  arguments.get('limit', MAX_PAGE))
            if verb == 'batch':
                return self.batch(arguments.get('ops'), arguments.get('if_match'))
            if verb == 'probe':
                if set(arguments) != {'request'}:
                    raise ValueError('probe takes exactly one request')
                return self.probe(arguments['request'])
            if verb == 'check':
                return self.check()
            if verb == 'output':
                return self.output(arguments.get('record'), arguments.get('offset'), arguments.get('limit'))
            return self.finish(arguments.get('reason'))
        except (OSError, ValueError, TypeError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
            return self._respond('error', {'verb': verb, 'arguments': arguments},
                                 {'error': clip(str(error), 1024)[0], 'requested_verb': verb,
                                  'verbs': list(VERBS)})


def serve(session, stream, out):
    """One JSON request per line in, one JSON response per line out; a malformed line is fatal."""
    for line in stream:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            return 2
        if (not isinstance(request, dict) or not isinstance(request.get('verb'), str)
                or not isinstance(request.get('arguments', {}), dict)
                or set(request) - {'verb', 'arguments'}):
            return 2
        response = session.dispatch(request['verb'], request.get('arguments', {}))
        out.write(json.dumps(response, ensure_ascii=False, allow_nan=False) + '\n')
        out.flush()
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--session-dir', type=Path, required=True)
    parser.add_argument('--asset-root', default=DEFAULT_ASSET_ROOT)
    parser.add_argument('--protected-module', action='append', default=None)
    parser.add_argument('--cases', type=Path, help='public case file for standalone check')
    parser.add_argument('--adapter', nargs=argparse.REMAINDER, required=True,
                        help='adapter argv template; {work} is the rendered snapshot')
    arguments = parser.parse_args(argv)
    try:
        cases = None if arguments.cases is None else json.loads(arguments.cases.read_text())
        session = StoreSession(arguments.db, arguments.branch, arguments.compiler, arguments.adapter,
                               arguments.session_dir, asset_root=arguments.asset_root, cases=cases,
                               protected_modules=arguments.protected_module or PROTECTED_MODULES)
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(json.dumps({'version': VERSION, 'error': str(error)[:2048]}), file=sys.stderr)
        return 2
    try:
        return serve(session, sys.stdin, sys.stdout)
    finally:
        session.close()


if __name__ == '__main__':
    sys.exit(main())
