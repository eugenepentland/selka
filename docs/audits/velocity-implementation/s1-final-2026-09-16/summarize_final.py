#!/usr/bin/env python3
"""Render the S1-final evidence tables from the pinned ReleaseFast runs.

Reads matrix-10k.json, matrix-100k.json, native-probe.json and budget-*.json
next to this script and prints/writes summary-tables.md. Raw JSON stays the
authority; this only formats bounded fields and never recomputes percentiles.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATES = ("cold", "unchanged", "no_cache", "implementation_edit", "constant_edit",
          "signature_edit", "union_edit", "provider_edit", "effect_edit",
          "session_implementation_edit", "session_constant_edit", "forced_tests")
PHASES = ("dependency_key_preparation", "retention_store_io", "source_load_parse",
          "syntax_parse", "syntax_replay", "ordinary_body_replay",
          "specialization_body_replay", "fresh_body_check", "source_merge",
          "effect_origin_passes", "warning_derivation", "entry_adaptation",
          "declarations_interfaces", "symbolic_templates", "domain_codec_validation")


def load(path):
    return json.loads(path.read_text()) if path.exists() else None


def fmt(value, digits=1):
    if value is None:
        return "–"
    return f"{value:.{digits}f}"


def matrix_table(document, title):
    lines = [f"### {title}", "",
             "| workload | state | n | p50 ms | p95 ms | peak RSS KiB |",
             "| --- | --- | ---: | ---: | ---: | ---: |"]
    for workload in document["workloads"]:
        for name in STATES:
            state = (workload.get("states") or {}).get(name)
            if not state:
                continue
            summary = state.get("summary") or {}
            status = state.get("status")
            if status != "measured":
                lines.append(f"| {workload['label']} | {name} | {status} | – | – | – |")
                continue
            lines.append(
                f"| {workload['label']} | {name} | {summary.get('count')} | "
                f"{fmt(summary.get('median_ms'))} | {fmt(summary.get('p95_ms'))} | "
                f"{state.get('peak_rss_kb_max')} |")
        forced = (workload.get("states") or {}).get("forced_tests")
        if forced and forced.get("cold_build"):
            cold = forced["cold_build"]
            lines.append(
                f"| {workload['label']} | forced cold_build | 1 | {fmt(cold['wall_ms'])} | – | "
                f"{cold['peak_rss_kb']} |")
    lines.append("")
    return "\n".join(lines)


def phase_table(document, states=("implementation_edit",)):
    lines = ["### Implementation-edit exclusive phase p50 (ms)", "",
             "| workload | state | total inclusive | " + " | ".join(PHASES) + " |",
             "| --- | --- | ---: | " + " | ".join("---:" for _ in PHASES) + " |"]
    for workload in document["workloads"]:
        for state_name in states:
            state = (workload.get("states") or {}).get(state_name)
            if not state or state.get("status") != "measured":
                continue
            summary = state.get("phase_summary") or {}
            cells = []
            for phase in PHASES:
                entry = summary.get(phase)
                cells.append("–" if not entry or entry.get("p50_ns") is None
                             else f"{entry['p50_ns'] / 1e6:.1f}")
            total = summary.get("total")
            total_text = "–" if not total or total.get("p50_ns") is None else f"{total['p50_ns'] / 1e6:.1f}"
            lines.append(f"| {workload['label']} | {state_name} | {total_text} | " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def native_table(document):
    lines = ["### Direct native-test probe (`mylang test --report`; C4 selective lowering)", "",
             "| workload | state | n | p50 ms | p95 ms | lowered | emitted | links | executed | cached | select-file |",
             "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |"]
    for workload in document["workloads"]:
        for state in workload["states"]:
            summary = state["summary"]
            sample = next((item for item in state["samples"] if item["success"]), None)
            def ctr(name):
                if not sample:
                    return "–"
                value = sample["counters"][name]
                return f"{value.get('performed')}/{value.get('reused')}"
            native = (sample or {}).get("native") or {}
            select = (sample or {}).get("select_file_count")
            lines.append(
                f"| {workload['label']} | {state['state']} | {summary['n']} | "
                f"{fmt(summary['p50_ms'])} | {fmt(summary['p95_ms'])} | "
                f"{ctr('lowered_functions')} | {ctr('emitted_fragments')} | {ctr('links')} | "
                f"{ctr('executed_tests')} | {native.get('cached', '–')} | {select if select is not None else '–'} |")
    lines.append("")
    return "\n".join(lines)


def budget_table(documents):
    lines = ["### 100k ordinary semantic-budget phase check (implementation_edit)", "",
             "| budget MiB | edit checked/reused | dep-key prep p50 ms | retention/store p50 ms | fresh body check p50 ms | total p50 ms |",
             "| ---: | --- | ---: | ---: | ---: | ---: |"]
    for document in documents:
        budget = (document.get("method") or {}).get("semantic_budget_bytes")
        for workload in document["workloads"]:
            state = (workload.get("states") or {}).get("implementation_edit")
            if not state or state.get("status") != "measured":
                continue
            summary = state.get("phase_summary") or {}
            sample = next((item for item in state["samples"] if item.get("success")), None)
            report = (sample or {}).get("work_report") or {}
            checked = report.get("checked_bodies") or {}

            def phase(name):
                entry = summary.get(name)
                return "–" if not entry or entry.get("p50_ns") is None else f"{entry['p50_ns'] / 1e6:.1f}"
            total = summary.get("total")
            total_text = "–" if not total or total.get("p50_ns") is None else f"{total['p50_ns'] / 1e6:.1f}"
            lines.append(
                f"| {budget // (1024 * 1024)} | {checked.get('performed')}/{checked.get('reused')} | "
                f"{phase('dependency_key_preparation')} | {phase('retention_store_io')} | "
                f"{phase('fresh_body_check')} | {total_text} |")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--markdown", type=Path, default=HERE / "summary-tables.md")
    args = parser.parse_args()
    sections = []
    m10 = load(HERE / "matrix-10k.json")
    m100 = load(HERE / "matrix-100k.json")
    native = load(HERE / "native-probe.json")
    native_m100 = load(HERE / "native-probe-managed-100k.json")
    if native and native_m100:
        replacements = {item["label"]: item for item in native_m100.get("workloads", [])}
        native["workloads"] = [replacements.get(item["label"], item) for item in native.get("workloads", [])]
    budgets = [load(HERE / f"budget-{b}mib.json") for b in (0, 16, 64)]
    if m10:
        sections.append(matrix_table(m10, "10k ReleaseFast matrix (pinned binary)"))
        sections.append(phase_table(m10))
    if m100:
        sections.append(matrix_table(m100, "100k ReleaseFast matrix (pinned binary)"))
        sections.append(phase_table(m100))
        sections.append(phase_table(m100, states=("unchanged",)))
    if native:
        sections.append(native_table(native))
    present = [item for item in budgets if item]
    if present:
        sections.append(budget_table(present))
    text = "\n".join(sections)
    args.markdown.write_text(text + "\n")
    print(text)
    print(f"wrote {args.markdown}")


if __name__ == "__main__":
    main()
