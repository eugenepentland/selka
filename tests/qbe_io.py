#!/usr/bin/env python3
"""Native `print` parity: every value shape, `sep=`/`end=`, and the depth cap."""
import argparse
from pathlib import Path
import sys
import tempfile

import golden

from qbe_parity import ROOT, run, signature


def cases():
    yield '''def main() -> int:
    print("hello", 42, True, None)
    print(["a", "b"], {"k": 1}, b"\\x00\\xff")
    print()
    print(1, 2, 3, sep="-", end="!\\n")
    print("only", end="")
    print("", sep="|")
    return 0
'''
    yield '''class Point:
    x: int
    y: int

enum Colour:
    red,
    green


union Shape:
    dot,
    span: int

def pick(n: int) -> Result[int, str]:
    if n < 0:
        return Err("nope")
    return Ok(n)

def main() -> int:
    print(Point(x=1, y=2), Colour.green, Colour.red)
    found: Option[int] = Some(4)
    missing: Option[int] = None
    print(pick(3), pick(-1), found, missing)
    dot: Shape = Shape.dot
    span: Shape = Shape.span(7)
    print(dot, span)
    return 0
'''
    # Text quoting differs between the top level and inside a container.
    yield '''def main() -> int:
    text = "quote'and\\\\slash\\ttab\\nnewline\\rreturn"
    print(text)
    print([text])
    print({text: text})
    print("h\\u00e9\\U0001f642")
    print(["h\\u00e9\\U0001f642"])
    return 0
'''
    # Byte strings always render as a Python b'...' literal.
    yield '''def main() -> int:
    print(b"")
    print(b"plain")
    print(b"\\x00\\x1f\\x20\\x7e\\x7f\\xff")
    print(b"quote'and\\\\slash\\ttab\\nnewline")
    print([b"ab"], {"k": b"cd"})
    return 0
'''
    # Every integer width and both signednesses.
    yield '''def main() -> int:
    print(0, -9223372036854775808, 9223372036854775807)
    print(255u8, 65535u16, 4294967295u32, 18446744073709551615u64)
    print(-128i8, -32768i16, -2147483648i32)
    print([1u8, 2u8], {1: 2u16})
    return 0
'''
    # Floats keep the shortest round-tripping decimal spelling.
    yield '''def main() -> int:
    print(0.0, 1.0, 2.5, 0.1, 100.0)
    print(1e20, 1e-7, 1.7976931348623157e308)
    print(3.0 / 7.0, 1.0 / 3.0, 2.0 / 3.0)
    print(0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0)
    print([0.5], {"k": 0.25})
    return 0
'''
    # Nesting deeper than 24 levels renders as an ellipsis.
    yield '''def main() -> int:
    deep: list[list[int]] = [[1]]
    rows: list[list[list[int]]] = [[[2]]]
    print(deep, rows)
    values: list[int] = [1]
    box = values
    ladder: list[list[int]] = [box]
    step = 0
    while step < 30:
        ladder = [ladder[0]]
        step += 1
    print(ladder)
    return 0
'''
    # Records nest inside collections and options.
    yield '''class Inner:
    label: str
    values: list[int]

class Outer:
    inner: Inner
    flag: bool

def main() -> int:
    value = Outer(inner=Inner(label="deep", values=[1, 2]), flag=False)
    print(value)
    print([value])
    box: Option[Outer] = Some(value)
    print(box)
    table: dict[str, Outer] = {"one": value}
    print(table)
    return 0
'''
    # Fixed arrays print like lists and domains print like a constructor.
    yield '''def main() -> int:
    row: [3]int = [1, 2, 3]
    print(row)
    return 0
'''
    # An empty collection still prints its brackets.
    yield '''def main() -> int:
    values: list[int] = []
    table: dict[str, int] = {}
    print(values, table, "")
    print([values], [table])
    return 0
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    golden.argument(parser)
    args = parser.parse_args()
    reference = golden.Reference('qbe_io', args.record)
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-io-') as directory:
        temp = Path(directory)
        reference.scrub = [(str(temp).encode(), b'<corpus>')]
        source, output = temp / 'case.my', temp / 'program'
        count = 0
        for text in cases():
            source.write_text(text)
            vm = reference.expect([text, []], [compiler, 'run', source, '--print-result'])
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, (text, built.stderr.decode())
            for options in ([], ['--gc-stress']):
                native = run([output, '--print-result', *options])
                assert signature(vm) == signature(native), (text, options, vm, native)
            count += 1
        reference.save()
    print(f'QBE output parity: {count} cases passed')


if __name__ == '__main__':
    main()
