#!/usr/bin/env python3
"""Instrument the schematic provider to report how many host calls one render makes.

usage: count_host_calls.py <provider.c> <out.c>

Every registered callback gets one counter increment at entry and the process's
cleanup hook prints `HOSTCALLS <n>` to stderr. The instrumented provider is only
ever built into a throwaway arm; production source is untouched.
"""
import re
import sys
from pathlib import Path

ENTRY = re.compile(r'^(static const char \*\w+\(void \*context, MylangHost(?:Packed)?Call \*call\) \{)$', re.M)


def main() -> None:
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    text = source.read_text()
    text = text.replace('static MylangSchematic state;',
                        'static MylangSchematic state;\nstatic unsigned long long host_calls;', 1)
    text, count = ENTRY.subn(r'\1 host_calls++;', text)
    text = text.replace('static void release(void) {',
                        'static void release(void) {\n    fprintf(stderr, "HOSTCALLS %llu\\n", host_calls);', 1)
    out.write_text(text)
    print(f'instrumented {count} callbacks -> {out}')


if __name__ == '__main__':
    main()
