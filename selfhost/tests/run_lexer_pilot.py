#!/usr/bin/env python3
"""Compare immutable fixture bytes with the Zig lexer and a seed-built pilot.
Run through scripts/build-slot.sh build. No source migration is performed.
"""
import argparse
import hashlib
import json
import os
import resource
import shutil
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIX = ROOT / 'selfhost/tests/fixtures/lexer_pilot'
MAX_REPLY = 67108864


def run(command, **kw):
    return subprocess.run([str(x) for x in command], cwd=ROOT, capture_output=True,
                          timeout=60, **kw)


def component_run(command):
    # Bound both streams during execution, rather than checking after an unbounded capture.
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_REPLY, MAX_REPLY))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        p = subprocess.run([str(x) for x in command], cwd=ROOT, stdout=out,
                           stderr=err, timeout=30, preexec_fn=limits)
        out.seek(0)
        err.seek(0)
        return subprocess.CompletedProcess(command, p.returncode,
                                           out.read(MAX_REPLY), err.read(MAX_REPLY))


def oracle(compiler, path):
    p = run([compiler, 'dump-tokens', path, '--diagnostics=json'], env=dict(os.environ, MYLANG_LEXER_MODE='reference'))
    if p.returncode == 0:
        return ['{} {} {}'.format(t['kind'], t['start'], t['end'])
                for t in json.loads(p.stdout)['tokens']]
    records = [json.loads(x) for x in p.stderr.splitlines() if x.startswith(b'{')]
    record = next(x['diagnostic'] for x in records if x.get('kind') == 'diagnostic')
    loc = record['location']
    span = loc['bytes']
    return ['error {} {} {} {} {}'.format(record['code'], loc['start']['line'],
             loc['start']['column'], span['start'], span['end'])]


def validate(lines, size):
    if len(lines) == 1 and lines[0].startswith('error '):
        fields = lines[0].split()
        assert len(fields) == 6 and fields[1].startswith('E_')
        line, column, start, end = map(int, fields[2:])
        assert line >= 1 and column >= 1 and 0 <= start <= end <= size
        return
    previous = 0
    for row in lines:
        kind, start, end = row.split()
        start, end = int(start), int(end)
        assert previous <= start <= end <= size
        if kind in ('eof', 'dedent'):
            assert start == end
        previous = start
    assert lines[-1] == f'eof {size} {size}'


