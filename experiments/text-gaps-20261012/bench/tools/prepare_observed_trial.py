#!/usr/bin/env python3
"""New run only: seven-arm trial with a pinned per-cell premeasurement snapshot."""
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def main():
    run_name = sys.argv[sys.argv.index('--run') + 1]
    subprocess.run([sys.executable, '-B', str(HERE / 'prepare_trial.py'), *sys.argv[1:]], check=True)
    run = HERE.parent / 'runs' / run_name
    for path in sorted((run / 'specs').glob('*.json')):
        spec = json.loads(path.read_text())
        snapshot = (run / 'results' / path.name).with_suffix('.host-before.json').resolve()
        spec['files'] = sorted(set(spec['files']) | {str(snapshot), str(Path(__file__).resolve()),
                              str(HERE / 'observe_cell.py'), str(HERE / 'schedule_observed.py')})
        spec['provenance']['host_snapshot'] = {'path': str(snapshot),
             'protocol': 'Read-only process-name/CPU, load, CPU frequency and topology inside exclusive lease before calibration/warmup; no process arguments or state changes.'}
        path.write_text(json.dumps(spec, indent=2) + '\n')


if __name__ == '__main__':
    main()
