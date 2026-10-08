#!/usr/bin/env python3
"""S5-0: keep the old core's column of the S4-exit 46-row measurement as a reference.

The row tool keeps measuring the archived old core interleaved with the new one
(`--mylang ~/.cache/mylang/oracles/old-core-d36658db/mylang`, MYLANG_QBE beside it);
this frozen column (cycles per unit per row and size, CPU 10, 7 rounds) is the
fallback should the archived binary ever stop running.
Usage: freeze_rows.py --all46 x-all46-01.json --output references/rows-old-v1.json
"""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all46", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.all46.read_text())
    column = {}
    for name, row in data["rows"].items():
        for size, cell in row["sizes"].items():
            column.setdefault(name, {})[size] = {
                "old_core_cycles_per_unit": cell["configurations"]["old core --release"]["cycles_per_unit"],
                "zig_release_safe_cycles_per_unit": cell["configurations"]["Zig ReleaseSafe"]["cycles_per_unit"],
                "iterations": cell["iterations"], "checksum": cell["checksum"]}
    document = {"version": "s5-rows-old-v1", "source": str(args.all46), "cpu": data["cpu"], "rounds": data["rounds"], "rows": column}
    args.output.write_text(json.dumps(document, indent=1, sort_keys=True) + "\n")
    print(json.dumps({"rows": len(column), "cells": sum(len(v) for v in column.values())}))


if __name__ == "__main__":
    main()
