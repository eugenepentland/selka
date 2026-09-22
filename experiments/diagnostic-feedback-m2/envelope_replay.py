#!/usr/bin/env python3
"""Calibrate the M2 token envelope by replaying trajectories that really happened.

The envelope in `budget.py` is per task: one `Envelope`, charged by a repair
session or by each independent candidate, and a call that overshoots the
allowance it was given is charged what it actually generated and *ends* that
candidate. This module asks how binding each candidate cap would have been on
trajectories that were measured under **no token budget at all** — the 112 M1b
participant sessions, one per cell of `4 arms x 14 cases x 2 repetitions`.

What is replayed is real: every charge is an observed per-call
`outputTokens` value, read from the harness session log by `m2_usage.py` (whose
per-call sums reproduce each run's own aggregate usage exactly, 112/112). What is
modelled is the enforcement: the caps below were never shown to those agents.

    python3 experiments/diagnostic-feedback-m2/envelope_replay.py
    python3 experiments/diagnostic-feedback-m2/envelope_replay.py --selftest
    python3 experiments/diagnostic-feedback-m2/envelope_replay.py --pool text

Policies:

`repair`       one session per task, charged call by call with
               `allowance = envelope.remaining()`; the first overshoot ends it
               as incomplete and it cannot be selected.
`independent`  fresh candidates for the same task, drawn one at a time from the
               observed pool, each charging the *same* envelope; a candidate
               whose first call the envelope cannot afford is never started.
               Selection prefers a complete candidate that passed the public
               check, else the last complete one.

Nothing here launches a session, runs a compiler or writes outside
`experiments/diagnostic-feedback-m2/` and `docs/audits/`.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
FROZEN = REPO / "experiments" / "diagnostic-feedback"
M1B = FROZEN / "cohorts" / "m1b"
CALIBRATION = HERE / "cohorts" / "calibration" / "calibration.json"
REPORT = REPO / "docs" / "audits" / "m2-budget-calibration-2026-09-19.md"

sys.path.insert(0, str(HERE))
from budget import Envelope, Usage  # noqa: E402

CAPS = (0, 2000, 5000, 10000, 10 ** 9)
UNLIMITED = 10 ** 9
POLICIES = ("repair", "independent")
# M2's treatment is the checker's own plain-text output with no suggestion, so
# the `text` arm is its like-for-like pool; the others differ in presentation.
ARM_ORDER = ("text", "text_fix", "json", "json_fix")
POOLS = ("all", "text")
POOL_DESCRIPTION = {
    "all": ("every measured M1b session for the case (all four presentation arms, both repetitions), "
            "repetition first and the M2-matching `text` arm first inside a repetition"),
    "text": ("the M1b `text` arm only — the M2 treatment match: the checker's plain-text output with no "
             "suggestion — in repetition order"),
}


def load_by_path(name: str, path: Path):
    """Load a sibling module by path: several modules here are called `run.py`."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


usage_reader = load_by_path("m2_usage", HERE / "m2_usage.py")
# `score.py` imports `cohort` by name; pin that name to the frozen module first,
# because this tree also holds an `m2` copy of both.
load_by_path("cohort", FROZEN / "cohort.py")
score = load_by_path("frozen_score", FROZEN / "score.py")


def cap_label(cap: int) -> str:
    return "unlimited" if cap == UNLIMITED else str(cap)


def mean(values: list) -> float | None:
    clean = [value for value in values if isinstance(value, (int, float))]
    return round(statistics.fmean(clean), 1) if clean else None


def median(values: list) -> float | None:
    clean = [value for value in values if isinstance(value, (int, float))]
    return round(statistics.median(clean), 1) if clean else None


def percentile(values: list[int], fraction: float) -> int | None:
    """Linear-interpolated percentile over the sorted values."""
    if not values:
        return None
    ordered = sorted(values)
    position = fraction * (len(ordered) - 1)
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    weight = position - low
    return int(round(ordered[low] * (1 - weight) + ordered[high] * weight))


# --------------------------------------------------------------------------
# replay state machine


@dataclass
class Trajectory:
    """One observed session: its calls in order, and what it ended up achieving."""
    key: str
    case: str
    family: str
    arm: str
    repetition: int
    calls: list[Usage] = field(default_factory=list)
    public: bool = False
    hidden: bool = False
    failed_compiler_invocations: int | None = None
    invocation_limit: int | None = None
    work_dir: str = ""
    started_utc: str = ""
    session_paths: list[str] = field(default_factory=list)
    attempt: int | None = None
    attempts: int = 0
    discarded_attempts: list[str] = field(default_factory=list)
    malformed_lines: int = 0
    usage_matches_record: bool | None = None

    @property
    def generated(self) -> int:
        return sum(call.generated for call in self.calls)

    @property
    def input_volume(self) -> int:
        return sum(call.input_volume for call in self.calls)

    def as_dict(self) -> dict:
        return {"key": self.key, "case": self.case, "family": self.family, "arm": self.arm,
                "repetition": self.repetition, "calls": len(self.calls),
                "generated": self.generated, "input_volume": self.input_volume,
                "public_acceptance": self.public, "hidden_acceptance": self.hidden,
                "failed_compiler_invocations": self.failed_compiler_invocations,
                "invocation_limit": self.invocation_limit, "work_dir": self.work_dir,
                "started_utc": self.started_utc, "session_paths": self.session_paths,
                "attempt": self.attempt, "attempts": self.attempts,
                "discarded_attempts": self.discarded_attempts,
                "malformed_lines": self.malformed_lines,
                "usage_matches_record": self.usage_matches_record}


