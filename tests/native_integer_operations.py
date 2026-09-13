"""Execute integer extension boundary cases in the VM and native optimization modes."""
from pathlib import Path
import subprocess
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
                checks.append(f'    if {op}({number(a)}, {number(b)}) != {number(expected)}:\n'
                              f'        return {len(checks) + 1}\n')
    yield 'def main() -> i64:\n' + ''.join(checks) + '    return 0\n', (0, b'0\n')
    for expression in ('shift_left(1, 64)', 'shift_right(1, -1)', 'shift_left(1u8, 8u8)'):
        yield f'def main() -> i64:\n    _ = {expression}\n    return 0\n', None
