"""Collect checked parser traffic only; native build and runs use build-slot.

Run after sourcing ~/.config/mylang/dev-env.sh:
  scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P3/collect.py
The two build commands and frozen inputs are recorded in handoff.md.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SCRATCH = Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3')
COMPILER = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert sha(COMPILER) == '2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329'
result = {'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER),
          'purpose': 'managed allocation traffic; no runtime timing claim', 'arms': {}}
for arm in ('baseline', 'candidate'):
    binary = SCRATCH / f'{arm}-probe'
    raw_path = HERE / f'{arm}-counters.json'
    env = os.environ.copy()
    env['MYLANG_COUNTERS'] = str(raw_path)
    run = subprocess.run([str(binary)], capture_output=True, text=True, env=env, timeout=60)
    assert run.returncode == 0 and run.stdout == '16000\n', (arm, run.returncode, run.stdout, run.stderr)
    raw = json.loads(raw_path.read_text())
    assert raw['version'] == 'mylang-counters-v1'
    totals = raw['totals']
    assert totals['live_bytes_at_exit'] == 0, (arm, totals)
    for key in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'):
        assert totals.get(key, 0) == 0, (arm, key, totals)
    for key in ('retain', 'release', 'unique_test'):
        assert raw['kinds'][key]['count'] == 0, (arm, key, raw['kinds'][key])
    result['arms'][arm] = {
        'command': [str(binary)], 'returncode': run.returncode,
        'stdout': run.stdout, 'stderr': run.stderr,
        'binary_sha256': sha(binary), 'counter_sha256': sha(raw_path),
        'source_sha256': {p.name: sha(p) for p in sorted((HERE / arm).glob('*.my'))},
        'totals': totals,
        'cumulative_allocated_bytes': totals['alloc_bytes'] + totals['realloc_added_bytes'],
        'functions': raw['functions'],
    }
    (HERE / f'{arm}-build.log').write_bytes((SCRATCH / f'{arm}-build.log').read_bytes())
for receipt in ('character-tests', 'character-exhaustive', 'zero-suite'):
    data = json.loads((SCRATCH / f'{receipt}.json').read_text())
    assert data['failed'] == 0 and data['unsupported'] == 0 and data['skipped'] == 0, (receipt, data)
    if receipt == 'zero-suite':
        assert len(data['tests']) == 322 and data['passed'] == 322, data
    (HERE / f'{receipt}.json').write_bytes((SCRATCH / f'{receipt}.json').read_bytes())
a = result['arms']['baseline']
b = result['arms']['candidate']
result['saved'] = {
    key: a['totals'][key] - b['totals'][key]
    for key in ('allocs', 'alloc_bytes', 'reallocs', 'realloc_added_bytes', 'text_copies', 'text_copy_bytes', 'list_copies', 'list_copy_bytes', 'buffer_copies', 'buffer_copy_bytes')
}
result['saved']['cumulative_allocated_bytes'] = a['cumulative_allocated_bytes'] - b['cumulative_allocated_bytes']
(HERE / 'traffic.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result['saved'], indent=2))
