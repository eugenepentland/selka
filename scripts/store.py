#!/usr/bin/env python3
"""Content-addressed declaration store: import a project tree, render it back, chain receipts."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

SCHEMA_VERSION = 'declaration-store-v1'
MODULE_VERSION = 'declaration-store-module-v1'
RECEIPT_VERSION = 'declaration-store-receipt-v1'
SNAPSHOT_VERSION = 'declaration-store-snapshot-v1'
DECLARATION_VERSION = 'declaration-store-declaration-v1'
# Exactly the kinds list-declarations emits; a new top-level construct adds one.
KINDS = ('alias', 'const', 'struct', 'enum', 'union', 'result', 'domain', 'resource', 'fn', 'host_fn', 'extern_fn')
ASSET_KINDS = {'.json': 'json', '.md': 'markdown', '.txt': 'text', '.c': 'text', '.py': 'text', '.stdout': 'text'}
MAX_FILES = 5000
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_DEPTH = 32
MAX_SIGNATURE_BYTES = 512
MAX_DOC_BYTES = 8192
MAX_EDGES = 200000
MAX_COMMAND_BYTES = 64 * 1024 * 1024
COMMAND_TIMEOUT = 300


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def bounded_read(path, limit):
    """Read one regular file without following symbolic links or exceeding a byte budget."""
    if limit <= 0:
        raise ValueError('store byte budget exhausted before ' + str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
            raise ValueError('the store requires bounded regular files: ' + str(path))
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError('file grew beyond its byte budget: ' + str(path))
        return data


def read_tree(root):
    """Every regular file beneath root as bytes, keyed by POSIX relative path, under fixed bounds."""
    root = Path(root).resolve(strict=True)
    if not root.is_dir():
        raise ValueError('the store imports a directory: ' + str(root))
    files, total, visited = {}, 0, 0
    for directory, directories, names in os.walk(root, followlinks=False):
        relative = Path(directory).relative_to(root)
        if len(relative.parts) > MAX_DEPTH:
            raise ValueError('project directory depth exceeds the store budget')
        directories.sort()
        for name in directories:
            if (Path(directory) / name).is_symlink():
                raise ValueError('the store refuses symbolic-link directories: ' + name)
        for name in sorted(names):
            visited += 1
            if visited > MAX_FILES:
                raise ValueError('project file count exceeds the store budget')
            path = Path(directory) / name
            data = bounded_read(path, min(MAX_FILE_BYTES, MAX_TOTAL_BYTES - total))
            total += len(data)
            files[path.relative_to(root).as_posix()] = data
    return files


def identifier(word):
    return bool(word) and (word[0].isalpha() or word[0] == '_') and all(c.isalnum() or c == '_' for c in word)


def module_of_path(relative):
    """The lexical module name for a relative .my path, or None when the path cannot name one."""
    if not relative.endswith('.my'):
        return None
    parts = relative[:-3].split('/')
    return '.'.join(parts) if all(identifier(part) for part in parts) else None


def tokens(text):
    """Source tokens as (kind, text, start); mirrors the compiler lexer's trivia and literal rules."""
    result, at, size = [], 0, len(text)
    while at < size:
        character = text[at]
        if character.isspace():
            at += 1
        elif character == '#':
            newline = text.find('\n', at)
            at = size if newline < 0 else newline
        elif character == '"':
            end = at + 1
            while end < size and text[end] != '"':
                end += 2 if text[end] == '\\' else 1
            end = min(end + 1, size)
            result.append(('bytes', text[at:end], at))
            at = end
        elif character.isalpha() or character == '_':
            end = at + 1
            while end < size and (text[end].isalnum() or text[end] == '_'):
                end += 1
            result.append(('word', text[at:end], at))
            at = end
        elif character.isdigit():
            end = at + 1
            while end < size and text[end].isalnum():
                end += 1
            result.append(('number', text[at:end], at))
            at = end
        else:
            result.append(('punctuation', character, at))
            at += 1
    return result


def qualifiers(text, aliases):
    """Known import aliases written as `alias.name`; a method call or field read on a value is not one."""
    stream = tokens(text)
    found = set()
    for index in range(len(stream) - 2):
        word, dot, following = stream[index:index + 3]
        if word[0] != 'word' or word[1] not in aliases or dot[1] != '.' or following[0] != 'word':
            continue
        if index >= 1 and stream[index - 1][1] == '.':
            continue
        found.add(word[1])
    return found


def comment_lines(text):
    return sum(1 for line in text.split('\n') if line.lstrip().startswith('#'))


