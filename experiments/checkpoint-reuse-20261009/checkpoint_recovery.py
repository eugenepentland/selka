#!/usr/bin/env python3
"""Exercise automatic CLI recovery after removing a transformed callee checkpoint."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess


MAGIC = b'mylang-stage-v1\n'
HEADER = len(MAGIC) + 64


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / 'mylang.json').write_text('{"version":1}\n')
    (root / 'leaf.my').write_text('public func leaf(n: int) -> int:\n    return n % 17\n')
    (root / 'wrapper.my').write_text('import leaf\npublic func wrapper(n: int) -> int:\n    return leaf.leaf(n) + 3\n')
    original = 'import wrapper\nfunc main() -> int:\n    return wrapper.wrapper(41) + 1\n'
    (root / 'main.my').write_text(original)
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(root / 'native'), MYLANG_JOBS='4')
    rows = []

    def build(label, cache, expected):
        binary = root / label
        command = [str(args.compiler.resolve()), 'build', 'main.my', '-o', str(binary),
                   '--cache-dir', str(root / cache), '--optimize-debug', '--report']
        run = subprocess.run(command, cwd=root, env=env, capture_output=True, timeout=180)
        (root / f'{label}.stderr').write_bytes(run.stderr)
        assert run.returncode == 0, run.stderr.decode()
        report = next(json.loads(line) for line in run.stderr.decode().splitlines()
                      if line.startswith('{"version":"cache-report-v1"'))
        execution = subprocess.run([binary], capture_output=True, timeout=10)
        assert (execution.returncode, execution.stdout, execution.stderr) == (expected, b'', b'')
        row = {'phase': label, 'cache': report, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
        rows.append(row)
        return row

    build('seed', 'cache', 11)
    removed = []
    for path in (root / 'cache').rglob('*.stage'):
        record = path.read_bytes()
        if not record.startswith(MAGIC):
            continue
        payload = record[HEADER:]
        # Transform begins with optional Wire: present byte, then Function.name's
        # u64 byte length and bytes. Final/raw records have no optional prefix.
        if len(payload) < 9 or payload[0] != 1:
            continue
        length = struct.unpack_from('<Q', payload, 1)[0]
        if not 0 < length <= 128 or 9 + length > len(payload):
            continue
        name = payload[9:9 + length]
        if b'wrapper' not in name or not all(32 <= c < 127 for c in name):
            continue
        removed.append({'path': str(path), 'function': name.decode()})
        path.unlink()
    assert removed, 'No transformed wrapper checkpoint found'
    (root / 'main.my').write_text(original.replace('+ 1', '+ 2'))
    repaired = build('repaired', 'cache', 12)
    assert repaired['cache']['stages']['lowering']['fallbacks'] == 1, repaired
    fresh = build('fresh', 'fresh-cache', 12)
    assert repaired['binary_sha256'] == fresh['binary_sha256']
    # A semantic caller edit forces another compiler invocation after repair.
    (root / 'main.my').write_text(original.replace('+ 1', '+ 3'))
    warm = build('warm', 'cache', 13)
    assert warm['cache']['stages']['lowering']['fallbacks'] == 0, warm
    fresh_again = build('fresh-again', 'fresh-cache-again', 13)
    assert warm['binary_sha256'] == fresh_again['binary_sha256']
    result = {'removed_checkpoints': removed, 'records': rows,
              'automatic_eager_repair': True, 'edited_binary_identity_and_execution': 'passed'}
    (root / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'removed': len(removed), 'fallbacks': [r['cache']['stages']['lowering']['fallbacks'] for r in rows],
                      'binary_identity_and_execution': 'passed'}))


if __name__ == '__main__':
    main()
