#!/usr/bin/env python3
"""One exclusive timing lease per immutable benchmark spec."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('specs', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--cpu', type=int, default=8)
p.add_argument('--resume', action='store_true')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
specs = sorted(a.specs.glob('*.json'))
assert specs
for spec in specs:
    result = a.output / spec.name
    if result.exists():
        assert a.resume, 'existing result needs explicit --resume'
        assert json.loads(result.read_text())['spec'] == json.loads(spec.read_text())
        print('verified existing', spec.stem, flush=True)
        continue
    print('measuring', spec.stem, flush=True)
    with (a.output / (spec.stem + '.log')).open('w') as log:
        subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable,
                        '-B', str(Path(__file__).with_name('measure.py')), str(spec),
                        str(result), '--cpu', str(a.cpu)], cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
print('COMPLETE', len(specs), 'cells', flush=True)
