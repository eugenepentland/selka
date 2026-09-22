#!/usr/bin/env python3
"""The M1 readout: delivery checks, per-case results, the factorial contrasts, the target.

Delivery is defined against *eligible* diagnostics. A session that never met a
diagnostic the remedy table covers has not failed delivery — it was never
eligible — so eligibility, representation and emission are reported separately,
and every session stays in its assigned arm for the outcome analysis.

The predeclared practical target: at least one fewer failed compiler invocation
per successful repair in each responsive family, with no observed hidden-acceptance
regression. Three states are possible — passes, fails, inconclusive — and the
inconclusive state is a result, not a failure to decide.

    python3 experiments/diagnostic-feedback/readout.py --cohort m1b
    python3 experiments/diagnostic-feedback/readout.py --selftest
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
import random
import shutil
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import conditions  # noqa: E402
import score  # noqa: E402

sys.path.insert(0, str(HERE.parents[1] / "experiments" / "cascade"))
import run as runlib  # noqa: E402

RESPONSIVE = ("checked-result", "generic-requirement")
SUGGESTION_ARMS = ("text_fix", "json_fix")
JSON_ARMS = ("json", "json_fix")


def eligible_needles(text: str) -> list[str]:
    """Which remedy rules the session's diagnostics made applicable."""
    hits = []
    for code, rules in conditions.REMEDIES.items():
        for needle, remedy in rules:
            if needle and needle in text:
                hits.append(f"{code}:{needle}")
    return sorted(set(hits))


# What render() emits for the JSON arms: pretty-printed, so it can never be
# confused with the shim's own source, where the payload is built by hand.
# render() emits this pretty-printed; the shim's source builds the same payload
# inline, so the "{\n" plus indentation is what distinguishes delivered output. A
# session log JSON-escapes tool results, so both spellings are accepted.
JSON_PAYLOAD_RE = re.compile(r'\{\\?n\s*\\?"version\\?":\s*\\?"diagnostics-v1\\?"')
# Identifiers that occur only in the wrapper shim's source. The shim embeds the
# remedy table for every arm, so its lines are removed before asking what the
# agent was actually delivered.
SHIM_MARKERS = ("REMEDY_ARMS", "JSON_ARMS", "remedy_for(", "REMEDIES", "CONDITION ==")


def sanitize(transcript: str) -> str:
    """The transcript with wrapper-shim source lines removed."""
    return "\n".join(line for line in transcript.splitlines()
                     if not any(marker in line for marker in SHIM_MARKERS))


def delivery(arm: str, transcript: str) -> dict:
    """Eligibility, representation and emission, kept apart.

    All three are judged on the sanitized transcript, so a participant that opened
    the wrapper cannot look eligible or treated on the strength of its source.
    """
    clean = sanitize(transcript)
    eligible = eligible_needles(clean)
    payload_seen = bool(JSON_PAYLOAD_RE.search(clean))
    shown = sorted({remedy for code, rules in conditions.REMEDIES.items() for needle, remedy in rules
                    if remedy and f"{code}:{needle}" in eligible and remedy in clean})
    representation_ok = payload_seen if arm in JSON_ARMS else not payload_seen
    entry = {"eligible": bool(eligible), "eligible_rules": eligible,
             "representation_ok": representation_ok, "payload_seen": payload_seen,
             "wrapper_source_visible": any(m in transcript for m in SHIM_MARKERS),
             "remedies_shown": len(shown),
             "emitted": bool(shown) if arm in SUGGESTION_ARMS else None}
    if not eligible:
        entry.update({"delivered": None, "reason": "no eligible diagnostic in this session"})
    else:
        entry["delivered"] = representation_ok and (bool(shown) if arm in SUGGESTION_ARMS else True)
    return entry


