"""Execute binary64 edge cases and conversions in both backends."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from native_cases import signature


def run(command):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=90)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    compiler = Path(args.compiler).resolve()
    expressions = [
        ('f64_add(4607182418800017408u64,4368491638549381120u64)', 4607182418800017408),
        ('f64_mul(2u64,4602678819172646912u64)', 1),
        ('f64_mul(9223372036854775808u64,4607182418800017408u64)', 9223372036854775808),
        ('f64_div(4607182418800017408u64,0u64)', 9218868437227405312),
        ('f64_div(0u64,0u64)', 9221120237041090560),
        ('f64_sqrt(13830554455654793216u64)', 9221120237041090560),
        ('f64_neg(9218868437227405313u64)', 9221120237041090560),
        ('f64_to_u64(f64_sqrt(f64_from_u64(1764u64)))', 42),
        ('f64_floor(13832806255468478464u64)', 13835058055282163712),
        ('f64_ceil(13832806255468478464u64)', 13830554455654793216),
        ('f64_trunc(13832806255468478464u64)', 13830554455654793216),
        ('f64_abs(9223372036854775808u64)', 0),
        ('f64_to_u64(13828302655841107968u64)', 0),
    ]
    body = ''.join(f'if {expr}!={expected}u64{{return {i+1};}}' for i, (expr, expected) in enumerate(expressions))
    body += 'if !f64_eq(0u64,9223372036854775808u64){return 90;}'
    body += 'if f64_eq(9221120237041090560u64,9221120237041090560u64){return 91;}'
    sources = [('fn main()->i64{' + body + 'return 0;}', (0, b'0\n'))]
    sources += [('fn main()->i64{discard f64_to_u64(' + value + 'u64);return 0;}', None)
                for value in ('9218868437227405312', '4895412794951729152', '13830554455654793216')]
    with tempfile.TemporaryDirectory(prefix='mylang-float-ops-') as directory:
        directory = Path(directory)
        for source, expected in sources:
            path = directory / 'case.my'
            path.write_text(source)
            interpreted = signature(run([compiler, 'run', path]))
            if expected is not None:
                assert interpreted == expected, interpreted
            else:
                assert interpreted[1][-1] == b'R_FLOAT_CONVERSION', interpreted
            emitted = run([compiler, 'emit-c', path])
            assert emitted.returncode == 0, emitted.stderr
            c_path = directory / 'case.c'
            c_path.write_bytes(emitted.stdout)
            for mode in ('-O0', '-O2'):
                executable = directory / 'case'
                compiled = run([args.cc, '-std=c11', mode, '-fsanitize=undefined', '-fno-sanitize-recover=all', c_path, '-lm', '-o', executable])
                assert compiled.returncode == 0, compiled.stderr
                native = run([executable])
                assert signature(native) == interpreted, native.stderr
    print('binary64 VM/native edge and conversion parity passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
