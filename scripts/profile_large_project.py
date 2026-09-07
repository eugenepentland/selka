#!/usr/bin/env python3
"""Generate a deterministic multi-module check workload and measure exact versus edited reuse."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
from profile_development import measure


def generate(root, modules, functions):
    imports, calls = [], []
    for module in range(modules):
        name = f'm{module:03d}'
        imports.append(f'import {name};')
        calls.append(f'{name}::value()')
        body = [f'module {name}; export value;', 'fn base(x:i64)->i64{return x + 1;}']
        previous = 'base'
        for index in range(functions - 1):
            current = f'f{index}'
            body.append(f'fn {current}(x:i64)->i64{{return {previous}(x) + 1;}}')
            previous = current
        body.append(f'fn value()->i64{{return {previous}(0);}}')
        (root / f'{name}.my').write_text('\n'.join(body))
    (root / 'main.my').write_text('module main;\n' + '\n'.join(imports) + '\nfn main()->i64{return ' + '+'.join(calls) + ';}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--modules', type=int, default=48)
    parser.add_argument('--functions', type=int, default=24)
    parser.add_argument('--repeats', type=int, default=7)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.modules <= 128 or not 1 <= args.functions <= 64 or not 2 <= args.repeats <= 100:
        parser.error('modules must be 1..128, functions 1..64, repeats 2..100')
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-large-check-') as temporary:
        root = Path(temporary)
        generate(root, args.modules, args.functions)
        sources = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(root.glob('*.my'))}
        size = sum(path.stat().st_size for path in root.glob('*.my'))
        result = measure(compiler, root / 'main.my', root / 'm000.my', 'x + 1', 'x + 2', args.repeats)
    result.update(version='large-development-profile-v1', modules=args.modules + 1,
                  functions=args.modules * (args.functions + 1) + 1, source_bytes=size,
                  source_sha256=sources, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                  generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  scope='Synthetic scalar call chains, sequential local checks; not representative of all language features or CI.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: {name: value for name, value in result[key].items() if name != 'samples'}
                      for key in ('cold_check', 'warm_verdict', 'edited_check')}, indent=2))


if __name__ == '__main__':
    main()
