#!/usr/bin/env python3
"""Measure all 45 parity arms, 46 rows, 26 Lox cells and 34 EDA designs on CPU 8.

This uses already built plain ce.py binaries. Run through a build slot to keep
CPU-10 quiet sessions exclusive. Output correctness is a separate mandatory gate.
"""
import argparse
import json
from pathlib import Path
import random
import statistics

import ce
import pstat


def arms_for(tag):
    bins = ce.CACHE / 'bin' / tag
    arms = []
    for name in ce.PARITY:
        arms.append({'program': 'parity/' + name, 'arm': tag, 'argv': [str(bins / ('parity-' + name + '-plain'))]})
    registry = ce.row_registry()
    for name, cell in ce.vp3_cells('rows').items():
        arms.append({'program': 'rows/' + name.removeprefix('row-'), 'arm': tag,
                     'argv': [str(bins / (name + '-plain')), str(cell['size']), str(cell['iterations']), str(registry.SEED)]})
    sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
    for name, counts in sizes.items():
        if name.startswith('_'):
            continue
        for engine in ('vm', 'tree'):
            script = ce.lox_script(name, counts[engine])
            arms.append({'program': f'lox/{engine}/{name}', 'arm': tag, 'cwd': str(ce.LOX),
                         'argv': [str(bins / 'lox-plain'), '--engine=' + engine, str(script)]})
    manifest = json.loads((ce.EDA / 'golden/manifest.json').read_text())['cases']
    for case in manifest:
        out = ce.CACHE / 'perf-eda-out' / tag / case['id']
        out.mkdir(parents=True, exist_ok=True)
        arms.append({'program': 'eda/' + case['id'], 'arm': tag, 'cwd': str(ce.EDA),
                     'argv': [str(bins / 'eda-plain'), '--model', f"golden/cases/{case['id']}/model.sexp",
                              '--project-dir', f"golden/projects/{case['project']}", '--out-dir', str(out), *case['flags']]})
    assert len(arms) == 45 + 46 + 26 + 34, len(arms)
    for arm in arms:
        if not Path(arm['argv'][0]).is_file():
            raise RuntimeError('missing binary: ' + arm['argv'][0])
    return arms


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tags', required=True, help='one tag or comma-separated interleaved tags')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    arms = [arm for tag in args.tags.split(',') for arm in arms_for(tag)]
    result = {'cpu': 8, 'rounds': args.rounds, 'events': pstat.EVENTS, 'arms': []}
    samples = {arm['program'] + '|' + arm['arm']: [] for arm in arms}
    rng = random.Random(20261009)
    for round_index in range(args.rounds):
        order = list(arms)
        rng.shuffle(order)
        for index, arm in enumerate(order):
            sample = pstat.run_once(arm, 8)
            if sample['status'] or not isinstance(sample.get('instructions'), int):
                raise RuntimeError(f'invalid perf sample: {arm}: {sample}')
            samples[arm['program'] + '|' + arm['arm']].append(sample)
            if (index + 1) % 25 == 0:
                print(f'round {round_index + 1}: {index + 1}/{len(order)}', flush=True)
        result['rounds_done'] = round_index + 1
        result['arms'] = []
        for arm in arms:
            rows = samples[arm['program'] + '|' + arm['arm']]
            medians = {}
            for event in pstat.EVENTS:
                values = [row[event] for row in rows if isinstance(row.get(event), int)]
                medians[event] = statistics.median(values) if values else None
            result['arms'].append({**arm, 'median': medians, 'samples': rows})
        args.out.write_text(json.dumps(result, indent=1) + '\n')
    print(f'complete: {len(arms)} arms, {args.rounds} rounds', flush=True)


if __name__ == '__main__':
    main()
