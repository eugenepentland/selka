#!/usr/bin/env python3
"""Seven shuffled CPU8 rounds for the exact four-arm R5 diagnostic spec.

Requires one outer scripts/build-slot.sh build admission; uses prebuilt binaries.
The same spec is consumed by confirm_rows_bound.py for CPU10 confirmation.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import sys

EVENTS = ('instructions', 'cycles', 'branch-misses')
LABELS = {'actual-m0', 'reconstructed', 'probe', 'final'}


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def sample(cell, arm, rows):
    events = ','.join('cpu_core/' + name + '/u' for name in EVENTS)
    command = ['taskset', '-c', '8', 'perf', 'stat', '-x,', '-e', events, '--', *arm['command']]
    proc = subprocess.run(command, capture_output=True, text=True, timeout=600,
                          env={**os.environ, 'LC_ALL': 'C'})
    assert proc.returncode == 0, (command, proc.returncode, proc.stdout, proc.stderr)
    checksum, elapsed = rows.parse_stdout(proc.stdout)
    assert checksum == cell['expected_checksum'], (command, checksum, cell['expected_checksum'])
    counters = {}
    for fields in csv.reader(proc.stderr.splitlines()):
        if len(fields) < 3 or not fields[2].startswith('cpu_core/'):
            continue
        name = fields[2][len('cpu_core/'):].rsplit('/', 1)[0]
        assert name in EVENTS and name not in counters and re.fullmatch(r'[0-9]+', fields[0]), fields
        counters[name] = int(fields[0])
    assert set(counters) == set(EVENTS) and counters['instructions'] > 0 and counters['cycles'] > 0
    return {'status': proc.returncode, 'checksum': checksum, 'elapsed_ns': elapsed,
            **counters, 'command': command, 'stdout': proc.stdout, 'stderr': proc.stderr}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tools', type=Path, required=True)
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    slot = os.readlink('/proc/self/fd/9')
    assert re.fullmatch(r'/run/user/\d+/mylang-slots/build\d+\.lock', slot), slot
    sys.path.insert(0, str(args.tools.resolve()))
    from confirm_rows_bound import prepare
    from rows_mylang import harness
    rows = harness()
    spec = json.loads(args.spec.read_text())
    for cell in spec['cells']:
        assert set(cell['arms']) == LABELS and cell['reference'] == 'probe'
    cells = prepare(spec, rows)
    result = {'complete': False, 'cpu': 8, 'rounds': 7, 'events': EVENTS,
              'spec': str(args.spec.resolve()), 'spec_sha256': digest(args.spec),
              'method': 'All two-cell/four-arm samples shuffled together each round; exact inherited size/iterations/seed and M0 checksum; median counters and per-cell ratios to probe. No startup subtraction for instruction/branch diagnostic.',
              'cells': cells, 'arms': []}
    data = {(cell['row'], label): [] for cell in cells for label in cell['arms']}
    rng = random.Random(20261010)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    for round_no in range(7):
        order = [(cell, label) for cell in cells for label in cell['arms']]
        rng.shuffle(order)
        for cell, label in order:
            data[cell['row'], label].append(sample(cell, cell['arms'][label], rows))
        result['rounds_done'] = round_no + 1
        result['arms'] = [{'program': cell['row'] + '/' + str(cell['size']), 'arm': label,
                           'binary': arm['binary'], 'binary_sha256': arm['sha256'],
                           'samples': data[cell['row'], label],
                           'median': {event: statistics.median(s[event] for s in data[cell['row'], label]) for event in EVENTS}}
                          for cell in cells for label, arm in cell['arms'].items()]
        args.out.write_text(json.dumps(result, indent=1) + '\n')
        print('R5 CPU8 round', round_no + 1, 'of 7 complete', flush=True)
    result['ratios_to_probe'] = {}
    for cell in cells:
        program = cell['row'] + '/' + str(cell['size'])
        arms = {arm['arm']: arm['median'] for arm in result['arms'] if arm['program'] == program}
        result['ratios_to_probe'][program] = {
            label: {event: counts[event] / arms['probe'][event] if arms['probe'][event] else None for event in EVENTS}
            for label, counts in arms.items()}
        for arm in cell['arms'].values():
            assert digest(arm['binary']) == arm['sha256']
    assert digest(args.spec) == result['spec_sha256']
    result['complete'] = True
    args.out.write_text(json.dumps(result, indent=1) + '\n')


if __name__ == '__main__':
    main()
