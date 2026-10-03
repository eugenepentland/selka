#!/usr/bin/env python3
"""Compose independent Lox source lanes, refusing ambiguous conflicts."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}


def merge_json(base, tree, vm):
    original, left, right = [json.loads(p.read_text()) for p in (base, tree, vm)]
    result = dict(original)
    for variant in (left, right):
        for key, value in variant.items():
            if key in result and result[key] != value:
                raise ValueError(f'conflicting provider: {key}')
            result[key] = value
    return (json.dumps(result, indent=2) + '\n').encode()


def merge_file(base, tree, vm):
    old, left, right = [p.read_bytes() for p in (base, tree, vm)]
    if left == old or left == right:
        return right
    if right == old:
        return left
    if base.name == 'driver_cases.json':
        return merge_json(base, tree, vm)
    if base.name == 'driver_tests.my':
        if left.startswith(old) and right.startswith(old):
            return left + right[len(old):]
        raise ValueError(f'test changes are not independent appends: {base.name}')
    result = subprocess.run(['git', 'merge-file', '-p', str(tree), str(base), str(vm)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f'conflicting source: {base.name}: {result.stderr!r}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base', 'tree', 'vm', 'out'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    roots = {n: getattr(args, n).resolve() for n in ('base', 'tree', 'vm')}
    before = {n: hashes(p) for n, p in roots.items()}
    if any(set(h) != set(before['base']) for h in before.values()):
        raise ValueError('lane file sets differ')
    out = args.out.resolve()
    merged_files = {relative: merge_file(*(roots[n] / relative
                    for n in ('base', 'tree', 'vm'))) for relative in sorted(before['base'])}
    shutil.copytree(roots['base'], out)
    diff = []
    for relative in sorted(before['base']):
        paths = [roots[n] / relative for n in ('base', 'tree', 'vm')]
        merged = merged_files[relative]
        (out / relative).write_bytes(merged)
        if merged != paths[0].read_bytes():
            diff.extend(difflib.unified_diff(paths[0].read_text().splitlines(True),
                        merged.decode().splitlines(True), 'a/' + relative, 'b/' + relative))
    if before != {n: hashes(p) for n, p in roots.items()}:
        raise ValueError('lane sources changed during composition')
    out.with_suffix('.patch').write_text(''.join(diff))
    record = {'inputs': {n: str(p) for n, p in roots.items()}, 'input_hashes': before,
              'output': str(out), 'output_hashes': hashes(out),
              'patch_sha256': hashlib.sha256(out.with_suffix('.patch').read_bytes()).hexdigest()}
    out.with_suffix('.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'source': str(out), 'files': len(record['output_hashes']),
                      'changed_files': [n for n in before['base']
                                        if before['base'][n] != record['output_hashes'][n]]}))


if __name__ == '__main__':
    main()
