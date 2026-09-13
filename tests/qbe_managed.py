#!/usr/bin/env python3
"""Native managed text/dictionary parity under allocation stress."""
import argparse
from pathlib import Path
import sys
import tempfile

from qbe_parity import ROOT, run, signature


def cases():
    yield '''def main() -> int:
    if str(-9223372036854775807 - 1) != "-9223372036854775808":
        return 1
    if str(True) != "True" or str(False) != "False":
        return 2
    if str(None) != "None":
        return 3
    if str(0.1) != "0.1" or str(-0.0) != "-0.0":
        return 4
    text = "value=" + str(42)
    if str(text) != "value=42":
        return 5
    return 42
'''
    yield '''def main() -> int:
    text = "hé🙂,x,"
    parts = text.split(",")
    if ",".join(parts) != text:
        return 1
    if "é🙂" not in text:
        return 2
    if parts[0][2] != "🙂":
        return 3
    return len(text)
'''
    yield '''def main() -> int:
    values: dict[str,int] = {"first": 40, "second": 2}
    alias = values
    alias["first"] = 41
    keys = values.keys()
    before = values.values()
    values["first"] = 42
    if keys[0] != "first":
        return 1
    return before[0] + values.get("missing", 1)
'''
    yield '''def make() -> list[str]:
    values: dict[int,str] = {1: "retained", 2: "🙂"}
    return values.values()
def main() -> int:
    values = make()
    i = 0
    while i < 40:
        garbage = ["new" + " text", "🙂"]
        i += 1
    if values[1] != "🙂":
        return 1
    return len(values[0])
'''
    yield '''def main() -> int:
    values = {"first": 40, "second": 2}
    total = 0
    for key in values:
        total += values[key]
    return total
'''
    yield '''def main() -> int:
    values = {"first": 40}
    for key in values:
        values["second"] = 2
    return 0
'''
    yield '''def main() -> int:
    text = "é🙂"
    if text[-99:99] != text:
        return 1
    if text[1:0] != "":
        return 2
    return len(text[-1])
'''
    yield '''def main() -> int:
    text = "a"
    return len(text[2])
'''
    yield '''def main() -> int:
    values = {"first": 40}
    return values["missing"]
'''
    yield '''def main() -> int:
    text = "a"
    return len(text.split(""))
'''


    yield '''def main() -> int:
    left = [1, 2, 3]
    right = [1, 2, 3]
    if left != right or 2 not in left:
        return 1
    a = {"first": left, "second": right}
    b = {"second": right, "first": left}
    if a != b:
        return 2
    right[0] = 9
    if left == right:
        return 3
    return 42
'''
    yield '''def main() -> int:
    a = [0.0]
    b = [-0.0]
    if a != b:
        return 1
    return 42
'''
    yield '''def main() -> int:
    raw = b"hi\\x00\\xff"
    if len(raw) != 4:
        return 1
    if raw[0] != 104 or raw[-1] != 255:
        return 2
    if raw != b"hi\\x00\\xff" or raw == b"hi":
        return 3
    total = 0
    for value in raw:
        total += value
    return total - 388
'''
    yield '''def main() -> int:
    raw = b"ab"
    return raw[2]
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-managed-') as directory:
        temp = Path(directory)
        source, output = temp / 'case.my', temp / 'program'
        count = 0
        for text in cases():
            source.write_text(text)
            vm = run([args.compiler.resolve(), 'run', source])
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', args.compiler.resolve(), '--qbe', args.qbe,
                         '--zig', args.zig, '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, (text, built.stderr.decode())
            for options in ([], ['--gc-stress']):
                native = run([output, *options])
                assert signature(vm) == signature(native), (text, options, vm, native)
            count += 1
    print(f'QBE managed parity: {count} cases passed')


if __name__ == '__main__':
    main()
