#!/usr/bin/env python3
"""Compare QBE executable behavior with freshly checked VM execution."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=120)


def signature(result):
    if result.returncode == 0:
        return (0, result.stdout)
    codes = re.findall(rb'R_[A-Z_]+', result.stderr)
    return (result.returncode, codes[:1])


def cases():
    yield ('def fact(n: i64) -> i64:\n    if n <= 1:\n        return 1\n    return n * fact(n - 1)\n\n\n'
           'def main() -> i64:\n    return fact(10)\n')
    yield ('def add(a: i64, b: i64) -> i64:\n    return a + b\n\n\n'
           'def main() -> i64:\n    return 1 + add(add(2, 3), add(4, 5))\n')
    yield ('def main() -> i64:\n    x = 0\n    i = 0\n    while i < 30:\n        i += 1\n'
           '        if i == 4:\n            continue\n        if i == 20:\n            break\n'
           '        x += i\n    return x\n')
    yield ('def main() -> i64:\n    if False and divtrunc(1, 0) == 0:\n        return 1\n'
           '    if True or divtrunc(1, 0) == 0:\n        return 7\n    return 0\n')
    yield 'def noop() -> None:\n    return\n\n\ndef main() -> i64:\n    noop()\n    return 42\n'
    # Truncating division and remainder are spelled as calls; `/` is float division.
    for expression in ('9223372036854775807 + 1', '-9223372036854775808 - 1', '3037000500 * 3037000500',
                       'divtrunc(1, 0)', 'remtrunc(1, 0)', '-(-9223372036854775808)',
                       'divtrunc(-9223372036854775808, -1)', 'divtrunc(-7, 3)', 'remtrunc(-7, 3)'):
        yield 'def main() -> i64:\n    return ' + expression + '\n'
    for signed in (False, True):
        for width in (8, 16, 32, 64):
            ty = ('i' if signed else 'u') + str(width)
            maximum = (1 << (width - int(signed))) - 1
            minimum = -(1 << (width - 1)) if signed else 0
            for expression in (f'{maximum}{ty} + 1{ty}', f'{minimum}{ty} - 1{ty}', f'{maximum}{ty} * 2{ty}'):
                yield 'def main() -> i64:\n    _ = ' + expression + '\n    return 0\n'
            yield (f'def id(x: {ty}) -> {ty}:\n    return x\n\n\n'
                   f'def main() -> i64:\n    if id({maximum}{ty}) == {maximum}{ty}:\n        return 7\n    return 0\n')
    # Existing boundary corpus covers all widths for bitwise/wrapping/saturating operations.
    from native_integer_operations import cases as integer_extension_cases
    for text, _expected in integer_extension_cases():
        yield text
    yield 'def main() -> i64:\n    return i64(18446744073709551615u64)\n'
    yield 'def main() -> i64:\n    return i64(u8(-1))\n'


def extended_cases():
    values = ', '.join(str(i) for i in range(700))
    large = f'def build() -> [700]i64 effects():\n    return [{values}]\n\n\n'
    yield large + 'def read(value: [700]i64) -> i64:\n    return value[699]\n\n\ndef main() -> i64:\n    return read(build())\n'
    yield (large + 'def apply(callback: def() -> [700]i64 effects()) -> [700]i64:\n    return callback()\n\n\n'
           'def main() -> i64:\n    values = apply(build)\n    return values[698]\n')
    parameters = ', '.join(f'a{i}: i64' for i in range(129))
    arguments = ', '.join(str(i) for i in range(129))
    total = ' + '.join(f'a{i}' for i in range(129))
    yield f'def wide({parameters}) -> i64:\n    return {total}\n\n\ndef main() -> i64:\n    return wide({arguments})\n'
    medium = 'def build() -> [512]i64 effects():\n    return [' + ', '.join(str(i) for i in range(512)) + ']\n\n\n'
    yield (medium + 'def total(a: [512]i64, b: [512]i64) -> i64 effects():\n    return a[511] + b[510]\n\n\n'
           'def main() -> i64:\n    f = total\n    return f(build(), build())\n')
    for name in ('records', 'arrays', 'variants', 'generic-records', 'generic-arrays',
                 'generic-variants', 'callbacks', 'results', 'generic-results'):
        yield (ROOT / 'examples' / (name + '.my')).read_text()
    # Managed list aliasing, nested managed graphs and bounds traps.
    yield ('def build() -> List[i64]:\n    xs: List[i64] = []\n    i = 0\n'
           '    while i < 40:\n        xs.push(i)\n        i += 1\n    return xs\n\n\n'
           'def main() -> i64:\n    xs = build()\n    alias = xs\n    alias[2u64] = 42\n'
           '    return xs[2u64] + len(xs)\n')
    yield ('class Box:\n    row: List[i64]\n\n\n'
           'def main() -> i64:\n    a: List[i64] = []\n    a.push(42)\n    box = Box(row=a)\n'
           '    rows: List[List[i64]] = []\n    rows.push(box.row)\n    i = 0\n'
           '    while i < 20:\n        garbage: List[i64] = []\n        garbage.push(i)\n        i += 1\n'
           '    inner = rows[0u64]\n    return inner[0u64]\n')
    yield 'def main() -> i64:\n    xs: List[i64] = []\n    return xs[0u64]\n'
    yield 'def main() -> i64:\n    xs: [2]i64 = [1, 2]\n    return xs[2]\n'
    yield ('def main() -> i64:\n    if f64_div(0u64, 0u64) != 9221120237041090560u64:\n        return 1\n'
           '    if not f64_eq(0u64, 9223372036854775808u64):\n        return 2\n'
           '    return i64(f64_to_u64(f64_add(f64_from_u64(20u64), f64_from_u64(22u64))))\n')



def deep_recursion_cases():
    source = ('def descend(n: i64) -> i64:\n    if n == 0:\n        return 0\n    return 1 + descend(n - 1)\n\n\n'
              'def main() -> i64:\n    return descend(20000)\n')
    yield source, ['--max-frames=25000'], (0, b'20000\n')
    yield source, [], (1, [b'R_FRAME_LIMIT'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-parity-') as directory:
        temp = Path(directory)
        source, output = temp / 'case.my', temp / 'program'
        count = 0
        for text in cases():
            source.write_text(text)
            vm = run([compiler, 'run', source, '--print-result'])
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, (text, built.stderr.decode())
            native = run([output])
            assert signature(vm) == signature(native), (text, vm, native)
            count += 1
        for text in extended_cases():
            source.write_text(text)
            vm = run([compiler, 'run', source, '--print-result'])
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, (text, built.stderr.decode())
            for options in ([], ['--gc-stress']):
                native = run([output, *options])
                assert signature(vm) == signature(native), (text, options, vm, native)
            count += 1
        for text, options in (
            ('def main() -> i64:\n    while True:\n        pass\n    return 0\n', ['--max-steps=17']),
            ('def recurse(n: i64) -> i64:\n    return recurse(n + 1)\n\n\ndef main() -> i64:\n    return recurse(0)\n', ['--max-frames=8']),
        ):
            source.write_text(text)
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, built.stderr
            vm = run([compiler, 'run', source, '--print-result', *options])
            native = run([output, *options])
            assert signature(vm) == signature(native), (text, vm, native)
            count += 1
        for text, options, expected in deep_recursion_cases():
            source.write_text(text)
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, built.stderr
            vm = run([compiler, 'run', source, '--print-result', *options])
            native = run([output, *options])
            assert signature(vm) == expected, (options, vm)
            assert signature(native) == expected, (options, native)
            count += 1
        print(f'QBE native parity: {count} cases passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
