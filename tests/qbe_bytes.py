#!/usr/bin/env python3
"""Native managed byte-string parity, including every documented operation."""
import argparse
from pathlib import Path
import sys
import tempfile

import golden

from qbe_parity import ROOT, run, signature


def cases():
    yield '''def main() -> int:
    header = b"my"
    body = b"lang"
    whole = header + body
    if len(whole) != 6:
        return 1
    if whole[0] != 109 or whole[-1] != 103:
        return 2
    if whole[2:6] != body or whole[2:99] != body:
        return 3
    if len(whole[-1:0]) != 0 or whole[-99:99] != whole:
        return 4
    return whole[0] - 67
'''
    yield '''def main() -> int:
    frame = b"\\x01\\x02\\x03\\x04"
    total = 0
    for value in frame:
        total += value
    for index, value in enumerate(frame):
        total += index * value
    return total
'''
    yield '''def main() -> int:
    record = b"GET /index.html"
    if not record.startswith(b"GET "):
        return 1
    if record.endswith(b".css"):
        return 2
    if record.find(b"/index") != 4 or record.find(b"?query") != -1:
        return 3
    if 47 not in record or b"html" not in record:
        return 4
    if record == b"GET /" or record != b"GET /index.html":
        return 5
    if b"" not in record or record.find(b"") != 0:
        return 6
    return len(record)
'''
    yield '''def main() -> int:
    line = b"name,age,city"
    fields = line.split(b",")
    if len(fields) != 3 or fields[1] != b"age":
        return 1
    if b",".join(fields) != line:
        return 2
    edges = b",a,".split(b",")
    if len(edges) != 3 or len(edges[0]) != 0 or len(edges[2]) != 0:
        return 3
    widths = 0
    for field in fields:
        widths += len(field)
    return widths
'''
    yield '''def main() -> int:
    values: list[int] = [72, 105]
    greeting = bytes(values)
    if greeting != b"Hi":
        return 1
    octets = greeting.to_list()
    if len(octets) != 2 or octets[1] != 105:
        return 2
    if len(bytes(octets)) != 2:
        return 3
    empty: list[int] = []
    if len(bytes(empty)) != 0:
        return 4
    return octets[0] + octets[1]
'''
    yield '''def text_of(raw: bytes) -> Result[str, str]:
    return raw.decode()

def main() -> int:
    encoded = "h\\u00e9llo".encode()
    if len(encoded) != 6:
        return 1
    match text_of(encoded):
        case Ok(value):
            if value != "h\\u00e9llo":
                return 2
        case Err(message):
            return 0 - len(message)
    match text_of(b"\\xff"):
        case Ok(other):
            return 0 - len(other)
        case Err(message):
            return len(encoded)
'''
    yield '''def parse(digits: str) -> Result[bytes, str]:
    return bytes.fromhex(digits)

def main() -> int:
    raw = b"\\x0f\\xa0"
    if raw.hex() != "0fa0":
        return 1
    if len(b"".hex()) != 0:
        return 2
    match parse("0fa0"):
        case Ok(value):
            if value != raw:
                return 3
        case Err(message):
            return 0 - len(message)
    match parse("0f0"):
        case Ok(value):
            return 0 - len(value)
        case Err(message):
            return len(message)
'''
    yield '''class Packet:
    kind: str
    payload: bytes

def main() -> int:
    packets: list[Packet] = [Packet(kind="hello", payload=b"\\x01"), Packet(kind="data", payload=b"\\x02\\x03")]
    index: dict[str, bytes] = {}
    for packet in packets:
        index[packet.kind] = packet.payload
    if len(index) != 2 or index["data"] != b"\\x02\\x03":
        return 1
    alias = packets[1]
    if alias.payload != packets[1].payload:
        return 2
    total = 0
    for value in index["data"]:
        total += value
    return total + len(index["hello"])
'''
    # Retained byte strings survive repeated collection while aliases stay equal.
    yield '''def make() -> list[bytes]:
    return b"a,b,c".split(b",")

def main() -> int:
    kept = make()
    i = 0
    while i < 60:
        garbage = (b"x" + b"y").split(b"x")
        i += 1
    if kept[2] != b"c":
        return 1
    return len(kept) + len(b"-".join(kept))
'''
    # Traps: index bounds, byte range, empty separator.
    yield '''def main() -> int:
    return b"ab"[2]
'''
    yield '''def main() -> int:
    values: list[int] = [256]
    return len(bytes(values))
'''
    yield '''def main() -> int:
    values: list[int] = [0 - 1]
    return len(bytes(values))
'''
    yield '''def main() -> int:
    return len(b"abc".split(b""))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    golden.argument(parser)
    args = parser.parse_args()
    reference = golden.Reference('qbe_bytes', args.record)
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-bytes-') as directory:
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
                native = run([output, *options])
                assert signature(vm) == signature(native), (text, options, vm, native)
            count += 1
        reference.save()
    print(f'QBE byte-string parity: {count} cases passed')


if __name__ == '__main__':
    main()
