#!/usr/bin/env python3
"""Print the README's ladder tables for one case from results/<case>.json and results/<case>.perf.json.
Usage: make_tables.py CASE [CASE ...]   (cases as named in ladder_cases.py)
Columns: step | what was added | x Rust small | x Rust large | cycles/unit | instructions/unit.
The unit is the one in the case's section (element, lookup, step, fragment, row, loop iteration)."""
import json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ladder_cases import CASES  # noqa: E402


def table(case):
    t = json.loads((HERE / 'results' / f'{case}.json').read_text())
    pf = json.loads((HERE / 'results' / f'{case}.perf.json').read_text())
    small = {r['label']: r for r in t['profiles']['small']['rows']}
    large = {r['label']: r for r in t['profiles']['large']['rows']}
    unit = CASES[case].get('unit_div', 1)
    size = t['profiles']['large']['size']
    div = size if unit == 'size' else unit
    print('| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |')
    print('|---|---:|---:|---:|---:|---:|')
    for label in large:
        s, l = small[label], large[label]
        p = pf.get(label)
        cyc = f"{p['cycles_per_iter'] / div:.2f}" if p else ''
        ins = f"{p['instr_per_iter'] / div:.1f}" if p else ''
        print(f"| {label} | {s['ratio_rust']:.2f} / {l['ratio_rust']:.2f} | {s['ratio_fastest_b0']:.2f} / {l['ratio_fastest_b0']:.2f} | {l['ns_per_unit']:.3f} | {cyc} | {ins} |")


if __name__ == '__main__':
    for c in sys.argv[1:]:
        print(f'### {c}')
        table(c)
        print()