def per_case(rows: list[dict]) -> dict:
    cases: dict[str, dict] = {}
    for row in rows:
        bucket = cases.setdefault(row["case"], {"family": row["family"], "arms": {}})
        bucket["arms"].setdefault(row["arm"], []).append(row)
    out = {}
    for case, bucket in cases.items():
        out[case] = {"family": bucket["family"],
                     "accepted": {arm: sum(1 for row in arm_rows if row["hidden_acceptance"])
                                  for arm, arm_rows in bucket["arms"].items()},
                     "failed_checks": {arm: statistics.median([row["metrics"].get("failed_checks_on_changed_source") or 0
                                                               for row in arm_rows]) if arm_rows else None
                                       for arm, arm_rows in bucket["arms"].items()}}
    return out


def target(rows: list[dict], seed: int = 7) -> dict:
    """The predeclared practical target, with its three states."""
    detail = {}
    states = []
    for family in RESPONSIVE:
        family_rows = [row for row in rows if row["family"] == family and row["hidden_acceptance"]]
        if not family_rows:
            detail[family] = {"state": "inconclusive", "reason": "no accepted repairs to compare"}
            states.append("inconclusive")
            continue
        best = None
        for treatment, baseline in (("text_fix", "text"), ("json_fix", "json")):
            # Scoped to this family: pooling families would let one family's gain
            # cancel another's regression.
            effect = score.paired(family_rows, treatment, baseline, "failed_checks_on_changed_source", seed)
            if effect.get("pairs"):
                # `paired` returns treatment - baseline, so *fewer* failed checks is
                # a negative difference; improvement is its negation.
                improvement = {"pairs": effect["pairs"], "mean": -effect["mean"],
                               "ci": [-effect["ci"][1], -effect["ci"][0]],
                               "per_case": {case: -value for case, value in effect["per_case"].items()}}
                if best is None or improvement["mean"] > best[1]["mean"]:
                    best = (treatment, improvement)
        if best is None:
            detail[family] = {"state": "inconclusive", "reason": "no paired blocks"}
            states.append("inconclusive")
            continue
        treatment, effect = best
        low, high = effect["ci"]
        accepted_gap = (sum(1 for row in rows if row["family"] == family and row["arm"] == treatment
                            and row["hidden_acceptance"])
                        - sum(1 for row in rows if row["family"] == family and row["arm"] == treatment.replace("_fix", "")
                              and row["hidden_acceptance"]))
        if accepted_gap < 0:
            state = "fails"
            reason = "hidden acceptance regressed"
        elif low is not None and low >= 1.0:
            state = "passes"
            reason = "at least one fewer failed invocation, lower bound"
        elif high is not None and high <= 0.0:
            state = "fails"
            reason = "no improvement, upper bound at or below zero"
        else:
            state = "inconclusive"
            reason = "interval spans meaningful benefit and no benefit"
        detail[family] = {"state": state, "reason": reason, "treatment": treatment,
                          "mean": effect["mean"], "ci": effect["ci"], "pairs": effect["pairs"]}
        states.append(state)
    overall = ("passes" if states and all(state == "passes" for state in states)
               else "fails" if any(state == "fails" for state in states) else "inconclusive")
    return {"state": overall, "families": detail}