def leading_comment(source):
    """The attached comment block of a canonical declaration source, markers stripped."""
    lines = []
    for line in source.split('\n'):
        if not line.lstrip().startswith('#'):
            break
        lines.append(line.lstrip()[1:].strip())
    return '\n'.join(lines)[:MAX_DOC_BYTES]


def body_start(source):
    for line in source.split('\n'):
        if not line.lstrip().startswith('#'):
            return source.index(line)
    return len(source)


def head_end(text):
    """Offset of the newline that ends a declaration head, skipping continuations inside delimiters."""
    depth, at, size = 0, 0, len(text)
    while at < size:
        character = text[at]
        if character in '([{':
            depth += 1
        elif character in ')]}':
            depth -= 1
        elif character == '"':
            at += 1
            while at < size and text[at] != '"':
                at += 2 if text[at] == '\\' else 1
        elif character == '\n' and depth <= 0:
            return at
        at += 1
    return size


def signature_of(source):
    """The declaration head up to the colon that opens its suite, whitespace collapsed."""
    body = source[body_start(source):]
    head = body[:head_end(body)].rstrip()
    if head.endswith(':'):
        head = head[:-1]
    return ' '.join(head.split())[:MAX_SIGNATURE_BYTES]


def effects_of(signature):
    """Declared effect names read from the signature text; a spelling, not a checked effect set."""
    marker = signature.find('effects(')
    if marker < 0:
        return []
    close = signature.find(')', marker)
    if close < 0:
        return []
    return [part.strip() for part in signature[marker + len('effects('):close].split(',') if part.strip()]


class Compiler:
    """Read-only, bounded compiler commands over scratch files; the binary identity is pinned."""

    def __init__(self, path):
        self.path = Path(path).resolve(strict=True)
        self.sha256 = hashlib.sha256(bounded_read(self.path, 256 * 1024 * 1024)).hexdigest()
        self.directory = None

    def close(self):
        if self.directory is not None:
            shutil.rmtree(self.directory, ignore_errors=True)
            self.directory = None

    def __enter__(self):
        return self

    def __exit__(self, *details):
        self.close()

    def scratch(self, name, data):
        if self.directory is None:
            self.directory = Path(tempfile.mkdtemp(prefix='mylang-store-'))
        path = self.directory / name
        path.write_bytes(data)
        return path

    def run(self, arguments, *, cwd=None):
        result = subprocess.run([str(self.path)] + [str(item) for item in arguments], capture_output=True,
                                cwd=None if cwd is None else str(cwd), timeout=COMMAND_TIMEOUT)
        if len(result.stdout) > MAX_COMMAND_BYTES:
            raise ValueError('compiler output exceeds the store budget')
        return result

    def format_module(self, data):
        """Canonical module bytes; syntax errors fail closed with the compiler's own diagnostic."""
        result = self.run(['fmt-module', self.scratch('source.my', data)])
        if result.returncode != 0:
            raise ValueError('fmt-module rejected the module: ' + result.stderr.decode(errors='replace')[:2048])
        return result.stdout

    def declarations(self, formatted):
        result = self.run(['list-declarations', self.scratch('formatted.my', formatted)])
        if result.returncode != 0:
            raise ValueError('list-declarations rejected the module: ' + result.stderr.decode(errors='replace')[:2048])
        document = json.loads(result.stdout)
        if document.get('version') != 'declarations-v1':
            raise ValueError('unsupported declaration listing version')
        return document

    def parse(self, data):
        formatted = self.format_module(data)
        return formatted.decode('utf-8'), self.declarations(formatted)

    def project_graph_loads(self, entry):
        """True when fmt-project could load the graph, whether or not the tree is canonical."""
        # An accepted program is its own canonical text, so this only rejects bad syntax.
        return self.run(['fmt-project', entry, '--check']).returncode == 0


