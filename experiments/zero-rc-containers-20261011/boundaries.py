#!/usr/bin/env python3
"""Check container ownership diagnostics through the packaged compiler."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
from measure import digest, save

CASES = {
    'moved-key': ('E_SINGLE_OWNER_MOVED', '''func main() -> int:
    mut values: dict[str, int] = {}
    const key = "key-" + str(1)
    values[key] = 1
    return len(key)
'''),
    'borrowed-value': ('E_SINGLE_OWNER_BORROW', '''func main() -> int:
    const values = {1: "value-" + str(1)}
    const value = values[1]
    return len(value)
'''),
    'overlapping-dictionary': ('E_SINGLE_OWNER_OVERLAP', '''func change(left: dict[int, str], mut right: dict[int, str]) -> int:
    right[2] = "two"
    return len(left)
func main() -> int:
    mut values = {1: "one"}
    return change(values, mut values)
'''),
    'escaped-pattern': ('E_SINGLE_OWNER_OVERLAP', '''enum Value:
    text(value: str)
func escape(owner: Value) -> str:
    match owner:
        case Value.text(value=text):
            return text
func main() -> int:
    return len(escape(Value.text(value="text")))
'''),
    'duplicate-recursive-child': ('E_SINGLE_OWNER_MOVED', '''enum Tree:
    leaf(value: str)
    pair(left: Tree, right: Tree)
func main() -> int:
    const child = Tree.leaf(value="one-" + str(1))
    const tree = Tree.pair(left=child, right=child)
    const trees = [tree]
    return len(trees)
'''),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'zig', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    result = {'compiler_sha256': digest(args.compiler), 'harness_sha256': digest(__file__), 'refusals': {}}
    for name, (code, source) in CASES.items():
        path = args.output / (name + '.my')
        path.write_text(source)
        ran = subprocess.run([str(args.compiler), 'build', str(path), '--experimental-zero-rc',
                              '--cache-dir', str(args.output / 'cache'), '-o', str(args.output / name)],
                             cwd=ROOT, env=env, capture_output=True, timeout=120)
        stderr = ran.stderr.decode()
        assert ran.returncode != 0 and f'error[{code}]' in stderr, (name, ran.returncode, stderr)
        assert not (args.output / name).exists()
        result['refusals'][name] = {'status': ran.returncode, 'stderr': stderr, 'source_sha256': digest(path)}
    assert digest(args.compiler) == result['compiler_sha256']
    save(HERE / 'boundaries.json', result)
    print(f"{len(result['refusals'])} container lifetime refusals passed")


if __name__ == '__main__':
    main()
