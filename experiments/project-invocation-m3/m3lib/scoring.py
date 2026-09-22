#!/usr/bin/env python3
"""Scoring: the pilot's headroom gate and the main cohort's restricted-time contrast.

Two rules from the runbook are implemented literally here.

*Primary score*: a submission that passes the full public and hidden workload
receives its elapsed participant time; non-submission, deadline expiry or hidden
rejection receives 900 seconds; a missing or corrupted record is **unknown** and
blocks a definitive decision, never zero seconds. Acceptance is reported
separately so a time score cannot conceal correctness losses.

*Uncertainty*: whole cases are resampled within each application, retaining every
paired repetition inside each selected case, 10,000 draws with a frozen seed.
There are six distinct tasks and two applications, so the interval is descriptive
and is never presented as a claim about programming projects generally.
"""

from __future__ import annotations

from datetime import datetime, timezone
import random
import statistics

DEADLINE_SECONDS = 900.0
BOOTSTRAP_DRAWS = 10000
BOOTSTRAP_SEED = 20260922


def restricted_seconds(record: dict | None) -> float | None:
    """The primary score for one cell: elapsed, 900, or unknown."""
    if not record:
        return None
    if record.get("record_error"):
        return None
    if record.get("accepted") and not record.get("timed_out"):
        elapsed = record.get("elapsed_seconds")
        if isinstance(elapsed, (int, float)) and 0 <= elapsed <= DEADLINE_SECONDS:
            return float(elapsed)
        return None
    return DEADLINE_SECONDS


def case_means(rows: list[dict]) -> dict:
    """Mean restricted time per (application, arm, case); None when any cell is unknown."""
    grouped: dict[tuple, list[float | None]] = {}
    for row in rows:
        grouped.setdefault((row["application"], row["arm"], row["case"]), []).append(
            restricted_seconds(row["record"]))
    means = {}
    for key, values in grouped.items():
        means[key] = None if any(value is None for value in values) else statistics.fmean(values)
    return means


def arm_mean(means: dict, application: str, arm: str) -> float | None:
    """Equal case weights inside one application."""
    values = [value for (app, row_arm, _), value in sorted(means.items())
              if app == application and row_arm == arm]
    if not values or any(value is None for value in values):
        return None
    return statistics.fmean(values)


def overall_mean(means: dict, arm: str) -> float | None:
    values = [value for (_, row_arm, _), value in sorted(means.items()) if row_arm == arm]
    if not values or any(value is None for value in values):
        return None
    return statistics.fmean(values)


def saving(means: dict, arm_left: str = "automatic", arm_right: str = "manual",
           application: str | None = None) -> float | None:
    """1 - mean(left) / mean(right), with the improvement sign: positive is better."""
    if application is None:
        left, right = overall_mean(means, arm_left), overall_mean(means, arm_right)
    else:
        left, right = arm_mean(means, application, arm_left), arm_mean(means, application, arm_right)
    if left is None or right is None or right == 0:
        return None
    return 1.0 - left / right


def bootstrap(rows: list[dict], applications: list[str], *, draws: int = BOOTSTRAP_DRAWS,
              seed: int = BOOTSTRAP_SEED) -> dict:
    """Resample whole cases within each application; keep every repetition inside a draw.

    A case selected twice contributes both copies, each carrying all of its
    repetitions, which is what keeps repeated sessions from being treated as
    independent generalisation examples.
    """
    by_application: dict[str, list[str]] = {}
    for row in rows:
        by_application.setdefault(row["application"], [])
        if row["case"] not in by_application[row["application"]]:
            by_application[row["application"]].append(row["case"])
    for application in applications:
        by_application.setdefault(application, [])
        by_application[application].sort()
    generator = random.Random(seed)
    samples: list[float] = []
    per_application: dict[str, list[float]] = {application: [] for application in applications}
    for _ in range(draws):
        draw_means: dict[tuple, list[float | None]] = {}
        for application in applications:
            cases = by_application[application]
            if not cases:
                continue
            picked = [cases[generator.randrange(len(cases))] for _ in cases]
            for case in picked:
                for row in rows:
                    if row["application"] == application and row["case"] == case:
                        draw_means.setdefault((application, row["arm"], case), []).append(
                            restricted_seconds(row["record"]))
        means = {key: (None if any(value is None for value in values) else statistics.fmean(values))
                 for key, values in draw_means.items()}
        for application in applications:
            value = saving(means, application=application)
            if value is not None:
                per_application[application].append(value)
        overall = saving(means)
        if overall is not None:
            samples.append(overall)

    def interval(values: list[float]) -> list[float] | None:
        if len(values) < 20:
            return None
        values = sorted(values)
        return [round(values[int(0.025 * len(values))], 4), round(values[int(0.975 * len(values))], 4)]

    return {"draws": draws, "seed": seed, "usable_draws": len(samples),
            "interval": interval(samples),
            "per_application": {application: interval(values)
                                for application, values in per_application.items()}}


