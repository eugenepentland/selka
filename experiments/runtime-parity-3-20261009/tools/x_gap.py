#!/usr/bin/env python3
"""Build X's complete paired gap table and mandatory >1.03 review queue.

Expected inputs: parity-pair.json[.gz], lox-runtime.json[.gz],
eda-runtime.json[.gz], all46-{1,2,3}.json[.gz]. Next-lever notes are supplied
separately after the coordinator has reviewed the final implementation.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import timing_data as td

AREA = Path(__file__).resolve().parents[1]
REFERENCES = ('zig-safe', 'rust-checked', 'zig-fast', 'rust', 'go')


def ratios(arms, own, field):
    return {key: arms[own][field] / arms[key][field] for key in REFERENCES if key in arms}


def cell(m0, base, final, relative, limit, perf_program):
    available = [final[key] for key in ('zig-safe', 'rust-checked') if key in final]
    return {'m0': m0, 'paired_base': base, 'final': final, 'final_over_base': relative,
            'limit': limit, 'available_gate': ('met' if max(available) <= limit else 'over') if available else 'unavailable',
            'review_required': relative > 1.03, 'perf_program': perf_program}


def parity(base, paired):
    assert set(base['benchmarks']) == set(paired['benchmarks'])
    assert paired['cpu'] == 10 and paired['rounds'] == 9 and paired['warmups'] == 2
    assert paired['rp3_pair']['base_source'] == '41ed360fb361c49938488ad111795bad8a726b73'
    result = {}
    for name, before in base['benchmarks'].items():
        arms = paired['benchmarks'][name]['arms']
        for label, arm in before['arms'].items():
            if arm['lang'] != 'my':
                continue
            for own in (label, 'base-' + label):
                assert arms[own]['matches_expected'] and arms[own]['status'] == 0
                assert len(arms[own]['wall']) == 9 and td.positive(arms[own]['wall_median'])
            result['parity/' + name + '/' + label] = cell(
                ratios(before['arms'], label, 'wall_median'), ratios(arms, 'base-' + label, 'wall_median'),
                ratios(arms, label, 'wall_median'), arms[label]['wall_median'] / arms['base-' + label]['wall_median'],
                1.1, 'parity/' + Path(arm['src']).stem)
    assert len(result) == 45
    return result


def lox(base, paired):
    old, new = td.lox(base, False), td.lox(paired, True)
    assert set(old) == set(new)
    labels = {'zig-safe': 'zig:release-safe', 'zig-fast': 'zig:release', 'rust': 'rust:release', 'go': 'go:release'}
    result = {}
    for name, arms in new.items():
        program, engine = name.split('/')
        assert engine in ('vm', 'tree')
        comparisons = [{key: data[own]['median_s'] / data[label]['median_s'] for key, label in labels.items()}
                       for data, own in [(old[name], 'mylang:release'), (arms, 'mylang-base:release'), (arms, 'mylang:release')]]
        key = f'lox/{engine}/{program}'
        result[key] = cell(*comparisons, arms['mylang:release']['median_s'] / arms['mylang-base:release']['median_s'],
                           1.5 if engine == 'vm' else 1.1, key)
    return result


def eda(base, paired):
    old, new = td.eda(base, False), td.eda(paired, True)
    assert set(old) == set(new)
    return {'eda/' + name: cell(ratios(old[name], 'mylang-base', 'median_s'), ratios(arms, 'mylang-base', 'median_s'),
                               ratios(arms, 'mylang-final', 'median_s'), arms['mylang-final']['median_s'] / arms['mylang-base']['median_s'],
                               1.1, 'eda/' + name) for name, arms in new.items()}


def rows(base, paired):
    old, new = td.row_ratios(base), td.row_ratios(paired)
    assert set(old) == set(new)
    result = {}
    for name, arm in new.items():
        value = cell(old[name]['final'], arm['base'], arm['final'], arm['final_over_base'], 1.1, 'rows/' + name.split('/')[0])
        result['rows/' + name] = {**value, 'batch_ratios': arm['batch_ratios']}
    return result


def render(cells, groups, notes, out):
    lines = ['# X gap — final against M0 and paired base', '',
             'Final/base uses base and final interleaved within each CPU-10 session. M0 columns retain the original baseline comparison. '
             'Rows preserve the median of three within-batch ratios after startup subtraction; all other cells use their session medians.', '',
             'A dash denotes an unavailable reference. Lox, EDA and rows have plain Rust references; they do not establish a checked-Rust result. '
             'The available gate tests Zig RS and checked Rust wherever present. Reference-free binary_trees_recursive remains unavailable. '
             'Every final/base result above 1.03 requires the separate CPU-8 review.', '']
    for group in ('parity', 'lox', 'eda', 'rows'):
        lines += ['## ' + group.capitalize(), '',
                  '| cell | M0/RS | M0/checked | paired base/RS | final/base | final/RS | final/checked | final/RF | final/Rust | final/Go | limit | available gate |',
                  '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|']
        for key, value in sorted(cells.items()):
            if not key.startswith(group + '/'):
                continue
            values = [value['m0'].get('zig-safe'), value['m0'].get('rust-checked'), value['paired_base'].get('zig-safe'),
                      value['final_over_base'], *(value['final'].get(ref) for ref in REFERENCES), value['limit']]
            lines.append('| ' + ' | '.join([key.removeprefix(group + '/'), *['—' if v is None else f'{v:.4f}' for v in values], value['available_gate']]) + ' |')
        lines += ['', 'Geomeans: `' + json.dumps(groups[group], sort_keys=True) + '`.', '']
    lines += ['## Remaining cells and next levers', '']
    for key, value in sorted(cells.items()):
        if value['available_gate'] != 'met':
            lines.append(f"- **{key}** ({value['available_gate']}): {notes.get(key, 'Coordinator review pending; no final next-lever claim yet.')}")
    out.write_text('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--require-notes', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    inputs = {name: args.input / (name + '.json') for name in ('parity-pair', 'lox-runtime', 'eda-runtime', 'all46-1', 'all46-2', 'all46-3')}
    identities = {name: td.identity(path) for name, path in inputs.items()}
    subprocess.run([sys.executable, str(AREA / 'tools/validate_parity.py'), identities['parity-pair']['path'], '--pair'], check=True)
    m0 = AREA / 'M0'
    cells = parity(td.read(m0 / 'parity-base.json'), td.read(inputs['parity-pair']))
    cells.update(lox(td.read(m0 / 'lox-base.json'), td.read(inputs['lox-runtime'])))
    cells.update(eda(td.read(m0 / 'eda-base.json'), td.read(inputs['eda-runtime'])))
    cells.update(rows([td.read(m0 / f'rows-base-{i}.json') for i in (1, 2, 3)], [td.read(inputs[f'all46-{i}']) for i in (1, 2, 3)]))
    assert len(cells) == 197
    groups = {}
    for group in ('parity', 'lox', 'lox/vm', 'lox/tree', 'eda', 'rows'):
        selected = [value for key, value in cells.items() if key.startswith(group + '/')]
        groups[group] = {'cells': len(selected), 'final_over_base': td.gm([v['final_over_base'] for v in selected]),
                         **{ref: td.gm([v['final'][ref] for v in selected if ref in v['final']])
                            for ref in REFERENCES if any(ref in v['final'] for v in selected)}}
    primary = [value for key, value in cells.items() if key.startswith('parity/') and key.endswith('/my') and 'zig-safe' in value['final']]
    assert len(primary) == 27
    groups['parity-primary'] = {'cells': len(primary), **{ref: td.gm([v['final'][ref] for v in primary]) for ref in ('zig-safe', 'zig-fast')}}
    notes = td.read(args.notes) if args.notes else {}
    missing_notes = [key for key, value in cells.items() if value['available_gate'] != 'met' and not notes.get(key)]
    if args.require_notes:
        assert not missing_notes, ('missing final next-lever analysis', missing_notes)
    result = {'complete_timing': True, 'final_analysis_complete': not missing_notes, 'inputs': identities,
              'groups': groups, 'cells': cells, 'above_1_03': [key for key, value in cells.items() if value['review_required']],
              'over_available_gate': [key for key, value in cells.items() if value['available_gate'] == 'over'],
              'unavailable_gate': [key for key, value in cells.items() if value['available_gate'] == 'unavailable'],
              'missing_next_lever_notes': missing_notes}
    (args.out / 'gap.json').write_text(json.dumps(result, indent=1) + '\n')
    render(cells, groups, notes, args.out / 'gap.md')
    print(f"197 cells; {len(result['above_1_03'])} require regression review; {len(missing_notes)} next-lever notes pending")


if __name__ == '__main__':
    main()
