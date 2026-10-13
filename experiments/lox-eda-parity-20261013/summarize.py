#!/usr/bin/env python3
"""Render the validated all-case report without dropping censored cases."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def ratio(left, right):
    return left / right if left is not None and right else None


def geometric(values):
    values = [x for x in values if x is not None]
    return {"pairs": len(values), "ratio": math.exp(sum(map(math.log, values)) / len(values)) if values else None}


def render(report):
    rows = []
    for name, cell in sorted(report["cells"].items()):
        arms = cell["arms"]
        new, old, zig = (arms[n] for n in ("mylang-zero-rc", "mylang-before", "zig-fast"))
        row = {"case": name, "group": name.split("-", 1)[0],
               "candidate_status": new["status"], "before_status": old["status"], "zig_status": zig["status"]}
        for label, arm in (("candidate", new), ("before", old), ("zig", zig)):
            for metric in ("wall_seconds", "rss_kib"):
                row[label + "_" + metric] = arm[metric] if arm["status"] == "ok" else None
        same = arms.get("mylang-before-same-compiler", {})
        row["before_same_compiler_status"] = same.get("status", "unavailable")
        row["before_same_compiler_wall_seconds"] = same.get("wall_seconds") if same.get("status") == "ok" else None
        row["compiler_change_ratio"] = ratio(row["before_same_compiler_wall_seconds"], row["before_wall_seconds"])
        row["application_source_change_ratio"] = ratio(row["candidate_wall_seconds"], row["before_same_compiler_wall_seconds"])
        for metric in ("wall_seconds", "rss_kib"):
            for control in ("zig", "before"):
                key = metric + "_over_" + control
                row[key] = ratio(row["candidate_" + metric], row[control + "_" + metric])
                row[key + "_percent_change"] = 100 * (row[key] - 1) if row[key] is not None else None
        row["parity_pass"] = cell["parity_pass"]
        counter_arms = (cell.get("counters") or {}).get("arms", {})
        for label, arm in (("candidate", "mylang-zero-rc"), ("before", "mylang-before")):
            metrics = (counter_arms.get(arm) or {}).get("metrics") or {}
            for metric in ("allocs", "reallocs", "cumulative_allocated_bytes", "peak_live_bytes", "live_bytes_at_exit",
                           "runtime_retains", "runtime_releases", "compiler_retains", "compiler_releases"):
                row[label + "_" + metric] = metrics.get(metric)
        rows.append(row)
    groups = {}
    for group in ("eda", "tree", "vm", "all"):
        subset = [r for r in rows if group == "all" or r["group"] == group]
        groups[group] = {"denominator": len(subset), "parity_pass": sum(r["parity_pass"] for r in subset),
                         "candidate_incomplete": [r["case"] for r in subset if r["candidate_status"] != "ok"],
                         "before_incomplete": [r["case"] for r in subset if r["before_status"] != "ok"]}
        for metric in ("wall_seconds", "rss_kib"):
            for control in ("zig", "before"):
                key = metric + "_over_" + control
                groups[group][key] = geometric([r[key] for r in subset])
        for key in ("compiler_change_ratio", "application_source_change_ratio"):
            groups[group][key] = geometric([r[key] for r in subset])
    return rows, groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = args.report.read_bytes()
    report = json.loads(raw)
    assert report["scope"] == 60 and len(report["cells"]) == 60
    rows, groups = render(report)
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {"report": str(args.report.resolve()), "report_sha256": hashlib.sha256(raw).hexdigest(),
               "harness_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "all_cases_pass": report["all_cases_pass"], "groups": groups,
               "method": "Ratios of per-arm medians. Negative percent changes mean less time or RSS. Group geometric means use only completed matched pairs; denominators and incomplete cases remain explicit. Managed metrics are separate instrumented observations. RSS is process maximum, not managed peak."}
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (args.output / "cases.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ["# All-case comparison", "", summary["method"], "",
             "| Case | Status | Runtime / Zig | Runtime change from previous | RSS / Zig |",
             "| --- | --- | ---: | ---: | ---: |"]
    for row in rows:
        def number(key, suffix="×"):
            value = row[key]
            return "—" if value is None else f"{value:.3f}{suffix}"
        lines.append(f"| {row['case']} | {row['candidate_status']} | {number('wall_seconds_over_zig')} | {number('wall_seconds_over_before_percent_change', '%')} | {number('rss_kib_over_zig')} |")
    (args.output / "cases.md").write_text("\n".join(lines) + "\n")
    print(json.dumps(groups, indent=2))


if __name__ == "__main__":
    main()
