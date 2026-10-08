#!/usr/bin/env python3
"""Render the retained early-tax or diagnostic JSON (optionally gzip) as Markdown."""
import gzip
import json
from pathlib import Path
import statistics
import sys


def render(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt") as handle:
        data = json.load(handle)
    assert data["valid"] and len(data["rows"]) == 92
    tags = data["tags"]
    lines = ["Wall times are native CLOCK_MONOTONIC kernel times, with the median",
             "one-iteration startup subtracted. Each time below is the median of",
             "the three batch medians; each ratio is the median of the three",
             "within-batch ratios. Consequently ratios need not equal the ratio",
             "of the two displayed times.", "",
             "| corpus / arm | cells | wall geomean vs base | cells >1.03 | verdict |",
             "|---|---:|---:|---:|---|"]
    for tag in tags[1:]:
        summary = data["summary"][tag]
        lines.append(f"| 46 rows / {tag} | 92 | {summary['geomean']:.6f} | "
                     f"{len(summary['rows_over_1_03'])} | {'PASS' if summary['pass'] else 'FAIL'} |")
    loads = [sample["load_before"][0] for row in data["rows"].values()
             for batch in row["batches"] for samples in batch["runs"].values() for sample in samples]
    lines += ["", f"CPU 10 under cpu10.lock. One-minute load across timed samples: {min(loads):.2f}–{max(loads):.2f}.", "",
              "| row | size | " + " | ".join(f"{tag} ms" for tag in tags) + " | " +
              " | ".join(f"{tag}/base" for tag in tags[1:]) + " |",
              "|---|---:|" + "---:|" * (2 * len(tags) - 1)]
    for key, row in data["rows"].items():
        assert len(row["batches"]) == 3
        name, size = key.split("/")
        times = [statistics.median(batch["medians"][tag]["elapsed_ns"] for batch in row["batches"]) / 1e6 for tag in tags]
        ratios = [data["summary"][tag]["ratios"][key]["elapsed_ns"] for tag in tags[1:]]
        cells = [name, size] + [f"{value:.4f}" for value in times] + [f"{value:.5f}" for value in ratios]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    print(render(Path(sys.argv[1])), end="")
