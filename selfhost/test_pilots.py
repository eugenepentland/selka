#!/usr/bin/env python3
"""Gate the independent pilots through receipt verification and nonempty checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCES = {
    'lexer': 'selfhost/components/lexer_pilot/tests.my',
    'parser': 'selfhost/components/parser_pilot/tests.my',
    'probes': 'selfhost/probes/compiler/tests.my',
}
GUEST_SUMMARY = re.compile(r'^(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped$', re.M)


def require_guest(output, expected, modes=1):
    summaries = GUEST_SUMMARY.findall(output)
    if len(summaries) != modes or expected <= 0:
        raise RuntimeError('missing or empty guest qualification selection')
    for row in summaries:
        if tuple(map(int, row)) != (expected, 0, 0, 0):
            raise RuntimeError(f'guest selection differs from declared tests: {row}, expected {expected}')


def execute(command, environment, stdout_only=False):
    result = subprocess.run([str(arg) for arg in command], cwd=ROOT,
                            env=environment, capture_output=True, text=True, timeout=600)
    print(result.stdout, end='', flush=True)
    print(result.stderr, end='', file=sys.stderr, flush=True)
    if result.returncode:
        raise RuntimeError(f'qualification command exited {result.returncode}: {command}')
    return result.stdout if stdout_only else result.stdout + result.stderr


def fixture_count(lane):
    directory = ROOT / f'selfhost/tests/fixtures/{lane}_pilot'
    manifest = json.loads((directory / ('manifest.json' if lane == 'lexer' else 'expect.json')).read_text())
    count = len(manifest)
    if count == 0:
        raise RuntimeError(f'{lane} fixture selection is empty')
    return count


def require_full_parser(output, fixtures, modules):
    summaries = re.findall(r'^(\d+) passed, (\d+) failed, (\d+) skipped; complete field AST/diagnostic comparison for declared fixtures$', output, re.M)
    if fixtures <= 0 or summaries != [(str(fixtures), '0', '0')]:
        raise RuntimeError('empty/incomplete complete parser qualification')
    roundtrips = re.findall(r'^oracle-only roundtrip: (\d+) selected modules, (\d+) AST, (\d+) diagnostics, (\d+) verified lexical exclusions, (\d+) failures, (\d+) skipped;', output, re.M)
    if len(roundtrips) != 1:
        raise RuntimeError('missing complete syntax roundtrip qualification')
    count, ast, diagnostics, lexical, failed, skipped = map(int, roundtrips[0])
    # The driver pins and rechecks the one historical provider fixture rejected
    # before parsing. It remains selected but never counts as parser parity.
    if modules <= 1 or count != modules or lexical != 1 or ast + diagnostics + lexical != modules or failed or skipped:
        raise RuntimeError('empty/incomplete complete syntax roundtrip qualification')
    corpus = re.findall(r'^full corpus: (\d+) selected modules; (\d+) exact AST, (\d+) exact diagnostics, (\d+) mismatches, (\d+) unsupported, (\d+) verified lexical exclusions; (\d+) skipped$', output, re.M)
    if len(corpus) != 1:
        raise RuntimeError('missing complete parser corpus qualification')
    count, ast, diagnostics, mismatches, unsupported, lexical, skipped = map(int, corpus[0])
    if count != modules or lexical != 1 or ast + diagnostics + lexical != modules or mismatches or unsupported or skipped:
        raise RuntimeError('incomplete complete parser corpus qualification')


def require_parser_component(output, fixtures):
    rows = re.findall(r'^parser component: (\d+) fixtures \((\d+) AST, (\d+) diagnostics\), (\d+) framed exchanges, (\d+) malformed/invocation checks, (\d+) deployment checks; (\d+) failures, (\d+) skipped$', output, re.M)
    if len(rows) != 1:
        raise RuntimeError('missing installed parser qualification')
    count, ast, diagnostics, frames, malformed, deployment, failed, skipped = map(int, rows[0])
    if fixtures <= 0 or count != fixtures or ast + diagnostics != fixtures or frames < fixtures + 2 or malformed < 28 or deployment != 3 or failed or skipped:
        raise RuntimeError('incomplete installed parser qualification')
    if 'component implementation edit: changed producer artifact, unchanged host, complete selected fixture comparison passed' not in output:
        raise RuntimeError('missing parser component-only rebuild qualification')


def qualify(args):
    # Do not let user test/routing/budget flags change the selected qualification.
    # Keep component cache selection: the coordinator verifies every store used.
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith('MYLANG_') or key == 'MYLANG_COMPONENT_CACHE'}
    environment['MYLANG_ZIG'] = args.zig
    environment['MYLANG_LEXER_MODE'] = 'reference'
    environment['MYLANG_COMPONENT_DIR'] = str(args.component_dir)
    environment['MYL_CORE_LEAKCHECK'] = '1'
    provision = execute([args.builder, '--root', ROOT, '--zig', args.zig, '--seed-only'], environment, stdout_only=True)
    lines = provision.strip().splitlines()
    if len(lines) != 1 or not Path(lines[0]).is_file():
        raise RuntimeError('coordinator did not return one qualified seed executable')
    seed = Path(lines[0])
    print('pilot qualified seed SHA256:', hashlib.sha256(seed.read_bytes()).hexdigest(), flush=True)
    source = ROOT / SOURCES[args.lane]
    roots = [(path, len(re.findall(r'^public func test_[A-Za-z0-9_]+\(', path.read_text(), re.M)))
             for path in sorted(source.parent.glob('*.my'))]
    roots = [(path, count) for path, count in roots if count > 0]
    expected = sum(count for _, count in roots)
    if expected == 0:
        raise RuntimeError('pure pilot test selection is empty')
    if args.lane == 'probes':
        output = execute([sys.executable, ROOT / 'selfhost/tests/run_compiler_probes.py',
                          '--builder', args.builder, '--zig', args.zig], environment)
        require_guest(output, expected, modes=2)
    else:
        fixtures = fixture_count(args.lane)
        for release in (False, True):
            flags = ['--release', '--verify-facts'] if release else []
            for source, count in roots:
                # The expanded parser profile deliberately reaches a million
                # value records; retain default budgets for every other root.
                budget = (['--max-steps', '500000000', '--max-memory', '1G']
                          if args.lane == 'parser' and source.name == 'profile_tests.my' else [])
                pure = execute([seed, 'test', source, '--force', '--no-cache', *flags, *budget], environment)
                require_guest(pure, count)
            command = [sys.executable, ROOT / f'selfhost/tests/run_{args.lane}_pilot.py',
                       '--builder', args.builder, '--zig', args.zig]
            if release:
                command.append('--release')
            if args.lane == 'lexer':
                command += ['--compiler', args.compiler, '--edit-check', '--host-shadow']
            output = execute(command, environment)
            if args.lane == 'lexer':
                summaries = re.findall(r'lexer pilot: (\d+) fixtures, (\d+) token/error lines, (\d+) failures, (\d+) skipped; (\d+) transport checks passed', output)
                if len(summaries) != 1:
                    raise RuntimeError('missing lexer qualification summary')
                count, rows, failed, skipped, transport = map(int, summaries[0])
                if (count, failed, skipped) != (fixtures, 0, 0) or rows <= 0 or transport < 6:
                    raise RuntimeError('empty/incomplete lexer qualification')
            else:
                summaries = re.findall(r'^(\d+) passed, (\d+) failed, (\d+) skipped;', output, re.M)
                if len(summaries) != 1:
                    raise RuntimeError('missing parser qualification summary')
                count, failed, skipped = map(int, summaries[0])
                if count < fixtures + 10 or failed or skipped:
                    raise RuntimeError('empty/incomplete parser qualification')
                full_manifest = ROOT / 'selfhost/tests/fixtures/parser_pilot/full/expect.json'
                full_fixtures = len(json.loads(full_manifest.read_text()))
                modules = sum(len(list((ROOT / path).rglob('*.my'))) for path in ('tests/lang', 'tests/value_semantics', 'src/stdlib'))
                full_output = execute([*command, '--full', '--oracle-roundtrip', '--full-corpus'], environment)
                require_full_parser(full_output, full_fixtures, modules)
                component_command = [sys.executable, ROOT / 'selfhost/tests/run_parser_component.py',
                                     '--builder', args.builder, '--zig', args.zig,
                                     '--compiler', args.compiler, '--component-dir', args.component_dir, '--edit-check']
                if release:
                    component_command.append('--release')
                require_parser_component(execute(component_command, environment), full_fixtures)
    print(f'pilot gate {args.lane}: {expected} pure tests in each of two modes; qualification passed', flush=True)


def main():
    if not __debug__:
        raise SystemExit('pilot qualification requires Python assertions enabled')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lane', choices=SOURCES, required=True)
    parser.add_argument('--builder', type=Path, required=True)
    parser.add_argument('--zig', required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    args = parser.parse_args()
    args.builder = args.builder.resolve()
    args.compiler = args.compiler.resolve()
    args.component_dir = args.component_dir.resolve()
    qualify(args)


if __name__ == '__main__':
    main()
