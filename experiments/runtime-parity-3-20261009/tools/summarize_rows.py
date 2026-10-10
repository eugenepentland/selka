#!/usr/bin/env python3
"""Summarize three row batches using FU-X's median of within-batch ratios."""
import argparse
import gzip
import json
import math
from pathlib import Path
import statistics


def read(path):
    with (gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()) as source:
        return json.load(source)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('batches', nargs=3, type=Path)
    parser.add_argument('--json', type=Path, required=True)
    parser.add_argument('--markdown', type=Path, required=True)
    args = parser.parse_args()
    batches = [read(path) for path in args.batches]
    assert all(b['valid'] and b['cpu'] == 10 and b['rounds'] == 7 and len(b['rows']) == 46 for b in batches)
    assert all(set(b['rows']) == set(batches[0]['rows']) for b in batches)
    cells = {}
    lines = ['# Row timing: three batches of seven interleaved rounds', '',
             'Every reported ratio is the median of its three within-batch ratios, after the original startup subtraction. All batches remain in the raw evidence.', '',
             '| row / size | new/base batch 1 | batch 2 | batch 3 | median | new/Zig RS median |',
             '|---|---:|---:|---:|---:|---:|']
    for name in sorted(batches[0]['rows']):
        for size in ('4096', '64'):
            configs = [b['rows'][name]['sizes'][size]['configurations'] for b in batches]
            assert all(set(c) == set(configs[0]) for c in configs)
            ratios = {label: [c['new core release']['cycles_per_unit'] / c[label]['cycles_per_unit'] for c in configs]
                      for label in configs[0] if label != 'new core release'}
            medians = {label: statistics.median(values) for label, values in ratios.items()}
            key = name + '/' + size
            cells[key] = {'batch_ratios': ratios, 'median_ratios': medians}
            old = ratios['old core --release']
            lines.append(f"| {key} | {old[0]:.4f} | {old[1]:.4f} | {old[2]:.4f} | {medians['old core --release']:.4f} | {medians['Zig ReleaseSafe']:.4f} |")
    above = [key for key, cell in cells.items() if cell['median_ratios']['old core --release'] > 1.03]
    single = {key: cell['batch_ratios']['old core --release'] for key, cell in cells.items()
              if max(cell['batch_ratios']['old core --release']) > 1.03}
    zig = [key for key, cell in cells.items() if cell['median_ratios']['Zig ReleaseSafe'] > 1.10]
    gm = math.exp(statistics.mean(math.log(cell['median_ratios']['old core --release']) for cell in cells.values()))
    result = {'method': 'FU-X median of three within-batch ratios; 7 rounds each', 'cpu': 10,
              'cells': cells, 'geomean_new_over_base': gm, 'medians_above_1_03': above,
              'single_batches_above_1_03': single, 'zig_rs_medians_above_1_10': zig}
    lines += ['', f'New/base geomean: {gm:.6f}. Median ratios above 1.03: {above}.', '',
              f'Single batches above 1.03 (retained for review): {single}.', '',
              f'Zig RS median ratios above 1.10: {zig}.', '']
    args.json.write_text(json.dumps(result, indent=1) + '\n')
    args.markdown.write_text('\n'.join(lines))
    print(f'{len(cells)} cells; new/base geomean {gm:.6f}; above 1.03: {above}; Zig RS misses: {zig}')


if __name__ == '__main__':
    main()
