#!/usr/bin/env python3
"""The unchanged S1 interleaved CPU-10 cycle method, extended to dictionary rows."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location('rows_dict', ROOT / 'experiments/new-core-s1-20261005/measure_rows.py')
rows = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rows)
DICT_UNITS = {
    'dict_lookup': ('collections', 'element', 4000, 250000),
    'dict_lookup_str': ('collections', 'element', 4000, 250000),
    'dict_update': ('collections', 'element', 1000, 60000),
    'dict_update_str': ('collections', 'element', 1000, 60000),
    'set_dedup': ('collections', 'element', 4000, 250000),
}
rows.UNITS.update(DICT_UNITS)

if __name__ == '__main__':
    raise SystemExit(rows.main())
