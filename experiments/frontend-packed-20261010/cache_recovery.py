#!/usr/bin/env python3
"""Compare repaired CLI builds with a fresh oracle after real packed-cache damage."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

MAGIC = b'mylang-pack-v1!\n\0'
HEADER = len(MAGIC) + 32 + 8 + 32


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pack_index(path):
    data = path.read_bytes()
    assert data.startswith(MAGIC), path
    length = struct.unpack_from('<Q', data, len(MAGIC) + 32)[0]
    index = memoryview(data)[HEADER:HEADER + length]
    count = struct.unpack_from('<Q', index)[0]
    blocks = []
    position = 8
    for _ in range(count):
        offset, encoded, plain = struct.unpack_from('<QII', index, position)
        blocks.append({'offset': offset, 'encoded': encoded, 'plain': plain, 'records': []})
        position += 48
    count = struct.unpack_from('<Q', index, position)[0]
    position += 8
    for _ in range(count):
        key = bytes(index[position:position + 32]).hex()
        sequence, block, offset, length = struct.unpack_from('<QIQI', index, position + 64)
        blocks[block]['records'].append({'key': key, 'sequence': sequence, 'offset': offset, 'length': length})
        position += 88
    assert position == len(index)
    for block in blocks:
        encoded = data[block['offset']:block['offset'] + block['encoded']]
        raw = zlib.decompress(encoded[1:]) if encoded[0] == 1 else encoded[1:]
        assert len(raw) == block['plain']
        for record in block['records']:
            start = record['offset']
            assert raw[start - 96:start - 64].hex() == record['key']
    return data, blocks


def run(command, cwd, env):
    result = subprocess.run([str(item) for item in command], cwd=cwd, env=env,
                            capture_output=True, timeout=300)
    return result.returncode, result.stdout, result.stderr


def build(compiler, source, cache, env, label, output):
    code, stdout, stderr = run([compiler, 'build', 'main.my', '-o', source / 'program',
                               '--cache-dir', cache, '--report', '--optimize-debug'], source, env)
    (output / (label + '.stdout')).write_bytes(stdout)
    (output / (label + '.stderr')).write_bytes(stderr)
    assert code == 0, (label, code, stderr[-6000:].decode(errors='replace'))
    reports = [json.loads(line) for line in stderr.decode().splitlines()
               if line.startswith('{"version":"cache-report-v1"')]
    assert len(reports) == 1, (label, stderr)
    report = reports[0]
    if report['storage'] is not None:
        assert report['storage']['flush_succeeded'], label
    else:
        assert report['program'] == 'replayed', label
    execution = run([source / 'program'], source, dict(env, MYL_CORE_LEAKCHECK='1'))
    assert execution[0] == 0 and not execution[2], (label, execution)
    return {'cache_report': report, 'binary_sha256': sha(source / 'program'),
            'execution': {'status': execution[0], 'stdout_sha256': hashlib.sha256(execution[1]).hexdigest(),
                          'stdout_bytes': len(execution[1]), 'stderr_bytes': len(execution[2])}}


def damage(cache, kind):
    paths = sorted((cache / 'stages-packed-v1').glob('*.pack'))
    assert paths
    if kind == 'whole-pack-loss':
        target = max(paths, key=lambda path: path.stat().st_size)
        size = target.stat().st_size
        target.unlink()
        return {'file': target.name, 'deleted_bytes': size}
    if kind == 'index-corruption':
        target = max(paths, key=lambda path: path.stat().st_size)
        data = bytearray(target.read_bytes())
        data[HEADER] ^= 1
        target.write_bytes(data)
        return {'file': target.name, 'changed_offset': HEADER}
    changed = []
    for path in paths:
        data, blocks = pack_index(path)
        output = bytearray(data)
        for ordinal, block in enumerate(blocks):
            if not any(record['length'] > 4096 for record in block['records']):
                continue
            start, size = block['offset'], block['encoded']
            output[start:start + size] = bytes(size)
            changed.append({'file': path.name, 'block': ordinal, 'encoded_bytes': size,
                            'plain_bytes': block['plain'], 'keys': [r['key'] for r in block['records']]})
        if output != data:
            path.write_bytes(output)
    assert changed, 'fixture did not create independently encoded body blocks'
    return {'blocks': changed, 'method': 'Zero encoded body blocks; preserve pack length, index and small metadata blocks.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--require-block-fallback', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = output / 'source'
    source.mkdir()
    (source / 'mylang.json').write_text('{"version":1}\n')
    compiler = args.compiler.resolve()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env.update(MYLANG_JOBS=str(args.jobs), MYLANG_CORE_RUNTIME_CACHE=str(output / 'native'))
    # The callee lives in its own file: editing the caller cannot change its source proof.
    library = 'public func helper(out: Stream, n: int) -> int:\n'
    library += ''.join(f'    out.print(n % 100 + {index})\n' for index in range(96))
    library += '    return n + 1\n'
    (source / 'lib.my').write_text(library)
    main_text = 'import lib\n\nfunc main(out: Stream) -> int:\n    out.print(lib.helper(out, 7))\n    return 0\n'
    (source / 'main.my').write_text(main_text)
    seed = output / 'seed-cache'
    seed_build = build(compiler, source, seed, env, 'seed', output)
    packs = sorted((seed / 'stages-packed-v1').glob('*.pack'))
    assert packs and not list((seed / 'stages-packed-v1').glob('*.journal'))
    # Every damaged and oracle build sees the same source and executable paths.
    # This same-length call-argument edit also prevents whole-program replay.
    (source / 'main.my').write_text(main_text.replace('out, 7', 'out, 8'))
    oracle = build(compiler, source, output / 'fresh-cache', env, 'fresh', output)
    report = {'started_utc': datetime.now(timezone.utc).isoformat(), 'compiler': str(compiler),
              'compiler_sha256': sha(compiler), 'seed': seed_build, 'oracle': oracle,
              'method': 'One cold publication with no duplicate-isolation. Each case copies that pristine cache, damages real packs before a new CLI process, and edits only a caller argument. Binary hashes and leak-checked execution must match a separate empty-cache oracle at the same source/output paths. Whole-pack and index damage may cause early misses; fallbacks are measured, never inferred.',
              'cases': []}
    for kind in ('whole-pack-loss', 'index-corruption', 'body-block-corruption'):
        cache = output / (kind + '-cache')
        shutil.copytree(seed, cache)
        mutation = damage(cache, kind)
        repaired = build(compiler, source, cache, env, kind, output)
        assert repaired['binary_sha256'] == oracle['binary_sha256'], kind
        assert repaired['execution'] == oracle['execution'], kind
        fallbacks = repaired['cache_report']['stages']['lowering']['fallbacks']
        if kind == 'body-block-corruption' and args.require_block_fallback:
            assert fallbacks > 0, 'body-block loss was not consulted after admission'
        warm = build(compiler, source, cache, env, kind + '-warm', output)
        assert warm['binary_sha256'] == oracle['binary_sha256'], kind
        assert warm['execution'] == oracle['execution'], kind
        if warm['cache_report']['stages'] is not None:
            assert warm['cache_report']['stages']['lowering']['fallbacks'] == 0, kind
        row = {'kind': kind, 'damage': mutation, 'actual_fallbacks': fallbacks,
               'repaired': repaired, 'warm': warm}
        report['cases'].append(row)
        (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'{kind}: fallbacks={fallbacks}; binary and execution match; warm repaired', flush=True)


if __name__ == '__main__':
    main()
