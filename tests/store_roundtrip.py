#!/usr/bin/env python3
"""Round trip every corpus project through the declaration store: bytes, hashes, diagnostics, counts."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import store  # noqa: E402  (the store lives beside the other repository scripts)

TRIALS = Path('/home/epentland/ai/canopy/application-trials/development-velocity-20260908/development-001')
HEADER = re.compile(r'\A(?:[ \t]*(?://[^\n]*)?\n)*[ \t]*module[ \t]+([A-Za-z_][A-Za-z0-9_.]*)[ \t]*;')
LEVELS = ('exact', 'imports-normalized', 'fully-normalized')


def module_header(path):
    """The declared module name of a file whose header may follow leading comment lines."""
    try:
        text = path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError):
        return None
    found = HEADER.match(text)
    return found.group(1) if found else None


def repository_projects():
    """Directories under examples/ and experiments/ that root a lexical module tree."""
    found = set()
    for base in ('examples', 'experiments'):
        for path in sorted((ROOT / base).rglob('*.my')):
            name = module_header(path)
            if name is None:
                continue
            root = path.parents[len(name.split('.')) - 1]
            if root.joinpath(*name.split('.')).with_suffix('.my') == path:
                found.add(root)
    return sorted(found)


def projects():
    found = [(f'trial/{path.parent.name}', path) for path in sorted(TRIALS.glob('*/my-baseline'))]
    practice = TRIALS / 'my-frozen-practice/starter'
    if practice.is_dir():
        found.append(('trial/practice-starter', practice))
    found += [(str(path.relative_to(ROOT)), path) for path in repository_projects()]
    return [(name, path) for name, path in found if path.is_dir()]


def splice_imports(formatted, document, lines):
    """The formatted original with only its import statements replaced by the derived block."""
    block = '\n'.join(lines)
    if document['imports']:
        start = document['imports'][0]['bytes']['start']
        end = document['imports'][-1]['bytes']['end']
        return formatted[:start] + block + formatted[end:] if block else formatted[:start] + formatted[end + 1:]
    if not block:
        return formatted
    at = document['header']['end'] if document['header'] else 0
    return formatted[:at] + '\n' + block + formatted[at:]


def entry_path(database, branch):
    """The project entry used for checking: main when present, else the first root module."""
    roots = sorted(name for name in database.modules(branch) if '.' not in name)
    if not roots:
        return None
    return database.module_meta(branch, 'main' if 'main' in roots else roots[0])['path']


def diagnostics(compiler, directory, entry):
    """check-project exit status and the set of code/message pairs; locations deliberately ignored."""
    result = compiler.run(['check-project', entry, '--diagnostics=json'], cwd=directory)
    found = set()
    for line in result.stderr.decode(errors='replace').split('\n'):
        if not line.strip():
            continue
        record = json.loads(line)
        if record.get('kind') == 'diagnostic':
            found.add((record['diagnostic']['code'], record['diagnostic']['message']))
    return result.returncode, found


def tree_files(directory):
    return {path.relative_to(directory).as_posix() for path in Path(directory).rglob('*') if path.is_file()}


def check_project(name, source, compiler, work, edges):
    """Import, render, re-import and compare; returns a summary row with every failure recorded."""
    row = {'project': name, 'level': None, 'failures': [], 'modules': 0, 'declarations': 0, 'assets': 0,
           'comment_lines': 0, 'diagnostics': 'skipped'}
    database = store.Store(work / 'store.sqlite', create=True, compiler=compiler)
    try:
        report = store.import_directory(database, compiler, source, 'base', edges=edges)
        row.update(modules=report['modules'], declarations=report['declarations'], assets=report['assets'],
                   comment_lines=report['comment_lines'], edges=report['edges'])
        rendered = work / 'render'
        database.render_branch('base', rendered, compiler=compiler)

        worst = 0
        for module in database.modules('base'):
            meta = database.module_meta('base', module)
            formatted, document = compiler.parse((Path(source) / meta['path']).read_bytes())
            parts = store.split_module(formatted, document)
            output = (rendered / meta['path']).read_text(encoding='utf-8')
            derived = store.import_lines(parts, parts['declarations'])
            if output == formatted:
                level = 0
            elif output == splice_imports(formatted, document, derived):
                level = 1
            elif output == store.render_module(parts, parts['declarations']):
                level = 2
            else:
                row['failures'].append(f'{meta["path"]}: rendered text differs from every normalization')
                level = 2
            worst = max(worst, level)
        row['level'] = LEVELS[worst]

        second = store.Store(work / 'again.sqlite', create=True, compiler=compiler)
        try:
            again = store.import_directory(second, compiler, rendered, 'base', edges=False)
            before = [(item['module'], item['position'], item['name'], item['hash'])
                      for item in database.list_branch('base')]
            after = [(item['module'], item['position'], item['name'], item['hash'])
                     for item in second.list_branch('base')]
            if before != after:
                row['failures'].append('re-import changed declaration names, positions or hashes')
            if {item['name']: item['sha256'] for item in database.assets()} != \
                    {item['name']: item['sha256'] for item in second.assets()}:
                row['failures'].append('re-import changed the asset set')
            for key in ('modules', 'declarations', 'assets', 'comment_lines'):
                if report[key] != again[key]:
                    row['failures'].append(f'{key} count changed on re-import: {report[key]} then {again[key]}')
        finally:
            second.close()

        if tree_files(source) != tree_files(rendered):
            row['failures'].append('the rendered tree is not a file-for-file drop-in')

        entry = entry_path(database, 'base')
        if entry is None:
            row['diagnostics'] = 'no-entry'
        else:
            original_status, original_set = diagnostics(compiler, source, entry)
            rendered_status, rendered_set = diagnostics(compiler, rendered, entry)
            row['diagnostics'] = 'exit=%d/%d codes=%d' % (original_status, rendered_status, len(original_set))
            if original_status != rendered_status:
                row['failures'].append(f'check-project exit differs: {original_status} then {rendered_status}')
            if original_set != rendered_set:
                row['failures'].append('check-project diagnostics differ: '
                                       + str(sorted(original_set ^ rendered_set))[:400])
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        row['failures'].append(type(error).__name__ + ': ' + str(error)[:400])
    finally:
        database.close()
    return row


def run(name, source, compiler_path, work_root, edges):
    work = Path(tempfile.mkdtemp(dir=work_root, prefix='project-'))
    with store.Compiler(compiler_path) as compiler:
        try:
            return check_project(name, source, compiler, work, edges)
        finally:
            shutil.rmtree(work, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--filter', default='', help='only projects whose label contains this text')
    parser.add_argument('--limit', type=int, default=0)
    parser.add_argument('--jobs', type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument('--no-edges', action='store_true', help='skip the optional index-project edge pass')
    parser.add_argument('--work-dir', type=Path, default=ROOT / '.zig-cache/tmp/store-roundtrip')
    arguments = parser.parse_args()
    compiler_path = str(Path(arguments.compiler).resolve(strict=True))
    selected = [item for item in projects() if arguments.filter in item[0]]
    if arguments.limit:
        selected = selected[:arguments.limit]
    if not selected:
        print('store-roundtrip: no projects selected')
        return 1
    arguments.work_dir.mkdir(parents=True, exist_ok=True)
    work_root = Path(tempfile.mkdtemp(dir=arguments.work_dir, prefix='run-'))
    try:
        with ThreadPoolExecutor(max_workers=max(1, arguments.jobs)) as pool:
            rows = list(pool.map(lambda item: run(item[0], item[1], compiler_path, work_root, not arguments.no_edges),
                                 selected))
    finally:
        shutil.rmtree(work_root, ignore_errors=True)
    levels = {level: 0 for level in LEVELS}
    normalized, failed = [], []
    for row in sorted(rows, key=lambda item: item['project']):
        status = 'ok' if not row['failures'] else 'FAIL'
        print(f'{status:4} {row["project"]:70} modules={row["modules"]:3} declarations={row["declarations"]:4} '
              f'assets={row["assets"]:3} comments={row["comment_lines"]:4} {row["level"]} {row["diagnostics"]}')
        for failure in row['failures']:
            print('       ' + failure)
        if row['level'] is not None:
            levels[row['level']] += 1
        if row['level'] and row['level'] != 'exact':
            normalized.append(row['project'])
        if row['failures']:
            failed.append(row['project'])
    print(f'store-roundtrip: {len(rows) - len(failed)}/{len(rows)} projects passed; '
          + ', '.join(f'{level}={levels[level]}' for level in LEVELS))
    if normalized:
        print('store-roundtrip: normalization needed for ' + ', '.join(normalized))
    if failed:
        print('store-roundtrip: failed ' + ', '.join(failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
