#!/usr/bin/env python3
"""Retain VP3 counting cells and add all 26 current full-size Lox cells."""
import json
import ce

old_cells = ce.vp3_cells


def complete_cells(group):
    cells = old_cells(group)
    if group == 'lox':
        present = {(cell['engine'], cell['script'], cell['n']) for cell in cells.values()}
        sizes = json.loads((ce.LOX / 'bench/sizes.json').read_text())
        for name, counts in sizes.items():
            if name.startswith('_'):
                continue
            for engine in ('vm', 'tree'):
                n = counts[engine]
                if (engine, name, n) not in present:
                    cells[f'lox-{engine}-{name}-{n}'] = {'engine': engine, 'script': name, 'n': n}
    return cells


if __name__ == '__main__':
    ce.vp3_cells = complete_cells
    ce.main()
