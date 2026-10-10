#!/usr/bin/env python3
"""Keep the strict 46-row timing method and include every rebuilt reference arm."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('rp3_rows', ROOT / 'experiments/new-core-s4-20261006/integration/measure_all46.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module.rows.configurations


def configurations(args, row):
    result = original(args, row)
    if row in module.CASES:
        return result
    suite = module.rows.UNITS[row][0]
    reference = module.rows.REFERENCE_NAMES.get(row, row)
    prefixes = (suite, 'legacy') if suite == 'ports' else (suite,)
    for label, suffix in (('Zig ReleaseFast', 'zig-fast'), ('Go', 'go')):
        binary = next((args.runner / f'{prefix}-{suffix}' for prefix in prefixes
                       if (args.runner / f'{prefix}-{suffix}').is_file()), None)
        if binary is None:
            raise module.rows.InvalidMeasurement(f'missing {label} reference for {suite}')
        result[label] = lambda size, iterations, binary=binary: [str(binary), reference, str(size), str(iterations), str(module.rows.SEED)]
    return result


module.rows.configurations = configurations
if __name__ == '__main__':
    raise SystemExit(module.main())