def split_module(formatted, document):
    """Split canonical module text into header, imports, exports, declarations and unplaceable trivia."""
    spans = []
    if document['header'] is not None:
        spans.append((document['header']['start'], document['header']['end'], 'header', None))
    for entry in document['imports']:
        spans.append((entry['bytes']['start'], entry['bytes']['end'], 'import', entry))
    for entry in document['exports']:
        spans.append((entry['bytes']['start'], entry['bytes']['end'], 'export', entry))
    for entry in document['declarations']:
        spans.append((entry['comment_start'], entry['bytes']['end'], 'declaration', entry))
    spans.sort()
    parts = {'header': None, 'imports': [], 'exports': [], 'declarations': [], 'prelude': '', 'trailing': ''}
    at = 0
    for index, (start, end, kind, entry) in enumerate(spans):
        gap = formatted[at:start]
        if gap.strip():
            if index != 0:
                raise ValueError('module comment cannot be placed by the store: ' + repr(gap[:64]))
            parts['prelude'] = gap.strip('\n')
        elif gap.strip('\n \t') != '':
            raise ValueError('canonical module text has unexpected blank space')
        at = end
        if kind == 'header':
            parts['header'] = formatted[start:end]
        elif kind == 'import':
            parts['imports'].append({'name': entry['name'], 'alias': entry['alias'], 'text': formatted[start:end]})
        elif kind == 'export':
            parts['exports'].append(entry['name'])
        else:
            parts['declarations'].append(dict(entry, source=formatted[start:end]))
    tail = formatted[at:]
    if tail.strip():
        parts['trailing'] = tail.strip('\n')
    elif tail.strip('\n \t') != '':
        raise ValueError('canonical module text has unexpected trailing space')
    return parts


def source_text(row):
    """A declaration's canonical source as text, whether it came from a listing or the database."""
    source = row['source'] if 'source' in row else row['canonical_source']
    return source if isinstance(source, str) else source.decode('utf-8')


def import_lines(meta, declarations, known=()):
    """Derived imports: every referenced alias, declared aliases preserved, sorted by module name."""
    declared = {(row['alias'] or row['name'].rsplit('.', 1)[-1]): row['name'] for row in meta['imports']}
    aliases = set(declared)
    for name in known:
        aliases.add(name.rsplit('.', 1)[-1])
    used = set()
    for row in declarations:
        used |= qualifiers(source_text(row), aliases)
    chosen = {}
    reachable = {name.rsplit('.', 1)[-1]: name for name in known}
    for alias in used:
        name = declared.get(alias) or reachable.get(alias, alias)
        if name in chosen and chosen[name] != alias:
            raise ValueError('two aliases derive the same import: ' + name)
        chosen[name] = alias
    lines = []
    for name in sorted(chosen):
        alias = chosen[name]
        lines.append(f'import {name}' if alias == name.rsplit('.', 1)[-1] else f'import {name} as {alias}')
    return lines


def export_lines(meta, declarations):
    """Exports keep their imported source order; newly exported declarations append in position order."""
    exported = [row['name'] for row in declarations if row['exported']]
    ordered = [name for name in meta['exports'] if name in exported]
    ordered += [name for name in exported if name not in ordered]
    return [f'export {name}' for name in ordered]


def render_module(meta, declarations, known=()):
    """Prelude, header, imports and exports one line each; declarations follow two blank lines apart."""
    head = []
    if meta['prelude']:
        head.append(meta['prelude'])
    if meta['header']:
        head.append(meta['header'])
    head.extend(import_lines(meta, declarations, known))
    head.extend(export_lines(meta, declarations))
    blocks = [source_text(row).rstrip('\n') for row in declarations]
    if meta['trailing']:
        blocks.append(meta['trailing'])
    if head:
        blocks.insert(0, '\n'.join(head))
    return '\n\n\n'.join(blocks) + '\n' if blocks else ''


def declaration_hash(module, entry):
    """SHA-256 over the declaration's canonical source framed by the identity it belongs to."""
    frame = f'{DECLARATION_VERSION}\n{module}\n{entry["kind"]}\n{entry["name"]}\n{int(entry["exported"])}\n'
    return hashlib.sha256(frame.encode('utf-8') + entry['canonical_source']).hexdigest()


def declaration_row(module, name, kind, exported, source):
    if kind not in KINDS:
        raise ValueError('unknown declaration kind: ' + str(kind))
    encoded = source.encode('utf-8')
    row = {'module': module, 'name': name, 'kind': kind, 'exported': bool(exported), 'canonical_source': encoded,
           'signature': signature_of(source), 'doc': leading_comment(source)}
    row['effects_json'] = json.dumps(effects_of(row['signature']), separators=(',', ':'))
    row['hash'] = declaration_hash(module, row)
    row['source_sha256'] = hashlib.sha256(encoded).hexdigest()
    return row


SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE declarations (hash TEXT PRIMARY KEY, kind TEXT NOT NULL, module TEXT NOT NULL, name TEXT NOT NULL,
    exported INTEGER NOT NULL, canonical_source BLOB NOT NULL, signature TEXT NOT NULL,
    effects_json TEXT NOT NULL, doc TEXT NOT NULL, source_sha256 TEXT NOT NULL);
