#!/usr/bin/env python3
"""Review X's >1.03 cells on CPU 8 using the exact timed guest binaries.

Run through scripts/build-slot.sh build to exclude CPU-10 sessions. The row
commands preserve each flagged size and iteration count, including size 64;
the 151-cell corpus receipt alone cannot diagnose both row sizes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics

import ce
import pstat
import timing_data as td


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def parity_arm(data, key, tag):
    _, name, label = key.split('/')
    arm = data['benchmarks'][name]['arms'][('base-' if tag == 'base' else '') + label]
    command = arm['build']['cmd']
    if command[0] == 'retained-build':
        binary = command[1]
    else:
        binary = command[command.index('-o') + 1]
    return {'argv': [binary]}


def lox_arm(data, key, tag):
    _, engine, name = key.split('/')
    count = json.loads((ce.LOX / 'bench/sizes.json').read_text())[name][engine]
    script = ce.lox_script(name, count)
    label = 'mylang-base:release' if tag == 'base' else 'mylang:release'
    return {'argv': [*data['commands'][label], '--engine=' + engine, str(script)], 'cwd': str(ce.LOX)}


def eda_arm(data, key, tag):
    name = key.removeprefix('eda/')
    manifest = json.loads((ce.EDA / 'golden/manifest.json').read_text())['cases']
    case = next(case for case in manifest if case['id'] == name)
    out = ce.CACHE / 'review-eda-out' / tag / name
    out.mkdir(parents=True, exist_ok=True)
    label = 'mylang-base' if tag == 'base' else 'mylang-final'
    return {'argv': [data['binaries'][label], '--model', f'golden/cases/{name}/model.sexp',
                     '--project-dir', f"golden/projects/{case['project']}", '--out-dir', str(out), *case['flags']],
            'cwd': str(ce.EDA)}


def rows_arm(data, key, tag):
    _, name, size = key.split('/')
    label = 'old core --release' if tag == 'base' else 'new core release'
    arm = data['rows'][name]['sizes'][size]['configurations'][label]
    commands = [run['command'] for run in arm['runs']]
    assert all(command == commands[0] for command in commands)
    command = commands[0]
    return {'argv': command[command.index('cpu_core/cycles/u') + 1:]}


def arms_for(gap, inputs):
    builders = {'parity': ('parity-pair', parity_arm), 'lox': ('lox-runtime', lox_arm),
                'eda': ('eda-runtime', eda_arm), 'rows': ('all46-1', rows_arm)}
    arms = []
    for key in gap['above_1_03']:
        name, builder = builders[key.split('/')[0]]
        for tag in ('base', 'final'):
            arm = {'program': key, 'arm': tag, **builder(inputs[name], key, tag)}
            arm['binary_sha256'] = digest(arm['argv'][0])
            arms.append(arm)
    return arms


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gap', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    assert args.rounds >= 3
    gap = td.read(args.gap)
    inputs = {}
    for name, identity in gap['inputs'].items():
        assert td.identity(identity['path']) == identity, name
        inputs[name] = td.read(identity['path'])
    arms = arms_for(gap, inputs)
    if args.prepare_only:
        args.out.write_text(json.dumps(arms, indent=1) + '\n')
        print(f'prepared {len(arms)} exact timed arms; no samples collected')
        return
    admission = Path(os.readlink('/proc/self/fd/9'))
    assert admission.name.startswith('build') and admission.suffix == '.lock', 'launch through scripts/build-slot.sh build'
    samples = {(arm['program'], arm['arm']): [] for arm in arms}
    rng = random.Random(20261010)
    for round_index in range(args.rounds):
        order = list(arms)
        rng.shuffle(order)
        for arm in order:
            sample = pstat.run_once(arm, 8)
            assert sample['status'] == 0, (arm['program'], sample)
            assert all(isinstance(sample.get(event), int) and sample[event] >= 0
                       for event in ('instructions', 'cycles', 'branch-misses')), (arm['program'], sample)
            assert sample['instructions'] > 0 and sample['cycles'] > 0
            samples[arm['program'], arm['arm']].append(sample)
        print(f'CPU-8 review round {round_index + 1}/{args.rounds}: {len(arms)} arms', flush=True)
    result = []
    for arm in arms:
        assert digest(arm['argv'][0]) == arm['binary_sha256'], arm['program']
        rows = samples[arm['program'], arm['arm']]
        medians = {event: statistics.median(row[event] for row in rows) for event in pstat.EVENTS
                   if all(isinstance(row.get(event), int) for row in rows)}
        result.append({**arm, 'samples': rows, 'median': medians})
    args.out.write_text(json.dumps({'cpu': 8, 'rounds': args.rounds, 'complete': True,
                                    'gap': td.identity(args.gap), 'review_cells': gap['above_1_03'],
                                    'events': pstat.EVENTS, 'arms': result}, indent=1) + '\n')
    print(f'{len(gap["above_1_03"])} cells reviewed; no automatic noise classification')


if __name__ == '__main__':
    main()
