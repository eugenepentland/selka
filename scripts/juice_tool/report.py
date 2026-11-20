"""Compare compatible evidence; instruction savings are not elapsed-time savings."""
from __future__ import annotations

import math
from pathlib import Path

from . import VERSION
from .common import JuiceError, digest, file_hash, read_json


CONTEXTUAL = {"alloc_bytes", "free_bytes", "realloc_added_bytes", "realloc_moves",
              "realloc_moved_bytes", "peak_live_bytes"}


def load_record(path):
    record = read_json(path)
    if record.get("version") != VERSION or record.get("status") != "complete":
        raise JuiceError(f"not a complete {VERSION} record: {path}")
    for name, expected in record.get("evidence", {}).items():
        artifact = Path(path).parent / name
        if not artifact.is_file() or file_hash(artifact) != expected:
            raise JuiceError(f"missing or modified raw evidence: {artifact}")
    return record


def differences(before, after):
    return {key: {"base": before.get(key), "candidate": after.get(key)}
            for key in sorted(before.keys() | after.keys()) if before.get(key) != after.get(key)}


def attribution(before, after, base_units, candidate_units):
    def index(rows):
        return {tuple(r.get(k) for k in ("file", "function", "object", "line")): r for r in rows}
    a, b = index(before), index(after)
    result = []
    for key in a.keys() | b.keys():
        left = a.get(key, {}).get("instructions", 0) / base_units
        right = b.get(key, {}).get("instructions", 0) / candidate_units
        if left != right:
            result.append({"file": key[0], "function": key[1], "object": key[2], "line": key[3],
                           "base_per_unit": left, "candidate_per_unit": right, "delta_per_unit": right - left,
                           "match": "same location" if key in a and key in b else "added or removed location"})
    return sorted(result, key=lambda r: abs(r["delta_per_unit"]), reverse=True)


def semantic_delta(base, candidate):
    a, b = base.get("semantic"), candidate.get("semantic")
    if a is None or b is None:
        return {"status": "unavailable"}
    if base["counter_semantics"] != candidate["counter_semantics"] or a["version"] != b["version"]:
        return {"status": "incompatible", "reason": "counter hook contracts differ"}
    totals = differences(a["totals"], b["totals"])
    functions = []
    def indexed(document):
        return {r["name"]: {k: v for k, v in r.items() if isinstance(v, (int, float))}
                for r in document.get("functions", [])}
    first, second = indexed(a), indexed(b)
    for name in sorted(first.keys() | second.keys()):
        changes = differences(first.get(name, {}), second.get(name, {}))
        if changes:
            functions.append({"function": name, "changes": changes})
    site_fields = ("function", "origin", "path", "line", "column", "kind", "detail")
    site_a = {tuple(s.get(k) for k in site_fields): s for s in a.get("sites", [])}
    site_b = {tuple(s.get(k) for k in site_fields): s for s in b.get("sites", [])}
    sites = []
    for key in site_a.keys() | site_b.keys():
        left = {k: site_a.get(key, {}).get(k, 0) for k in ("count", "bytes", "extra")}
        right = {k: site_b.get(key, {}).get(k, 0) for k in ("count", "bytes", "extra")}
        if left != right:
            sites.append({**dict(zip(site_fields, key)), "base": left, "candidate": right,
                          "match": "same location" if key in site_a and key in site_b else "added or removed location"})
    sites.sort(key=lambda s: (abs(s["candidate"]["count"] - s["base"]["count"]),
                              abs(s["candidate"]["bytes"] - s["base"]["bytes"])), reverse=True)
    return {"status": "compatible", "totals": totals,
            "contextual_metrics": sorted(CONTEXTUAL), "functions": functions, "sites": sites,
            "requested_allocation_bytes": {"status": "unavailable", "reason": "v1 counters expose allocated class/usable sizes"},
            "kinds": differences(a.get("kinds", {}), b.get("kinds", {})),
            "site_scope": "before LLVM optimization; source sites retained in capture records"}