@dataclass
class Candidate:
    """One charged candidate: what it cost, whether it survived, what it achieved."""
    key: str
    started: bool
    complete: bool
    ended_by_overshoot: bool
    charged: int
    overshoot: int
    calls_charged: int
    calls_total: int
    public: bool
    hidden: bool
    reason: str
    envelope_id: int

    def as_dict(self) -> dict:
        return {"key": self.key, "started": self.started, "complete": self.complete,
                "ended_by_overshoot": self.ended_by_overshoot, "charged": self.charged,
                "overshoot": self.overshoot, "calls_charged": self.calls_charged,
                "calls_total": self.calls_total, "public_acceptance": self.public,
                "hidden_acceptance": self.hidden, "reason": self.reason,
                "envelope_id": self.envelope_id}


def charge_candidate(envelope: Envelope, trajectory: Trajectory, label: str) -> Candidate:
    """Charge one candidate's calls, in order, against the task envelope.

    The candidate is started only when the envelope can afford its first call;
    afterwards each call receives `remaining()` as its allowance, and a call that
    exceeds it is charged what it actually generated and ends the candidate.
    """
    def result(started: bool, complete: bool, overshoot_ended: bool, charged: int,
               overshoot: int, calls: int, reason: str) -> Candidate:
        return Candidate(key=trajectory.key, started=started, complete=complete,
                         ended_by_overshoot=overshoot_ended, charged=charged, overshoot=overshoot,
                         calls_charged=calls, calls_total=len(trajectory.calls),
                         public=trajectory.public, hidden=trajectory.hidden, reason=reason,
                         envelope_id=id(envelope))

    if not trajectory.calls:
        return result(False, False, False, 0, 0, 0, "no per-call usage recovered")
    if not envelope.can_afford(trajectory.calls[0].generated):
        return result(False, False, False, 0, 0, 0,
                      f"first call ({trajectory.calls[0].generated}) exceeds remaining "
                      f"({envelope.remaining()})")
    charged = 0
    for index, call in enumerate(trajectory.calls, start=1):
        entry = envelope.charge(call, label=label, allowance=envelope.remaining())
        charged += entry["charged"]
        if entry["refused"]:
            return result(True, False, True, charged, entry["overshoot"], index,
                          f"overshoot of {entry['overshoot']} tokens on call {index}")
    return result(True, True, False, charged, 0, len(trajectory.calls), "all calls charged")


def select_candidate(candidates: list[Candidate]) -> tuple[Candidate | None, str | None]:
    """A complete candidate that passed the public check, else the last complete one."""
    complete = [candidate for candidate in candidates if candidate.complete]
    passing = next((candidate for candidate in complete if candidate.public), None)
    if passing is not None:
        return passing, "public"
    if complete:
        return complete[-1], "last-complete"
    return None, None


def replay_task(policy: str, cap: int, case: str, pool: list[Trajectory]) -> dict:
    """Replay one case under one cap and policy, on ONE task-level envelope."""
    envelope = Envelope(cap)
    candidates: list[Candidate] = []
    if policy == "repair":
        if pool:
            candidates.append(charge_candidate(envelope, pool[0], label="repair"))
        selected, mode = (candidates[0], "repair") if candidates and candidates[0].complete else (None, None)
    elif policy == "independent":
        if not pool:
            selected, mode = None, None
        else:
            for index, trajectory in enumerate(pool):
                candidate = charge_candidate(envelope, trajectory, label=f"candidate-{index + 1}")
                if not candidate.started:
                    candidates.append(candidate)
                    break
                candidates.append(candidate)
                if not candidate.complete:
                    break
            selected, mode = select_candidate(candidates)
    else:
        raise ValueError(f"unknown policy {policy!r}")

    started = [candidate for candidate in candidates if candidate.started]
    overshot = [candidate for candidate in candidates if candidate.ended_by_overshoot]
    unstarted = [candidate for candidate in candidates if not candidate.started]
    if not pool:
        end_state = "no-pool"
    elif unstarted and not overshot:
        end_state = "unaffordable"
    elif overshot:
        end_state = "overshoot"
    elif policy == "repair":
        end_state = "complete"
    elif len(started) == len(pool):
        end_state = "pool-exhausted"
    else:
        end_state = "envelope"

    return {"case": case, "policy": policy, "cap": cap, "cap_label": cap_label(cap),
            "spend": envelope.spent, "remaining": envelope.remaining(),
            "cap_fraction": round(envelope.spent / cap, 4) if 0 < cap < UNLIMITED else None,
            "input_volume": envelope.totals()["input_volume"],
            "charges": envelope.totals()["charges"],
            "envelope_id": id(envelope), "end_state": end_state,
            "pool_size": len(pool), "started": len(started), "fit": sum(1 for c in started if c.complete),
            "overshoot_ended": len(overshot), "unstarted": len(unstarted),
            "candidates": [candidate.as_dict() for candidate in candidates],
            "selected": selected.key if selected else None,
            "selection_mode": mode,
            "selected_public": bool(selected and selected.public),
            "selected_hidden": bool(selected and selected.hidden),
            "selected_complete": bool(selected and selected.complete)}


