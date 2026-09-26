#!/usr/bin/env python3
"""Check successful capability producers and partial readlines trap ownership."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--backend', choices=('qbe', 'llvm'), required=True)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--cache', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
rows = []
for source, code in [('tests/lang/rc_capability_values.my', 0),
                     ('experiments/d9-rc-arena-probes-20260926/capability_trap.my', 1)]:
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(args.compiler.resolve()),
               'build', str(ROOT / source), '--backend', args.backend, '--mode', 'ReleaseFast',
               '--rc-runtime=stats', '--cache-dir=' + str(args.cache.resolve()), '--max-memory=512M', '--run']
    done = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=300)
    counts = [json.loads(line.removeprefix('MYLANG_RC_COUNTS '))
              for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    row = dict(source=source, sha256=hashlib.sha256((ROOT / source).read_bytes()).hexdigest(),
               command=command, exit=done.returncode, stdout=done.stdout, stderr=done.stderr, counts=counts)
    rows.append(row)
    args.output.write_text(json.dumps(dict(backend=args.backend, rows=rows), indent=2) + '\n')
    assert done.returncode == code and not done.stdout and len(counts) == 1, row
    count = counts[0]
    assert not count['saturated'] and count['heap_allocate'] == count['retire'], row
    assert count['heap_allocate'] + count['owner_acquire'] == count['owner_release'], row
    assert count['hold_acquire'] == count['hold_release'], row
    if code: assert 'R_FILE' in done.stderr, row
    print(args.backend, source, count, flush=True)