def compare_records(base, candidate, mode="combined", max_spread=0.005, min_change=0.001):
    if base["contract"] != candidate["contract"]:
        raise JuiceError("workload contracts differ (inputs, units, paths, oracle, environment or selection)")
    context_a, context_b = dict(base["context"]), dict(candidate["context"])
    libs_a, libs_b = context_a.pop("libraries", {}), context_b.pop("libraries", {})
    if context_a != context_b or any(libs_a[k] != libs_b[k] for k in libs_a.keys() & libs_b.keys()):
        raise JuiceError("measurement contexts differ (CPU, collector, libraries, kernel or execution paths)")
    # New/removed DT_NEEDED libraries are part of the generated program, not a
    # changed host installation. Existing shared libraries must still match.
    library_changes = differences(libs_a, libs_b)
    if base["workloads"].keys() != candidate["workloads"].keys():
        raise JuiceError("workload sets differ")
    if mode == "backend" and base["sources"] != candidate["sources"]:
        raise JuiceError("backend comparison requires identical application sources")
    if mode == "application" and base["build_config"] != candidate["build_config"]:
        raise JuiceError("application comparison requires identical compiler, flags, tools and build environment")
    report = {"version": "juice-comparison-v1", "base": base["name"], "candidate": candidate["name"],
              "mode": mode, "context_id": digest({**context_a, "libraries": {**libs_a, **libs_b}}), "collector": base["collector"],
              "source_roots": {"base": base.get("source_root"), "candidate": candidate.get("source_root")},
              "library_changes": library_changes,
              "base_id": digest(base), "candidate_id": digest(candidate), "workloads": {},
              "change_id": digest([base["sources"], base["build_config"], candidate["sources"], candidate["build_config"]]),
              "meaning": "100 × candidate instructions per completed unit / baseline; not a time ratio",
              "max_spread": max_spread, "min_change": min_change, "runtime_prediction": {"status": "uncalibrated"}}
    before_code, after_code = base["build"]["code"], candidate["build"]["code"]
    report["code"] = {"available": before_code.get("available", False) and after_code.get("available", False),
                      "sections": differences(before_code["sections"], after_code["sections"]),
                      "functions": differences(before_code["functions"], after_code["functions"]),
                      "scope": "static bytes and instruction sites, not executions"}
    cost_a, cost_b = base["build"].get("static_cost"), candidate["build"].get("static_cost")
    if cost_a and cost_b and cost_a.get("version") == cost_b.get("version") == "cost-v1":
        report["static_cost"] = {"scope": "static Core sites/LLVM remarks, not executions",
                                 "totals": differences(cost_a["totals"], cost_b["totals"])}
    else:
        report["static_cost"] = {"status": "unavailable or incompatible"}
    code_risks = ["linked library set changed; costs include library startup/work"] if library_changes else []
    if not report["code"]["available"]:
        code_risks.append("static code analysis unavailable; instruction mix unresolved")
    for metric in ("atomic_sites", "divide_sites"):
        before = sum(f.get(metric, 0) for f in before_code["functions"].values())
        after = sum(f.get(metric, 0) for f in after_code["functions"].values())
        if after > before:
            code_risks.append(f"static {metric} increased ({before} → {after}); hotness unresolved")
    ratios, weights = [], []
    for name, a in base["workloads"].items():
        b = candidate["workloads"][name]
        if a["correctness"] != b["correctness"]:
            raise JuiceError(f"{name}: baseline and candidate outputs differ")
        am, bm = a["metrics"]["instructions"], b["metrics"]["instructions"]
        if am["median"] <= 0 or bm["median"] <= 0 or a["units"] <= 0 or b["units"] <= 0:
            raise JuiceError(f"{name}: invalid work counts or units")
        ratio = (bm["median"] / b["units"]) / (am["median"] / a["units"])
        envelope = [(bm["min"] / b["units"]) / (am["max"] / a["units"]),
                    (bm["max"] / b["units"]) / (am["min"] / a["units"])]
        unstable = max(am["spread"], bm["spread"]) > max_spread
        direction = "uncertain" if unstable else (
            "unchanged" if envelope[0] >= 1 - min_change and envelope[1] <= 1 + min_change else
            "less-work" if envelope[1] < 1 - min_change else
            "more-work" if envelope[0] > 1 + min_change else "uncertain")
        risks = list(code_risks)
        for metric in ("atomics", "data_reads", "data_writes"):
            if metric in a["metrics"] and metric in b["metrics"]:
                if b["metrics"][metric]["median"] / b["units"] > a["metrics"][metric]["median"] / a["units"]:
                    risks.append(f"{metric} per completed unit increased")
        semantic = semantic_delta(a, b)
        if semantic["status"] == "compatible":
            for key, delta in semantic["totals"].items():
                if key not in CONTEXTUAL and (key.endswith("copy_bytes") or key in ("allocs", "shared_retains", "shared_releases")):
                    if delta["base"] is not None and delta["candidate"] is not None and delta["candidate"] > delta["base"]:
                        risks.append(f"semantic {key} increased")
        elif semantic["status"] == "incompatible":
            risks.append("semantic counter contracts changed")
        cell = {"juice": ratio * 100, "instruction_ratio": ratio, "ratio_envelope": envelope,
                "envelope_meaning": "observed min/max repeat range, not a statistical confidence interval",
                "direction": direction, "assessment": "mixed" if direction == "less-work" and risks else direction,
                "repeatable": not unstable, "risks": risks, "units": a["units"], "unit": a["unit"],
                "family": a["family"], "tier": a["tier"], "scope": a["scope"], "weight": a["weight"],
                "metrics": {k: {"base": a["metrics"].get(k), "candidate": b["metrics"].get(k)}
                            for k in sorted(a["metrics"].keys() | b["metrics"].keys())},
                "semantic": semantic,
                "functions": attribution(a["functions"], b["functions"], a["units"], b["units"]),
                "lines": attribution(a["lines"], b["lines"], a["units"], b["units"]),
                "coverage": "measured scenario only; whole-job representativeness unverified"}
        report["workloads"][name] = cell
        ratios.append(ratio)
        weights.append(a["weight"])
    report["suite_juice"] = 100 * math.exp(sum(w * math.log(r) for w, r in zip(weights, ratios)) / sum(weights))
    report["suite_meaning"] = "weighted geometric mean of selected scenarios; not whole-job runtime"
    return report


