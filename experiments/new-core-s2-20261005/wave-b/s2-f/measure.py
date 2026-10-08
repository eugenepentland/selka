#!/usr/bin/env python3
"""Use the accepted row timing/checksum method for the three S2-F rows."""
import importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location("rows", ROOT / "experiments/new-core-s1-20261005/measure_rows.py")
rows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rows)
rows.UNITS = {
    "call_indirect": ("compute", "element", 4000, 250000),
    "sort_int": ("collections", "element", 400, 25000),
    "sort_records": ("collections", "element", 400, 25000),
}
if __name__ == "__main__":
    rows.main()
