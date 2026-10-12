#!/usr/bin/env python3
"""Source-check fourteen reserved fixtures, retaining explicit failure evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--phase', required=True)
args = parser.parse_args()
report = HERE / (args.phase + '.json')
assert not report.exists(), 'choose a new evidence phase'
mirror = ROOT / '.tmp/memory-closeout/A04/additional-migrations' / args.phase
mirror.mkdir(parents=True)
rows = []
for original in json.loads((HERE / 'originals.json').read_text())['sources']:
    source = ROOT / original['source']
    checked = mirror / source.name
    text = source.read_text()
    if not re.search(r'^(?:public )?func main\(', text, re.M):
        text += '\n\nfunc main() -> int:\n    return 0\n'
    checked.write_text(text)
    command = [str(args.compiler), 'check', str(checked), '--experimental-zero-rc', '--cache-dir', str(mirror / 'cache')]
    ran = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, timeout=120)
    row = dict(original, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), command=command,
               status=ran.returncode, stdout=ran.stdout, stderr=ran.stderr)
    rows.append(row)
    print(source.name, ran.returncode, ran.stderr.splitlines()[0] if ran.stderr else '', flush=True)
report.write_text(json.dumps({'compiler': str(args.compiler), 'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
                             'rows': rows, 'passed': sum(row['status'] == 0 for row in rows), 'total': len(rows)}, indent=2) + '\n')
