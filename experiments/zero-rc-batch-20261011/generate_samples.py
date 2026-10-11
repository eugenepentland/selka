#!/usr/bin/env python3
"""Generate fixed lookup scaling and enum-record field transfer workloads."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SIBLINGS = (1, 16, 128)
REPEATS = 32
TEXT = 'a' * 64
SELECTED = [TEXT, TEXT]


def lookup_source(kind, siblings, action, repeats=REPEATS):
    if kind == 'object':
        value = {'target': SELECTED, **{f'other-{i}': ['b' * 64, 'c' * 64] for i in range(siblings)}}
        hit = 'json.get(document, "target")'
        miss = 'json.get(document, "missing")'
    else:
        value = [SELECTED] + [['b' * 64, 'c' * 64] for _ in range(siblings)]
        hit = 'json.at(document, 0)'
        miss = f'json.at(document, {siblings + 1})'
    document = json.dumps(value, separators=(',', ':'))
    operation = {
        'control': '        total += 1\n',
        'hit': f'''        match {hit}:
            case Some(selected):
                total += score(selected)
            case None:
                assert False
''',
        'miss': f'''        match {miss}:
            case Some(_):
                assert False
            case None:
                total += 1
''',
    }[action]
    return f'''import json

func score(value: json.Json) -> int:
    match value:
        case json.Json.array(value=items):
            mut total = 0
            for item in items:
                match item:
                    case json.Json.text(value=text):
                        total += len(text)
                    case _:
                        assert False
            return total
        case _:
            assert False
            return 0

func run(document: json.Json) -> int:
    mut total = 0
    for i in range({repeats}):
{operation}    return total

func main(out: Stream) -> int:
    match json.loads({json.dumps(document)}):
        case Ok(document):
            out.print(json.type_name(document), run(document))
        case Err(_):
            assert False
    return 0
'''


def record_source(phase, repeats=1000):
    copy = '.copy()' if phase == 'before' else ''
    fields = ', '.join(f'{name}=["{letter * 64}" + str(n), "{letter.upper() * 64}" + str(n)]' for name, letter in (('left', 'l'), ('right', 'r'), ('ignored', 'x')))
    return f'''enum Bundle:
    parts(left: str[], right: str[], ignored: str[])

record Pair:
    left: str[]
    right: str[]

func make(n: int) -> Bundle:
    return Bundle.parts({fields})

func unpack(n: int) -> Pair:
    match make(n):
        case Bundle.parts(left=left, right=right, ignored=_):
            return Pair(left=left{copy}, right=right{copy})

func score(value: Pair) -> int:
    return len(value.left[0]) + len(value.left[1]) + len(value.right[0]) + len(value.right[1])

func main(out: Stream) -> int:
    mut total = 0
    for i in range({repeats}):
        total += score(unpack(i))
    out.print(total)
    return 0
'''


def main():
    directory = HERE / 'samples'
    directory.mkdir(exist_ok=True)
    for kind in ('array', 'object'):
        for siblings in SIBLINGS:
            for action in ('control', 'hit', 'miss'):
                (directory / f'{kind}_{siblings}_{action}.my').write_text(lookup_source(kind, siblings, action))
        (directory / f'{kind}_timing.my').write_text(lookup_source(kind, 128, 'hit', 4000))
    for phase in ('before', 'after'):
        (directory / f'record_{phase}.my').write_text(record_source(phase))
        (directory / f'record_timing_{phase}.my').write_text(record_source(phase, 20000))


if __name__ == '__main__':
    main()
