#!/usr/bin/env python3
"""Score a frozen cohort: manifest-listed attempts only, every arm, JSON and Markdown.

The tables come from one aggregation, so the Markdown and the JSON cannot drift.
Paired blocks (`case`, `repetition`) carry all arms, so the suggestion effect and
the format effect are read as within-block differences, and the uncertainty is a
bootstrap over cases — repeated runs of one case are not independent observations.

    python3 experiments/diagnostic-feedback/score.py --cohort m1-pilot
    python3 experiments/diagnostic-feedback/score.py --cohort m1 --json m1.json --markdown m1.md
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import statistics
import sys

HERE = Path(__file__).resolve().parent
COHORTS = HERE / "cohorts"
sys.path.insert(0, str(HERE))
import cohort  # noqa: E402

METRICS = ("failed_checks_on_changed_source", "failed_compiler_invocations", "failed_candidate_versions",
           "repeated_diagnostics", "invocations")


def attempt_records(root: Path, arm: str, case: str, repetition: int) -> list[dict]:
    directory = root / "runs" / arm / case / str(repetition)
    records = []
    if directory.is_dir():
        for attempt in sorted(directory.iterdir(), key=lambda path: int(path.name)):
            record = attempt / "record.json"
            if record.is_file():
                records.append(json.loads(record.read_text()))
    return records


def selected(records: list[dict]) -> dict | None:
    """The attempt that stands for the cell: the first, unless it was a retry."""
    return records[-1] if records else None


def collect(manifest: dict, root: Path) -> list[dict]:
    rows = []
    for row in manifest["schedule"]:
        records = attempt_records(root, row["arm"], row["case"], row["repetition"])
        record = selected(records)
        rows.append({
            "arm": row["arm"], "case": row["case"], "repetition": row["repetition"],
            "attempts": len(records),
            "present": record is not None,
            "hidden_acceptance": bool(record and record.get("hidden_acceptance")),
            "public_acceptance": bool(record and record.get("public_acceptance")),
            "termination": (record or {}).get("termination"),
            "metrics": ((record or {}).get("events") or {}).get("metrics", {}),
            "usage": ((record or {}).get("session") or {}).get("usage", {}),
            "steps": ((record or {}).get("session") or {}).get("steps"),
            "family": json.loads((HERE / "cases" / _split(root) / row["case"] / "case.json").read_text())["family"]
            if (HERE / "cases" / _split(root) / row["case"] / "case.json").is_file() else "unknown",
        })
    return rows


def _split(root: Path) -> str:
    return "dev" if "pilot" in root.name else "test"


def summarise(rows: list[dict]) -> dict:
    present = [row for row in rows if row["present"]]
    accepted = [row for row in present if row["hidden_acceptance"]]
    def med(values):
        return statistics.median(values) if values else None
    return {
        "cells": len(rows),
        "recorded": len(present),
        "missing": len(rows) - len(present),
        "hidden_acceptance": len(accepted),
        "hidden_acceptance_rate": round(len(accepted) / len(rows), 3) if rows else None,
        "conditional_failed_checks": med([row["metrics"].get("failed_checks_on_changed_source") for row in accepted]),
        "all_attempt_failed_checks": sum((row["metrics"].get("failed_checks_on_changed_source") or 0) for row in present),
        "median_invocations": med([row["metrics"].get("invocations") for row in present]),
        "median_output_tokens": med([row["usage"].get("outputTokens") for row in present]),
        "timeouts": sum(1 for row in present if row["termination"] == "timeout"),
        "public_only": sum(1 for row in present if row["public_acceptance"] and not row["hidden_acceptance"]),
    }


def paired(rows: list[dict], left: str, right: str, field: str, seed: int = 11) -> dict:
    """Within-block differences of one metric, bootstrapped over cases."""
    blocks: dict[tuple[str, int], dict[str, dict]] = {}
    for row in rows:
        blocks.setdefault((row["case"], row["repetition"]), {})[row["arm"]] = row
    differences = []
    for (case, _), arms in sorted(blocks.items()):
        if left in arms and right in arms:
            a = arms[left]["metrics"].get(field)
            b = arms[right]["metrics"].get(field)
            if isinstance(a, (int, float)) and isinstance(b, (int, float)):
                differences.append((case, a - b))
    if not differences:
        return {"pairs": 0, "mean": None, "ci": [None, None]}
    values = [value for _, value in differences]
    generator = random.Random(seed)
    means = []
    for _ in range(2000):
        sample = [values[generator.randrange(len(values))] for _ in values]
        means.append(statistics.fmean(sample))
    means.sort()
    return {"pairs": len(values), "mean": round(statistics.fmean(values), 3),
            "ci": [round(means[int(0.025 * len(means))], 3), round(means[int(0.975 * len(means))], 3)],
            "per_case": {case: value for case, value in differences}}


def report(manifest: dict, rows: list[dict]) -> dict:
    arms = manifest["arms"]
    by_arm = {arm: summarise([row for row in rows if row["arm"] == arm]) for arm in arms}
    families = sorted({row["family"] for row in rows})
    by_family = {family: {arm: summarise([row for row in rows if row["arm"] == arm and row["family"] == family])
                          for arm in arms} for family in families}
    return {
        "version": 1,
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "cohort": manifest["cohort_id"],
        "identity": manifest["identity"],
        "arms": arms,
        "by_arm": by_arm,
        "by_family": by_family,
        "effects": {
            "suggestion_in_text": paired(rows, "text_fix", "text", "failed_checks_on_changed_source"),
            "suggestion_in_json": paired(rows, "json_fix", "json", "failed_checks_on_changed_source"),
            "format_without_suggestion": paired(rows, "json", "text", "failed_checks_on_changed_source"),
            "format_with_suggestion": paired(rows, "json_fix", "text_fix", "failed_checks_on_changed_source"),
        },
        "rows": rows,
    }


def markdown(report_data: dict) -> str:
    lines = [f"# Cohort {report_data['cohort']}", "",
             f"captured {report_data['captured_utc']}", "",
             "| arm | cells | recorded | hidden ok | rate | median failed checks (accepted) | median invocations | timeouts | public-only |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for arm in report_data["arms"]:
        summary = report_data["by_arm"][arm]
        def show(value):
            return "-" if value is None else (f"{value:,.0f}" if isinstance(value, float) else str(value))
        lines.append(f"| {arm} | {summary['cells']} | {summary['recorded']} | {summary['hidden_acceptance']} | "
                     f"{show(summary['hidden_acceptance_rate'])} | {show(summary['conditional_failed_checks'])} | "
                     f"{show(summary['median_invocations'])} | {summary['timeouts']} | {summary['public_only']} |")
    lines += ["", "## Paired within-block effects (failed checks on changed source)", "",
              "| contrast | pairs | mean difference | 95% CI |", "| --- | ---: | ---: | --- |"]
    for name, effect in report_data["effects"].items():
        lines.append(f"| {name} | {effect['pairs']} | {effect['mean']} | {effect['ci']} |")
    lines += ["", "## Per family", "", "| family | arm | hidden ok / cells | median failed checks |", "| --- | --- | ---: | ---: |"]
    for family, arms in report_data["by_family"].items():
        for arm, summary in arms.items():
            if summary["cells"]:
                lines.append(f"| {family} | {arm} | {summary['hidden_acceptance']} / {summary['cells']} | "
                             f"{'-' if summary['conditional_failed_checks'] is None else summary['conditional_failed_checks']} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    root = COHORTS / args.cohort
    manifest = cohort.load(root / "manifest.json")
    rows = collect(manifest, root)
    data = report(manifest, rows)
    text = markdown(data)
    print(text)
    if args.json:
        args.json.write_text(json.dumps(data, indent=2) + "\n")
    if args.markdown:
        args.markdown.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
