#!/usr/bin/env python3
"""Declaration store API: if-match rejection, branches, receipt chains, bounds and invalid databases."""
import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import store  # noqa: E402  (the store lives beside the other repository scripts)

MAIN = b'''module main
import helper


# The entry keeps one comment so comment attachment is exercised.
def main() -> i64:
    return helper.twice(21)
'''
HELPER = b'''module helper



public def twice(value: i64) -> i64:
    return value + value


def unused() -> i64:
    return 0
'''


class Failures:
    def __init__(self):
        self.checked = 0
        self.failed = []

    def ok(self, condition, label):
        self.checked += 1
        if not condition:
            self.failed.append(label)

    def raises(self, label, call, marker=''):
        self.checked += 1
        try:
            call()
        except (OSError, ValueError, sqlite3.Error) as error:
            if marker and marker not in str(error):
                self.failed.append(f'{label}: wrong message {str(error)[:120]}')
            return
        self.failed.append(label + ': no rejection')


def fixture(directory):
    directory.mkdir(parents=True)
    (directory / 'main.my').write_bytes(MAIN)
    (directory / 'helper.my').write_bytes(HELPER)
    (directory / '.trial-public').mkdir()
    (directory / '.trial-public/TASK.md').write_bytes(b'# Task\n')
    (directory / '.trial-public/cases.json').write_bytes(b'{"cases":[]}\n')
    return directory


def declarations(report, compiler, work, results):
    """Import once, then exercise reads, if-match writes, branches and rendering."""
    source = fixture(work / 'source')
    database = store.Store(work / 'store.sqlite', create=True, compiler=compiler)
    report['import'] = store.import_directory(database, compiler, source, 'base', edges=False)
    results.ok(report['import']['declarations'] == 3, 'import counts three declarations')
    results.ok(report['import']['assets'] == 2, 'import counts two assets')

    twice = database.declaration('base', 'helper::twice')
    results.ok(twice['exported'] and twice['kind'] == 'fn', 'helper::twice is an exported fn')
    results.ok(twice['signature'] == 'def twice(value: i64) -> i64', 'signature is the head of the declaration')
    entry = database.declaration('base', 'main::main')
    results.ok(entry['doc'].startswith('The entry keeps'), 'leading comments become the declaration doc')
    results.ok(entry['canonical_source'].startswith(b'# The entry'), 'canonical source carries its comments')
    results.ok(len(database.list_branch('base')) == 3, 'list_branch returns every declaration')
    results.raises('unknown declaration', lambda: database.declaration('base', 'helper::missing'), 'no declaration')

    # If-match rejection leaves the branch untouched.
    body = b'def twice(value: i64) -> i64:\n    return value * 2\n'
    results.raises('replace with a stale hash', lambda: database.replace(
        'base', 'helper::twice', body, '0' * 64, compiler=compiler), 'if-match rejected')
    results.raises('remove with a stale hash', lambda: database.remove('base', 'helper::twice', '0' * 64),
                   'if-match rejected')
    results.ok(database.declaration('base', 'helper::twice')['hash'] == twice['hash'], 'rejection changed nothing')
    replaced = database.replace('base', 'helper::twice', body, twice['hash'], compiler=compiler)
    results.ok(replaced != twice['hash'], 'a matching if-match replaces the declaration')
    results.ok(database.declaration('base', 'helper::twice')['exported'], 'replace keeps the exported flag')
    results.raises('rename through replace', lambda: database.replace(
        'base', 'helper::twice', b'def thrice() -> i64:\n    return 3\n', replaced, compiler=compiler), 'keeps the')
    results.raises('two declarations in one source', lambda: database.replace(
        'base', 'helper::twice', b'def a() -> i64:\n    return 1\n\n\ndef b() -> i64:\n    return 2\n', replaced,
        compiler=compiler), 'exactly one top-level declaration')

    # Branch creation and independent edits.
    database.create_branch('base', 'work')
    results.raises('duplicate branch', lambda: database.create_branch('base', 'work'), 'already exists')
    results.raises('unknown source branch', lambda: database.create_branch('none', 'other'), 'no such branch')
    database.add('work', 'helper', b'def thrice(value: i64) -> i64:\n    return value * 3\n', compiler=compiler,
                 after='twice', exported=True)
    positions = [(row['name'], row['position']) for row in database.list_branch('work', 'helper')]
    results.ok(positions == [('twice', 0), ('thrice', 1), ('unused', 2)], 'add places a declaration after a sibling')
    results.ok([row['name'] for row in database.list_branch('base', 'helper')] == ['twice', 'unused'],
               'the source branch is unchanged by an edit on its copy')
    results.raises('duplicate name', lambda: database.add(
        'work', 'helper', b'def thrice() -> i64:\n    return 3\n', compiler=compiler), 'already exists')
    unused = database.declaration('work', 'helper::unused')
    database.remove('work', 'helper::unused', unused['hash'])
    results.ok([row['position'] for row in database.list_branch('work', 'helper')] == [0, 1],
               'remove closes the position gap')

    # Rendering both branches; the edited branch must still be canonical.
    database.render_branch('base', work / 'render-base', compiler=compiler)
    database.render_branch('work', work / 'render-work', compiler=compiler)
    rendered = (work / 'render-work/helper.my').read_text()
    results.ok(rendered.index('export twice') < rendered.index('export thrice'), 'exports keep their order')
    results.ok('def thrice' in rendered and 'def unused' not in rendered, 'the edited branch renders its edits')
    results.ok((work / 'render-base/.trial-public/cases.json').read_bytes() == b'{"cases":[]}\n',
               'assets render back to their original relative paths')
    results.raises('non-empty output', lambda: database.render_branch('base', work / 'render-base', compiler=compiler),
                   'non-empty output directory')
    results.raises('unknown branch render', lambda: database.render_branch('none', work / 'render-none',
                                                                           compiler=compiler), 'no such branch')

    # Receipts chain over the two committed states.
    first = database.head()
    second = database.commit('work', {'operation': 'test'}, {'new': 1})
    results.ok(second['parent_id'] == first['id'], 'receipts link to their parent')
    results.ok(database.verify_chain()['sha256'] == second['sha256'], 'the chain verifies to its head')
    database.connection.execute('UPDATE receipts SET branch = ? WHERE id = ?', ('tampered', second['id']))
    database.connection.commit()
    results.raises('tampered receipt', database.verify_chain, 'receipt chain broken')
    database.close()

    # A second tree may only enter an existing store under a new branch.
    reopened = store.Store(work / 'store.sqlite', compiler=compiler)
    results.raises('branch reuse', lambda: store.import_directory(reopened, compiler, source, 'base', edges=False),
                   'already exists')
    reopened.close()
    results.raises('replacing a database', lambda: store.Store(work / 'store.sqlite', create=True, compiler=compiler),
                   'existing database')
    return report


