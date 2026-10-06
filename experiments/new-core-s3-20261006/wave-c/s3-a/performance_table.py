#!/usr/bin/env python3
"""Render the retained strict four-program measurements and both S3 speed gates."""
import argparse
import json
import math
from pathlib import Path

CONFIGURATIONS = ("old core --release", "new core release", "Rust", "Zig ReleaseSafe")
SIZES = ("4096", "64")


def pair(values):
    return " / ".join(f"{value:.3f}" for value in values)


def table(report):
    if not report["valid"] or report["cpu"] != 10 or report["rounds"] != 7:
        raise ValueError("only valid CPU10 seven-round receipts may form the qualification table")
    lines = ["| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig | Both gates |",
             "|---|---:|---:|---:|---:|---:|---:|---|"]
    for row, result in report["rows"].items():
        values = [[result["sizes"][size]["configurations"][name]["cycles_per_unit"] for size in SIZES]
                  for name in CONFIGURATIONS]
        ratios = [[result["sizes"][size][field] for size in SIZES]
                  for field in ("new_over_old", "new_over_zig")]
        if not all(math.isfinite(value) and value > 0 for items in values + ratios for value in items):
            raise ValueError(f"{row}: nonpositive or non-finite retained value")
        passed = all(value <= 1.10 for items in ratios for value in items)
        if passed != all(result["sizes"][size]["within_both_limits"] for size in SIZES):
            raise ValueError(f"{row}: stored gate classification disagrees with ratios")
        lines.append("| " + " | ".join([row, *map(pair, values), *map(pair, ratios), "Pass" if passed else "Miss"]) + " |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    rendered = table(json.loads(args.receipt.read_text()))
    if args.output:
        with args.output.open("x") as output:
            output.write(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
