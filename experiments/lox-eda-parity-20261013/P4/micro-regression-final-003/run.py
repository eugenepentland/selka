#!/usr/bin/env python3
"""Explicitly start the prepared fresh campaign, using unchanged benchmark tools."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location('p4_micro_prepare', HERE / 'prepare.py')
prepare = importlib.util.module_from_spec(loader)
loader.loader.exec_module(prepare)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start-measurement', action='store_true', required=True)
    args = parser.parse_args()
    assert args.start_measurement
    pins = json.loads((HERE / 'inputs.json').read_text())
    prepare.validate_original(pins)
    assert len(list((HERE / 'specs').glob('*.json'))) == 6
    assert not (HERE / 'results').exists() and not (HERE / 'reports').exists(), 'fresh destinations required'
    commands = [[sys.executable, '-B', str(prepare.TOOLS / 'schedule_observed.py'), str(HERE / 'specs'), str(HERE / 'results'), '--cpu', '8'],
                [sys.executable, '-B', str(prepare.TOOLS / 'report.py'), str(HERE), str(HERE / 'reports'), '--check-artifacts']]
    prepare.write_new(HERE / 'measurement-commands.json', commands)
    for command in commands:
        subprocess.run(command, cwd=prepare.ROOT, check=True)
    prepare.validate_original(pins)


if __name__ == '__main__':
    main()
