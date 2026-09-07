"""Execute integer extension boundary cases in the VM and native optimization modes."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from native_cases import signature


def run(command):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=90)


def cases():
    checks = []
    for signed in (False, True):
        for width in (8, 16, 32, 64):
            ty = ('i' if signed else 'u') + str(width)
            minimum = -(1 << (width - 1)) if signed else 0
            maximum = (1 << (width - int(signed))) - 1
            def number(value):
                return str(value) + ty
            for op, a, b, expected in (
                ('wrapping_add', maximum, 1, minimum),
                ('wrapping_sub', minimum, 1, maximum),
                ('wrapping_mul', maximum, maximum, 1),
                ('saturating_add', maximum, 1, maximum),
                ('saturating_sub', minimum, 1, minimum),
                ('saturating_mul', maximum, maximum, maximum),
                ('bit_and', 7, 3, 3), ('bit_or', 4, 1, 5), ('bit_xor', 7, 3, 4),
                ('shift_left', 1, width - 1, minimum if signed else 1 << (width - 1)),
                ('shift_right', minimum if signed else maximum, 1, minimum // 2 if signed else maximum // 2),
            ):
                checks.append(f'if {op}({number(a)},{number(b)})!={number(expected)}{{return {len(checks)+1};}}')
    yield 'fn main()->i64{' + ''.join(checks) + 'return 0;}', (0, b'0\n')
    for expression in ('shift_left(1,64)', 'shift_right(1,-1)', 'shift_left(1u8,8u8)'):
        yield 'fn main()->i64{discard ' + expression + ';return 0;}', None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    compiler = Path(args.compiler).resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-integer-ops-') as directory:
        directory = Path(directory)
        for source, expected in cases():
            path = directory / 'case.my'
            path.write_text(source)
            interpreted = signature(run([compiler, 'run', path]))
            if expected is not None:
                assert interpreted == expected, interpreted
            else:
                assert interpreted[1][-1] == b'R_INVALID_SHIFT', interpreted
            emitted = run([compiler, 'emit-c', path])
            assert emitted.returncode == 0, emitted.stderr
            c_path = directory / 'case.c'
            c_path.write_bytes(emitted.stdout)
            for mode in ('-O0', '-O2'):
                executable = directory / 'case'
                compiled = run([args.cc, '-std=c11', mode, '-fsanitize=undefined', '-fno-sanitize-recover=all', c_path, '-o', executable])
                assert compiled.returncode == 0, compiled.stderr
                native = run([executable])
                assert signature(native) == interpreted, native.stderr
    print('integer operation VM/native boundary and trap parity passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
