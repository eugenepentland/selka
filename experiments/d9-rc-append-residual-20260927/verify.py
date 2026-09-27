#!/usr/bin/env python3
"""Verify static path attribution against immutable measured binary identities."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--live', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent
identity = json.loads((root / 'identity.json').read_text())
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

assembly = {}
if args.live:
    assert sha(identity['input']['path']) == identity['input']['sha256']
    for key, binary in identity['binaries'].items():
        assert sha(binary['path']) == binary['sha256'], key
        assert sha(binary['path'] + '.qbe-manifest.json') == binary['manifest_sha256'], key
        assembly[key] = subprocess.check_output(
            ['objdump', '-d', '--no-show-raw-insn', binary['path']], text=True).splitlines()
for row in identity['loops']:
    saved = (root / row['file']).read_text().splitlines()
    assert len(saved) == row['instructions']
    assert row['instructions'] / row['elements_per_iteration'] == row['per_element']
    assert all(not re.match(r'\s*[0-9a-f]+:\s+call\b', line) for line in saved)
    if args.live:
        ranges = [(int(a, 16), int(b, 16)) for a, b in row['ranges']]
        selected = []
        for line in assembly[row['mode'] + '-' + row['backend']]:
            match = re.match(r'\s*([0-9a-f]+):\s+(\S+)', line)
            if match and any(a <= int(match[1], 16) <= b for a, b in ranges):
                selected.append(line)
        assert selected == saved, row['file']
for key, median in identity['measured_instruction_medians'].items():
    mode, backend = key.split('-')
    cost = sum(row['per_element'] for row in identity['loops']
               if row['mode'] == mode and row['backend'] == backend)
    common = int(cost * identity['input']['elements'])
    assert 0 <= median - common < median * 0.02
    print(f'{key}: common={common:,} measured={median:,} remainder={median-common:,}')
print('PASS: eight exact common-path slices; static attribution agrees with completed hardware observations')
