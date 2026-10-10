#!/usr/bin/env python3
"""Standalone seed build, fixture-token adapter and production AST projection.
Run through scripts/build-slot.sh build; this is not the repository gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PILOT = ROOT / 'selfhost/components/parser_pilot'
FIXTURES = ROOT / 'selfhost/tests/fixtures/parser_pilot'


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], capture_output=True,
                            text=True, timeout=180, **kwargs)
    if result.returncode:
        raise RuntimeError(f'command failed ({result.returncode}): {command}\n{result.stdout}{result.stderr}')
    return result


def tree(text):
    """Compare reachable trees, independent of production/pilot pool allocation."""
    nodes = []
    for line in text.splitlines():
        kind, start, end, *children = line.split()
        refs = [int(x) for x in children]
        if any(x < 0 or x >= len(nodes) for x in refs):
            raise AssertionError('invalid syntax index')
        nodes.append([kind, int(start), int(end), [nodes[x] for x in refs]])
    return nodes[-1]


def main():
    if not __debug__:
        raise SystemExit('parser qualification requires Python assertions enabled')
    manifest = json.loads((FIXTURES / 'expect.json').read_text())
    if set(manifest) != {p.name for p in FIXTURES.glob('*.parse')} or {name + '.tokens' for name in manifest} != {p.name for p in FIXTURES.glob('*.tokens')}:
        raise SystemExit('manifest must cover every source/token fixture exactly once')
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--builder', type=Path, default=ROOT / 'zig-out/tools/selka-components')
    ap.add_argument('--seed', type=Path,
                    help='verified component-seed executable, obtain with selka-components --seed-only')
    ap.add_argument('--zig', default='zig')
    ap.add_argument('--release', action='store_true')
    args = ap.parse_args()
    verified = run([args.builder.resolve(), '--root', ROOT, '--zig', shutil.which(args.zig) or args.zig, '--seed-only']).stdout.strip()
    seed = Path(verified).resolve()
    if args.seed is not None and args.seed.resolve() != seed:
        raise SystemExit('--seed differs from coordinator-verified component seed')
    args.seed = seed
    print('verified seed SHA256 ' + hashlib.sha256(seed.read_bytes()).hexdigest())
    with tempfile.TemporaryDirectory(prefix='parser-pilot-') as temporary:
        work = Path(temporary)
        shutil.copytree(ROOT / 'src', work / 'src')
        shutil.copy(PILOT / 'oracle.zig', work / 'oracle.zig')
        oracle = work / 'oracle'
        build = run([args.zig, 'build-exe', work / 'oracle.zig', '-lc', '-OReleaseSafe',
                     '--cache-dir', work / 'zig-cache', '-femit-bin=' + str(oracle)])
        executable = work / 'parser'
        command = [args.seed.resolve(), 'build', PILOT / 'adapter.my', '-o', executable, '--no-cache']
        if args.release:
            command.extend(['--release', '--verify-facts'])
        run(command, cwd=ROOT)
        passed = 0
        for name, classification in manifest.items():
            source = FIXTURES / name
            env = dict(os.environ, PILOT_SOURCE=str(source))
            token_env = dict(env, PILOT_TOKENS='1')
            tokens = run([oracle], env=token_env).stdout
            # Baseline tables are immutable; regenerating does not rewrite fixtures.
            table = FIXTURES / (name + '.tokens')
            if table.read_text() != tokens:
                raise AssertionError(f'{name}: baseline token table changed')
            request = work / 'request'
            request.write_bytes(str(len(source.read_bytes())).encode() + b'\n' + source.read_bytes() + b'\n' + tokens.split('\n', 1)[1].encode())
            actual = subprocess.run([executable, '--request', request], capture_output=True,
                                    text=True, timeout=30)
            expected = run([oracle], env=env).stdout if classification in ('ok', 'error') else ''
            if classification == 'ok':
                assert actual.returncode == 0, (name, actual.stderr)
                assert tree(actual.stdout) == tree(expected), (name, tree(actual.stdout), tree(expected))
            elif classification == 'error':
                assert actual.returncode == 2 and not actual.stdout, (name, actual)
                # First production parser error, code and exact byte span.
                assert expected.splitlines()[0] == 'error ' + actual.stderr.strip(), (name, expected, actual.stderr)
            else:
                assert actual.returncode == 2 and not actual.stdout, (name, actual)
                assert actual.stderr.startswith('P_UNSUPPORTED ' if classification == 'unsupported' else 'E_EXPRESSION '), (name, actual.stderr)
            passed += 1
            print(f'passed {name}: {classification}')
        for request_text in ['0\n\nunknown 0 0\neof 0 0\n', '0\n\neof 0 0 extra\n', '0\n\neof x 0\n', '0\n\n' + 'eof 0 0\n' * 4097, '262145\n', '', '0\n\neof 0 0\neof 0 0\n', '1\ninteger 0 2\neof 1 1\n',
                             '0\neof x 0\n', '0\neof 0 0 extra\n']:
            request.write_text(request_text)
            actual = subprocess.run([executable, '--request', request], capture_output=True,
                                    text=True, timeout=30)
            assert actual.returncode == 2 and actual.stderr.strip() == 'P_TRANSPORT' and not actual.stdout, actual
            passed += 1
        print(f'{passed} passed, 0 failed, 0 skipped; structural projection (not full AST ABI parity)')


if __name__ == '__main__':
    main()
