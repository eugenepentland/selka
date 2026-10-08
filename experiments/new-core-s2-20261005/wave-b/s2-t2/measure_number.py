#!/usr/bin/env python3
"""Measure the two number rows with the established S1 CPU10 method."""
import importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
NUMBER_UNITS = {
    'int_parse': ('text', 'iteration', 4000000, 4000000),
    'int_format': ('text', 'iteration', 4000000, 4000000),
}

def main():
    spec = importlib.util.spec_from_file_location('number_rows', ROOT / 'experiments/new-core-s1-20261005/measure_rows.py')
    rows = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rows)
    rows.UNITS = NUMBER_UNITS
    return rows.main()

if __name__ == '__main__':
    raise SystemExit(main())
