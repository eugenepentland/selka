#!/usr/bin/env python3
"""Checked migration of every tracked .my source, without modifying any file."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = ('examples', 'src/stdlib', 'test/fixtures', 'src/board_trial/guest', 'src/schematic/guest')
# Migration reproduces Python sources exactly, so these must report no work at all.
ALREADY_PYTHON = ('src/schematic/guest',)


def sources():
    for directory in DIRECTORIES:
        for path in sorted((ROOT / directory).rglob('*.my')):
            yield directory, path


def run(compiler, path, extra):
    command = [compiler, 'migrate', str(path), '--diagnostics=json'] + extra
    return subprocess.run(command, capture_output=True, text=True, timeout=120, cwd=ROOT)


def diagnostics(text):
    found = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith('{'):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get('kind') == 'diagnostic':
            found.append(record['diagnostic'])
    return found


def unsupported(compiler, path):
    """Re-run in partial mode so every gap in one file is reported, not just the first."""
    result = run(compiler, path, ['--allow-partial'])
    gaps = []
    for record in diagnostics(result.stderr):
        if record.get('code') != 'E_MIGRATE_UNSUPPORTED':
            continue
        start = record.get('location', {}).get('start', {})
        gaps.append({
            'construct': record.get('message', '').removeprefix('no Python spelling for '),
            'line': start.get('line'),
            'column': start.get('column'),
        })
    return gaps


def classify(compiler, directory, path):
    relative = str(path.relative_to(ROOT))
    original = path.read_text(encoding='utf-8')
    result = run(compiler, path, ['--check'])
    entry = {'file': relative, 'directory': directory}
    if result.returncode == 0:
        migrated = result.stdout
        entry['status'] = 'already-python' if migrated == original else 'converted'
        return entry
    codes = {record.get('code') for record in diagnostics(result.stderr)}
    if 'E_MIGRATE_UNSUPPORTED' in codes:
        entry['status'] = 'unsupported'
        entry['constructs'] = unsupported(compiler, path)
        return entry
    entry['status'] = 'failed'
    entry['reason'] = (result.stderr.strip().splitlines() or ['exit %d' % result.returncode])[0]
    return entry


def totals(entries):
    summary = {}
    for entry in entries:
        per = summary.setdefault(entry['directory'], {'converted': 0, 'unsupported': 0, 'already-python': 0, 'failed': 0})
        per[entry['status']] += 1
    overall = {'converted': 0, 'unsupported': 0, 'already-python': 0, 'failed': 0}
    for per in summary.values():
        for key, value in per.items():
            overall[key] += value
    return {'directories': summary, 'all': overall}


def constructs(entries):
    counts = {}
    for entry in entries:
        for gap in entry.get('constructs', []):
            counts[gap['construct']] = counts.get(gap['construct'], 0) + 1
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--output', default=None, help='write the JSON report to this path')
    arguments = parser.parse_args()
    before = {path: path.read_bytes() for _, path in sources()}
    entries = [classify(arguments.compiler, directory, path) for directory, path in sources()]
    report = {
        'version': 'migrate-report-v1',
        'totals': totals(entries),
        'constructs': constructs(entries),
        'files': entries,
    }
    text = json.dumps(report, indent=2, sort_keys=True)
    if arguments.output:
        Path(arguments.output).write_text(text + '\n', encoding='utf-8')
    problems = []
    for path, content in before.items():
        if path.read_bytes() != content:
            problems.append('migration modified %s' % path)
    for entry in entries:
        if entry['status'] == 'failed':
            problems.append('%s: %s' % (entry['file'], entry['reason']))
        if entry['status'] != 'already-python' and any(entry['file'].startswith(root) for root in ALREADY_PYTHON):
            problems.append('%s: Python source did not migrate to itself' % entry['file'])
    print(json.dumps(report['totals'], sort_keys=True))
    if problems:
        for problem in problems:
            print('migrate:', problem, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
