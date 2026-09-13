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
    yield 'fn fact(n:i64)->i64{if n<=1{return 1;}return n*fact(n-1);}fn main()->i64{return fact(10);}'
    yield 'fn add(a:i64,b:i64)->i64{return a+b;}fn main()->i64{return 1+add(add(2,3),add(4,5));}'
    yield 'fn main()->i64{let mut x=0;let mut i=0;while i<30{ i+=1;if i==4{continue;}if i==20{break;}x+=i;}return x;}'
    yield 'fn main()->i64{if false && 1/0==0{return 1;}if true || 1/0==0{return 7;}return 0;}'
    yield 'fn noop()->unit{return;}fn main()->i64{noop();return 42;}'
    for expression in ('9223372036854775807+1', '-9223372036854775808-1', '3037000500*3037000500', '1/0', '1%0', '-(-9223372036854775808)', '-9223372036854775808/-1', '-7/3', '-7%3'):
        yield 'fn main()->i64{return '+expression+';}'
    for signed in (False, True):
        for width in (8, 16, 32, 64):
            ty = ('i' if signed else 'u') + str(width)
            maximum = (1 << (width - int(signed))) - 1
            minimum = -(1 << (width - 1)) if signed else 0
            for expression in (f'{maximum}{ty}+1{ty}', f'{minimum}{ty}-1{ty}', f'{maximum}{ty}*2{ty}'):
                yield 'fn main()->i64{_ = '+expression+';return 0;}'
            yield f'fn id(x:{ty})->{ty}{{return x;}}fn main()->i64{{if id({maximum}{ty})=={maximum}{ty}{{return 7;}}return 0;}}'
    # Existing boundary corpus covers all widths for bitwise/wrapping/saturating operations.
    from native_integer_operations import cases as integer_extension_cases
    for text, _expected in integer_extension_cases():
        yield text
    yield 'fn main()->i64{return cast<i64>(18446744073709551615u64);}' 
    yield 'fn main()->i64{return cast<i64>(cast<u8>(-1));}'


def extended_cases():
    values = ','.join(str(i) for i in range(700))
    large = 'fn build()->[700]i64 effects(){return new [700]i64[' + values + '];}'
    yield large + 'fn read(value:[700]i64)->i64{return value[699];}fn main()->i64{return read(build());}'
    yield large + 'fn apply(callback:fn()->[700]i64 effects())->[700]i64{return callback();}fn main()->i64{let values=apply(build);return values[698];}'
    parameters = ','.join(f'a{i}:i64' for i in range(129))
    arguments = ','.join(str(i) for i in range(129))
    total = '+'.join(f'a{i}' for i in range(129))
    yield f'fn wide({parameters})->i64{{return {total};}}fn main()->i64{{return wide({arguments});}}'
    medium = 'fn build()->[512]i64 effects(){return new [512]i64[' + ','.join(str(i) for i in range(512)) + '];}'
    yield medium + 'fn total(a:[512]i64,b:[512]i64)->i64 effects(){return a[511]+b[510];}fn main()->i64{let f=total;return f(build(),build());}'
    for name in ('records', 'arrays', 'variants', 'generic-records', 'generic-arrays',
                 'generic-variants', 'callbacks', 'results', 'generic-results'):
        yield (ROOT / 'examples' / (name + '.my')).read_text()
    # Managed list aliasing, nested managed graphs and bounds traps.
    yield ('fn build()->List<i64>{let xs:List<i64>=[];let mut i=0;while i<40{xs.push(i);i+=1;}return xs;}'
           'fn main()->i64{let xs=build();let alias=xs;alias[2u64]=42;return xs[2u64]+len(xs);}')
    yield ('struct Box{row:List<i64>}'
           'fn main()->i64{let a:List<i64>=[];a.push(42);let box=new Box{row:a};'
           'let rows:List<List<i64>>=[];rows.push(box.row);let mut i=0;'
           'while i<20{let garbage:List<i64>=[];garbage.push(i);i+=1;}'
           'let inner=rows[0u64];return inner[0u64];}')
    yield 'fn main()->i64{let xs:List<i64>=[];return xs[0u64];}'
    yield 'fn main()->i64{let xs=new [2]i64[1,2];return xs[2];}'
    yield 'fn main()->i64{if f64_div(0u64,0u64)!=9221120237041090560u64{return 1;}if !f64_eq(0u64,9223372036854775808u64){return 2;}return cast<i64>(f64_to_u64(f64_add(f64_from_u64(20u64),f64_from_u64(22u64))));}'



def deep_recursion_cases():
    source = ('fn descend(n:i64)->i64{if n==0{return 0;}return 1+descend(n-1);}'
              'fn main()->i64{return descend(20000);}')
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
            ('fn main()->i64{while true{}return 0;}', ['--max-steps=17']),
            ('fn recurse(n:i64)->i64{return recurse(n+1);}fn main()->i64{return recurse(0);}', ['--max-frames=8']),
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
