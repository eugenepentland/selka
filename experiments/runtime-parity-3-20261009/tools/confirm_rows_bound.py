#!/usr/bin/env python3
"""Confirm R5 against its no-barrier probes with the inherited row method.

The spec contains a cells list: row, size, reference, and arms mapping labels to
{binary, sha256}. Each arm is prebuilt. Three batches retain three startup
samples and seven shuffled rounds, then take median within-batch ratios.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import statistics

from quiet import quiet
from rows_mylang import harness
from timing_data import read

ROOT = Path(__file__).resolve().parents[3]


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare(spec, rows):
    baseline = read(ROOT / 'experiments/runtime-parity-3-20261009/M0/rows-base-1.json.gz')
    result = []
    assert {(cell['row'], cell['size']) for cell in spec['cells']} == {
        ('result_propagate', 4096), ('option_handle', 64)}
    assert len(spec['cells']) == 2
    for cell in spec['cells']:
        row, size = cell['row'], cell['size']
        unit = rows.UNITS[row][1]
        iterations = rows.UNITS[row][2 if size == 4096 else 3]
        original = baseline['rows'][row]['sizes'][str(size)]
        assert original['iterations'] == iterations
        assert cell['reference'] in cell['arms'] and 'final' in cell['arms']
        assert len(cell['arms']) >= 2
        arms = {}
        for label, arm in cell['arms'].items():
            assert digest(arm['binary']) == arm['sha256'], (row, label)
            arms[label] = {**arm,
                           'startup_command': [arm['binary'], str(size), '1', str(rows.SEED)],
                           'command': [arm['binary'], str(size), str(iterations), str(rows.SEED)]}
        starts = {run['checksum'] for arm in original['configurations'].values() for run in arm['startup']}
        assert len(starts) == 1
        result.append({**cell, 'arms': arms, 'iterations': iterations, 'unit': unit,
                       'units': size * iterations if unit == 'element' else iterations,
                       'expected_checksum': original['checksum'], 'expected_startup_checksum': starts.pop()})
    return result


def measure(cell, rows, rng):
    startup = {label: [rows.sample(arm['startup_command']) for _ in range(3)]
               for label, arm in cell['arms'].items()}
    runs = {label: [] for label in cell['arms']}
    for values in startup.values():
        assert all(run['checksum'] == cell['expected_startup_checksum'] for run in values)
    for _ in range(7):
        labels = list(runs)
        rng.shuffle(labels)
        for label in labels:
            run = rows.sample(cell['arms'][label]['command'])
            assert run['checksum'] == cell['expected_checksum'], (cell['row'], label)
            runs[label].append(run)
    arms = {}
    for label in runs:
        value = (statistics.median(run['cycles'] for run in runs[label]) -
                 statistics.median(run['cycles'] for run in startup[label])) / cell['units']
        assert math.isfinite(value) and value > 0
        arms[label] = {'cycles_per_unit': value, 'startup': startup[label], 'runs': runs[label]}
    reference = arms[cell['reference']]['cycles_per_unit']
    return {'arms': arms, 'ratios': {label: arm['cycles_per_unit'] / reference for label, arm in arms.items()}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    rows = harness()
    cells = prepare(json.loads(args.spec.read_text()), rows)
    result = {'complete': False, 'cpu': 10, 'batches': 3, 'rounds': 7, 'startup_samples': 3,
              'method': 'inherited sample/startup subtraction; median of within-batch ratios',
              'cells': cells, 'samples': []}
    if args.prepare_only:
        result['prepare_only'] = True
        args.out.write_text(json.dumps(result, indent=1) + '\n')
        return
    rng = random.Random(20261010)
    with quiet():
        result['load_start'] = os.getloadavg()
        for _ in range(3):
            result['samples'].append({cell['row'] + '/' + str(cell['size']): measure(cell, rows, rng) for cell in cells})
            args.out.write_text(json.dumps(result, indent=1) + '\n')
        result['load_end'] = os.getloadavg()
    for cell in cells:
        for label, arm in cell['arms'].items():
            assert digest(arm['binary']) == arm['sha256'], (cell['row'], label)
    result['ratios'] = {
        key: {label: statistics.median(batch[key]['ratios'][label] for batch in result['samples'])
              for label in result['samples'][0][key]['ratios']}
        for key in result['samples'][0]}
    result['complete'] = True
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    print(json.dumps(result['ratios']))


if __name__ == '__main__':
    main()