CREATE TABLE names (branch TEXT NOT NULL, module TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL,
    hash TEXT NOT NULL REFERENCES declarations(hash), PRIMARY KEY (branch, module, name));
CREATE TABLE module_meta (branch TEXT NOT NULL, module TEXT NOT NULL, header_json TEXT NOT NULL,
    PRIMARY KEY (branch, module));
CREATE TABLE edges (branch TEXT NOT NULL, from_hash TEXT NOT NULL, to_id TEXT NOT NULL, kind TEXT NOT NULL,
    PRIMARY KEY (branch, from_hash, to_id, kind));
CREATE TABLE assets (name TEXT PRIMARY KEY, kind TEXT NOT NULL, bytes BLOB NOT NULL, sha256 TEXT NOT NULL);
CREATE TABLE receipts (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES receipts(id), branch TEXT NOT NULL,
    utc TEXT NOT NULL, batch_json TEXT NOT NULL, delta_json TEXT NOT NULL, snapshot_sha256 TEXT NOT NULL,
    sha256 TEXT NOT NULL);
CREATE INDEX names_by_module ON names (branch, module, position);
"""


class Store:
    """One SQLite declaration store; branches are `names` rows, history is a receipt hash chain."""

    def __init__(self, path, *, create=False, compiler=None):
        path = Path(path)
        if create and path.exists():
            raise ValueError('the store refuses to replace an existing database: ' + str(path))
        if not create and not path.exists():
            raise ValueError('no such declaration store: ' + str(path))
        self.path = path
        self.connection = sqlite3.connect(str(path), timeout=30)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute('PRAGMA foreign_keys = ON')
        if create:
            with self.connection:
                self.connection.executescript(SCHEMA)
                self.connection.executemany('INSERT INTO meta (key, value) VALUES (?, ?)', [
                    ('schema_version', SCHEMA_VERSION), ('created_utc', datetime.now(timezone.utc).isoformat()),
                    ('compiler_sha256', '' if compiler is None else compiler.sha256),
                    ('compiler_path', '' if compiler is None else str(compiler.path))])
        self.validate(compiler)

    def close(self):
        self.connection.close()

    def __enter__(self):
        return self

    def __exit__(self, *details):
        self.close()

    def validate(self, compiler=None):
        """Fail closed on anything that is not this schema version, or on a different compiler."""
        try:
            rows = dict(self.connection.execute('SELECT key, value FROM meta').fetchall())
        except sqlite3.DatabaseError as error:
            raise ValueError('not a declaration store: ' + str(self.path)) from error
        if rows.get('schema_version') != SCHEMA_VERSION:
            raise ValueError('unsupported declaration store schema: ' + str(rows.get('schema_version')))
        if compiler is not None and rows.get('compiler_sha256') not in ('', compiler.sha256):
            raise ValueError('declaration store was built by a different compiler')
        return rows

    def setting(self, key):
        row = self.connection.execute('SELECT value FROM meta WHERE key = ?', (key,)).fetchone()
        return None if row is None else row['value']

    def compiler(self, path=None):
        """The pinned compiler, from an explicit path or the one recorded at import time."""
        chosen = path or self.setting('compiler_path')
        if not chosen:
            raise ValueError('the store records no compiler; pass --compiler')
        found = Compiler(chosen)
        expected = self.setting('compiler_sha256')
        if expected and found.sha256 != expected:
            raise ValueError('compiler identity does not match the store')
        return found

    # Reads -----------------------------------------------------------------
    def branches(self):
        rows = self.connection.execute('SELECT DISTINCT branch FROM module_meta ORDER BY branch').fetchall()
        return [row['branch'] for row in rows]

    def modules(self, branch):
        rows = self.connection.execute('SELECT module FROM module_meta WHERE branch = ? ORDER BY module', (branch,))
        return [row['module'] for row in rows.fetchall()]

    def module_meta(self, branch, module):
        row = self.connection.execute('SELECT header_json FROM module_meta WHERE branch = ? AND module = ?',
                                      (branch, module)).fetchone()
        if row is None:
            raise ValueError(f'no module {module} on branch {branch}')
        meta = json.loads(row['header_json'])
        if meta.get('version') != MODULE_VERSION:
            raise ValueError('unsupported module metadata version')
        return meta

    def declaration(self, branch, qualified_id):
        """One declaration by `module::name`, with its branch position and current hash."""
        module, _, name = qualified_id.partition('::')
        row = self.connection.execute(
            'SELECT n.position, d.* FROM names n JOIN declarations d ON d.hash = n.hash '
            'WHERE n.branch = ? AND n.module = ? AND n.name = ?', (branch, module, name)).fetchone()
        if row is None:
            raise ValueError(f'no declaration {qualified_id} on branch {branch}')
        return self.row(row)

    @staticmethod
    def row(row):
        return {'id': row['module'] + '::' + row['name'], 'hash': row['hash'], 'kind': row['kind'],
                'module': row['module'], 'name': row['name'], 'exported': bool(row['exported']),
                'position': row['position'], 'canonical_source': bytes(row['canonical_source']),
                'signature': row['signature'], 'effects': json.loads(row['effects_json']), 'doc': row['doc'],
                'source_sha256': row['source_sha256']}

    def list_branch(self, branch, module=None):
        """Every declaration on a branch in module then position order."""
        query = ('SELECT n.position, d.* FROM names n JOIN declarations d ON d.hash = n.hash WHERE n.branch = ?'
                 + ('' if module is None else ' AND n.module = ?') + ' ORDER BY n.module, n.position')
        arguments = (branch,) if module is None else (branch, module)
        return [self.row(row) for row in self.connection.execute(query, arguments).fetchall()]

    def assets(self):
        rows = self.connection.execute('SELECT name, kind, sha256, length(bytes) AS size FROM assets ORDER BY name')
        return [dict(row) for row in rows.fetchall()]

    def asset(self, name):
        row = self.connection.execute('SELECT * FROM assets WHERE name = ?', (name,)).fetchone()
        if row is None:
            raise ValueError('no such asset: ' + name)
        return {'name': row['name'], 'kind': row['kind'], 'bytes': bytes(row['bytes']), 'sha256': row['sha256']}

    def snapshot(self, branch):
        """A digest over every name, position, hash, module header and asset on a branch."""
        modules = {}
        for module in self.modules(branch):
            rows = self.connection.execute(
                'SELECT name, position, hash FROM names WHERE branch = ? AND module = ? ORDER BY position',
                (branch, module)).fetchall()
            modules[module] = {'header_sha256': hashlib.sha256(
                self.connection.execute('SELECT header_json FROM module_meta WHERE branch = ? AND module = ?',
                                        (branch, module)).fetchone()['header_json'].encode()).hexdigest(),
                'names': [[row['position'], row['name'], row['hash']] for row in rows]}
        assets = {row['name']: row['sha256'] for row in self.assets()}
        return digest({'version': SNAPSHOT_VERSION, 'branch': branch, 'modules': modules, 'assets': assets})

    # Writes ----------------------------------------------------------------
    def store_declaration(self, row):
        self.connection.execute(
            'INSERT OR IGNORE INTO declarations (hash, kind, module, name, exported, canonical_source, signature, '
            'effects_json, doc, source_sha256) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (row['hash'], row['kind'], row['module'], row['name'], int(row['exported']), row['canonical_source'],
             row['signature'], row['effects_json'], row['doc'], row['source_sha256']))
        return row['hash']

    def put_module(self, branch, module, meta, rows):
        """Replace one module's metadata and names on a branch; positions are the given order."""
        self.connection.execute('INSERT OR REPLACE INTO module_meta (branch, module, header_json) VALUES (?, ?, ?)',
                                (branch, module, json.dumps(dict(meta, version=MODULE_VERSION), sort_keys=True)))
        self.connection.execute('DELETE FROM names WHERE branch = ? AND module = ?', (branch, module))
        for position, row in enumerate(rows):
            self.store_declaration(row)
            self.connection.execute('INSERT INTO names (branch, module, name, position, hash) VALUES (?, ?, ?, ?, ?)',
                                    (branch, module, row['name'], position, row['hash']))

    def put_asset(self, name, kind, data):
        sha256 = hashlib.sha256(data).hexdigest()
        row = self.connection.execute('SELECT sha256 FROM assets WHERE name = ?', (name,)).fetchone()
        if row is not None and row['sha256'] != sha256:
            raise ValueError('an asset with different bytes is already stored: ' + name)
        self.connection.execute('INSERT OR REPLACE INTO assets (name, kind, bytes, sha256) VALUES (?, ?, ?, ?)',
                                (name, kind, data, sha256))

    def create_branch(self, source, target):
        """Copy a branch's names, module metadata and edges under a new label."""
        if target in self.branches():
            raise ValueError('branch already exists: ' + target)
        if source not in self.branches():
            raise ValueError('no such branch: ' + source)
        with self.connection:
            for table, columns in (('module_meta', 'branch, module, header_json'),
                                   ('names', 'branch, module, name, position, hash'),
                                   ('edges', 'branch, from_hash, to_id, kind')):
                rest = columns.split(', ', 1)[1]
                self.connection.execute(f'INSERT INTO {table} ({columns}) SELECT ?, {rest} FROM {table} '
                                        'WHERE branch = ?', (target, source))
        return target

    def parse_declaration(self, compiler, module, source, *, exported=False):
        """Canonicalize one declaration's source on its own; exactly one declaration must result."""
        text = source if isinstance(source, str) else source.decode('utf-8')
        synthetic = f'module {module};\n{text}\n'.encode('utf-8')
        formatted, document = compiler.parse(synthetic)
        if document['imports'] or document['exports'] or len(document['declarations']) != 1:
            raise ValueError('a declaration source is exactly one top-level declaration')
        entry = document['declarations'][0]
        return declaration_row(module, entry['name'], entry['kind'], exported,
                               formatted[entry['comment_start']:entry['bytes']['end']])

    def replace(self, branch, qualified_id, source, if_match, *, compiler):
        """Replace one declaration in place; the current hash must equal if_match."""
        current = self.declaration(branch, qualified_id)
        if current['hash'] != if_match:
            raise ValueError(f'if-match rejected {qualified_id}: branch holds {current["hash"]}')
        row = self.parse_declaration(compiler, current['module'], source, exported=current['exported'])
        if row['name'] != current['name']:
            raise ValueError('replace keeps the declaration name; add and remove to rename')
        with self.connection:
            self.store_declaration(row)
            self.connection.execute('UPDATE names SET hash = ? WHERE branch = ? AND module = ? AND name = ?',
                                    (row['hash'], branch, current['module'], current['name']))
        return row['hash']

    def add(self, branch, module, source, *, compiler, after=None, exported=False):
        """Add a declaration after a named sibling, or at the end of the module."""
        rows = self.list_branch(branch, module)
        row = self.parse_declaration(compiler, module, source, exported=exported)
        if any(item['name'] == row['name'] for item in rows):
            raise ValueError(f'{module}::{row["name"]} already exists on {branch}')
        names = [item['name'] for item in rows]
        index = len(names) if after is None else names.index(after) + 1
        names.insert(index, row['name'])
        with self.connection:
            self.store_declaration(row)
            self.connection.execute('INSERT INTO names (branch, module, name, position, hash) VALUES (?, ?, ?, ?, ?)',
                                    (branch, module, row['name'], index, row['hash']))
            for position, name in enumerate(names):
                self.connection.execute('UPDATE names SET position = ? WHERE branch = ? AND module = ? AND name = ?',
                                        (position, branch, module, name))
        return row['hash']

    def remove(self, branch, qualified_id, if_match):
        """Remove one declaration and close the position gap; the current hash must equal if_match."""
        current = self.declaration(branch, qualified_id)
        if current['hash'] != if_match:
            raise ValueError(f'if-match rejected {qualified_id}: branch holds {current["hash"]}')
        with self.connection:
            self.connection.execute('DELETE FROM names WHERE branch = ? AND module = ? AND name = ?',
                                    (branch, current['module'], current['name']))
            for position, row in enumerate(self.list_branch(branch, current['module'])):
                self.connection.execute('UPDATE names SET position = ? WHERE branch = ? AND module = ? AND name = ?',
                                        (position, branch, current['module'], row['name']))
        return current['hash']

    def put_edges(self, branch, rows):
        with self.connection:
            self.connection.execute('DELETE FROM edges WHERE branch = ?', (branch,))
            self.connection.executemany('INSERT OR IGNORE INTO edges (branch, from_hash, to_id, kind) '
                                        'VALUES (?, ?, ?, ?)', [(branch,) + row for row in rows[:MAX_EDGES]])
        return min(len(rows), MAX_EDGES)

    # Receipts --------------------------------------------------------------
    def head(self):
        row = self.connection.execute('SELECT * FROM receipts ORDER BY id DESC LIMIT 1').fetchone()
        return None if row is None else dict(row)

    def commit(self, branch, batch, delta):
        """Append a receipt whose SHA-256 covers its parent, the batch, the delta and the branch snapshot."""
        parent = self.head()
        record = {'version': RECEIPT_VERSION, 'parent_sha256': None if parent is None else parent['sha256'],
                  'branch': branch, 'utc': datetime.now(timezone.utc).isoformat(), 'batch': batch, 'delta': delta,
                  'snapshot_sha256': self.snapshot(branch)}
        with self.connection:
            cursor = self.connection.execute(
                'INSERT INTO receipts (parent_id, branch, utc, batch_json, delta_json, snapshot_sha256, sha256) '
                'VALUES (?, ?, ?, ?, ?, ?, ?)',
                (None if parent is None else parent['id'], branch, record['utc'],
                 canonical(batch).decode(), canonical(delta).decode(), record['snapshot_sha256'], digest(record)))
        return dict(self.connection.execute('SELECT * FROM receipts WHERE id = ?', (cursor.lastrowid,)).fetchone())

    def verify_chain(self):
        """Recompute every receipt digest and its parent link; any break is fatal."""
        previous = None
        for row in self.connection.execute('SELECT * FROM receipts ORDER BY id').fetchall():
            expected = digest({'version': RECEIPT_VERSION, 'parent_sha256': None if previous is None else previous['sha256'],
                               'branch': row['branch'], 'utc': row['utc'], 'batch': json.loads(row['batch_json']),
                               'delta': json.loads(row['delta_json']), 'snapshot_sha256': row['snapshot_sha256']})
            if expected != row['sha256'] or (previous is None) != (row['parent_id'] is None) or (
                    previous is not None and row['parent_id'] != previous['id']):
                raise ValueError('receipt chain broken at receipt ' + str(row['id']))
            previous = row
        return None if previous is None else dict(previous)

    # Rendering -------------------------------------------------------------
    def render_branch(self, branch, directory, *, compiler):
        """Write a branch as a complete project tree and verify it with the formatter; fail closed."""
        directory = Path(directory)
        if directory.exists() and any(directory.iterdir()):
            raise ValueError('the renderer refuses a non-empty output directory: ' + str(directory))
        modules = self.modules(branch)
        if not modules:
            raise ValueError('no such branch: ' + branch)
        directory.mkdir(parents=True, exist_ok=True)
        entries, written = [], {}
        for module in modules:
            meta = self.module_meta(branch, module)
            text = render_module(meta, self.list_branch(branch, module), [m for m in modules if m != module])
            path = directory / meta['path']
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode('utf-8'))
            written[meta['path']] = text
            if meta.get('entry'):
                entries.append(meta['path'])
        for row in self.connection.execute('SELECT name, bytes FROM assets ORDER BY name').fetchall():
            path = directory / row['name']
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(bytes(row['bytes']))
        for name in sorted(written):
            result = compiler.run(['fmt-module', directory / name, '--check'])
            if result.returncode != 0:
                raise ValueError('rendered module is not canonical: ' + name)
        for entry in sorted(entries):
            result = compiler.run(['fmt-project', directory / entry, '--check'])
            if result.returncode != 0:
                raise ValueError('rendered project is not canonical from ' + entry + ': '
                                 + result.stderr.decode(errors='replace')[:2048])
        return {'modules': len(written), 'assets': len(self.assets()), 'entries': sorted(entries)}