def acceptance(rows: list[dict]) -> dict:
    result: dict[str, dict] = {}
    for row in rows:
        entry = result.setdefault(row["arm"], {"scheduled": 0, "recorded": 0, "accepted": 0,
                                               "public": 0, "hidden": 0})
        entry["scheduled"] += 1
        record = row.get("record")
        if record:
            entry["recorded"] += 1
            entry["accepted"] += 1 if record.get("accepted") else 0
            entry["public"] += 1 if record.get("public_acceptance") else 0
            entry["hidden"] += 1 if record.get("hidden_acceptance") else 0
    for application in sorted({row["application"] for row in rows}):
        for arm in sorted({row["arm"] for row in rows}):
            subset = [row for row in rows if row["application"] == application and row["arm"] == arm]
            if not subset:
                continue
            entry = result.setdefault(f"{application}/{arm}", {"scheduled": 0, "recorded": 0,
                                                               "accepted": 0, "public": 0, "hidden": 0})
            for row in subset:
                entry["scheduled"] += 1
                record = row.get("record")
                if record:
                    entry["recorded"] += 1
                    entry["accepted"] += 1 if record.get("accepted") else 0
                    entry["public"] += 1 if record.get("public_acceptance") else 0
                    entry["hidden"] += 1 if record.get("hidden_acceptance") else 0
    return result


def decision(overall_saving: float | None, interval: list[float] | None,
             per_application_saving: dict, acceptance_table: dict,
             avoidable_invocations: dict, evidence_complete: bool) -> dict:
    """Apply the runbook's predeclared decision rule and name the row it meets."""
    if not evidence_complete:
        return {"row": "unknown-evidence",
                "verdict": "a missing or corrupted record blocks a definitive decision; the cohort "
                           "is inconclusive rather than repaired by quietly adding sessions"}
    if overall_saving is None:
        return {"row": "unknown-evidence",
                "verdict": "restricted time could not be computed for every scheduled cell"}
    acceptance_manual = acceptance_table.get("manual", {}).get("accepted", 0)
    acceptance_automatic = acceptance_table.get("automatic", {}).get("accepted", 0)
    acceptance_fell = acceptance_automatic < acceptance_manual
    positive_applications = [name for name, value in per_application_saving.items()
                             if value is not None and value > 0]
    interval_above_zero = bool(interval) and interval[0] > 0
    fewer_invocations = avoidable_invocations.get("automatic", 0) < avoidable_invocations.get("manual", 0)
    if acceptance_fell:
        return {"row": "regression",
                "verdict": "acceptance fell; investigate the concrete regression, do not claim the "
                           "intervention helps"}
    if overall_saving < 0:
        return {"row": "regression",
                "verdict": "total delivery time worsened without an offsetting correctness benefit"}
    if (overall_saving >= 0.20 and interval_above_zero
            and len(positive_applications) == len(per_application_saving) and fewer_invocations):
        return {"row": "keep",
                "verdict": "at least 20% overall time saving with an interval above zero, positive "
                           "point saving in both applications, no lower observed acceptance and "
                           "fewer avoidable invocation failures"}
    return {"row": "inconclusive",
            "verdict": "smaller saving, mixed applications, uncertain interval or insufficient "
                       "invocation reduction: report inconclusive or below practical target and "
                       "stop this research line for now"}


def break_even(configuration_seconds: float, per_task_saving_seconds: float | None) -> dict:
    if not per_task_saving_seconds or per_task_saving_seconds <= 0:
        return {"configuration_seconds": configuration_seconds, "tasks_to_break_even": None,
                "note": "no positive per-task time saving was observed, so no break-even is demonstrated"}
    return {"configuration_seconds": configuration_seconds,
            "tasks_to_break_even": round(configuration_seconds / per_task_saving_seconds, 2),
            "note": "setup time divided by observed positive per-task time saved"}


def captured() -> str:
    return datetime.now(timezone.utc).isoformat()
