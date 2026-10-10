#!/usr/bin/env python3
"""Standalone seed build, fixture-token adapter and production AST projection.
Run through scripts/build-slot.sh build; this is not the repository gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PILOT = ROOT / 'selfhost/components/parser_pilot'
FIXTURES = ROOT / 'selfhost/tests/fixtures/parser_pilot'
LEXICAL_EXCLUSIONS = {
    'src/stdlib/fixtures/time_random_provider.my': {
        'sha256': 'c00a39d7b71a7c9ff0cacd4a0d2144e9a8d35562a6fdb3bb1fc52bcacbb9f3ba',
        'reason': 'historical provider fixture spells removed clock_cap/random_cap capability names; production lexer rejects E_REMOVED_SPELLING before a parser token stream exists',
    },
}


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


def wire_tree(data):
    """Readable values after the independent Zig decoder has validated a reply."""
    if data[:8] not in (b'SLKAST01', b'SLKERR01'):
        raise AssertionError('unexpected syntax wire magic')
    count, root = struct.unpack_from('<II', data, 8)
    if not 0 < count <= 262144 or root >= count:
        raise AssertionError('invalid syntax value count/root')
    position = 16
    values = []

    def integer(fmt):
        nonlocal position
        value = struct.unpack_from(fmt, data, position)[0]
        position += struct.calcsize(fmt)
        return value

    def blob():
        nonlocal position
        size = integer('<I')
        value = data[position:position + size]
        if len(value) != size:
            raise AssertionError('truncated syntax blob')
        position += size
        return value

    for index in range(count):
        kind = integer('<B')
        number = integer('<q')
        text = blob()
        refs = [integer('<I') for _ in range(integer('<I'))]
        if any(ref >= index for ref in refs):
            raise AssertionError('invalid syntax value reference')
        children = [values[ref] for ref in refs]
        names = [blob().decode('ascii') for _ in range(integer('<I'))]
        if kind == 0:
            value = None
        elif kind == 1:
            value = number
        elif kind == 2:
            value = bool(number)
        elif kind == 3:
            value = text
        elif kind == 4:
            value = ('enum', text)
        elif kind == 5:
            value = dict(zip(names, children))
        elif kind == 6:
            value = children
        elif kind == 7:
            value = ('tag', text, children[0])
        else:
            raise AssertionError('invalid syntax value kind')
        values.append(value)
    if position != len(data):
        raise AssertionError('trailing syntax bytes')
    return values[root]


def first_difference(expected, actual, path='program'):
    if type(expected) is not type(actual):
        return f'{path}: expected {expected!r}, actual {actual!r}'
    if isinstance(expected, dict):
        if expected.keys() != actual.keys():
            context = f'; guest diagnostic {actual["diagnostics"][0]!r}' if actual.get('diagnostics') else ''
            return f'{path}: expected fields {list(expected)}, actual fields {list(actual)}{context}'
        for key in expected:
            difference = first_difference(expected[key], actual[key], path + '.' + key)
            if difference:
                return difference
    elif isinstance(expected, (list, tuple)):
        if len(expected) != len(actual):
            return f'{path}: expected length {len(expected)}, actual length {len(actual)}'
        for index, (left, right) in enumerate(zip(expected, actual)):
            difference = first_difference(left, right, path + f'[{index}]')
            if difference:
                return difference
    elif expected != actual:
        return f'{path}: expected {expected!r}, actual {actual!r}'
    return None


def oracle_environment(source, module=False, trusted=False):
    env = {key: value for key, value in os.environ.items() if not key.startswith('PILOT_')}
    env['PILOT_SOURCE'] = str(source)
    env['MYLANG_LEXER_MODE'] = 'reference'
    env['MYLANG_PARSER_MODE'] = 'reference'
    if module:
        env['PILOT_MODULE'] = '1'
    if trusted:
        env['PILOT_TRUSTED'] = '1'
    return env


def corpus_sources(args):
    language = sorted((args.oracle_source_root / 'tests/lang').rglob('*.my'))
    semantics = sorted((args.oracle_source_root / 'tests/value_semantics').rglob('*.my'))
    standard = sorted((args.oracle_source_root / 'src/stdlib').rglob('*.my'))
    assert language and semantics and standard, 'all recursive corpus selections must be nonempty'
    selected = {str(source.relative_to(args.oracle_source_root)) for source in language + semantics + standard}
    assert LEXICAL_EXCLUSIONS.keys() <= selected, 'pinned lexical exclusion disappeared from the corpus'
    return language + semantics, standard


def lexical_exclusion(args, source, oracle, env):
    name = str(source.relative_to(args.oracle_source_root))
    spec = LEXICAL_EXCLUSIONS.get(name)
    if spec is None:
        return None
    assert hashlib.sha256(source.read_bytes()).hexdigest() == spec['sha256'], (name, 'lexical exclusion content changed; requalify it')
    # PILOT_TOKENS exits before parser invocation. A source that now tokenizes
    # must be promoted to parser parity instead of silently retaining exclusion.
    rejected = subprocess.run([oracle], env=dict(env, PILOT_TOKENS='1'), capture_output=True, timeout=30)
    assert rejected.returncode != 0 and not rejected.stdout and b'SourceError' in rejected.stderr, (name, 'expected native lexical rejection', rejected.stderr)
    print(f'lexical exclusion {name}: {spec["reason"]}', flush=True)
    return dict(source=name, **spec)


def oracle_roundtrip(args, oracle, work):
    """Qualify transport coverage separately from Selka parser grammar parity."""
    language, standard = corpus_sources(args)
    ast_count = 0
    diagnostics_count = 0
    lexical_count = 0
    for source in language + standard:
        env = oracle_environment(source, True, source in standard)
        if lexical_exclusion(args, source, oracle, env):
            lexical_count += 1
            continue
        expected = subprocess.run([oracle], env=env, capture_output=True, timeout=30)
        assert expected.returncode == 0, (source, 'unexpected lexical/oracle failure; no implicit exclusions', expected.stderr)
        if expected.stdout.startswith(b'SLKAST01'):
            ast_count += 1
        else:
            assert expected.stdout.startswith(b'SLKERR01'), (source, expected.stdout[:32])
            diagnostics_count += 1
        reply = work / 'roundtrip-reply'
        reply.write_bytes(expected.stdout)
        canonical = subprocess.run([oracle], env=dict(env, PILOT_REPLY=str(reply)), capture_output=True, timeout=30)
        assert canonical.returncode == 0, (source, canonical.stderr.decode())
        assert canonical.stdout == expected.stdout, (source, first_difference(wire_tree(expected.stdout), wire_tree(canonical.stdout)))
    print(f'oracle-only roundtrip: {len(language) + len(standard)} selected modules, {ast_count} AST, {diagnostics_count} diagnostics, {lexical_count} verified lexical exclusions, 0 failures, 0 skipped; no Selka parity asserted')


def full_request(oracle, source, module, trusted, work):
    env = oracle_environment(source, module, trusted)
    tokens = run([oracle], env=dict(env, PILOT_TOKENS='1')).stdout
    rows = tokens.splitlines()[1:]
    raw = source.read_bytes()
    path = str(source).encode()
    request = bytearray(b'SLKPAR01' + struct.pack('<5I', len(raw), len(rows), int(module), int(trusted), len(path)))
    request.extend(path)
    request.extend(raw)
    for row in rows:
        kind, start, end = row.split()
        tag = kind.encode()
        request.extend(struct.pack('<I', len(tag)) + tag + struct.pack('<II', int(start), int(end)))
    request_path = work / 'request'
    request_path.write_bytes(request)
    return env, request_path


def full_corpus(args, oracle, executable, work):
    """Audit the complete selected corpus; unsupported modules never count as parity."""
    language, standard = corpus_sources(args)
    counts = dict(ast=0, diagnostics=0, mismatches=0, unsupported=0, lexical_exclusions=0)
    details = []
    buckets = {}
    exclusions = []
    for source in language + standard:
        env = oracle_environment(source, True, source in standard)
        exclusion = lexical_exclusion(args, source, oracle, env)
        if exclusion:
            exclusions.append(exclusion)
            counts['lexical_exclusions'] += 1
            continue
        env, request = full_request(oracle, source, True, source in standard, work)
        expected = subprocess.run([oracle], env=env, capture_output=True, timeout=30, check=True)
        actual = subprocess.run([executable, '--request', request], capture_output=True, timeout=30)
        difference = None
        category = 'mismatches'
        bucket = 'transport'
        if actual.returncode or actual.stderr:
            difference = f'guest exit {actual.returncode}: {actual.stderr[:512]!r}'
            if b'P_UNSUPPORTED' in actual.stderr:
                category = 'unsupported'
                bucket = 'P_UNSUPPORTED'
        elif actual.stdout[:8] not in (b'SLKAST01', b'SLKERR01'):
            difference = f'invalid reply signature {actual.stdout[:32]!r}'
        else:
            reply = work / 'corpus-reply'
            reply.write_bytes(actual.stdout)
            canonical = subprocess.run([oracle], env=dict(env, PILOT_REPLY=str(reply)), capture_output=True, timeout=30)
            if canonical.returncode:
                difference = f'independent decoder rejected reply: {canonical.stderr[:512]!r}'
            else:
                tree = wire_tree(canonical.stdout)
                if tree.get('diagnostics'):
                    diagnostic = tree['diagnostics'][0]
                    bucket = diagnostic['code'].decode('ascii') + ': ' + diagnostic['message'].decode('utf-8', errors='replace')
                if actual.stdout.startswith(b'SLKERR01') and any(d['code'] == b'P_UNSUPPORTED' for d in tree['diagnostics']):
                    category = 'unsupported'
                    difference = 'guest explicitly rejected unsupported grammar'
                elif canonical.stdout != expected.stdout:
                    difference = first_difference(wire_tree(expected.stdout), tree) or 'canonical bytes differ'
                    if not tree.get('diagnostics'):
                        bucket = re.sub(r'\[\d+\]', '[*]', difference.split(':', 1)[0])
                else:
                    category = 'ast' if expected.stdout.startswith(b'SLKAST01') else 'diagnostics'
        counts[category] += 1
        if difference:
            name = str(source.relative_to(args.oracle_source_root))
            details.append(dict(source=name, category=category, bucket=bucket, difference=difference))
            group = buckets.setdefault(bucket, dict(count=0, examples=[]))
            group['count'] += 1
            if len(group['examples']) < 5:
                group['examples'].append(name)
    assert sum(counts.values()) == len(language) + len(standard)
    print(f'full corpus: {sum(counts.values())} selected modules; {counts["ast"]} exact AST, {counts["diagnostics"]} exact diagnostics, {counts["mismatches"]} mismatches, {counts["unsupported"]} unsupported, {counts["lexical_exclusions"]} verified lexical exclusions; 0 skipped', flush=True)
    for detail in details[:10]:
        print(f'{detail["category"]} {detail["source"]}: {detail["difference"]}', flush=True)
    if args.full_corpus_report:
        args.full_corpus_report.write_text(json.dumps(dict(counts=counts, buckets=buckets, failures=details, lexical_exclusions=exclusions), indent=2) + '\n')
    if counts['mismatches'] or counts['unsupported']:
        raise SystemExit('full corpus parity failed; unsupported modules do not qualify')


def full_run(args):
    fixtures = FIXTURES / 'full'
    manifest = json.loads((fixtures / 'expect.json').read_text())
    if set(manifest) != {p.name for p in fixtures.glob('*.parse')}:
        raise SystemExit('full manifest must cover every source fixture')
    if not manifest or any(spec['class'] not in ('ok', 'error') for spec in manifest.values()):
        raise SystemExit('full manifest must declare nonempty AST/diagnostic qualification')
    with tempfile.TemporaryDirectory(prefix='parser-full-') as temporary:
        work = Path(temporary)
        shutil.copytree(args.oracle_source_root / 'src', work / 'src')
        shutil.copy(PILOT / 'full_oracle.zig', work / 'full_oracle.zig')
        oracle = work / 'oracle'
        run([args.zig, 'build-exe', work / 'full_oracle.zig', '-lc', '-OReleaseSafe',
             '--cache-dir', work / 'zig-cache', '-femit-bin=' + str(oracle)])
        executable = work / 'parser'
        command = [args.seed.resolve(), 'build', PILOT / 'full_adapter.my', '-o', executable, '--no-cache']
        if args.release:
            command.extend(['--release', '--verify-facts'])
        run(command, cwd=ROOT)
        passed = 0
        ast_count = 0
        diagnostics_count = 0
        for name, spec in manifest.items():
            source = fixtures / name
            env, request_path = full_request(oracle, source, spec.get('module', False), spec.get('trusted', False), work)
            actual = subprocess.run([executable, '--request', request_path], capture_output=True, timeout=30)
            expected = subprocess.run([oracle], env=env, capture_output=True, timeout=30, check=True)
            signature = b'SLKAST01' if spec['class'] == 'ok' else b'SLKERR01'
            assert actual.returncode == 0 and not actual.stderr, (name, actual.stderr.decode())
            assert actual.stdout.startswith(signature), (name, actual.stdout[:32])
            assert expected.stdout.startswith(signature), (name, expected.stdout[:32])
            reply = work / 'reply'
            reply.write_bytes(actual.stdout)
            canonical = subprocess.run([oracle], env=dict(env, PILOT_REPLY=str(reply)), capture_output=True, timeout=30)
            assert canonical.returncode == 0, (name, canonical.stderr.decode())
            expected_tree = wire_tree(expected.stdout)
            actual_tree = wire_tree(canonical.stdout)
            if spec['class'] != 'ok':
                assert spec['code'].encode() == expected_tree['diagnostics'][0]['code'], (name, expected_tree)
            difference = first_difference(expected_tree, actual_tree)
            assert canonical.stdout == expected.stdout, (name, 'exact AST/diagnostic mismatch', difference)
            if spec['class'] == 'ok':
                ast_count += 1
            else:
                diagnostics_count += 1
            passed += 1
            print(f'passed full/{name}: exact AST/diagnostic {spec["class"]}')
        print(f'{passed} passed, 0 failed, 0 skipped; complete field AST/diagnostic comparison for declared fixtures')
        print(f'parser full: {ast_count} AST, {diagnostics_count} diagnostic, 0 unsupported, 0 transport; 0 failed, 0 skipped')
        if args.oracle_roundtrip:
            oracle_roundtrip(args, oracle, work)
        if args.full_corpus:
            full_corpus(args, oracle, executable, work)


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
    ap.add_argument('--full', action='store_true')
    ap.add_argument('--oracle-roundtrip', action='store_true', help='roundtrip tests/lang and embedded standard modules through the Zig AST value boundary; requires --full')
    ap.add_argument('--full-corpus', action='store_true', help='require exact Selka AST/diagnostic parity for tests/lang and embedded standard modules; requires --full')
    ap.add_argument('--full-corpus-report', type=Path, help='write corpus counts, failure buckets and every mismatch path; requires --full-corpus')
    ap.add_argument('--oracle-source-root', type=Path, default=ROOT)
    args = ap.parse_args()
    verified = run([args.builder.resolve(), '--root', ROOT, '--zig', shutil.which(args.zig) or args.zig, '--seed-only']).stdout.strip()
    seed = Path(verified).resolve()
    if args.seed is not None and args.seed.resolve() != seed:
        raise SystemExit('--seed differs from coordinator-verified component seed')
    args.seed = seed
    print('verified seed SHA256 ' + hashlib.sha256(seed.read_bytes()).hexdigest())
    if (args.oracle_roundtrip or args.full_corpus) and not args.full:
        raise SystemExit('--oracle-roundtrip/--full-corpus require --full')
    if args.full_corpus_report and not args.full_corpus:
        raise SystemExit('--full-corpus-report requires --full-corpus')
    if args.full:
        full_run(args)
        return
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
