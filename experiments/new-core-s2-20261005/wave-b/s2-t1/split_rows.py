#!/usr/bin/env python3
"""Extract the five S2 text rows with the original setup and timed kernel."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[4]
source = (root / 'benchmarks/runtime/expanded/text/main.my').read_text()

def function(name):
    return re.search(r'^def ' + name + r'\(.*?(?=^def |\Z)', source, re.M | re.S).group(0).rstrip() + '\n'

def branch(name, row):
    text = function(name)
    text = text[:text.index('    if kind ==')]
    original = function(name)
    marker = re.search(r'^    (?:if|elif) kind == "' + row + '".*:\n', original, re.M)
    start = marker.end()
    end = re.search(r'^    (?:elif |return )', original[start:], re.M).start() + start
    body = original[start:end]
    body = '\n'.join(line[4:] if line.startswith('    ') else line for line in body.splitlines()) + '\n'
    tail = '    return Inputs(raw=raw, texts=texts, other=other, numbers=numbers, fragments=fragments)\n' if name == 'inputs' else '    return checksum\n'
    return text + body + tail

header = source[source.index('extern def'):source.index('def number')]
repeat = 'def repeated(text: str, count: int) -> str:\n    result = ""\n    for j in range(count):\n        result += text\n    return result\n'
for row in ('string_equal', 'string_search', 'string_split', 'string_join', 'bytes_scan'):
    input_row = 'string_split' if row == 'string_join' else row
    main = function('main').replace('len(args) != 4', 'len(args) != 3')
    start = main.index('    kind = args[0]'); end = main.index('    size = number(args[1])')
    main = main[:start] + '    kind = "' + row + '"\n' + main[end:]
    for old, new in ((3, 2), (2, 1), (1, 0)):
        main = main.replace(f'args[{old}]', f'argTEMP{new}')
    main = main.replace('argTEMP', 'args[').replace('args[2\n', 'args[2]\n') if False else main
    main = re.sub(r'argTEMP(\d)', r'args[\1]', main)
    extras = [function('score')] if row in ('string_split', 'string_join') else []
    if row == 'string_split': extras += [function('split_job')]
    if row == 'bytes_scan': extras += [function('bytes_job')]
    text = f'module row_{row}\n\n# Split from benchmarks/runtime/expanded/text/main.my; identical timed work.\n\n' + header + '\n' + function('number') + '\n' + repeat + '\n' + '\n'.join(extras) + '\n' + branch('inputs', input_row) + '\n' + branch('kernel', row) + '\n' + main
    (root / f'test/core/row_{row}.my').write_text(text)
