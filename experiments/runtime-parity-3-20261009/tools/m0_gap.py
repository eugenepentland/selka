#!/usr/bin/env python3
"""Render a complete M0 gap table from qualified timing receipts; no missing cells."""
import gzip
import json
import math
from pathlib import Path
import statistics

AREA = Path(__file__).resolve().parents[1]
M0 = AREA / 'M0'


def read(name):
    path = M0 / name
    if path.exists():
        return json.loads(path.read_text())
    return json.loads(gzip.open(path.with_suffix(path.suffix + '.gz'), 'rt').read())


def gm(values):
    return math.exp(statistics.mean(math.log(v) for v in values))


def row(label, own, refs, limit):
    ratios = {name: own / value for name, value in refs.items() if value is not None}
    rs = ratios.get('zig-safe')
    checked = ratios.get('rust-checked')
    passed = rs is not None and rs <= limit and (checked is None or checked <= limit)
    cells = ['—' if key not in ratios else f"{ratios[key]:.3f}" for key in ('zig-safe', 'rust-checked', 'zig-fast', 'rust', 'go')]
    return '| ' + ' | '.join([label, *cells, f'{limit:.2f}', 'met' if passed else 'over']) + ' |', ratios


def main():
    lines = ['# M0 gap — current-main base', '',
             'Base: `41ed360fb361c49938488ad111795bad8a726b73`. Ratios below divide mylang by the named reference; smaller is faster.', '',
             'CPU 10 runs hold the timing lock and all build/gate slots. Parity uses 9 rounds and 2 warmups; Lox 3 rounds; EDA 10 rounds and 1 warmup. Rows use the median of three 7-round batches, after startup subtraction, in cycles per unit.', '',
             'A dash means the corpus has no such arm. Lox and EDA provide plain Rust only; its ratio is evidence, not a checked-Rust gate result. The `met` column applies only to the available gated references. Missing checked-Rust coverage remains explicit.', '']
    header = ['| program / arm | ÷ Zig RS | ÷ rust-checked | ÷ Zig RF | ÷ plain Rust | ÷ Go | limit | available gate |',
              '|---|---:|---:|---:|---:|---:|---:|---|']
    parity = read('parity-base.json')
    lines += ['## Parity', '', *header]
    n = 0
    main_ratios = []
    for name, bench in sorted(parity['benchmarks'].items()):
        refs = {key: value['wall_median'] for key, value in bench['arms'].items() if key in ('zig-safe', 'rust-checked', 'zig-fast', 'rust', 'go')}
        for key, value in bench['arms'].items():
            assert value['build']['ok'] and value.get('matches_expected'), (name, key)
            if value['lang'] != 'my':
                continue
            n += 1
            line, ratios = row(name + '/' + key, value['wall_median'], refs, 1.1)
            lines.append(line)
            if key == 'my': main_ratios.append(ratios)
    assert n == 45, n
    lines += ['', f"Primary-arm geomean ÷ Zig RS: {gm([r['zig-safe'] for r in main_ratios]):.3f}; ÷ Zig RF: {gm([r['zig-fast'] for r in main_ratios]):.3f}.", '']
    lox = read('lox-base.json')
    assert not lox['failures'] and len(lox['summary']) == 26
    lines += ['## Lox', '', *header]
    engine_ratios = {'vm': [], 'tree': []}
    for name, arms in sorted(lox['summary'].items()):
        refs = {'zig-safe': arms['zig:release-safe']['median_s'], 'zig-fast': arms['zig:release']['median_s'],
                'rust': arms['rust:release']['median_s'], 'go': arms['go:release']['median_s']}
        engine = name.split('/')[1]
        line, ratios = row(name, arms['mylang:release']['median_s'], refs, 1.5 if engine == 'vm' else 1.1)
        lines.append(line)
        engine_ratios[engine].append(ratios['zig-safe'])
    lines += ['', '; '.join(f"{engine} geomean ÷ Zig RS: {gm(values):.3f}" for engine, values in engine_ratios.items()) + '.', '']
    eda = read('eda-base.json')
    assert eda['all_outputs_verified'] and len(eda['per_case']) == 34
    lines += ['## EDA', '', *header]
    ratios = []
    for name, arms in sorted(eda['per_case'].items()):
        refs = {key: arms[key]['median_s'] for key in ('zig-safe', 'zig-fast', 'rust', 'go')}
        line, compared = row(name, arms['mylang-base']['median_s'], refs, 1.1)
        lines.append(line)
        ratios.append(compared['zig-safe'])
    lines += ['', f'EDA geomean ÷ Zig RS: {gm(ratios):.3f}.', '']
    batches = [read(f'rows-base-{i}.json') for i in (1, 2, 3)]
    assert all(batch['valid'] and len(batch['rows']) == 46 for batch in batches)
    lines += ['## Rows', '', 'All 46 rows at both registered sizes. Rust is the existing row reference. The historical row threshold is 1.10× Zig RS; its Rust ratio is reported alongside it.', '', *header]
    for name in sorted(batches[0]['rows']):
        for size in ('4096', '64'):
            configs = [batch['rows'][name]['sizes'][size]['configurations'] for batch in batches]
            median = {key: statistics.median(config[key]['cycles_per_unit'] for config in configs) for key in configs[0]}
            refs = {short: median[key] for short, key in (('zig-safe', 'Zig ReleaseSafe'), ('rust', 'Rust'), ('go', 'Go')) if key in median}
            lines.append(row(name + '/' + size, median['new core release'], refs, 1.1)[0])
    (M0 / 'gap.md').write_text('\n'.join(lines) + '\n')
    print('gap.md: 45 parity arms, 26 Lox cells, 34 EDA designs, 92 row cells')


if __name__ == '__main__':
    main()