def report(cohort: str, rows: list[dict], manifest: dict) -> dict:
    """The three conclusions, kept apart so one cannot stand in for another."""
    completed = [row for row in rows if row["present"]]
    delivery_rows = []
    for row in completed:
        record_path = None
        candidate = HERE / "cohorts" / cohort / "runs" / row["arm"] / row["case"] / str(row["repetition"])
        attempts = sorted(candidate.iterdir(), key=lambda path: int(path.name)) if candidate.is_dir() else []
        if attempts and (attempts[-1] / "record.json").is_file():
            record = json.loads((attempts[-1] / "record.json").read_text())
            # Delivery is about what the agent was *shown*, so it is read from the
            # session log rather than the participant's final message.
            transcript = ""
            work = Path(record.get("work_dir", ""))
            started = ((record.get("session_launch") or {}).get("started_utc"))
            if started:
                import datetime as _dt
                try:
                    transcript = "".join(runlib.session_log_text(work, _dt.datetime.fromisoformat(started)))
                except Exception:
                    transcript = ""
            if not transcript:
                transcript = (attempts[-1] / "session.txt").read_text() if (attempts[-1] / "session.txt").is_file() else ""
                transcript += (attempts[-1] / "events.jsonl").read_text() if (attempts[-1] / "events.jsonl").is_file() else ""
            entry = delivery(row["arm"], transcript)
            entry["arm"] = row["arm"]
            delivery_rows.append(entry)
    eligible = [entry for entry in delivery_rows if entry["eligible"]]
    # 1. measurement validity
    coverage = {"scheduled": len(rows), "completed": len(completed), "missing": len(rows) - len(completed),
                "grading_incidents": sum(1 for row in completed
                                         if not ((row.get("grading") or {}).get("grader_ok", True))),
                "identity_mismatches": sum(1 for row in completed
                                           if row.get("model_mismatch") or row.get("toolchain_mismatch")),
                "delivery_eligible_sessions": len(eligible),
                "delivery_failures": sum(1 for entry in eligible if entry["delivered"] is False),
                "sessions_without_an_eligible_diagnostic": len(delivery_rows) - len(eligible),
                # Observations kept visible rather than folded into the verdict: the
                # wrapper shim was readable inside the work directory.
                "wrapper_source_visible_sessions": sum(1 for entry in delivery_rows
                                                       if entry.get("wrapper_source_visible")),
                "remedy_text_in_control_arms": sum(1 for entry in delivery_rows
                                                   if entry["arm"] not in SUGGESTION_ARMS
                                                   and entry.get("remedies_shown")),
                "json_payload_in_text_arms": sum(1 for entry in delivery_rows
                                                 if entry["arm"] not in JSON_ARMS
                                                 and entry.get("payload_seen"))}
    coverage["valid"] = (coverage["missing"] == 0 and coverage["grading_incidents"] == 0
                         and coverage["identity_mismatches"] == 0 and coverage["delivery_failures"] == 0)
    # 2. practical benefit, per responsive family
    target_result = target(rows)
    # 3. uncertainty, per responsive family contrast
    uncertainty = {}
    for family, detail in target_result["families"].items():
        if detail.get("ci") is None:
            uncertainty[family] = "no estimate"
            continue
        low, high = detail["ci"]
        if low >= 1.0:
            uncertainty[family] = "improvement"
        elif high <= 0.0:
            uncertainty[family] = "harm or no benefit"
        else:
            uncertainty[family] = "inconclusive"
    return {"cohort": cohort, "identity": manifest["identity"],
            "measurement_validity": coverage,
            "practical_benefit": {"target": target_result["state"], "families": target_result["families"]},
            "uncertainty": uncertainty}


