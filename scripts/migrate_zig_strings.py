#!/usr/bin/env python3
"""Migrate legacy .my sources embedded as Zig multiline string literals.

Zig multiline literals are raw: every `\\\\` line contributes its bytes and a
newline separator, so a run of them can be handed to `mylang migrate` unchanged
and written back with the same indentation.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('src/*_test.zig', 'test/integration.zig')
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


def classify(compiler, text):
    if not any(hint in text for hint in HINTS):
        return None
    result = migrate(compiler, text, False)
    if result.returncode == 0:
        migrated = result.stdout.rstrip('\n')
        return ('already-python' if migrated == text.rstrip('\n') else 'converted', migrated)
    gaps = constructs(migrate(compiler, text, True).stderr)
    if gaps:
        return ('unsupported', gaps)
    return ('failed', (result.stderr.strip().splitlines() or ['unknown'])[0])


SINGLE = re.compile(r'"((?:\\.|[^"\\])*)"')
DECLARED = re.compile(r'\b(fn|struct|enum|union|domain|result)\s+[A-Za-z_]')


def single_line(path):
    """Census of one-line quoted guest sources, which need a reshape this tool does not do."""
    found = 0
    for match in SINGLE.finditer(path.read_text(encoding='utf-8')):
        body = match.group(1)
        if DECLARED.search(body) and '{' in body:
            found += 1
    return found


def rewrite(indent, migrated):
    return [indent + '\\\\' + line + '\n' for line in migrated.split('\n')]


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
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--report', action='store_true', help='classify every literal without editing')
    group.add_argument('--write', action='store_true', help='rewrite convertible literals in place')
    arguments = parser.parse_args()
    overall = {'literals': 0, 'converted': 0, 'already-python': 0, 'unsupported': 0, 'failed': 0, 'skipped': 0}
    per_file = {}
    every_gap = {}
    quoted = 0
    for path in targets():
        quoted += single_line(path)
        counts, gaps = process(arguments.compiler, path, arguments.write)
        if counts['literals'] == 0:
            continue
        per_file[str(path.relative_to(ROOT))] = counts
        for key, value in counts.items():
            overall[key] += value
        for gap in gaps:
            every_gap[gap] = every_gap.get(gap, 0) + 1
    report = {
        'version': 'migrate-strings-v1',
        'mode': 'write' if arguments.write else 'report',
        'totals': overall,
        'single_line_literals': quoted,
        'constructs': dict(sorted(every_gap.items(), key=lambda item: (-item[1], item[0]))),
        'files': per_file,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
