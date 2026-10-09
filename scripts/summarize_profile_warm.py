#!/usr/bin/env python3
"""Summarize the budget-sweep evidence produced by profile_large_project.py.

The harness preserves complete work-report-v1 and phase-timings-v1 records.
This helper extracts the bounded comparison fields the corrected S1 profile
report needs without hiding the raw evidence files.
"""
from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path

MIB = 1024 * 1024
STATES = ("cold", "unchanged", "no_cache", "implementation_edit", "session_implementation_edit")
PHASES = (
    "dependency_key_preparation",
    "retention_store_io",
    "source_load_parse",
    "syntax_replay",
    "syntax_parse",
    "ordinary_body_replay",
    "fresh_body_check",
    "source_merge",
    "effect_origin_passes",
    "warning_derivation",
)


def measurement_replies(probe):
    if not probe or probe.get("status") != "measured":
        return []
    return [entry["reply"] for entry in probe.get("replies", [])
            if entry.get("role") == "measurement"]


def summarize_file(path):
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt") as stream:
        document = json.load(stream)
    result = {
        "file": str(path),
        "version": document.get("version"),
        "compiler_sha256": (document.get("compiler") or {}).get("sha256"),
        "host_before": (document.get("host") or {}).get("before"),
        "host_after": (document.get("host") or {}).get("after"),
        "workloads": [],
    }
    for workload in document.get("workloads", []):
        item = {
            "label": workload.get("label"),
            "budget_bytes": (document.get("method") or {}).get("semantic_budget_bytes"),
            "status": workload.get("status"),
            "states": {},
            "session_probe": workload.get("session_probe"),
        }
        for state_name in STATES:
            state = (workload.get("states") or {}).get(state_name)
            if not state:
                continue
            summary = state.get("summary") or {}
            entry = {
                "status": state.get("status"),
                "successful_samples": state.get("successful_samples"),
                "failed_samples": state.get("failed_samples"),
                "p50_ms": summary.get("median_ms"),
                "p95_ms": summary.get("p95_ms"),
                "peak_rss_kb": state.get("peak_rss_kb_max"),
                "phases_p50_ms": {},
                "total_inclusive_p50_ms": None,
            }
            phase_summary = state.get("phase_summary") or {}
            for phase in PHASES:
                value = phase_summary.get(phase)
                if value and value.get("p50_ns") is not None:
                    entry["phases_p50_ms"][phase] = value["p50_ns"] / 1e6
            total = phase_summary.get("total")
            if total and total.get("p50_ns") is not None:
                entry["total_inclusive_p50_ms"] = total["p50_ns"] / 1e6
            first = next((sample for sample in state.get("samples", [])
                          if sample.get("success")), None)
            if first:
                report = first.get("work_report") or {}
                entry["checked_bodies"] = report.get("checked_bodies")
                entry["specialization_bodies"] = report.get("specialization_bodies")
                entry["symbolic_templates"] = report.get("symbolic_templates")
                entry["semantic_retention"] = first.get("semantic_retention")
                entry["frontend_retained_bytes"] = (first.get("frontend_cache") or {}).get("retained_bytes")
            item["states"][state_name] = entry
        replies = measurement_replies(item["session_probe"])
        if replies:
            last = replies[-1]
            item["probe_last"] = {
                "status": last.get("status"),
                "specialization_bodies": last.get("specialization_bodies"),
                "symbolic_templates": last.get("symbolic_templates"),
                "semantic_retention": last.get("semantic_retention"),
                "semantic_miss_reasons": last.get("semantic_miss_reasons"),
                "work": (last.get("work") or {}).get("request"),
            }
        result["workloads"].append(item)
    return result


def markdown(summaries):
    lines = []
    for summary in summaries:
        for workload in summary["workloads"]:
            budget = workload["budget_bytes"]
            budget_text = "?" if budget is None else f"{budget // MIB}"
            lines.append(f"### {workload['label']} semantic budget {budget_text} MiB\n")
            lines.append("| state | n | p50 ms | p95 ms | peak RSS KiB |")
            lines.append("| --- | ---: | ---: | ---: | ---: |")
            for state_name in STATES:
                entry = workload["states"].get(state_name)
                if not entry:
                    continue
                if entry.get("status") not in (None, "measured"):
                    lines.append(f"| {state_name} | {entry.get('status')} | – | – | – |")
                    continue
                lines.append(
                    f"| {state_name} | {entry.get('successful_samples')} | "
                    f"{entry.get('p50_ms'):.1f} | {entry.get('p95_ms'):.1f} | "
                    f"{entry.get('peak_rss_kb')} |"
                )
            edit = workload["states"].get("implementation_edit")
            if edit and edit.get("phases_p50_ms"):
                lines.append("\nImplementation-edit exclusive phase p50 (ms):\n")
                lines.append("| phase | p50 ms |")
                lines.append("| --- | ---: |")
                for phase, value in sorted(edit["phases_p50_ms"].items(), key=lambda item: -item[1]):
                    lines.append(f"| {phase} | {value:.1f} |")
            probe = workload.get("probe_last")
            if probe:
                lines.append("\nLast session-probe reply:\n")
                lines.append(f"- specialization_bodies: `{probe.get('specialization_bodies')}`")
                lines.append(f"- symbolic_templates: `{probe.get('symbolic_templates')}`")
                lines.append(f"- semantic_retention: `{probe.get('semantic_retention')}`")
                lines.append(f"- miss reasons: `{probe.get('semantic_miss_reasons')}`")
            lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    paths = sorted(args.evidence_dir.glob("*-budget-*.json"))
    paths += sorted(args.evidence_dir.glob("*-budget-*.json.gz"))
    summaries = [summarize_file(path) for path in paths]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summaries, indent=2) + "\n")
    if args.markdown:
        args.markdown.write_text(markdown(summaries))
    print(f"wrote {args.output} from {len(paths)} evidence file(s)")


if __name__ == "__main__":
    main()