def bounds(work, results):
    """Bounded inputs: byte, file-count and symlink limits reject before anything is stored."""
    big = work / 'big'
    big.mkdir()
    (big / 'main.my').write_bytes(b'module main\n\n\ndef main() -> i64:\n    return 0\n')
    results.raises('oversized file', lambda: store.bounded_read(big / 'main.my', 4), 'bounded regular files')
    results.raises('exhausted budget', lambda: store.bounded_read(big / 'main.my', 0), 'byte budget exhausted')
    (big / 'link').symlink_to(work / 'source')
    results.raises('symbolic-link directory', lambda: store.read_tree(big), 'symbolic-link directories')
    (big / 'link').unlink()
    saved = store.MAX_FILES
    try:
        store.MAX_FILES = 0
        results.raises('file count budget', lambda: store.read_tree(big), 'file count exceeds')
    finally:
        store.MAX_FILES = saved
    results.raises('missing directory', lambda: store.read_tree(work / 'absent'), '')
    results.ok(store.module_of_path('a/b.my') == 'a.b' and store.module_of_path('a-b/c.my') is None,
               'only identifier path segments name a module')
    results.raises('unknown kind', lambda: store.declaration_row('m', 'n', 'proc', False, 'proc n;'), 'unknown declar')


def invalid(compiler, work, results):
    """Anything that is not this schema at this compiler is refused rather than half-read."""
    plain = work / 'plain.sqlite'
    plain.write_bytes(b'not a database at all\n')
    results.raises('not a database', lambda: store.Store(plain), 'not a declaration store')
    empty = work / 'empty.sqlite'
    connection = sqlite3.connect(str(empty))
    connection.execute('CREATE TABLE other (value TEXT)')
    connection.commit()
    connection.close()
    results.raises('foreign schema', lambda: store.Store(empty), 'not a declaration store')
    results.raises('missing database', lambda: store.Store(work / 'absent.sqlite'), 'no such declaration store')
    wrong = work / 'wrong.sqlite'
    database = store.Store(wrong, create=True, compiler=compiler)
    database.connection.execute('UPDATE meta SET value = ? WHERE key = ?', ('declaration-store-v0', 'schema_version'))
    database.connection.commit()
    database.close()
    results.raises('unsupported version', lambda: store.Store(wrong), 'unsupported declaration store schema')
    other = work / 'other.sqlite'
    database = store.Store(other, create=True, compiler=compiler)
    database.connection.execute('UPDATE meta SET value = ? WHERE key = ?', ('f' * 64, 'compiler_sha256'))
    database.connection.commit()
    database.close()
    results.raises('different compiler', lambda: store.Store(other, compiler=compiler), 'different compiler')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--work-dir', type=Path, default=ROOT / '.zig-cache/tmp/store-api')
    arguments = parser.parse_args()
    arguments.work_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(dir=arguments.work_dir, prefix='api-'))
    results = Failures()
    report = {}
    try:
        with store.Compiler(arguments.compiler) as compiler:
            declarations(report, compiler, work, results)
            bounds(work, results)
            invalid(compiler, work, results)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for label in results.failed:
        print('FAIL ' + label)
    print(f'store-api: {results.checked - len(results.failed)}/{results.checked} checks passed'
          + (' (import ' + json.dumps(report.get('import', {}).get('counts', report.get('import', {}))) + ')'
             if report else ''))
    return 1 if results.failed else 0


if __name__ == '__main__':
    sys.exit(main())
