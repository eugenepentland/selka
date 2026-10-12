#!/usr/bin/env python3
"""Add read-only host context around the calibrated application measurer."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OBSERVER = ROOT / 'experiments/text-gaps-20261012/bench/tools/observe_cell.py'


def main():
    spec, output = map(Path, sys.argv[1:3])
    cpu = int(sys.argv[sys.argv.index('--cpu') + 1])
    loader = importlib.util.spec_from_file_location('host_observer', OBSERVER)
    observer = importlib.util.module_from_spec(loader)
    loader.loader.exec_module(observer)
    before = output.with_suffix('.host-before.json')
    assert not before.exists() and not output.exists()
    before.write_text(json.dumps(observer.snapshot(cpu), indent=2) + '\n')
    subprocess.run([sys.executable, '-B', str(HERE / 'measure.py'), *sys.argv[1:]], check=True)
    document = json.loads(output.read_text())
    document['host_snapshot'] = {'path': str(before), 'sha256': hashlib.sha256(before.read_bytes()).hexdigest(),
                                 'observer_sha256': hashlib.sha256(OBSERVER.read_bytes()).hexdigest()}
    document['observation_wrapper_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    output.write_text(json.dumps(document, indent=2) + '\n')


if __name__ == '__main__':
    main()