def selftest() -> int:
    """Synthetic cohorts: target passes, fails, stays inconclusive; gaps reported."""
    checks: list[tuple[str, bool, str]] = []

    def check(name, condition, detail=""):
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    def rows_for(family: str, treatment_failed: list[int], baseline_failed: list[int], gap: int) -> list[dict]:
        rows = []
        for index, (left, right) in enumerate(zip(treatment_failed, baseline_failed)):
            for arm, value, accepted in (("text_fix", left, index >= gap), ("text", right, True)):
                rows.append({"arm": arm, "case": f"{family}-{index}", "repetition": 1, "family": family,
                             "hidden_acceptance": accepted, "public_acceptance": True, "termination": "completed",
                             "metrics": {"failed_checks_on_changed_source": value}, "usage": {}, "steps": 1})
        return rows

    passing = rows_for("checked-result", [0, 1, 0], [2, 2, 2], 0) + rows_for("generic-requirement", [0, 1, 1], [2, 3, 2], 0)
    check("target passes when every responsive family improves by a whole invocation",
          target(passing)["state"] == "passes", json.dumps(target(passing)["families"])[:120])

    failing = rows_for("checked-result", [2, 2, 3], [1, 1, 1], 0) + rows_for("generic-requirement", [0, 1, 1], [2, 3, 2], 0)
    check("target fails on a regression", target(failing)["state"] == "fails")

    uncertain = rows_for("checked-result", [1, 2, 1, 2, 1], [2, 1, 2, 1, 2], 0) + \
        rows_for("generic-requirement", [1, 2, 1, 2, 1], [2, 2, 2, 2, 2], 0)
    check("target is inconclusive when intervals span benefit and no benefit",
          target(uncertain)["state"] == "inconclusive", json.dumps(target(uncertain)["families"])[:140])

    eligible_text = "main.my:5:5: error[E_TYPE]: expected int, found bool\n"
    remedy = conditions.REMEDIES["E_TYPE"][0][1]
    check("a session with no eligible diagnostic is not a delivery failure",
          delivery("text", "no diagnostics here")["delivered"] is None)
    check("a suggestion arm that received the diagnostic but no remedy failed delivery",
          delivery("text_fix", eligible_text)["delivered"] is False)
    check("a json arm that received prose failed representation",
          delivery("json", eligible_text)["representation_ok"] is False)
    check("a delivered suggestion is recognised",
          delivery("text_fix", eligible_text + "note: " + remedy)["delivered"] is True)
    # Regressions for the two delivery-measurement bugs found during the m1b readout.
    shim = ('    if CONDITION in JSON_ARMS:\n'
            '        payload = {"version": "diagnostics-v1", "count": 0}\n'
            '        remedies = REMEDIES if condition in REMEDY_ARMS else {}\n')
    check("the wrapper's own source is not mistaken for a delivered JSON payload",
          delivery("text", shim)["representation_ok"] is True)
    check("the wrapper's own source cannot make a session eligible",
          delivery("text", shim)["eligible"] is False)
    escaped = '{"type":"text","text":"{\\n  \\"version\\": \\"diagnostics-v1\\",\\n  \\"count\\": 1}"}'
    check("an escaped pretty-printed payload still counts as JSON delivery",
          delivery("json", escaped)["representation_ok"] is True)

    scratch = HERE / ".tmp" / "readout-selftest"
    shutil.rmtree(scratch, ignore_errors=True)
    (scratch / "runs" / "text" / "c1" / "1" / "1").mkdir(parents=True)
    (scratch / "manifest.json").write_text(json.dumps(
        {"schema": "cohort-manifest-v1", "cohort_id": "synthetic", "arms": ["text"],
         "schedule": [{"arm": "text", "case": "c1", "repetition": 1}]}))
    check("a scheduled cell with no record is reported missing, not imputed",
          score.collect(json.loads((scratch / "manifest.json").read_text()), scratch)[0]["present"] is False)
    shutil.rmtree(scratch, ignore_errors=True)

    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} readout checks passed")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if not args.cohort:
        raise SystemExit("one of --cohort or --selftest is required")
    root = HERE / "cohorts" / args.cohort
    manifest = json.loads((root / "manifest.json").read_text())
    rows = score.collect(manifest, root)
    families = {}
    for row in rows:
        case_file = HERE / "cases" / ("dev" if "pilot" in args.cohort else "test") / row["case"] / "case.json"
        families[row["case"]] = json.loads(case_file.read_text())["family"] if case_file.is_file() else "unknown"
    for row in rows:
        row["family"] = families.get(row["case"], row.get("family", "unknown"))
    report_data = {"cohort": args.cohort, "identity": manifest["identity"],
              "arms": {arm: score.summarise([row for row in rows if row["arm"] == arm]) for arm in manifest["arms"]},
              "per_case": per_case(rows),
              "effects": {
                  "suggestion_in_text": score.paired(rows, "text_fix", "text", "failed_checks_on_changed_source"),
                  "suggestion_in_json": score.paired(rows, "json_fix", "json", "failed_checks_on_changed_source"),
                  "format_without_suggestion": score.paired(rows, "json", "text", "failed_checks_on_changed_source"),
                  "format_with_suggestion": score.paired(rows, "json_fix", "text_fix", "failed_checks_on_changed_source"),
              },
              "target": target(rows), "rows": rows}
    report_data.update(three=report(args.cohort, rows, manifest))
    print(json.dumps({key: report_data[key] for key in ("cohort", "arms", "effects", "target", "three")},
                     indent=2)[:2500])
    if args.json:
        args.json.write_text(json.dumps(report_data, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
