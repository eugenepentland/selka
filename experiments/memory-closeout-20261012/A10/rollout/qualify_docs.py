#!/usr/bin/env python3
"""Qualify draft blocks in bounded batches; never publish drafts or change sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--start', type=int, default=0)
parser.add_argument('--limit', type=int, default=10)
parser.add_argument('--default', action='store_true')
parser.add_argument('--document', type=Path, action='append', help='Draft document; repeat to form an explicit corpus')
args = parser.parse_args()
base = Path(__file__).resolve().parent
compiler = args.compiler.resolve()
compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
blocks = []
for path in args.document or (base / 'ownership-C2.md', base / 'managed-memory-C2.md'):
    path = path.resolve()
    source = path.read_text()
    for match in re.finditer(r'^```mylang\n(.*?)^```\s*$', source, re.MULTILINE | re.DOTALL):
        blocks.append(dict(path=str(path), line=source.count('\n', 0, match.start()) + 1, source=match.group(1), sha256=hashlib.sha256(match.group(1).encode()).hexdigest()))
selected = blocks[args.start:args.start + args.limit]
if not selected:
    raise ValueError('empty documentation selection cannot qualify')
def project(block):
    found = re.search(r'^# doc: project (\S+)\s*$', block['source'], re.MULTILINE)
    return found.group(1) if found else None
projects = {project(block) for block in selected} - {None}
for name in projects:
    if sum(project(block) == name for block in selected) != sum(project(block) == name for block in blocks):
        raise ValueError('batch splits documentation project: ' + name)
expected_units = sum(project(block) is None for block in selected) + len(projects)
scratch = args.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
(scratch / 'docs').mkdir(exist_ok=True)
(scratch / 'README.md').write_text('\n\n'.join('```mylang\n' + block['source'] + '```' for block in selected) + '\n')
report_path = scratch / 'report.json'
command = [str(compiler), 'doctest', str(scratch), '--jobs', '1', '--report', str(report_path)]
if not args.default:
    command.append('--experimental-zero-rc')
run = subprocess.run(command, capture_output=True, text=True, timeout=120, env=dict(os.environ, MYL_CORE_LEAKCHECK='1'))
if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_hash:
    raise RuntimeError('compiler changed during documentation qualification')
raw = json.loads(report_path.read_text()) if report_path.exists() else None
totals = raw.get('totals', {}) if raw else {}
complete = raw is not None and raw['compiler_sha256'] == compiler_hash and totals.get('run', 0) + totals.get('checked', 0) == expected_units and len(raw['units']) == expected_units and sum(item['blocks'] for item in raw['files'].values()) == len(selected) and all(totals.get(key, -1) == 0 for key in ['skipped', 'mistagged', 'failed'])
report = dict(compiler=str(compiler), compiler_sha256=compiler_hash, default=args.default, total_blocks=len(blocks), expected_units=expected_units, selected_blocks=selected, argv=command, status=run.returncode, stdout=run.stdout, stderr=run.stderr, doctest_report=raw, success=run.returncode == 0 and complete)
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(run.stdout, end='')
print(run.stderr, end='')
raise SystemExit(0 if report['success'] else 1)