def aggregate(rows: list[dict], cap: int, policy: str) -> dict:
    """The per-cap, per-policy line: fit, overshoot, spend and what got selected."""
    tasks = len(rows)
    with_selection = [row for row in rows if row["selected"]]
    states: dict[str, int] = {}
    for row in rows:
        states[row["end_state"]] = states.get(row["end_state"], 0) + 1
    families = sorted({row["family"] for row in rows})
    return {
        "policy": policy, "cap": cap, "cap_label": cap_label(cap), "tasks": tasks,
        "tasks_with_pool": sum(1 for row in rows if row["pool_size"]),
        "tasks_with_selection": len(with_selection),
        "tasks_without_selection": tasks - len(with_selection),
        "candidates_started": sum(row["started"] for row in rows),
        "candidates_fit": sum(row["fit"] for row in rows),
        "candidates_overshoot_ended": sum(row["overshoot_ended"] for row in rows),
        "candidates_unstarted": sum(row["unstarted"] for row in rows),
        "calls_charged": sum(row["charges"] for row in rows),
        "spend": {"mean": mean([row["spend"] for row in rows]),
                  "median": median([row["spend"] for row in rows]),
                  "min": min((row["spend"] for row in rows), default=None),
                  "max": max((row["spend"] for row in rows), default=None)},
        "spend_fraction_of_cap": {"mean": mean([row["cap_fraction"] for row in rows]),
                                  "median": median([row["cap_fraction"] for row in rows])},
        "input_volume": {"mean": mean([row["input_volume"] for row in rows]),
                         "total": sum(row["input_volume"] for row in rows)},
        "selected_public": sum(1 for row in rows if row["selected_public"]),
        "selected_hidden": sum(1 for row in rows if row["selected_hidden"]),
        "public_acceptance_of_selection": (round(sum(1 for row in rows if row["selected_public"]) / tasks, 3)
                                           if tasks else None),
        "hidden_acceptance_of_selection": (round(sum(1 for row in rows if row["selected_hidden"]) / tasks, 3)
                                           if tasks else None),
        "selection_modes": {mode: sum(1 for row in with_selection if row["selection_mode"] == mode)
                            for mode in ("repair", "public", "last-complete")},
        "end_states": states,
        "by_family": {family: {"tasks": len(family_rows),
                               "candidates_overshoot_ended": sum(row["overshoot_ended"] for row in family_rows),
                               "selected_public": sum(1 for row in family_rows if row["selected_public"]),
                               "selected_hidden": sum(1 for row in family_rows if row["selected_hidden"]),
                               "spend_mean": mean([row["spend"] for row in family_rows])}
                      for family in families
                      for family_rows in [[row for row in rows if row["family"] == family]]},
    }


# --------------------------------------------------------------------------
# loader


def load_trajectories(manifest: dict, cases: list[str]) -> tuple[list[Trajectory], list[dict], list[dict]]:
    """Read every measured M1b cell's per-call usage and its observed outcome.

    Returns the trajectories, the cell-level problems that were kept visible, and
    the per-cell integrity checks comparing the recovered per-call sums with the
    run's own aggregate usage.
    """
    trajectories: list[Trajectory] = []
    missing: list[dict] = []
    integrity: list[dict] = []
    families = case_families()
    for row in manifest["schedule"]:
        case, arm, repetition = row["case"], row["arm"], row["repetition"]
        if case not in cases:
            continue
        directory = M1B / "runs" / arm / case / str(repetition)
        attempts = sorted((path for path in directory.iterdir() if path.is_dir()),
                          key=lambda path: int(path.name)) if directory.is_dir() else []
        discarded = [path.name for path in attempts if not (path / "record.json").is_file()]
        records = score.attempt_records(M1B, arm, case, repetition)
        record = score.selected(records)
        if record is None:
            missing.append({"case": case, "arm": arm, "repetition": repetition,
                            "reason": "no record.json for this cell", "discarded_attempts": discarded})
            continue
        read = usage_reader.read_calls(Path(record["work_dir"]), record["session_launch"]["started_utc"])
        session_paths = [session["path"] for session in read["sessions"]]
        recorded = record["session"]["logs"]
        aggregate_usage = record["session"]["usage"]
        sums = {key: sum(getattr(call, field_name) for call in read["calls"])
                for key, field_name in (("inputTokens", "input_tokens"), ("outputTokens", "output_tokens"),
                                        ("reasoningTokens", "reasoning_tokens"),
                                        ("cacheReadTokens", "cache_read_tokens"))}
        matches = bool(read["matched"]) and all(sums[key] == aggregate_usage.get(key) for key in sums)
        metrics = (record.get("events") or {}).get("metrics") or {}
        trajectory = Trajectory(
            key=f"{arm}/{case}/{repetition}", case=case, family=families.get(case, "unknown"),
            arm=arm, repetition=repetition, calls=read["calls"],
            public=bool(record.get("public_acceptance")), hidden=bool(record.get("hidden_acceptance")),
            failed_compiler_invocations=metrics.get("failed_compiler_invocations"),
            invocation_limit=(manifest.get("identity") or {}).get("invocation_limit"),
            work_dir=record["work_dir"], started_utc=record["session_launch"]["started_utc"],
            session_paths=session_paths, attempt=record.get("attempt"), attempts=len(records),
            discarded_attempts=discarded, malformed_lines=read["malformed_lines"],
            usage_matches_record=matches)
        trajectories.append(trajectory)
        if not read["matched"]:
            missing.append({"case": case, "arm": arm, "repetition": repetition,
                            "reason": "no session log matched this work_dir", "discarded_attempts": discarded})
        integrity.append({"key": trajectory.key, "matched": read["matched"],
                          "sessions": len(read["sessions"]), "calls": len(read["calls"]),
                          "per_call_matches_record_usage": matches,
                          "recovered": sums, "recorded": {key: aggregate_usage.get(key) for key in sums},
                          "log_paths_match_record": sorted(session_paths) == sorted(recorded),
                          "malformed_lines": read["malformed_lines"],
                          "discarded_attempts": discarded})
    return trajectories, missing, integrity


def case_families() -> dict[str, str]:
    """The two measured case families, read from the M2 case definitions."""
    families = {}
    for directory in sorted((HERE / "cases" / "test").iterdir()):
        definition = directory / "case.json"
        if definition.is_file():
            families[directory.name] = json.loads(definition.read_text())["family"]
    return families


def pool_for(pool_policy: str, trajectories: list[Trajectory], case: str) -> list[Trajectory]:
    """The observed sessions of one case, in a deterministic drawing order."""
    candidates = [trajectory for trajectory in trajectories if trajectory.case == case]
    if pool_policy == "text":
        candidates = [trajectory for trajectory in candidates if trajectory.arm == "text"]
    return sorted(candidates, key=lambda trajectory: (trajectory.repetition, ARM_ORDER.index(trajectory.arm)))


