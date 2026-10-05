#!/usr/bin/env python3
"""Group tests/lang files by the S2 features that block them (docs/design/new-core-s2.md §6).

Reads a `conformance.py --set all` result (its "blocking features per file" section, which
names each unsupported test's first blocker) and prints, per group, the files whose
blockers all lie inside it: s2 (dict, set, bytes, text, sort, ...), s2+fa (fixed arrays
too), s2+fv (function values too), s2+fa+fv, and other.

Usage: conformance_groups.py RESULT.txt
"""
import re
import sys

S2 = set('dict type|bytes type|set type|sort|slice|split|index|text of a non-integer value|'
         'extend|contains|number_format|replace|upper|index_of|strip|text_tail|count|sort_keyed|'
         'string index|find_range|find_start|find|text_format|text_ord|split_whitespace|'
         'splitlines|strip_chars|rfind|text_repr|pop_at|blob|array|parse_float|float_round|'
         'slice_step|print options|operator on an aggregate value|'
         'equality of a recursive value'.split('|'))
FA = {'fixed array type'}
FV = {'function value type', 'function_value'}


def group_of(features):
    if features <= S2:
        return 's2'
    if features <= S2 | FA and not features & FV:
        return 's2+fa'
    if features <= S2 | FV and not features & FA:
        return 's2+fv'
    if features <= S2 | FA | FV:
        return 's2+fa+fv'
    return 'other'


def main(path):
    lines = open(path).read().split('\n')
    start = next(k for k, line in enumerate(lines) if line.startswith('blocking features per file'))
    groups = {}
    for line in lines[start + 1:]:
        m = re.match(r'\s+(\S+)\s+(\d+) of\s+(\d+): (.*)', line)
        if not m:
            continue
        name, unsupported, total, rest = m.groups()
        features = {a.strip(): int(b) for a, b in re.findall(r'(.+?) x(\d+)(?:, |$)', rest)}
        groups.setdefault(group_of(set(features)), []).append((name, int(unsupported), int(total), rest))
    for group, files in groups.items():
        print('==', group, len(files), 'files', sum(f[1] for f in files), 'tests unsupported')
        for name, unsupported, total, rest in files:
            print('   ', name, unsupported, '/', total, ':', rest)


if __name__ == '__main__':
    main(sys.argv[1])