def classify(files, compiler):
    """Split a project tree into lexical modules and assets; a stray .my file stays a verbatim asset."""
    modules, assets = {}, {}
    for name in sorted(files):
        data = files[name]
        expected = module_of_path(name)
        if expected is not None:
            try:
                formatted, document = compiler.parse(data)
            except ValueError:
                document = None
            if document is not None and document['module'] == expected:
                modules[expected] = {'path': name, 'formatted': formatted, 'document': document}
                continue
            assets[name] = 'foreign_module'
            continue
        assets[name] = ASSET_KINDS.get(Path(name).suffix, 'binary')
    return modules, assets


def index_edges(store, compiler, branch, directory, entry):
    """Reference edges from index-project, keyed by store hash; skipped unless the project checks."""
    result = compiler.run(['index-project', str(Path(directory) / entry), '--full'])
    if result.returncode != 0:
        return 0
    document = json.loads(result.stdout)
    if not document.get('checked'):
        return 0
    hashes = {row['id']: row['hash'] for row in store.list_branch(branch)}
    rows = []
    for reference in document['references']:
        source = hashes.get(reference['from'])
        if source is not None and '/local:' not in reference['to']:
            rows.append((source, reference['to'], reference['kind']))
    return store.put_edges(branch, sorted(set(rows)))


