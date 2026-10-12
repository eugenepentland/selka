#!/usr/bin/env python3
"""Exploratory three-arm five-round screen; never substitutes for final evidence."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BENCH = HERE.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--run', required=True)
p.add_argument('--case', choices=['string_split', 'json_transform', 'csv_aggregate'], required=True)
p.add_argument('--candidate-runtime', required=True)
p.add_argument('--candidate-counted', required=True)
p.add_argument('--candidate-manifest', required=True)
a = p.parse_args()
subprocess.run([sys.executable, '-B', str(HERE / 'prepare_candidate.py'), '--run', a.run,
                '--candidate-runtime', a.candidate_runtime, '--candidate-counted', a.candidate_counted,
                '--candidate-manifest', a.candidate_manifest], check=True)
run = BENCH / 'runs' / a.run
fastest = 'zig-fast' if a.case == 'csv_aggregate' else 'rust'
for path in (run / 'specs').glob('*.json'):
    spec = json.loads(path.read_text())
    if spec['case'] != a.case:
        path.unlink()  # Unused specs in this newly reserved run, before any timing.
        continue
    baseline = BENCH / f"runs/baseline-001/results/{path.name}"
    spec['arms'] = {name: spec['arms'][name] for name in ('checked-baseline', 'checked-candidate', fastest)}
    spec['qualified_counted_inputs'] = spec.pop('counted')
    spec['counted'] = {}
    spec.update(warmups=1, rounds=5, rss_rounds=0, screening=True,
                screen_iterations=json.loads(baseline.read_text())['iterations'], screen_iteration_source=str(baseline))
    spec['files'] += [str(HERE / 'measure_screen.py'), str(HERE / 'screen.py'), str(baseline)]
    path.write_text(json.dumps(spec, indent=2) + '\n')
(run / 'results').mkdir()
for path in sorted((run / 'specs').glob('*.json')):
    with (run / 'results' / (path.stem + '.log')).open('w') as log:
        subprocess.run([str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable, '-B',
                        str(HERE / 'measure_screen.py'), str(path), str(run / 'results' / path.name), '--cpu', '8'],
                       stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, check=True)
print('SCREEN COMPLETE', run)
