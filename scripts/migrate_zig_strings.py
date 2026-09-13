#!/usr/bin/env python3
"""Migrate legacy .my sources embedded in Zig tests to the canonical Python surface.

Two literal shapes carry guest source. A run of `\\\\` multiline lines is raw: every
line contributes its bytes and a newline separator, so it can be handed to
`mylang migrate` unchanged and written back with the same indentation. A quoted
literal, or a `++` chain of them, holds the whole program on one line; Python
layout needs real newlines, so each converted chain is reshaped into a multiline
literal indented under the line that held it.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('src/*_test.zig', 'src/*/tests.zig', 'test/integration.zig')
# This tool's own tests pin expected migration output, so they are never rewritten.
EXCLUDED = ('src/migrate_test.zig',)
# A literal is guest source only when the parser accepts it; these words avoid
# spending a compiler run on prose, JSON fixtures and expected-output blocks.
HINTS = ('fn ', 'def ', 'struct ', 'class ', 'enum ', 'union ', 'result ', 'domain ', 'module ', 'const ')


def targets():
    seen = []
    for pattern in TARGETS:
        for path in sorted(ROOT.glob(pattern)):
            if str(path.relative_to(ROOT)) in EXCLUDED:
                continue
            if path not in seen:
                seen.append(path)
    return seen


def literals(lines):
    """Yield (start, end, indent) for each run of consecutive multiline-literal lines."""
    at = 0
    while at < len(lines):
        stripped = lines[at].lstrip()
        if not stripped.startswith('\\\\'):
            at += 1
            continue
        start = at
        indent = lines[at][:len(lines[at]) - len(stripped)]
        while at < len(lines) and lines[at].lstrip().startswith('\\\\'):
            at += 1
        yield start, at, indent


def content(lines, start, end):
    return '\n'.join(line.lstrip()[2:] for line in lines[start:end])


def migrate(compiler, text, partial):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'embedded.my'
        path.write_text(text if text.endswith('\n') else text + '\n', encoding='utf-8')
        command = [compiler, 'migrate', str(path), '--diagnostics=json']
        if partial:
            command.append('--allow-partial')
        return subprocess.run(command, capture_output=True, text=True, timeout=120)


def constructs(stderr):
    found = []
    for line in stderr.splitlines():
        line = line.strip()
        if not line.startswith('{'):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get('kind') != 'diagnostic':
            continue
        diagnostic = record['diagnostic']
        if diagnostic.get('code') == 'E_MIGRATE_UNSUPPORTED':
            found.append(diagnostic.get('message', '').removeprefix('no Python spelling for '))
    return found


CACHE = {}


def classify(compiler, text):
    if not any(hint in text for hint in HINTS):
        return None
    if text in CACHE:
        return CACHE[text]
    result = migrate(compiler, text, False)
    if result.returncode == 0:
        migrated = result.stdout.rstrip('\n')
        verdict = ('already-python' if migrated == text.rstrip('\n') else 'converted', migrated)
    else:
        gaps = constructs(migrate(compiler, text, True).stderr)
        verdict = ('unsupported', gaps) if gaps else ('failed', (result.stderr.strip().splitlines() or ['unknown'])[0])
    CACHE[text] = verdict
    return verdict


ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', "'": "'", '\\': '\\'}


def decode(body):
    """Decode one Zig quoted-literal body, or return None for bytes a multiline literal cannot hold."""
    out = []
    at = 0
    while at < len(body):
        ch = body[at]
        if ch != '\\':
            out.append(ch)
            at += 1
            continue
        if at + 1 >= len(body):
            return None
        nxt = body[at + 1]
        if nxt in ESCAPES:
            out.append(ESCAPES[nxt])
            at += 2
        elif nxt == 'x' and at + 3 < len(body):
            out.append(chr(int(body[at + 2:at + 4], 16)))
            at += 4
        else:
            return None
    text = ''.join(out)
    if any(ch < ' ' and ch != '\n' for ch in text):
        return None
    return text


def chains(text):
    """Yield (start, end, [bodies]) for every quoted literal or `++` chain of them.

    Comments, character literals and multiline-literal lines are skipped so their
    bytes are never mistaken for a quoted literal.
    """
    at = 0
    end = len(text)
    while at < end:
        ch = text[at]
        if ch == '/' and text.startswith('//', at):
            at = text.find('\n', at)
            at = end if at < 0 else at
        elif ch == '\\' and text.startswith('\\\\', at):
            at = text.find('\n', at)
            at = end if at < 0 else at
        elif ch == "'":
            at += 1
            while at < end and text[at] != "'":
                at += 2 if text[at] == '\\' else 1
            at += 1
        elif ch == '"':
            start = at
            bodies = []
            while True:
                at += 1
                body = at
                while at < end and text[at] != '"':
                    at += 2 if text[at] == '\\' else 1
                if at >= end:
                    return
                bodies.append(text[body:at])
                at += 1
                after = at
                while after < end and text[after] in ' \t\n':
                    after += 1
                if not text.startswith('++', after):
                    break
                after += 2
                while after < end and text[after] in ' \t\n':
                    after += 1
                if after >= end or text[after] != '"':
                    break
                at = after
            yield start, at, bodies
        else:
            at += 1


def rewrite(indent, migrated):
    return [indent + '\\\\' + line + '\n' for line in migrated.split('\n')]


def quoted(compiler, path, write):
    """Reshape every convertible one-line guest source in one file."""
    text = path.read_text(encoding='utf-8')
    counts = {'quoted': 0, 'converted': 0, 'already-python': 0, 'unsupported': 0, 'failed': 0, 'skipped': 0}
    edits = []
    for start, end, bodies in chains(text):
        parts = [decode(body) for body in bodies]
        if any(part is None for part in parts):
            continue
        source = ''.join(parts)
        verdict = classify(compiler, source)
        if verdict is None:
            continue
        counts['quoted'] += 1
        kind, payload = verdict
        counts[kind] += 1
        if kind == 'converted':
            edits.append((start, end, payload))
    if write and edits:
        out = []
        at = 0
        for start, end, migrated in edits:
            line = text.rfind('\n', 0, start) + 1
            # Two chains on one line need two passes: reshaping the first moves the rest
            # of the line down, so the second is rewritten the next time the tool runs.
            if line < at:
                continue
            prefix = text[line:start]
            indent = prefix[:len(prefix) - len(prefix.lstrip())]
            inner = indent if prefix.strip() == '' else indent + '    '
            out.append(text[at:line])
            out.append(indent if prefix.strip() == '' else prefix.rstrip() + '\n')
            out.extend(inner + '\\\\' + part + '\n' for part in migrated.split('\n'))
            out.append(indent)
            at = end
        out.append(text[at:])
        path.write_text(''.join(out), encoding='utf-8')
    return counts


def process(compiler, path, write):
    lines = path.read_text(encoding='utf-8').splitlines()
    counts = {'literals': 0, 'converted': 0, 'already-python': 0, 'unsupported': 0, 'failed': 0, 'skipped': 0}
    gaps = []
    replacements = []
    for start, end, indent in literals(lines):
        counts['literals'] += 1
        verdict = classify(compiler, content(lines, start, end))
        if verdict is None:
            counts['skipped'] += 1
            continue
        kind, payload = verdict
        counts[kind] += 1
        if kind == 'unsupported':
            gaps.extend(payload)
        if kind == 'converted':
            replacements.append((start, end, indent, payload))
    if write and replacements:
        output = []
        at = 0
        for start, end, indent, migrated in replacements:
            output.extend(line + '\n' for line in lines[at:start])
            output.extend(rewrite(indent, migrated))
            at = end
        output.extend(line + '\n' for line in lines[at:])
        path.write_text(''.join(output), encoding='utf-8')
    return counts, gaps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--only', default=None, help='restrict to paths containing this substring')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--report', action='store_true', help='classify every literal without editing')
    group.add_argument('--write', action='store_true', help='rewrite convertible literals in place')
    arguments = parser.parse_args()
    overall = {'literals': 0, 'quoted': 0, 'converted': 0, 'already-python': 0, 'unsupported': 0, 'failed': 0, 'skipped': 0}
    per_file = {}
    every_gap = {}
    for path in targets():
        if arguments.only and arguments.only not in str(path):
            continue
        counts, gaps = process(arguments.compiler, path, arguments.write)
        one = quoted(arguments.compiler, path, arguments.write)
        for key, value in one.items():
            counts[key] = counts.get(key, 0) + value
        if counts['literals'] == 0 and counts['quoted'] == 0:
            continue
        per_file[str(path.relative_to(ROOT))] = counts
        for key, value in counts.items():
            overall[key] = overall.get(key, 0) + value
        for gap in gaps:
            every_gap[gap] = every_gap.get(gap, 0) + 1
    report = {
        'version': 'migrate-strings-v2',
        'mode': 'write' if arguments.write else 'report',
        'totals': overall,
        'constructs': dict(sorted(every_gap.items(), key=lambda item: (-item[1], item[0]))),
        'files': per_file,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