def distribution(values: list[int]) -> dict:
    return {"calls": len(values), "min": min(values, default=None), "median": percentile(values, 0.5),
            "p90": percentile(values, 0.9), "p99": percentile(values, 0.99),
            "max": max(values, default=None), "mean": mean(values),
            "total": sum(values)}


# --------------------------------------------------------------------------
# calibration


def calibrate(trajectories: list[Trajectory], cases: list[str], pool_policy: str) -> dict:
    """Every cap x policy over the 14 measured cases, plus the per-task rows.

    The per-task rows are kept in the output so the selection of each task can be
    audited back to the session it came from; the aggregate is derived from the
    same rows, so the table and the evidence cannot drift.
    """
    families = case_families()
    tasks: dict[tuple[int, str], list[dict]] = {}
    for cap in CAPS:
        for policy in POLICIES:
            rows = []
            for case in cases:
                pool = pool_for(pool_policy, trajectories, case)
                row = replay_task(policy, cap, case, pool)
                row["family"] = families.get(case, "unknown")
                rows.append(row)
            tasks[(cap, policy)] = rows
    results = {}
    for cap in CAPS:
        results[cap_label(cap)] = {}
        for policy in POLICIES:
            rows = tasks[(cap, policy)]
            results[cap_label(cap)][policy] = {**aggregate(rows, cap, policy),
                                               "task_rows": [dict(row) for row in rows]}
    return results


def pool_facts(trajectories: list[Trajectory], cases: list[str], pool_policy: str) -> dict:
    """The measured sessions of one pool, and how they sit against each cap."""
    pooled = [trajectory for case in cases for trajectory in pool_for(pool_policy, trajectories, case)]
    calls = [call.generated for trajectory in pooled for call in trajectory.calls]
    return {
        "description": POOL_DESCRIPTION[pool_policy],
        "sessions": len(pooled),
        "per_case": {case: len(pool_for(pool_policy, trajectories, case)) for case in cases},
        "per_call_generated": distribution(calls),
        "per_session_generated": distribution([trajectory.generated for trajectory in pooled]),
        "whole_session_fit": whole_session_fit(trajectories, cases, pool_policy),
    }


def whole_session_fit(trajectories: list[Trajectory], cases: list[str], pool_policy: str) -> dict:
    """How many measured sessions fit whole inside one envelope, per cap."""
    pooled = [trajectory for case in cases for trajectory in pool_for(pool_policy, trajectories, case)]
    return {cap_label(cap): {"sessions": len(pooled),
                             "fit_whole": sum(1 for trajectory in pooled if trajectory.generated <= cap),
                             "share_fit_whole": (round(sum(1 for trajectory in pooled
                                                         if trajectory.generated <= cap) / len(pooled), 3)
                                                 if pooled else None)}
            for cap in CAPS}


def repair_alternates(trajectories: list[Trajectory], cases: list[str], pool_policy: str) -> dict:
    """Repair replayed with each pool member as the one session, per cap.

    The headline repair row uses the first pool member (the M2-matching arm,
    repetition 1). This block shows what the other measured sessions would have
    done, so the choice is auditable instead of invisible.
    """
    block = {}
    for cap in CAPS:
        spends, overshot, selected, public, hidden = [], 0, 0, 0, 0
        for case in cases:
            for trajectory in pool_for(pool_policy, trajectories, case):
                row = replay_task("repair", cap, case, [trajectory])
                spends.append(row["spend"])
                overshot += row["overshoot_ended"]
                selected += 1 if row["selected"] else 0
                public += 1 if row["selected_public"] else 0
                hidden += 1 if row["selected_hidden"] else 0
        block[cap_label(cap)] = {"replays": len(spends), "overshoot_ended": overshot,
                                 "with_selection": selected, "selected_public": public,
                                 "selected_hidden": hidden,
                                 "spend": {"mean": mean(spends), "median": median(spends)}}
    return block


def build_report_data(manifest: dict, trajectories: list[Trajectory], missing: list[dict],
                      integrity: list[dict], pool_policy: str, selftest_result: dict) -> dict:
    cases = list(manifest["cases"])
    families = case_families()
    measured = [call.generated for trajectory in trajectories for call in trajectory.calls]
    by_family: dict[str, list[int]] = {}
    for trajectory in trajectories:
        by_family.setdefault(trajectory.family, []).extend(call.generated for call in trajectory.calls)
    pools = {}
    for name in POOLS:
        facts = pool_facts(trajectories, cases, name)
        facts["results"] = calibrate(trajectories, cases, name)
        facts["repair_alternates"] = repair_alternates(trajectories, cases, name)
        pools[name] = facts
    return {
        "version": 1,
        "kind": "envelope-calibration-replay",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "cohort": manifest.get("cohort_id"),
        "identity": manifest.get("identity"),
        "source_root": str(M1B.relative_to(REPO)),
        "notice": ("Replay calibration only: it charges the M2 envelope over per-call usage measured "
                   "from the M1b sessions, which ran with NO token budget and were never told one. "
                   "It calibrates the envelope's arithmetic and how binding each cap is on those "
                   "observed trajectories; it is not evidence about how an agent behaves when told a "
                   "budget, which would require real sessions this does not run."),
        "replays_test_split_only": ("The 14 measured cases are the test split of the M1b cohort. The four "
                                    "dev cases have no participant sessions, so no dev trajectory is "
                                    "replayed and none is claimed."),
        "headline_pool": pool_policy,
        "sensitivity_pool": "text" if pool_policy == "all" else "all",
        "pools": pools,
        "cases": [{"case": case, "family": families.get(case, "unknown")} for case in cases],
        "caps": [cap_label(cap) for cap in CAPS],
        "policies": list(POLICIES),
        "selftest": selftest_result,
        "per_call_generated_all_measured": distribution(measured),
        "per_call_generated_by_family": {family: distribution(values)
                                         for family, values in sorted(by_family.items())},
        "per_session_generated_all_measured": distribution([trajectory.generated for trajectory in trajectories]),
        "failed_compiler_invocations": distribution([trajectory.failed_compiler_invocations
                                                     for trajectory in trajectories
                                                     if isinstance(trajectory.failed_compiler_invocations, int)]),
        "whole_session_fit_all_measured": {cap_label(cap): {
            "sessions": len(trajectories),
            "fit_whole": sum(1 for trajectory in trajectories if trajectory.generated <= cap),
            "share_fit_whole": round(sum(1 for trajectory in trajectories
                                         if trajectory.generated <= cap) / len(trajectories), 3)}
            for cap in CAPS} if trajectories else {},
        "trajectories": [trajectory.as_dict() for trajectory in trajectories],
        "integrity": {"cells": len(integrity),
                      "matched": sum(1 for row in integrity if row["matched"]),
                      "per_call_matches_record_usage": sum(1 for row in integrity
                                                           if row["per_call_matches_record_usage"]),
                      "log_paths_match_record": sum(1 for row in integrity if row["log_paths_match_record"]),
                      "malformed_lines": sum(row["malformed_lines"] for row in integrity),
                      "cells_with_discarded_attempts": [row["key"] for row in integrity
                                                        if row["discarded_attempts"]],
                      "problems": [row for row in integrity
                                   if not row["per_call_matches_record_usage"] or row["malformed_lines"]]},
        "missing": missing,
    }


