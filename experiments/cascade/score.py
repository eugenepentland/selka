#!/usr/bin/env python3
"""Score the cascading-benefit experiment.

Reads the run records written by ``run.py`` and reports, per task and arm:

* the verified cost (input + output + reasoning tokens, summed over the session
  log; cache reads are reported beside it, never added);
* the run-to-run spread, which rule 1 of the decision rule compares a margin to;
* ``gain(P, tau) = cost(B, tau) - cost(P, tau)`` and ``R(P)``, the pack total
  minus the designer's upfront cost;
* the two coupling columns the pack watches: files touched outside
  ``sexpr/printer.my`` on T4, and new boolean parameters on T6;
* the transfer-probe scores, when the probes have been run.

The decision rule is evaluated, not applied silently: the report prints whether
each of its three clauses holds, so a pack revision is a deliberate act.

    python3 experiments/cascade/score.py
    python3 experiments/cascade/score.py --json experiments/cascade/score.json
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
TASKS = [f"T{i}" for i in range(1, 8)]
PRINTER = "sexpr/printer.my"


CHAIN_KEYED = re.compile(r"chain-r(\d+)-s(\d+)-a(\d+)$")


def chain_keys(stem: str) -> tuple[int, int, int] | None:
    """(repetition, step, attempt) for a chained record, in either naming era."""
    match = CHAIN_KEYED.match(stem)
    if match:
        return int(match.group(1)), int(match.group(2)), int(match.group(3))
    if stem.startswith("chain-") and stem[6:].isdigit():  # pre-keying records
        return 1, int(stem[6:]), 1
    return None


def is_run_record(path: Path) -> bool:
    """True for a live run record, false for a preserved verdict or a transcript."""
    return path.stem.isdigit() or chain_keys(path.stem) is not None


def load_cohort(path: Path) -> dict:
    """Read a frozen cohort manifest: which records belong to which experiment."""
    manifest = json.loads(path.read_text())
    manifest["_path"] = str(path)
    return manifest


def cohort_keys(manifest: dict) -> set[tuple[str, str, str]]:
    keys = set()
    for row in manifest.get("runs", []):
        keys.add((row["arm"], row["task"], str(row["run"])))
    return keys


def cohort_record_digest(record: dict) -> str:
    """A digest of a record's measurement content, not of its file bytes.

    Enriching records with new derived signals must not look like tampering, and
    a substituted record must not pass: the projection is the identity, the
    verdict, the raw token fields and cost terms, the toolchain, the launch
    environment, the files changed and the verification steps.
    """
    usage = ((record.get("session") or {}).get("usage")) or {}
    projection = {
        "arm": record.get("arm"),
        "task": record.get("task"),
        "run": record.get("run"),
        "chain_step": record.get("chain_step"),
        "verdict": record.get("verdict"),
        "usage": {key: usage.get(key) for key in
                  ("inputTokens", "outputTokens", "reasoningTokens", "cacheReadTokens", "totalTokens",
                   "cost_v1_input_output_reasoning", "cost_v2_input_output", "provider_total_tokens")},
        "toolchain": record.get("toolchain"),
        "env": (record.get("session_launch") or {}).get("env"),
        "files_changed": (record.get("diff") or {}).get("files_changed"),
        "steps": [step.get("status") for step in (record.get("verify") or {}).get("steps", [])],
    }
    return hashlib.sha256(json.dumps(projection, sort_keys=True).encode()).hexdigest()


def cohort_drift(manifest: dict) -> list[str]:
    """Records whose measurement content differs from the frozen manifest."""
    drift = []
    for row in manifest.get("runs", []):
        record = RUNS / row["arm"] / row["task"] / f"{row['run']}.json"
        if not record.is_file():
            drift.append(f"missing {record}")
            continue
        payload = json.loads(record.read_text())
        digest = cohort_record_digest(payload)
        expected = row.get("digest") or row.get("sha256")
        if expected and digest != expected:
            drift.append(f"changed {record}")
    return drift


def load_runs(cohort: dict | None = None) -> dict[str, dict[str, list[dict]]]:
    table: dict[str, dict[str, list[dict]]] = {}
    allowed = cohort_keys(cohort) if cohort else None
    for path in sorted(RUNS.glob("*/*/*.json")):
        if not is_run_record(path):
            continue
        record = json.loads(path.read_text())
        arm, task, run = record.get("arm"), record.get("task"), record.get("run")
        if not arm or not task or record.get("chain"):
            continue
        if allowed is not None and (arm, task, str(run)) not in allowed:
            continue
        table.setdefault(arm, {}).setdefault(task, []).append(record)
    for arm in table:
        for task in table[arm]:
            table[arm][task].sort(key=lambda row: row.get("run", 0))
    return table


# Which token total counts as "cost". v1 is what the cascade published: it adds
# reasoning to output, but the provider reports reasoning *inside* output, so v1
# double-counts it. v2 is input + output (no cache reads, which the plan excludes
# because they measure the harness's caching). `total` is the provider's own
# total, cache reads included. Simulated runs stamp the option into the report.
COST_TERMS = {
    "v1": "cost_v1_input_output_reasoning",
    "v2": "cost_v2_input_output",
    "total": "provider_total_tokens",
}
COST_TERM = "v2"


def cost_of(record: dict) -> float | None:
    usage = ((record.get("session") or {}).get("usage")) or {}
    if not usage:
        return None
    field = COST_TERMS[COST_TERM]
    if field in usage:
        return usage[field]
    if COST_TERM == "v2":  # older records before the field existed
        return usage.get("cost")
    return None


def cohort_models(table: dict[str, dict[str, list[dict]]]) -> dict[str, str]:
    """The most frequent model per task, across arms: the cohort the plan discards against."""
    models: dict[str, dict[str, int]] = {}
    for arm, tasks in table.items():
        for task, records in tasks.items():
            for record in records:
                for model, count in (((record.get("session") or {}).get("models")) or {}).items():
                    bucket = models.setdefault(task, {})
                    bucket[model] = bucket.get(model, 0) + count
    return {task: max(counts.items(), key=lambda item: item[1])[0] for task, counts in models.items() if counts}


def model_matches_cohort(record: dict, cohort: str | None) -> bool:
    if cohort is None:
        return True
    models = ((record.get("session") or {}).get("models")) or {}
    return not models or set(models) == {cohort}


def summarise(records: list[dict]) -> dict:
    """Costs come from runs that verified: a run that failed scores nothing.

    A run whose toolchain died is neither a pass nor a wrong answer; it is
    reported as discarded and the cell needs a rerun, so it contributes no cost.
    """
    scored = [row for row in records if row.get("verdict") == "passed" and cost_of(row) is not None]
    costs = [cost_of(row) for row in scored]
    passed = list(scored)
    failed = [row for row in records if row.get("verdict") == "failed"]
    discarded = [row.get("verdict") for row in records if str(row.get("verdict", "")).startswith("discarded")]
    # Every attempt counts in the all-attempt total: a cheaper design that fails
    # more often must not look cheap by dropping its failures from the sum.
    all_costs = [cost_of(row) for row in records if cost_of(row) is not None]
    attempts = len(records)
    successes = len(passed)
    models = sorted({model for row in scored for model in ((row.get("session") or {}).get("models") or {})})
    usage_totals = {"inputTokens": 0, "outputTokens": 0, "reasoningTokens": 0, "cacheReadTokens": 0}
    for row in scored:
        usage = ((row.get("session") or {}).get("usage")) or {}
        for key in usage_totals:
            usage_totals[key] += usage.get(key, 0)
    return {
        "runs": len(records),
        "attempts": attempts,
        "successes": successes,
        "success_rate": round(successes / attempts, 3) if attempts else None,
        "all_attempt_cost": sum(all_costs) if all_costs else None,
        "scored": len(scored),
        "passed": len(passed),
        "failed": [row.get("run") for row in failed],
        "solved": len(passed) == len(records) and bool(records),
        "discarded": discarded,
        "costs": costs,
        "median_cost": statistics.median(costs) if costs else None,
        "min_cost": min(costs) if costs else None,
        "max_cost": max(costs) if costs else None,
        "spread": (max(costs) - min(costs)) if costs else None,
        "usage_totals": usage_totals,
        "models": models,
    }


def upfront(arm: str) -> dict:
    path = HERE / "designs" / arm / "evidence" / "designer.json"
    if not path.is_file():
        return {"cost": None, "source": None}
    evidence = json.loads(path.read_text())
    usage = evidence.get("session", {}).get("usage", evidence.get("usage", {}))
    cost = usage.get(COST_TERMS[COST_TERM])
    if cost is None:
        cost = usage.get("cost")
    return {"cost": cost, "source": str(path), "tokens": usage}


def coupling(table: dict[str, dict[str, list[dict]]]) -> dict:
    """T4 files outside the printer; T6 new boolean parameters, per arm."""
    result: dict[str, dict] = {}
    for arm, tasks in table.items():
        rows = {"t4_files_outside_printer": [], "t4_runs_touching_other_files": 0, "t6_new_bool_params": []}
        for record in tasks.get("T4", []):
            files = (record.get("diff") or {}).get("files_changed", [])
            outside = [name for name in files if name != PRINTER]
            rows["t4_files_outside_printer"].extend(outside)
            if outside:
                rows["t4_runs_touching_other_files"] += 1
        for record in tasks.get("T6", []):
            rows["t6_new_bool_params"].append((record.get("diff") or {}).get("new_bool_params", 0))
        result[arm] = rows
    return result


def transfer() -> dict:
    probes = {}
    for path in sorted((HERE / "probes").glob("*/*.json")):
        record = json.loads(path.read_text())
        arm = record.get("arm", path.parent.name)
        bucket = probes.setdefault(arm, {"probes": 0, "correct": 0, "total": 0, "bytes_read": 0})
        bucket["probes"] += 1
        bucket["correct"] += record.get("correct", 0)
        bucket["total"] += record.get("questions", 0)
        bucket["bytes_read"] += record.get("bytes_read", 0)
    for arm, bucket in probes.items():
        bucket["score"] = (bucket["correct"] / bucket["total"]) if bucket["total"] else None
    return probes


def load_chains() -> dict[str, dict[str, list[dict]]]:
    """Chained runs, keyed by arm and then by their position in the chain."""
    chains: dict[str, dict[str, list[dict]]] = {}
    for path in sorted(RUNS.glob("*/*/chain-*.json")):
        keys = chain_keys(path.stem)
        if keys is None:
            continue
        record = json.loads(path.read_text())
        arm = record.get("arm")
        if not arm:
            continue
        repetition, step, _ = keys
        record.setdefault("chain_repetition", repetition)
        chains.setdefault(arm, {}).setdefault(str(step), []).append(record)
    return chains


def pairs(table: dict[str, dict[str, list[dict]]], baseline: str) -> list[dict]:
    """One row per (task, run) with the baseline and treatment costs side by side.

    This is the preference data the proposals describe — design X beat design Y
    because the same later change cost less on it — emitted straight from the run
    records rather than reconstructed from the aggregate table.
    """
    rows = []
    tasks = sorted({task for arm in table for task in table[arm]})
    for task in tasks:
        base = {record.get("run"): record for record in table.get(baseline, {}).get(task, [])}
        for arm in sorted(table):
            if arm == baseline:
                continue
            for record in table[arm].get(task, []):
                partner = base.get(record.get("run"))
                rows.append({
                    "task": task,
                    "run": record.get("run"),
                    "baseline_arm": baseline,
                    "baseline_verdict": (partner or {}).get("verdict"),
                    "baseline_cost": cost_of(partner) if partner else None,
                    "arm": arm,
                    "verdict": record.get("verdict"),
                    "cost": cost_of(record),
                    "gain": None if not partner else (
                        None if cost_of(partner) is None or cost_of(record) is None else cost_of(partner) - cost_of(record)
                    ),
                    "model": sorted(((record.get("session") or {}).get("models") or {})),
                })
    return rows


def main() -> int:
    global COST_TERM
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", type=Path, help="also write the report here")
    parser.add_argument("--pairs", type=Path, help="write the paired per-run comparison as JSON Lines")
    parser.add_argument("--cohort", type=Path, default=HERE / "cohorts" / "original.json",
                        help="frozen cohort manifest (default: the published cascade cohort)")
    parser.add_argument("--all-runs", action="store_true", help="ignore the cohort and score every record on disk")
    parser.add_argument("--cost-term", choices=sorted(COST_TERMS), default="v2",
                        help="v2 (input+output, default), v1 (as published: adds reasoning again), total (provider total)")
    parser.add_argument("--baseline", default="B", help="baseline arm (default B)")
    parser.add_argument("--treatment", default="P1", help="treatment arm (default P1)")
    parser.add_argument("--control", default="P2", help="control arm (default P2)")
    args = parser.parse_args()
    COST_TERM = args.cost_term
    cohort = None if args.all_runs else load_cohort(args.cohort)
    table = load_runs(cohort)
    drift = cohort_drift(cohort) if cohort else []
    scored_paths = {str(RUNS / row["arm"] / row["task"] / f"{row['run']}.json") for row in (cohort or {}).get("runs", [])}
    outside = []
    for path in sorted(RUNS.glob("*/*/*.json")):
        if is_run_record(path) and str(path) not in scored_paths:
            record = json.loads(path.read_text())
            if record.get("verdict") == "passed":
                outside.append(f"{record['arm']}/{record['task']}/{path.stem}")
    arms = sorted(table)
    cohorts = cohort_models(table)
    off_cohort = [
        f"{arm}/{task}/{record.get('run')}"
        for arm, tasks in table.items()
        for task, records in tasks.items()
        for record in records
        if not model_matches_cohort(record, cohorts.get(task))
    ]
    summaries = {arm: {task: summarise(table[arm].get(task, [])) for task in TASKS} for arm in arms}
    gains: dict[str, dict] = {}
    if args.baseline in summaries:
        for arm in arms:
            if arm == args.baseline:
                continue
            per_task = {}
            for task in TASKS:
                base = summaries[args.baseline][task]["median_cost"]
                other = summaries[arm][task]["median_cost"]
                per_task[task] = None if base is None or other is None else base - other
            total = sum(value for value in per_task.values() if value is not None)
            design = upfront(arm)
            gains[arm] = {
                "per_task": per_task,
                "pack_gain": total,
                "upfront": design["cost"],
                "upfront_source": design["source"],
                "R": None if design["cost"] is None else total - design["cost"],
            }
    report = {
        "version": 1,
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "cost_term": COST_TERM,
        "cohort": None if cohort is None else {
            "name": cohort.get("name"),
            "path": cohort.get("_path"),
            "sha256": hashlib.sha256(Path(cohort["_path"]).read_bytes()).hexdigest(),
            "captured_utc": cohort.get("captured_utc"),
            "records": len(cohort.get("runs", [])),
            "policy": cohort.get("policy"),
            "drift": drift,
            "records_outside_cohort": outside,
        },
        "tasks": TASKS,
        "arms": arms,
        "cohort_models": cohorts,
        "runs_off_cohort": off_cohort,
        "summaries": summaries,
        "upfront": {arm: upfront(arm) for arm in arms},
        "gains": gains,
        "coupling": coupling(table),
        "transfer": transfer(),
    }
    report["chains"] = {
        arm: {
            step: {
                "task": records[0].get("task") if records else None,
                "median_cost": statistics.median(costs) if (costs := [cost_of(row) for row in records if cost_of(row) is not None]) else None,
                "verdicts": [row.get("verdict") for row in records],
            }
            for step, records in sorted(steps.items())
        }
        for arm, steps in load_chains().items()
    }
    report["decision"] = decide(report, args.baseline, args.treatment, args.control)
    print(render(report, args.baseline, args.treatment, args.control))
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    if args.pairs:
        rows = pairs(table, args.baseline)
        args.pairs.write_text("".join(json.dumps(row) + "\n" for row in rows))
    return 0


def decide(report: dict, baseline: str, treatment: str, control: str) -> dict:
    """Rule 1 (five of seven, beyond the spread), rule 2 (R > 0), rule 3 (control does not pass rule 1)."""
    def rule_one(arm: str) -> dict:
        wins = losses = 0
        detail = {}
        for task in report["tasks"]:
            gain = (report["gains"].get(arm, {}).get("per_task") or {}).get(task)
            spread = max(
                report["summaries"].get(baseline, {}).get(task, {}).get("spread") or 0,
                report["summaries"].get(arm, {}).get(task, {}).get("spread") or 0,
            )
            if gain is None:
                detail[task] = "no data"
                continue
            if gain > spread:
                wins += 1
                detail[task] = f"win by {gain:.0f} (spread {spread:.0f})"
            elif gain < -spread:
                losses += 1
                detail[task] = f"loss by {-gain:.0f} (spread {spread:.0f})"
            else:
                detail[task] = f"within spread ({gain:+.0f}, spread {spread:.0f})"
        return {"wins": wins, "losses": losses, "holds": wins >= 5 and losses == 0, "detail": detail}

    def success_rates(arm: str) -> dict:
        rates = {}
        for task in report["tasks"]:
            summary = report["summaries"].get(arm, {}).get(task) or {}
            if summary.get("attempts"):
                rates[task] = summary.get("success_rate")
        return rates

    baseline_rates = success_rates(baseline)
    treatment_rates = success_rates(treatment)
    regressions = [task for task, rate in treatment_rates.items()
                   if rate is not None and baseline_rates.get(task) is not None and rate < baseline_rates[task]]

    treatment_rule = rule_one(treatment) if treatment in report["arms"] else {"holds": None}
    control_rule = rule_one(control) if control in report["arms"] else {"holds": None}
    recovery = (report["gains"].get(treatment) or {}).get("R")
    return {
        "rule_0_success_not_worse": {
            "baseline_rates": baseline_rates,
            "treatment_rates": treatment_rates,
            "regressed_tasks": regressions,
            "holds": not regressions and bool(treatment_rates),
        },
        "rule_1_treatment_beats_baseline": treatment_rule,
        "rule_2_upfront_recovered": {"R": recovery, "holds": None if recovery is None else recovery > 0},
        "rule_3_control_does_not_win": {"control": control_rule, "holds": None if control_rule.get("holds") is None else not control_rule["holds"]},
        "justified": bool(
            not regressions
            and treatment_rule.get("holds")
            and recovery is not None and recovery > 0
            and control_rule.get("holds") is False
        ),
    }


def render(report: dict, baseline: str, treatment: str, control: str) -> str:
    lines = []
    arms = report["arms"]
    cohort = report.get("cohort")
    if cohort:
        lines.append(f"cohort {cohort['name']} ({cohort['records']} records, sha256 {cohort['sha256'][:12]}), "
                     f"cost term {report['cost_term']}")
        if cohort["drift"]:
            lines.append(f"  COHORT DRIFT: {len(cohort['drift'])} record(s) changed — {', '.join(cohort['drift'][:3])}")
        if cohort["records_outside_cohort"]:
            lines.append(f"  not in cohort: {', '.join(cohort['records_outside_cohort'][:6])}"
                         + (" ..." if len(cohort["records_outside_cohort"]) > 6 else ""))
    else:
        lines.append(f"all runs on disk, cost term {report['cost_term']}")
    header = f"{'task':<6}" + "".join(f"{arm:>28}" for arm in arms)
    lines.append(f"cost per task (median {COST_TERMS[report['cost_term']]}; solved/attempted)")
    lines.append(header)
    for task in report["tasks"]:
        row = f"{task:<6}"
        for arm in arms:
            summary = report["summaries"][arm][task]
            if summary["median_cost"] is None:
                row += f"{'-':>28}"
            else:
                note = f"{summary['successes']}/{summary['attempts']}"
                if summary["failed"]:
                    note += f" f{len(summary['failed'])}"
                if summary["discarded"]:
                    note += f" d{len(summary['discarded'])}"
                row += f"{summary['median_cost']:>18.0f} {note:<7}"
        lines.append(row)
    lines.append("")
    lines.append("spread per task (max - min over scored runs)")
    lines.append(header)
    for task in report["tasks"]:
        row = f"{task:<6}"
        for arm in arms:
            summary = report["summaries"][arm][task]
            row += f"{'-' if summary['spread'] is None else format(summary['spread'], '.0f'):>28}"
        lines.append(row)
    if report["gains"]:
        lines.append("")
        lines.append(f"gain over {baseline} (positive = cheaper), and R(P) after upfront cost")
        for arm, gain in report["gains"].items():
            per_task = " ".join(
                f"{task}:{'-' if value is None else format(value, '.0f')}" for task, value in gain["per_task"].items()
            )
            lines.append(f"  {arm}: {per_task}")
            lines.append(f"     pack gain {gain['pack_gain']:.0f}, upfront {gain['upfront']}, R = {gain['R']}")
    lines.append("")
    lines.append("coupling")
    for arm, rows in report["coupling"].items():
        outside = rows["t4_files_outside_printer"]
        lines.append(
            f"  {arm}: T4 runs touching files outside {PRINTER}: {rows['t4_runs_touching_other_files']}"
            f" ({', '.join(sorted(set(outside))) or 'none'});"
            f" T6 new boolean params: {rows['t6_new_bool_params'] or 'none'}"
        )
    if report["transfer"]:
        lines.append("")
        lines.append("transfer probes")
        for arm, bucket in report["transfer"].items():
            lines.append(f"  {arm}: {bucket['correct']}/{bucket['total']} correct, {bucket['bytes_read']} bytes read")
    if report.get("cohort_models"):
        lines.append("")
        lines.append("model cohort per task (a run whose model differs is discarded)")
        for task, model in sorted(report["cohort_models"].items()):
            lines.append(f"  {task}: {model}")
        if report.get("runs_off_cohort"):
            lines.append(f"  off-cohort runs: {', '.join(report['runs_off_cohort'])}")
    if report.get("chains"):
        lines.append("")
        lines.append("chained runs (T2 -> T3 -> T7, each starting from the previous result)")
        for arm, steps in report["chains"].items():
            row = " ".join(
                f"{step}:{details['task']}={'-' if details['median_cost'] is None else format(details['median_cost'], '.0f')}"
                for step, details in steps.items()
            )
            lines.append(f"  {arm}: {row}")
    lines.append("")
    decision = report["decision"]
    lines.append("decision rule")
    lines.append(f"  rule 0 ({treatment} solves at least as often as {baseline}): {decision['rule_0_success_not_worse']}")
    lines.append(f"  rule 1 ({treatment} beats {baseline} on >=5 of 7 beyond the spread): {decision['rule_1_treatment_beats_baseline']}")
    lines.append(f"  rule 2 (R > 0): {decision['rule_2_upfront_recovered']}")
    lines.append(f"  rule 3 ({control} does not satisfy rule 1): {decision['rule_3_control_does_not_win']}")
    lines.append(f"  justified: {decision['justified']}")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
