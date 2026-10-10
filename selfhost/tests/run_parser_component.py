#!/usr/bin/env python3
"""Qualify an already installed parser component; run under build-slot.sh build.
No hidden compilation: only --edit-check explicitly builds a private producer copy.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LIMIT = 67108928


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv, env=None, timeout=35):
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (LIMIT, LIMIT))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        p = subprocess.run([str(x) for x in argv], stdout=out, stderr=err,
                           env=env, timeout=timeout, preexec_fn=limits)
        out.seek(0)
        err.seek(0)
        return p.returncode, out.read(LIMIT), err.read(LIMIT)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def installed(directory):
    manifest = json.loads((directory / 'parser-pilot.json').read_text())
    require(all(manifest.get(k) == v for k, v in
                {'format': 1, 'component': 'parser-pilot', 'protocol': 1, 'schema': 2}.items()),
            'invalid installed parser manifest identity')
    name = manifest['artifact']
    require(name not in ('', '.', '..') and '/' not in name and '\\' not in name,
            'invalid artifact basename')
    binary = directory / name
    require(digest(binary) == manifest['sha256'], 'installed parser digest mismatch')
    return binary, manifest


def copy_artifact(source, target):
    if target.exists():
        target.chmod(0o700)
    shutil.copyfile(source, target)
    target.chmod(0o700)


def request(source, rows, path=b'qualification.my', module=1, trusted=0):
    require(len(source) <= 1048576 and 0 < len(rows) <= 1048833 and len(path) <= 16384,
            'request bounds exceeded')
    payload = bytearray(b'SLKPAR01' + struct.pack('<IIIII', len(source), len(rows), module, trusted, len(path)))
    payload.extend(path)
    payload.extend(source)
    for row in rows:
        name = row['kind'].encode('ascii')
        payload.extend(struct.pack('<I', len(name)) + name + struct.pack('<II', row['start'], row['end']))
    identity = b'qualify1' + hashlib.sha256(payload).digest()
    return b'SLKPRS01' + struct.pack('<IIII', 1, 2, 0, len(payload)) + identity + payload


def reply(data, frame):
    require(80 <= len(data) <= LIMIT, 'reply bounds')
    require(data[:8] == b'SLKPRS01', 'reply magic')
    require(struct.unpack('<IIII', data[8:24]) == (1, 2, 1, len(data) - 64), 'reply envelope')
    require(data[24:64] == frame[24:64], 'reply request identity')
    require(data[64:72] in (b'SLKAST01', b'SLKERR01'), 'reply value magic')
    return data[64:]


def host(compiler, path, directory, mode, lexer='reference'):
    env = dict(os.environ, MYLANG_TYPE_INTERFACE_MODE='reference', MYLANG_PARSER_MODE=mode, MYLANG_LEXER_MODE=lexer,
               MYLANG_COMPONENT_DIR=str(directory))
    return run([compiler, 'dump-syntax', path, '--diagnostics=json'], env)


def compare(compiler, directory, fixtures):
    successes = errors = 0
    failures = []
    for path in fixtures:
        original = path.read_bytes()
        native = host(compiler, path, directory, 'reference')
        shadow = host(compiler, path, directory, 'shadow')
        if native != shadow:
            failures.append(f'{path.name}: reference={native[0]}, shadow={shadow[0]} {shadow[2][:300]!r}')
        require(native[0] in (0, 1), f'unexpected native status: {path.name}')
        if native[0] == 0:
            require(native[1].startswith(b'SLKAST01') and not native[2], 'successful host value framing')
            successes += 1
        else:
            require(not native[1] and b'"kind":"diagnostic"' in native[2], 'native diagnostic framing')
            errors += 1
        require(path.read_bytes() == original, 'fixture changed')
    require(not failures, 'host reference/shadow mismatches:\n' + '\n'.join(failures))
    return successes, errors


def transport(binary, compiler, fixtures, work):
    checked = 0
    for path in fixtures:
        token_env = dict(os.environ, MYLANG_LEXER_MODE='reference', MYLANG_TYPE_INTERFACE_MODE='reference', MYLANG_PARSER_MODE='reference')
        code, out, err = run([compiler, 'dump-tokens', path, '--diagnostics=json'], token_env)
        if code != 0:
            continue  # Host comparison covers lexical diagnostics; parser request needs tokens.
        rows = json.loads(out)['tokens']
        frame = request(path.read_bytes(), rows, os.fsencode(path))
        file = work / 'request'
        file.write_bytes(frame)
        result = run([binary, '--exchange', file])
        require(result[0] == 0 and not result[2], f'valid exchange rejected {path.name}: {result[2][:300]!r}')
        reply(result[1], frame)
        checked += 1
    require(checked > 0, 'no valid framed requests tested')
    for source, path in [(b' ' * 1048576, b'boundary.my'), (b'', b'x' * 16384)]:
        frame = request(source, [{'kind': 'eof', 'start': len(source), 'end': len(source)}], path)
        file = work / 'boundary'
        file.write_bytes(frame)
        code, out, err = run([binary, '--exchange', file])
        require(code == 0 and not err, 'exact request limit rejected')
        reply(out, frame)
        checked += 1
    empty = request(b'', [{'kind': 'eof', 'start': 0, 'end': 0}])
    cases = [b'', empty[:63], empty[:-1], empty + b'x']
    for offset, value in [(0, b'BADMAGIC'), (8, struct.pack('<I', 2)),
                          (12, struct.pack('<I', 1)), (16, struct.pack('<I', 1)),
                          (20, struct.pack('<I', 0)), (64, b'BADINNER'),
                          (72, struct.pack('<I', 1048577)), (76, struct.pack('<I', 0)),
                          (76, struct.pack('<I', 1048834)), (80, struct.pack('<I', 2)),
                          (84, struct.pack('<I', 2)), (88, struct.pack('<I', 16385))]:
        cases.append(empty[:offset] + value + empty[offset + len(value):])
    for source, rows in [
        (b'', [{'kind': 'unknown_tag', 'start': 0, 'end': 0}]),
        (b'x', [{'kind': 'eof', 'start': 0, 'end': 0}]),
        (b'x', [{'kind': 'ident', 'start': 0, 'end': 2}, {'kind': 'eof', 'start': 1, 'end': 1}]),
        (b'x', [{'kind': 'ident', 'start': 0, 'end': 0}, {'kind': 'eof', 'start': 1, 'end': 1}]),
        (b'x', [{'kind': 'eof', 'start': 0, 'end': 0}, {'kind': 'eof', 'start': 1, 'end': 1}]),
        (b'x', [{'kind': 'dedent', 'start': 0, 'end': 1}, {'kind': 'eof', 'start': 1, 'end': 1}]),
        (b'x', [{'kind': 'ident', 'start': 0, 'end': 1}]),
        (b'x', [{'kind': 'ident', 'start': 0, 'end': 1}, {'kind': 'ident', 'start': 0, 'end': 1}, {'kind': 'eof', 'start': 1, 'end': 1}]),
    ]:
        cases.append(request(source, rows))
    for index, data in enumerate(cases):
        file = work / 'malformed'
        file.write_bytes(data)
        code, out, err = run([binary, '--exchange', file])
        require(code == 2 and not out and b'P_TRANSPORT' in err,
                f'malformed exchange {index} not rejected safely: {code} {err[:200]!r}')
    for argv in ([], ['--exchange'], ['--wrong', file], ['--exchange', work / 'absent']):
        code, out, err = run([binary, *argv])
        require(code == 2 and not out and err, 'invalid invocation not rejected')
    return checked, len(cases) + 4


def self_test():
    frame = request(b'', [{'kind': 'eof', 'start': 0, 'end': 0}])
    payload = b'SLKAST01' + bytes(8)
    good = b'SLKPRS01' + struct.pack('<IIII', 1, 2, 1, len(payload)) + frame[24:64] + payload
    require(reply(good, frame) == payload, 'self-test valid frame')
    for bad in (good[:-1], b'BADMAGIC' + good[8:], good[:24] + bytes(40) + good[64:]):
        try:
            reply(bad, frame)
        except RuntimeError:
            continue
        raise RuntimeError('self-test accepted corrupt reply')
    print('parser component harness: 4 framing self-checks passed; no installed qualification asserted')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    ap.add_argument('--builder', type=Path, default=ROOT / 'zig-out/tools/selka-components')
    ap.add_argument('--component-dir', type=Path, default=ROOT / 'zig-out/libexec/mylang/components')
    ap.add_argument('--source-root', type=Path, default=ROOT)
    ap.add_argument('--zig', default=shutil.which('zig'))
    ap.add_argument('--edit-check', action='store_true')
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--self-test', action='store_true')
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    compiler = args.compiler.resolve()
    directory = args.component_dir.resolve()
    code, out, err = run([args.builder.resolve(), '--root', args.source_root.resolve(), '--zig', args.zig, '--seed-only'], timeout=180)
    require(code == 0, f'seed receipt verification failed: {err!r}')
    seed = Path(out.decode().strip().splitlines()[-1])
    binary, manifest = installed(directory)
    fixture_root = args.source_root / 'selfhost/tests/fixtures/parser_pilot/full'
    classifications = json.loads((fixture_root / 'expect.json').read_text())
    require(classifications, 'fixture selection empty')
    fixtures = [fixture_root / name for name in classifications]
    require(all(p.is_file() for p in fixtures), 'missing manifest fixture')
    host_digest = digest(compiler)
    print(f'verified seed SHA256 {digest(seed)}')
    print(f'host SHA256 {host_digest}; parser SHA256 {manifest["sha256"]}; recipe key {manifest.get("key", "unspecified")}')
    successes, errors = compare(compiler, directory, fixtures)
    with tempfile.TemporaryDirectory(prefix='parser-component-') as temporary:
        work = Path(temporary)
        exchanges, malformed = transport(binary, compiler, fixtures, work)
        # Verify fail-closed deployment before any successful syntax stdout.
        deployment = work / 'deployment'
        deployment.mkdir()
        sample = next(p for p in fixtures if host(compiler, p, directory, 'reference')[0] == 0)
        for variant in ('missing', 'manifest', 'digest'):
            if variant != 'missing':
                private = dict(manifest)
                if variant == 'manifest':
                    private['schema'] = 1
                copy_artifact(binary, deployment / manifest['artifact'])
                if variant == 'digest':
                    with (deployment / manifest['artifact']).open('ab') as file:
                        file.write(b'corruption')
                (deployment / 'parser-pilot.json').write_text(json.dumps(private))
            code, out, err = host(compiler, sample, deployment, 'shadow')
            require(code == 2 and not out and b'component comparison failed' in err, f'deployment {variant} did not fail closed')
        if args.edit_check:
            source = work / 'source'
            shutil.copytree(args.source_root / 'selfhost/components/parser_pilot', source)
            edited = work / 'edited-parser'
            command = [seed, 'build', source / 'full_adapter.my', '--project', '--no-cache', '-o', edited]
            if args.release:
                command += ['--release', '--verify-facts']
            code, out, err = run(command, timeout=180)
            require(code == 0, f'private baseline producer build failed: {err[:2000]!r}')
            before = digest(edited)
            file = source / 'full_resource.my'
            text = file.read_text()
            needle = '    mut count = 1\n'
            require(text.count(needle) == 1, 'edit branch marker ambiguous')
            file.write_text(text.replace(needle, needle + '    if tag == "pilot_edit_marker":\n        return Signature(typed=False, owner=False, arguments=0, variadic=False)\n'))
            code, out, err = run(command, timeout=180)
            require(code == 0, f'private edited producer build failed: {err[:2000]!r}')
            require(digest(edited) != before, 'implementation edit did not change artifact')
            copy_artifact(edited, deployment / manifest['artifact'])
            private = dict(manifest, sha256=digest(edited))
            (deployment / 'parser-pilot.json').write_text(json.dumps(private))
            compare(compiler, deployment, fixtures)
            require(digest(compiler) == host_digest, 'host changed during component edit')
            print('component implementation edit: changed producer artifact, unchanged host, complete selected fixture comparison passed')
    require(digest(compiler) == host_digest and digest(binary) == manifest['sha256'], 'qualification changed installed binaries')
    print(f'parser component: {len(fixtures)} fixtures ({successes} AST, {errors} diagnostics), {exchanges} framed exchanges, {malformed} malformed/invocation checks, 3 deployment checks; 0 failures, 0 skipped')


if __name__ == '__main__':
    main()