def main():
    if not __debug__:
        raise RuntimeError("lexer pilot checks require Python assertions (do not use -O)")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT/'zig-out/bin/mylang')
    parser.add_argument('--builder', type=Path, default=ROOT/'zig-out/tools/selka-components')
    parser.add_argument('--zig', type=Path, default=Path(os.environ.get('ZIG') or shutil.which('zig') or 'zig'))
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--host-shadow', action='store_true', help='also compare the installed verified host shadow boundary, including full diagnostics/fixes')
    parser.add_argument('--edit-check', action='store_true', help='rebuild a private algorithm edit; verify host identity stays unchanged')
    args = parser.parse_args()
    # Coordinator verifies the immutable source/toolchain/compiler receipt before reuse.
    provision = run([args.builder.resolve(), '--root', ROOT, '--zig', args.zig, '--seed-only'])
    if provision.returncode:
        raise RuntimeError(provision.stderr.decode())
    seed = Path(provision.stdout.decode().strip().splitlines()[-1])
    print('qualified seed:', seed)
    manifest = json.loads((FIX/'manifest.json').read_text())
    names = [entry['file'] for entry in manifest]
    assert len(names) == len(set(names)) and set(names) == {p.name for p in FIX.glob('*.lex')}, 'manifest must cover every fixture exactly once'
    failed = 0
    token_lines = 0
    with tempfile.TemporaryDirectory(prefix='lexer-pilot-') as directory:
        binary = Path(directory)/'lexer'
        command = [seed, 'build', ROOT/'selfhost/components/lexer_pilot/main.my',
                   '--project', '-o', binary, '--no-cache']
        if args.release:
            command += ['--release', '--verify-facts']
        build = run(command)
        if build.returncode:
            raise RuntimeError(build.stderr.decode())
        for entry in manifest:
            path = FIX/entry['file']
            original = path.read_bytes()
            assert hashlib.sha256(original).hexdigest() == entry['sha256']
            expected = oracle(args.compiler.resolve(), path)
            actual = component_run([binary, '--request', path])
            try:
                assert actual.returncode == 0, actual.stderr.decode(errors='replace')
                assert len(actual.stdout) <= MAX_REPLY
                rows = actual.stdout.decode('ascii').splitlines()
                validate(rows, len(original))
                assert rows == expected, f'expected {expected[:12]!r}, actual {rows[:12]!r}'
                if args.host_shadow:
                    command = [args.compiler.resolve(), 'dump-tokens', path, '--diagnostics=json']
                    reference = run(command, env=dict(os.environ, MYLANG_LEXER_MODE='reference'))
                    for mode in ('shadow', 'component'):
                        candidate = run(command, env=dict(os.environ, MYLANG_LEXER_MODE=mode))
                        assert (candidate.returncode, candidate.stdout, candidate.stderr) == (reference.returncode, reference.stdout, reference.stderr), candidate.stderr.decode(errors='replace')
                assert path.read_bytes() == original
                token_lines += len(rows)
            except (AssertionError, ValueError) as error:
                failed += 1
                print('FAIL', entry['file'], error)
        # Transport failures are nonzero and cannot masquerade as lexical errors.
        for request in ([], ['--request'], ['--wrong', FIX/manifest[0]['file']],
                        ['--request', Path(directory)/'absent']):
            p = component_run([binary, *request])
            assert p.returncode == 2 and not p.stdout and b'lexer transport:' in p.stderr
        over = Path(directory)/'oversize'
        over.write_bytes(b' ' * 1048577)
        p = component_run([binary, '--request', over])
        assert p.returncode == 2 and not p.stdout and b'exceeds' in p.stderr
        boundary = Path(directory)/'exact-limit'
        boundary.write_bytes(b' ' * 1048576)
        p = component_run([binary, '--request', boundary])
        assert p.returncode == 0 and p.stdout == b'eof 1048576 1048576\n'
        assert p.stdout.decode().splitlines() == oracle(args.compiler.resolve(), boundary)
        if args.edit_check:
            host_digest = hashlib.sha256(args.compiler.resolve().read_bytes()).digest()
            private = Path(directory)/'source'
            shutil.copytree(ROOT/'selfhost/components/lexer_pilot', private)
            edited_binary = Path(directory)/'edited-lexer'
            recipe = [seed, 'build', private/'main.my', '--project', '-o', edited_binary, '--no-cache']
            if args.release:
                recipe += ['--release', '--verify-facts']
            p = run(recipe)
            assert p.returncode == 0, p.stderr.decode()
            before = hashlib.sha256(edited_binary.read_bytes()).digest()
            library = private/'lexer.my'
            text = library.read_text()
            needle = '    return "ident"\n'
            assert text.count(needle) == 1
            library.write_text(text.replace(needle, '    if word == b"pilot_edit_marker":\n        return "ident"\n' + needle))
            p = run(recipe)
            assert p.returncode == 0, p.stderr.decode()
            assert hashlib.sha256(edited_binary.read_bytes()).digest() != before
            assert hashlib.sha256(args.compiler.resolve().read_bytes()).digest() == host_digest
            for entry in manifest:
                path = FIX/entry['file']
                p = component_run([edited_binary, '--request', path])
                assert p.returncode == 0 and p.stdout.decode().splitlines() == oracle(args.compiler.resolve(), path)
            print('algorithm edit rebuilt with changed artifact, unchanged host; full corpus still matches')
        if args.host_shadow:
            path = FIX/manifest[0]['file']
            for mode in ('invalid', 'unqualified'):
                p = run([args.compiler.resolve(), 'dump-tokens', path], env=dict(os.environ, MYLANG_LEXER_MODE=mode))
                assert p.returncode == 2 and not p.stdout and b'ComponentMode' in p.stderr
            print('host shadow/component: full exit/stdout/stderr parity for 79 fixtures; 2 invalid-mode checks passed')
        print(f'lexer pilot: {len(manifest)} fixtures, {token_lines} token/error lines, {failed} failures, 0 skipped; 6 transport checks passed')
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(main())
