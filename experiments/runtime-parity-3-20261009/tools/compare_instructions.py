#!/usr/bin/env python3
"""Compare complete CPU-8 corpus receipts and expose every >1.03 instruction ratio."""
import argparse
import gzip
import json
from pathlib import Path
import statistics

import ce


def expected_programs():
    names = {'parity/' + name for name in ce.PARITY}
    names.update('rows/' + name for name in ce.row_sources())
    sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
    names.update(f'lox/{engine}/{name}' for name in sizes if not name.startswith('_')
                 for engine in ('vm', 'tree'))
    cases = json.loads((ce.EDA / 'golden/manifest.json').read_text())['cases']
    names.update('eda/' + case['id'] for case in cases)
    assert len(names) == 151
    return names


def receipt(path, tag):
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt') as stream:
        data = json.load(stream)
    assert data['cpu'] == 8 and data['rounds'] >= 3
    assert data['rounds_done'] == data['rounds'], 'incomplete instruction run'
    arms = [arm for arm in data['arms'] if tag is None or arm['arm'] == tag]
    names = [arm['program'] for arm in arms]
    assert len(names) == len(set(names)), 'select one tag per input receipt'
    assert set(names) == expected_programs(), 'missing or extra corpus cells'
    result = {}
    for arm in arms:
        samples = arm['samples']
        assert len(samples) == data['rounds']
        assert all(sample['status'] == 0 for sample in samples), arm['program']
        for event in ('instructions', 'cycles'):
            assert all(isinstance(sample.get(event), int) and sample[event] > 0
                       for sample in samples), (arm['program'], event)
            assert statistics.median(sample[event] for sample in samples) == arm['median'][event]
        result[arm['program']] = arm
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--base-tag')
    parser.add_argument('--candidate-tag')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--markdown', type=Path, required=True)
    args = parser.parse_args()
    base = receipt(args.base, args.base_tag)
    candidate = receipt(args.candidate, args.candidate_tag)
    cells = {}
    for name in sorted(base):
        ratios = {}
        for event in ('instructions', 'cycles', 'branch-misses'):
            before, after = base[name]['median'].get(event), candidate[name]['median'].get(event)
            ratios[event] = after / before if before and after is not None else None
        cells[name] = {'base': base[name]['median'], 'candidate': candidate[name]['median'],
                       'ratios': ratios, 'instruction_gate_met': ratios['instructions'] <= 1.03}
    regressions = [name for name, cell in cells.items() if not cell['instruction_gate_met']]
    result = {'base_receipt': str(args.base), 'candidate_receipt': str(args.candidate),
              'cpu': 8, 'instruction_limit': 1.03, 'complete': True,
              'instruction_gate_met': not regressions, 'regressions': regressions, 'cells': cells}
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    lines = ['# Complete corpus instruction comparison', '',
             f'{len(cells)} cells; {len(regressions)} above 1.03× instructions. Ratios are candidate/base.', '',
             'Cycles and branch misses are diagnostic; CPU-10 wall time at X is binding. '
             'Cycle ratios from separate sessions are not an exit measurement.', '',
             '| cell | instructions | cycles | branch misses | instruction gate |',
             '|---|---:|---:|---:|---|']
    for name, cell in cells.items():
        values = ['—' if value is None else f'{value:.4f}' for value in cell['ratios'].values()]
        lines.append('| ' + ' | '.join([name, *values, 'met' if cell['instruction_gate_met'] else 'over']) + ' |')
    args.markdown.write_text('\n'.join(lines) + '\n')
    print(f'{len(cells)} complete cells; {len(regressions)} instruction regressions', flush=True)
    raise SystemExit(1 if regressions else 0)


if __name__ == '__main__':
    main()