def import_directory(store, compiler, directory, branch, *, edges=True):
    """Import every module and file of a project tree into one branch and commit a receipt."""
    directory = Path(directory).resolve(strict=True)
    if branch in store.branches():
        raise ValueError('branch already exists in this store: ' + branch)
    files = read_tree(directory)
    modules, assets = classify(files, compiler)
    if not modules:
        raise ValueError('no lexical modules under ' + str(directory))
    roots = sorted(name for name in modules if '.' not in name)
    counts = {'modules': len(modules), 'assets': len(assets), 'declarations': 0, 'comment_lines': 0, 'bytes': 0}
    with store.connection:
        for module in sorted(modules):
            item = modules[module]
            parts = split_module(item['formatted'], item['document'])
            rows = [declaration_row(module, entry['name'], entry['kind'], entry['exported'], entry['source'])
                    for entry in parts['declarations']]
            meta = {'path': item['path'], 'module': module, 'header': parts['header'], 'imports': parts['imports'],
                    'exports': parts['exports'], 'prelude': parts['prelude'], 'trailing': parts['trailing'],
                    'declared_order': [row['name'] for row in parts['imports']],
                    'formatted_sha256': hashlib.sha256(item['formatted'].encode()).hexdigest(),
                    'entry': '.' not in module and compiler.project_graph_loads(directory / item['path'])}
            store.put_module(branch, module, meta, rows)
            counts['declarations'] += len(rows)
            counts['comment_lines'] += comment_lines(item['formatted'])
            counts['bytes'] += len(item['formatted'].encode())
        for name in sorted(assets):
            store.put_asset(name, assets[name], files[name])
            counts['bytes'] += len(files[name])
    counts['edges'] = 0
    if edges and roots:
        entry = modules['main']['path'] if 'main' in modules else modules[roots[0]]['path']
        try:
            counts['edges'] = index_edges(store, compiler, branch, directory, entry)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            counts['edges'] = 0  # Edges are an optional index convenience, never an import requirement.
    receipt = store.commit(branch, {'operation': 'import', 'source': str(directory), 'counts': counts},
                           {'new': counts['declarations'], 'resolved': 0, 'unchanged_count': 0})
    return dict(counts, branch=branch, receipt=receipt['id'], receipt_sha256=receipt['sha256'])


