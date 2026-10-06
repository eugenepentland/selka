#!/usr/bin/env python3
"""Split S3 applications from the unchanged expanded benchmark sources.

Helper functions and selected dispatch bodies are copied literally. Only the
row selector, unused setup and unused helper parameters are removed. --check
verifies that every saved fixture still matches this extraction.
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[4]


def function(source, name):
    found = re.search(r'^def ' + re.escape(name) + r'\(.*?(?=^def |\Z)', source, re.M | re.S)
    if not found:
        raise ValueError(f'missing function {name}')
    return found.group(0).rstrip() + '\n'


def deindent(body, count=4):
    return '\n'.join(line[count:] if line.startswith(' ' * count) else line
                     for line in body.splitlines()) + '\n'


def selected_branch(body, condition, indent):
    pattern = r'^' + ' ' * indent + r'(?:if|elif) ' + re.escape(condition) + r':\n'
    found = re.search(pattern, body, re.M)
    if not found:
        raise ValueError(f'missing branch {condition}')
    start = found.end()
    end = re.search(r'^' + ' ' * indent + r'(?:elif |else:|return )', body[start:], re.M)
    if not end:
        raise ValueError(f'missing branch boundary {condition}')
    return deindent(body[start:start + end.start()])


def arguments(main):
    main = main.replace('len(args) != 4', 'len(args) != 3')
    return re.sub(r'args\[([123])\]', lambda found: f'args[{int(found[1]) - 1}]', main)


def header(row, suite, imports=''):
    return (f'module row_{row}\n{imports}\n'
            f'# Split from benchmarks/runtime/expanded/{suite}/main.my; identical timed work.\n\n'
            'extern def runtime_bench_now(host: Host) -> i64 effects(host)\n\n')


def text_fixture(source, row, helpers):
    fields = source[source.index('record Inputs:'):source.index('def number')].rstrip() + '\n'
    imports = 'import json\n' if row == 'json_transform' else ''
    result = header(row, 'text', imports) + fields + '\n'
    result += '\n'.join(function(source, name) for name in ('number', *helpers)) + '\n'
    for name, tail in (('inputs', '    return Inputs(raw=raw, texts=texts, other=other, numbers=numbers, fragments=fragments)\n'),
                       ('kernel', '    return checksum\n')):
        original = function(source, name)
        prefix = original[:original.index('    if kind ==')]
        result += prefix + selected_branch(original, f'kind == "{row}"', 4) + tail + '\n'
    main = function(source, 'main')
    start = main.index('    kind = args[0]')
    end = main.index('    size = number(args[1])')
    main = main[:start] + f'    kind = "{row}"\n' + main[end:]
    return result + arguments(main)


def packet_fixture(source):
    result = header('packet_decode', 'compute')
    start = source.index('record Packet:')
    end = source.index('def parse_number')
    result += source[start:end].rstrip() + '\n\n'
    result += '\n'.join(function(source, name) for name in ('parse_number', 'make_frame', 'decode')) + '\n'
    main = function(source, 'main')
    start = main.index('    names = ')
    end = main.index('    size = parse_number(args[1])')
    main = main[:start] + main[end:]
    setup_start = main.index('    values = ')
    setup_end = main.index('    checksum = 0')
    main = main[:setup_start] + ('    values = [(seed + j * 37) % 1009 for j in range(size)]\n'
                               '    frames = [make_frame(j, seed) for j in range(size)]\n') + main[setup_end:]
    start = main.index('            if kind == ')
    end = main.index('            pass_total += value')
    main = main[:start] + selected_branch(main[start:end] + '            return 0\n', 'kind == 11', 12) + main[end:]
    return result + arguments(main)


def lox_fixture(source):
    result = header('lox_eval', 'collections')
    result += source[source.index('union Value:'):source.index('record Row:')].rstrip() + '\n\n'
    result += source[source.index('record Instruction:'):source.index('def integer')].rstrip() + '\n\n'
    result += '\n'.join(function(source, name) for name in ('integer', 'boolean', 'execute', 'parse_number')) + '\n'
    batch = function(source, 'batch_result')
    result += ('def batch_result(size: int, batch: int, seed: int, program: list[Instruction]) -> int:\n'
               + selected_branch(batch, 'kind == 13', 4) + '\n')
    main = function(source, 'main')
    start = main.index('    case_id = -1')
    end = main.index('    size = parse_number(args[1])')
    main = main[:start] + main[end:]
    start = main.index('    values = ')
    end = main.index('    program = ')
    main = main[:start] + main[end:]
    main = main.replace('batch_result(case_id, size, batch, seed, values, keys, lookup, lookup_str, mut nested, program)',
                        'batch_result(size, batch, seed, program)')
    start = main.index('    if args[0] == "mutate_nested":')
    end = main.index('    out.print(checksum, elapsed)')
    main = main[:start] + main[end:]
    return result + arguments(main)


def fixtures():
    sources = {suite: (ROOT / f'benchmarks/runtime/expanded/{suite}/main.my').read_text()
               for suite in ('text', 'compute', 'collections')}
    return {
        'word_count': text_fixture(sources['text'], 'word_count', ('score', 'word_job')),
        'csv_aggregate': text_fixture(sources['text'], 'csv_aggregate', ('row_name', 'score', 'csv_rows', 'csv_job')),
        'json_transform': text_fixture(sources['text'], 'json_transform', ('row_name', 'score', 'json_integer', 'json_active', 'json_job')),
        'packet_decode': packet_fixture(sources['compute']),
        'lox_eval': lox_fixture(sources['collections']),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for row, text in fixtures().items():
        path = ROOT / f'test/core/row_{row}.my'
        if args.check:
            if not path.is_file() or path.read_text() != text:
                raise SystemExit(f'fixture differs from literal extraction: {path}')
        else:
            path.write_text(text)
        print(f'{row}: {"checked" if args.check else "written"} {len(text.splitlines())} lines')


if __name__ == '__main__':
    main()
