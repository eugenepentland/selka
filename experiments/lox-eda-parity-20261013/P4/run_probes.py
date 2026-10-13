#!/usr/bin/env python3
"""Bounded P4 allocation probes; these are not full benchmark/timing results."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
arm, binary = sys.argv[1:]
binary = Path(binary).resolve()
dest = HERE / arm
dest.mkdir(exist_ok=False)
results = {'arm': arm, 'binary': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
           'label': 'tiny bounded allocation probes; no runtime or RSS claim', 'probes': []}
for script in sorted((HERE / 'probes').glob('*.lox')):
    for stress in (False, True):
        name = script.stem + ('-stress' if stress else '')
        counters = dest / (name + '.counters.json')
        command = [str(binary), '--engine=tree', *(['--gc-stress'] if stress else []), str(script)]
        env = dict(os.environ, MYLANG_COUNTERS=str(counters), MYL_CORE_LEAKCHECK='1')
        run = subprocess.run(command, env=env, capture_output=True, timeout=20)
        (dest / (name + '.stdout')).write_bytes(run.stdout)
        (dest / (name + '.stderr')).write_bytes(run.stderr)
        expected = b'10100\n'
        assert run.returncode == 0 and run.stdout == expected, (name, run.returncode, run.stdout, run.stderr)
        data = json.loads(counters.read_text())
        totals, kinds = data['totals'], data['kinds']
        assert totals['live_bytes_at_exit'] == 0
        assert all(totals[k] == 0 for k in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'))
        assert all(kinds[k]['count'] == 0 for k in ('retain', 'release', 'unique_test'))
        results['probes'].append({'name': name, 'command': command, 'script_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
                                 'returncode': run.returncode, 'totals': totals,
                                 'allocation_traffic_bytes': totals['alloc_bytes'] + totals['realloc_added_bytes']})
(dest / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps({p['name']:p['allocation_traffic_bytes'] for p in results['probes']}, indent=2))