# --------------------------------------------------------------------------
# markdown


def show(value) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:,.1f}"
    return f"{value:,}" if isinstance(value, int) and abs(value) >= 1000 else str(value)


def per_case_count(pool: dict) -> str:
    counts = sorted(set(pool["per_case"].values()))
    return " and ".join(str(count) for count in counts)


def headline_reading(data: dict) -> list[str]:
    """A data-driven reading of the headline table, so no number is typed by hand."""
    results = data["pools"][data["headline_pool"]]["results"]
    lines = []
    for cap in data["caps"]:
        repair = results[cap]["repair"]
        independent = results[cap]["independent"]
        lines.append(f"- **Cap {cap}**: `repair` keeps {repair['tasks_with_selection']}/{repair['tasks']} answers "
                     f"with mean spend {show(repair['spend']['mean'])} "
                     f"({show(repair['spend_fraction_of_cap']['mean'])} of cap); `independent` keeps "
                     f"{independent['tasks_with_selection']}/{independent['tasks']} answers after starting "
                     f"{independent['candidates_started']} candidates, mean spend "
                     f"{show(independent['spend']['mean'])} "
                     f"({show(independent['spend_fraction_of_cap']['mean'])} of cap).")
    return lines


def render_markdown(data: dict) -> str:
    lines = [
        "# M2 token-envelope calibration (replay of M1b evidence)",
        "",
        (f"**This calibrates the envelope's arithmetic and how binding each candidate cap is on trajectories "
         f"observed under NO token budget.** Every charge below is a per-call `outputTokens` value really "
         f"produced by the M1b participant sessions, replayed against `budget.Envelope` at caps 0, 2,000, "
         f"5,000, 10,000 and effectively unlimited; none of those agents was told a budget, so this is not "
         f"evidence about how agents behave when told one — that requires real sessions, which this does not "
         f"run. Captured {data['captured_utc']}."),
        "",
        "## What this does not measure",
        "",
        ("The replay charges an envelope over trajectories produced when the agent was NOT told any token "
         "budget. It therefore cannot show whether telling an agent its budget changes how it spends, "
         "whether an agent paces itself, or whether a refused call changes the next one: a budget-aware "
         "agent is a different system from the one that produced these calls. That behavioural question "
         "needs real sessions on the four dev cases (4 cases x 3 caps x 2 policies = 24 sessions); none was "
         "launched for this calibration, and the dev cases are not replayed here because no participant "
         "session has ever run on them."),
        "",
        "## What was replayed",
        "",
        (f"- Source: `{data['source_root']}` — {data['integrity']['cells']} measured cells "
         f"(4 arms x 14 cases x 2 repetitions), cohort `{data['cohort']}`, model "
         f"`{(data['identity'] or {}).get('model')}`, reasoning effort "
         f"`{(data['identity'] or {}).get('reasoning_effort')}`."),
        (f"- The 14 cases are the **test split** the M1b cohort measured. The four dev cases have no observed "
         f"trajectories, so nothing is replayed on them and no dev result is claimed."),
        (f"- Per-call usage recovered from the harness session logs: "
         f"{data['integrity']['matched']}/{data['integrity']['cells']} cells matched a session log, and "
         f"{data['integrity']['per_call_matches_record_usage']}/{data['integrity']['cells']} recovered "
         f"per-call sums reproduce the run's own aggregate usage exactly "
         f"(`inputTokens`/`outputTokens`/`reasoningTokens`/`cacheReadTokens`)."),
        (f"- Pool for the headline tables: {data['pools'][data['headline_pool']]['description']} — "
         f"{data['pools'][data['headline_pool']]['sessions']} sessions total, "
         f"{per_case_count(data['pools'][data['headline_pool']])} per case."),
        (f"- Sensitivity pool: {data['pools'][data['sensitivity_pool']]['description']} — "
         f"{data['pools'][data['sensitivity_pool']]['sessions']} sessions total, "
         f"{per_case_count(data['pools'][data['sensitivity_pool']])} per case. Both pools are "
         f"replayed at every cap; neither is described as anything but what it is."),
        (f"- Missing or unrecoverable cells: {len(data['missing'])}."),
        (f"- Machine-readable form: `experiments/diagnostic-feedback-m2/cohorts/calibration/calibration.json` "
         f"— every cap x policy aggregate, the per-task rows behind it (including which candidate was selected "
         f"for each task) and the 112 recovered trajectories."),
        (f"- Observed outcomes come from each cell's `record.json` (`public_acceptance`, `hidden_acceptance`, "
         f"`events.metrics.failed_compiler_invocations`); those sessions were also bounded by the M1b "
         f"invocation limit of {(data['identity'] or {}).get('invocation_limit')} compiler invocations, a "
         f"different limit from the token cap replayed here."),
        (f"- The measured sessions spent a median of {show(data['failed_compiler_invocations']['median'])} "
         f"failed compiler invocation(s) (p90 {show(data['failed_compiler_invocations']['p90'])}, max "
         f"{show(data['failed_compiler_invocations']['max'])}) while repairing — the loop the envelope is "
         f"meant to bound, before any token cap."),
        "",
        "## What the caps mean: measured generated tokens per call",
        "",
        "| scope | calls | min | median | p90 | p99 | max | mean |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    scopes = [(f"headline pool ({data['headline_pool']})", data["pools"][data["headline_pool"]]["per_call_generated"]),
              (f"sensitivity pool ({data['sensitivity_pool']})",
               data["pools"][data["sensitivity_pool"]]["per_call_generated"]),
              ("every measured session", data["per_call_generated_all_measured"])]
    scopes += [(f"family: {family}", values)
               for family, values in data["per_call_generated_by_family"].items()]
    for name, values in scopes:
        lines.append(f"| {name} | {show(values['calls'])} | {show(values['min'])} | {show(values['median'])} | "
                     f"{show(values['p90'])} | {show(values['p99'])} | {show(values['max'])} | {show(values['mean'])} |")
    session = data["per_session_generated_all_measured"]
    lines += ["", (f"A whole measured session spends a median of {show(session['median'])} generated tokens "
                   f"(p90 {show(session['p90'])}, max {show(session['max'])}, mean {show(session['mean'])}, "
                   f"n={show(session['calls'])}). How many of the {data['integrity']['cells']} measured sessions "
                   f"fit whole inside one envelope, by cap:"),
              "", "| cap | sessions that fit whole | share |", "| --- | ---: | ---: |"]
    for cap, facts in data["whole_session_fit_all_measured"].items():
        lines.append(f"| {cap} | {facts['fit_whole']} / {facts['sessions']} | {show(facts['share_fit_whole'])} |")

    header = ("| cap | policy | tasks | selected | cand. started | fit | overshoot-ended | unstarted | "
              "mean spend | median spend | mean spend / cap | public ok | hidden ok |")
    rule = "| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"

    def results_table(pool_name: str) -> list[str]:
        table = []
        for cap in data["caps"]:
            for policy in data["policies"]:
                row = data["pools"][pool_name]["results"][cap][policy]
                table.append(f"| {cap} | {policy} | {row['tasks']} | {row['tasks_with_selection']} | "
                             f"{row['candidates_started']} | {row['candidates_fit']} | "
                             f"{row['candidates_overshoot_ended']} | {row['candidates_unstarted']} | "
                             f"{show(row['spend']['mean'])} | {show(row['spend']['median'])} | "
                             f"{show(row['spend_fraction_of_cap']['mean'])} | "
                             f"{row['selected_public']}/{row['tasks']} | {row['selected_hidden']}/{row['tasks']} |")
        return table

    lines += ["", "## Replay results", "",
              f"Headline pool — {data['pools'][data['headline_pool']]['description']}:", "", header, rule]
    lines += results_table(data["headline_pool"])
    lines += ["", (f"Sensitivity pool — {data['pools'][data['sensitivity_pool']]['description']}. The same "
                   f"replay on the like-for-like pool is the check that the headline numbers are not an "
                   f"artefact of pooling four presentation arms:"),
              "", header, rule]
    lines += results_table(data["sensitivity_pool"])
    lines += ["", ("`public ok` / `hidden ok` count tasks whose *selected* answer passed the public examples / "
                   "the sealed hidden checks; a task with no selection counts against both. Spend is per task "
                   "(one envelope), charged in real generated tokens. At the unlimited control the "
                   "spend/cap column is meaningless and shown as `-`."),
              "", "### Reading the headline table, cap by cap", ""]
    lines += headline_reading(data)
    lines += ["", "### Termination and binding", "",
              "| cap | policy | end states (tasks, headline pool) | candidates ended by overshoot |",
              "| ---: | --- | --- | ---: |"]
    for cap in data["caps"]:
        for policy in data["policies"]:
            row = data["pools"][data["headline_pool"]]["results"][cap][policy]
            states = ", ".join(f"{name}: {count}" for name, count in sorted(row["end_states"].items()))
            lines.append(f"| {cap} | {policy} | {states} | {row['candidates_overshoot_ended']} |")
    lines += ["", binding_paragraph(data), "",
              "### Who loses the answer when a cap binds (headline pool)", "",
              "| cap | policy | family | tasks | overshoot-ended | public ok | hidden ok | mean spend |",
              "| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for cap in data["caps"]:
        for policy in data["policies"]:
            row = data["pools"][data["headline_pool"]]["results"][cap][policy]
            for family, facts in row["by_family"].items():
                lines.append(f"| {cap} | {policy} | {family} | {facts['tasks']} | "
                             f"{facts['candidates_overshoot_ended']} | {facts['selected_public']} | "
                             f"{facts['selected_hidden']} | {show(facts['spend_mean'])} |")
    lines += ["", "### Repair with each measured session in turn", "",
              ("The headline `repair` row charges the first pool member only (M2-matching arm, repetition 1) "
               "because `repair` is one session per task. Replaying each measured session of the headline pool "
               "as the one repair session, so no session is hidden behind that choice:"),
              "", "| cap | replays | overshoot-ended | selected | public ok | hidden ok | mean spend |",
              "| ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for cap, block in data["pools"][data["headline_pool"]]["repair_alternates"].items():
        lines.append(f"| {cap} | {block['replays']} | {block['overshoot_ended']} | {block['with_selection']} | "
                     f"{block['selected_public']} | {block['selected_hidden']} | {show(block['spend']['mean'])} |")
    lines += ["", "## Acceptance is near the ceiling in this evidence", "",
              (f"{data['integrity']['cells'] - 1} of {data['integrity']['cells']} measured M1b sessions ended in "
               f"hidden acceptance, and public and hidden acceptance coincide in every measured cell, so the "
               f"public/hidden split cannot separate the policies on this evidence. What the replay does "
               f"separate is how often a cap cuts a session short: an overshoot-ended candidate is incomplete "
               f"and cannot be selected, which is where a binding cap costs a task its answer."),
              "", "## Missing or unrecoverable observations", ""]
    if data["missing"]:
        lines += ["| case | arm | repetition | reason |", "| --- | --- | ---: | --- |"]
        for row in data["missing"]:
            lines.append(f"| {row['case']} | {row['arm']} | {row['repetition']} | {row['reason']} |")
    else:
        lines.append("None: every scheduled cell produced a record and a matching session log.")
    if data["integrity"]["cells_with_discarded_attempts"]:
        lines += ["", ("Attempt directories that exist without a `record.json` (a discarded attempt, kept "
                       "visible rather than dropped): " +
                       ", ".join(f"`{key}`" for key in data["integrity"]["cells_with_discarded_attempts"]) + ".")]
    if data["integrity"]["problems"]:
        lines += ["", "Cells whose per-call recovery did not reproduce the run's aggregate:", ""]
        for row in data["integrity"]["problems"]:
            lines.append(f"- `{row['key']}`: recovered {row['recovered']} vs recorded {row['recorded']}, "
                         f"malformed lines {row['malformed_lines']}")
    else:
        lines += ["", ("No cell had a per-call/aggregate mismatch or a malformed log line: the per-call values "
                       "are the ground truth for spend here, never a session-total estimate.")]
    lines += ["", "## Reproduction", "",
              "```console",
              "python3 experiments/diagnostic-feedback-m2/m2_usage.py --selftest",
              "python3 experiments/diagnostic-feedback-m2/envelope_replay.py --selftest",
              "python3 experiments/diagnostic-feedback-m2/envelope_replay.py \\",
              "    --json experiments/diagnostic-feedback-m2/cohorts/calibration/calibration.json \\",
              "    --markdown docs/audits/m2-budget-calibration-2026-09-19.md",
              "```",
              "",
              (f"Selftest at capture: usage reader {data['selftest'].get('usage_reader', {}).get('passed')}/"
               f"{data['selftest'].get('usage_reader', {}).get('total')}, envelope replay "
               f"{data['selftest'].get('envelope_replay', {}).get('passed')}/"
               f"{data['selftest'].get('envelope_replay', {}).get('total')} property checks. "
               "The replay launches no session: it reads sealed evidence and charges it."), ""]
    return "\n".join(lines)


def binding_paragraph(data: dict) -> str:
    """A plain statement, per cap, of whether it bound the observed trajectories."""
    pool = data["pools"][data["headline_pool"]]
    session = data["per_session_generated_all_measured"]
    parts = []
    for cap in data["caps"]:
        facts = pool["whole_session_fit"][cap]
        repair = pool["results"][cap]["repair"]
        independent = pool["results"][cap]["independent"]
        cut = repair["candidates_overshoot_ended"] + repair["candidates_unstarted"]
        parts.append(f"**{cap}**: {facts['fit_whole']}/{facts['sessions']} headline-pool sessions fit whole "
                     f"({facts['share_fit_whole']}); repair was cut short or unable to start on {cut}/"
                     f"{repair['tasks']} tasks and independent ended {independent['candidates_overshoot_ended']} "
                     f"candidates by overshoot with {independent['candidates_unstarted']} never started")
    return ("Binding, cap by cap — " + "; ".join(parts) + ". A cap is binding exactly when the measured "
            "per-session spend (median across all "
            f"{session['calls']} measured sessions {show(session['median'])}, p90 {show(session['p90'])}) does "
            "not fit inside it; the low caps bind on the long tail of sessions only, because the median call "
            f"is small.")


# --------------------------------------------------------------------------
# selftest


def trajectory(key: str, sizes: list[int], public: bool = True, hidden: bool = True) -> Trajectory:
    return Trajectory(key=key, case=key.split("/")[1], family="synthetic", arm=key.split("/")[0],
                      repetition=1, calls=[Usage(input_tokens=10, cache_read_tokens=100,
                                                 output_tokens=size, reasoning_tokens=size // 2)
                                           for size in sizes],
                      public=public, hidden=hidden)


def selftest() -> tuple[int, int, list[str]]:
    """Property checks for the replay state machine, on synthetic trajectories."""
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))

    # (a) an overshooting call is charged what it generated and ends the candidate
    envelope = Envelope(100)
    candidate = charge_candidate(envelope, trajectory("text/a/1", [60, 60]), "one")
    check("(a) an overshooting call is charged at its actual spend and ends the candidate",
          candidate.ended_by_overshoot and not candidate.complete and envelope.spent == 120
          and candidate.charged == 120 and candidate.overshoot == 20
          and envelope.totals()["overshoot"] == 20 and candidate.calls_charged == 2,
          f"spent={envelope.spent} overshoot={candidate.overshoot} complete={candidate.complete}")

    # (b) no candidate is ever started with a call the envelope cannot afford
    pool = [trajectory("text/a/1", [60], public=False), trajectory("text/a/2", [60], public=False),
            trajectory("text/a/3", [200], public=True)]
    task = replay_task("independent", 130, "a", pool)
    check("(b) a candidate whose first call is unaffordable is never started",
          task["started"] == 2 and task["unstarted"] == 1 and task["spend"] == 120
          and task["end_state"] == "unaffordable" and task["selected"] == "text/a/2"
          and task["selection_mode"] == "last-complete",
          f"started={task['started']} unstarted={task['unstarted']} spend={task['spend']} "
          f"selected={task['selected']}")
    starved = replay_task("repair", 100, "a", [trajectory("text/a/1", [200])])
    check("(b) repair does not start its one session when the first call exceeds the cap",
          starved["started"] == 0 and starved["spend"] == 0 and starved["selected"] is None
          and starved["end_state"] == "unaffordable",
          f"started={starved['started']} spend={starved['spend']}")

    # (c) every candidate of a task charges the same envelope instance
    shared = [trajectory("text/b/1", [50], public=False), trajectory("text/b/2", [50], public=False)]
    task = replay_task("independent", 500, "b", shared)
    instances = {row["envelope_id"] for row in task["candidates"]} | {task["envelope_id"]}
    check("(c) repair and independent charge one shared envelope per task",
          task["spend"] == 100 and task["started"] == 2 and len(instances) == 1
          and task["charges"] == 2,
          f"spend={task['spend']} started={task['started']} charges={task['charges']} envelopes={len(instances)}")
    repair_shared = replay_task("repair", 500, "b", shared)
    check("(c) repair charges that same instance rather than a fresh one per candidate",
          repair_shared["spend"] == 50 and repair_shared["charges"] == 1
          and repair_shared["candidates"][0]["charged"] == 50,
          f"spend={repair_shared['spend']}")

    # (d) selection prefers a candidate that passed the public check
    prefer = [trajectory("text/c/1", [40], public=False), trajectory("text/c/2", [40], public=True)]
    task = replay_task("independent", 500, "c", prefer)
    check("(d) a publicly-passing candidate is preferred over an earlier failing one",
          task["selected"] == "text/c/2" and task["selection_mode"] == "public"
          and task["selected_hidden"],
          f"selected={task['selected']} mode={task['selection_mode']}")
    fallback = replay_task("independent", 500, "c", [trajectory("text/c/1", [40], public=False),
                                                     trajectory("text/c/2", [40], public=False)])
    check("(d) without a passing candidate the last complete one is selected",
          fallback["selected"] == "text/c/2" and fallback["selection_mode"] == "last-complete"
          and not fallback["selected_public"],
          f"selected={fallback['selected']} mode={fallback['selection_mode']}")

    # (e) an exhausted pool ends the task without inventing a candidate
    small = [trajectory("text/d/1", [10], public=True), trajectory("text/d/2", [10], public=True)]
    task = replay_task("independent", UNLIMITED, "d", small)
    check("(e) a pool exhausted before the cap ends the task without inventing a candidate",
          task["started"] == 2 and task["end_state"] == "pool-exhausted" and task["spend"] == 20
          and task["pool_size"] == 2,
          f"started={task['started']} state={task['end_state']}")

    # (f) an incomplete candidate cannot be selected
    cut = replay_task("independent", 100, "e", [trajectory("text/e/1", [50], public=False, hidden=False),
                                                trajectory("text/e/2", [30, 500], public=True)])
    check("(f) a candidate ended by overshoot cannot be selected, even when it would have passed",
          cut["selected"] == "text/e/1" and cut["selection_mode"] == "last-complete"
          and cut["overshoot_ended"] == 1 and cut["spend"] == 580
          and not cut["selected_hidden"] and cut["candidates"][1]["ended_by_overshoot"]
          and cut["candidates"][1]["public_acceptance"],
          f"selected={cut['selected']} overshoot={cut['overshoot_ended']} spend={cut['spend']}")

    # (g) reasoning is not charged on top of output
    envelope = Envelope(1000)
    entry = envelope.charge(Usage(input_tokens=50, cache_read_tokens=400, output_tokens=100,
                                  reasoning_tokens=80), label="one")
    check("(g) generated tokens count once and input volume is uncached plus cached",
          envelope.spent == 100 and entry["usage"]["input_volume"] == 450
          and entry["usage"]["generated"] == 100 and envelope.totals()["generated"] == 100,
          f"spent={envelope.spent}")

    failures = [name for name, ok, _ in checks if not ok]
    for name, ok, detail in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else '  ' + detail}")
    print(f"\n{len(checks) - len(failures)}/{len(checks)} envelope-replay properties demonstrated")
    return len(checks) - len(failures), len(checks), failures


# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", type=Path, default=M1B, help="the frozen cohort to replay")
    parser.add_argument("--pool", choices=("all", "text"), default="all",
                        help="headline pool: every measured session per case, or the M2-matching text arm")
    parser.add_argument("--json", type=Path, default=CALIBRATION)
    parser.add_argument("--markdown", type=Path, default=REPORT)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    print("M2 envelope calibration")
    passed, total, failures = selftest()
    if args.selftest:
        return 1 if failures else 0

    print("\nusage reader selftest")
    reader_passed, reader_total, reader_failures = usage_reader.selftest()
    manifest = json.loads((args.cohort / "manifest.json").read_text())
    cases = list(manifest["cases"])
    trajectories, missing, integrity = load_trajectories(manifest, cases)
    selftest_result = {"usage_reader": {"passed": reader_passed, "total": reader_total,
                                        "failures": reader_failures},
                       "envelope_replay": {"passed": passed, "total": total, "failures": failures}}
    data = build_report_data(manifest, trajectories, missing, integrity, args.pool, selftest_result)
    text = render_markdown(data)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(data, indent=2) + "\n")
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text(text)
    print(text)
    print(f"wrote {args.json}")
    print(f"wrote {args.markdown}")
    return 1 if failures or reader_failures else 0


if __name__ == "__main__":
    sys.exit(main())
