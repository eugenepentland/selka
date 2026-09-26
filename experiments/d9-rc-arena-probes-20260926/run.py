#!/usr/bin/env python3
"""Run RC arena boundaries, escaped graphs, receivers and real trap cleanup."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def driver(workspace, name, selections):
    imports, calls, hashes = [], [], {}
    for source, selected in selections:
        text = source.read_text()
        module = re.search(r'^module (\w+)', text).group(1)
        (workspace / (module + '.my')).write_text(text)
        imports.append('import ' + module)
        cases = selected or re.findall(r'public def (test_\w+)\(', text)
        calls.extend(module + '.' + case for case in cases)
        hashes[str(source.relative_to(ROOT))] = sha(source)
    text = 'module ' + name + '\n' + '\n'.join(imports) + '\n\ndef main() -> int:\n'
    text += ''.join('    assert ' + case + '()\n' for case in calls) + '    return 0\n'
    path = workspace / (name + '.my')
    path.write_text(text)
    return path, calls, hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', choices=('qbe', 'llvm'), required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    compiler = args.compiler.resolve()
    arenas = [(ROOT / 'tests/lang' / (name + '.my'), None) for name in
              ('rc_arena_values', 'arena_managed', 'arena_scopes', 'arena_regions', 'arena_class_escape')]
    arenas += [(ROOT / 'tests/lang/option_niche.my', ['test_an_escaped_graph_keeps_its_optional_links']),
               (ROOT / 'tests/lang/text_views.my', ['test_pieces_in_arenas_read_and_escape'])]
    selected = [('arenas', driver(workspace, 'arena_driver', arenas)),
                ('receivers', driver(workspace, 'receiver_driver', [(ROOT / 'tests/value_semantics/nested_array_callbacks.my', None)])),
                ('trap', (HERE / 'trap.my', ['nested arena failure unwind'], {}))]
    result = {'compiler_sha256': sha(compiler), 'compiler_mode': 'Debug',
              'compiler_source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'backend': args.backend, 'guest_mode': 'ReleaseFast', 'groups': {}}
    for name, (source, cases, hashes) in selected:
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source),
                   '--backend', args.backend, '--mode', 'ReleaseFast', '--rc-runtime=stats',
                   '--cache-dir=' + str(workspace / 'cache'), '--max-memory=512M', '--run']
        done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
        counts = [json.loads(line.removeprefix('MYLANG_RC_COUNTS '))
                  for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
        row = {'cases': cases, 'source_sha256': hashes or {str(source.relative_to(ROOT)): sha(source)},
               'command': command, 'exit': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr, 'counts': counts}
        result['groups'][name] = row
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        assert done.returncode == (1 if name == 'trap' else 0), row
        assert not done.stdout and len(counts) == 1, row
        count = counts[0]
        assert count['version'] == 1 and not count['saturated'], row
        assert count['heap_allocate'] == count['retire'], row
        assert count['heap_allocate'] + count['owner_acquire'] == count['owner_release'], row
        assert count['hold_acquire'] == count['hold_release'], row
        if name == 'trap':
            assert 'R_ASSERT' in done.stderr and 'arena unwind probe' in done.stderr, row
        print(args.backend, name, len(cases), count, flush=True)


if __name__ == '__main__':
    main()