def command_import(arguments):
    with Compiler(arguments.compiler or 'zig-out/bin/mylang') as compiler:
        create = not Path(arguments.db).exists()
        with Store(arguments.db, create=create, compiler=compiler) as store:
            report = import_directory(store, compiler, arguments.directory, arguments.branch, edges=not arguments.no_edges)
    print(json.dumps(dict(report, version=SCHEMA_VERSION)))
    return 0


def command_render(arguments):
    with Store(arguments.db) as store:
        with store.compiler(arguments.compiler) as compiler:
            report = store.render_branch(arguments.branch, arguments.output, compiler=compiler)
    print(json.dumps(dict(report, version=SCHEMA_VERSION, branch=arguments.branch, output=str(arguments.output))))
    return 0


def command_receipt(arguments):
    with Store(arguments.db) as store:
        head = store.verify_chain()
    if head is None:
        print(json.dumps({'version': SCHEMA_VERSION, 'head': None}))
        return 1
    print(json.dumps({'version': SCHEMA_VERSION, 'head': {key: head[key] for key in (
        'id', 'parent_id', 'branch', 'utc', 'snapshot_sha256', 'sha256')}, 'batch': json.loads(head['batch_json'])}))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    importer = commands.add_parser('import', help='import a project tree into a new branch')
    importer.add_argument('directory', type=Path)
    importer.add_argument('--db', type=Path, required=True)
    importer.add_argument('--branch', required=True)
    importer.add_argument('--compiler', type=Path)
    importer.add_argument('--no-edges', action='store_true', help='skip the optional index-project edge pass')
    importer.set_defaults(handler=command_import)
    renderer = commands.add_parser('render', help='render a branch into an empty directory')
    renderer.add_argument('--db', type=Path, required=True)
    renderer.add_argument('--branch', required=True)
    renderer.add_argument('--output', type=Path, required=True)
    renderer.add_argument('--compiler', type=Path)
    renderer.set_defaults(handler=command_render)
    receipt = commands.add_parser('receipt', help='print and verify the receipt chain head')
    receipt.add_argument('--db', type=Path, required=True)
    receipt.set_defaults(handler=command_receipt)
    arguments = parser.parse_args(argv)
    try:
        return arguments.handler(arguments)
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(json.dumps({'version': SCHEMA_VERSION, 'error': str(error)[:2048]}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
