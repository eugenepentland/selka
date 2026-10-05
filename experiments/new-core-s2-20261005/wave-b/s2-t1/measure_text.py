#!/usr/bin/env python3
"""Use the S1 CPU-10 method for the five S2 text rows."""
import importlib.util
from pathlib import Path
root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('rows', root / 'experiments/new-core-s1-20261005/measure_rows.py')
rows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rows)
rows.UNITS.update({
    'bytes_scan': ('text', 'element', 4000, 250000),
    'string_equal': ('text', 'iteration', 200000, 200000),
    'string_search': ('text', 'iteration', 40000, 40000),
    'string_split': ('text', 'element', 400, 25000),
    'string_join': ('text', 'element', 1000, 60000),
})
raise SystemExit(rows.main())