def render(report):
    lines = [f"Juice: {report['base']} → {report['candidate']}",
             "Baseline 100; lower means fewer instructions per completed unit, not proportionally less time.", "",
             "| Workload | Juice | Assessment | Repeat range |", "|---|---:|---|---|"]
    for name, cell in report["workloads"].items():
        low, high = cell["ratio_envelope"]
        lines.append(f"| {name} | {cell['juice']:.3f} | {cell['assessment']} | {low * 100:.3f}–{high * 100:.3f} |")
    lines += ["", f"Selected-scenario index: {report['suite_juice']:.3f} (weighted geometric mean).",
              f"Unchanged means within ±{report['min_change']:.1%}. Coverage: selected scenarios only.",
              "Repeat ranges are observations, not confidence intervals."]
    for name, cell in report["workloads"].items():
        details = [*cell["risks"]]
        semantic = cell["semantic"]
        if semantic["status"] == "compatible":
            for key, delta in list(semantic["totals"].items())[:12]:
                suffix = " (allocator-dependent)" if key in CONTEXTUAL else ""
                details.append(f"{key}: {delta['base']} → {delta['candidate']}{suffix}")
            for site in semantic["sites"][:5]:
                details.append(f"{site['path']}:{site['line']} {site['origin']} / {site['kind']}: "
                               f"{site['base']['count']} → {site['candidate']['count']} emitted executions ({site['match']})")
        for row in cell["functions"][:5]:
            details.append(f"{row['function']}: {row['delta_per_unit']:+.3f} instructions/{cell['unit']} ({row['file']})")
        if details:
            lines += ["", f"{name}:", "", *[f"- {detail}" for detail in details]]
    prediction = report.get("runtime_prediction", {})
    lines += ["", "Runtime estimate: " + prediction.get("status", "uncalibrated") + "."]
    for name, value in prediction.get("workloads", {}).items():
        if "ratio" in value:
            lines.append(f"- {name}: modeled runtime ratio {value['ratio']:.3f}; held-out max error {value['validation_max_error']:.1%}.")
        else:
            lines.append(f"- {name}: {value['reason']}.")
    return "\n".join(lines) + "\n"


def validate_scenarios(quick, larger, tolerance=0.03):
    if quick["context_id"] != larger["context_id"]:
        raise JuiceError("quick and validation collectors/contexts differ")
    if quick["change_id"] != larger["change_id"]:
        raise JuiceError("quick and validation reports compare different source/compiler changes")
    families = {}
    for cell in larger["workloads"].values():
        if cell["tier"] == "validation":
            families.setdefault(cell["family"], []).append(cell)
    result = {"version": "juice-scenario-validation-v1", "families": {}, "passed": True,
              "scope": "agreement for these changes and inputs, not a universal coverage guarantee"}
    for name, cell in quick["workloads"].items():
        if cell["tier"] != "quick":
            continue
        matches = [other for other in families.get(cell["family"], [])
                   if other["unit"] == cell["unit"] and other["scope"] == cell["scope"]]
        errors = [abs(cell["instruction_ratio"] / other["instruction_ratio"] - 1) for other in matches]
        directions = [cell["direction"] == other["direction"] for other in matches]
        passed = bool(matches) and cell["repeatable"] and all(o["repeatable"] for o in matches) and max(errors) <= tolerance and all(directions)
        result["families"].setdefault(cell["family"], {})[name] = {
            "passed": passed, "relative_errors": errors, "directions_agree": directions}
        result["passed"] &= passed
    if not result["families"]:
        raise JuiceError("no quick scenarios to validate")
    return result
