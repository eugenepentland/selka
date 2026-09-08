"""Failure-inclusive, preregistered matched-cohort analysis; no telemetry inference."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import random
import re

VERSION = "development-velocity-analysis-v1"
# Arm-aware registrations report candidate/comparator series and need their own version.
ARM_VERSION = "development-velocity-analysis-v2"
FAMILIES = ("data-text", "configuration", "stateful-collections", "binary-codecs",
            "filesystem-path", "multi-module-maintenance")
ALPHA_PER_GATE = 0.00625
LOOKS = 4


def canonical_hash(value):
    """SHA256 of compact sorted UTF-8 JSON, rejecting nonfinite numbers."""
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def registration_hash(registration):
    return canonical_hash(registration)


def version_for(configuration):
    """Registrations declaring configuration.arms are v2; legacy my/python stay v1."""
    return ARM_VERSION if configuration.get("arms") is not None else VERSION


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _fields(value, required, optional=()):
    _require(isinstance(value, dict), "expected object")
    _require(set(required) <= value.keys(), "missing fields: " + str(set(required) - value.keys()))
    _require(value.keys() <= set(required) | set(optional), "unknown fields: " + str(value.keys() - set(required) - set(optional)))


def _id(value):
    _require(isinstance(value, str) and bool(value.strip()), "expected nonempty identifier")


def _hash(value):
    _require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value), "expected lowercase SHA256")


def _time(value):
    _require(isinstance(value, str) and value.endswith("Z"), "timestamp must be ISO UTC ending Z")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError("invalid timestamp") from exc
    _require(parsed.utcoffset().total_seconds() == 0, "timestamp must be UTC")
    return parsed.timestamp()


def _number(value, positive=False):
    _require(type(value) in (int, float) and math.isfinite(value), "expected finite number")
    _require(value > 0 if positive else value >= 0, "number outside allowed range")


def _arms(configuration):
    """Registered comparator/candidate arms, or None for a legacy my/python cohort."""
    arms = configuration.get("arms")
    if arms is None:
        return None
    _fields(arms, ("comparator", "candidate"))
    labels = set()
    for role in ("candidate", "comparator"):
        arm = arms[role]
        _fields(arm, ("label", "language", "interface"))
        _id(arm["label"])
        _require(arm["language"] in ("my", "python"), "invalid arm language")
        _require(arm["interface"] in ("files", "store"), "invalid arm interface")
        labels.add(arm["label"])
    _require(len(labels) == 2, "arm labels must be distinct")
    return arms


def _validate(document):
    _fields(document, ("schema_version", "registration", "registration_hash", "attempts"))
    _require(type(document["schema_version"]) is int and document["schema_version"] == 1, "unsupported schema version")
    reg = document["registration"]
    _fields(reg, ("study_id", "candidate_id", "phase", "look", "frozen_at", "analysis",
                  "configuration", "configuration_hash", "tasks", "prior_variant_hashes"))
    for name in ("study_id", "candidate_id"):
        _id(reg[name])
    _hash(document["registration_hash"])
    _require(registration_hash(reg) == document["registration_hash"], "registration hash mismatch")
    _require(isinstance(reg["configuration"], dict), "configuration must be object")
    _hash(reg["configuration_hash"])
    _require(canonical_hash(reg["configuration"]) == reg["configuration_hash"], "configuration hash mismatch")
    arms = _arms(reg["configuration"])
    series = ("my", "python") if arms is None else tuple(arms[role]["label"] for role in ("candidate", "comparator"))
    _require(reg["phase"] in ("development", "confirmation"), "invalid phase")
    _require(type(reg["look"]) is int, "look must be integer")
    _require(reg["look"] == 0 if reg["phase"] == "development" else 1 <= reg["look"] <= LOOKS, "look outside preregistered schedule")
    frozen = _time(reg["frozen_at"])
    settings = reg["analysis"]
    _fields(settings, ("version", "seed", "bootstrap_samples", "speed_margin", "quality_margin"))
    _require(settings["version"] == version_for(reg["configuration"]), "analysis version mismatch")
    _require(type(settings["seed"]) is int, "seed must be integer")
    _require(type(settings["bootstrap_samples"]) is int and 1000 <= settings["bootstrap_samples"] <= 1000000, "bootstrap samples must be 1000..1000000")
    for name, target in (("speed_margin", 1.0), ("quality_margin", 0.0)):
        _number(settings[name])
        _require(settings[name] == target, "fixed margin mismatch: " + name)
    prior = reg["prior_variant_hashes"]
    _require(isinstance(prior, list), "prior variants must be array")
    for value in prior:
        _hash(value)
    _require(len(set(prior)) == len(prior), "duplicate prior variant hash")
    _require(isinstance(reg["tasks"], list) and reg["tasks"], "tasks must be nonempty array")
    task_ids, variants, expected = set(), set(), set()
    family_counts = Counter()
    tasks = {}
    for task in reg["tasks"]:
        _fields(task, ("task_id", "variant_hash", "family", "kind", "budget_seconds", "pair_ids"))
        _id(task["task_id"])
        _require(task["task_id"] not in task_ids, "duplicate task identity")
        task_ids.add(task["task_id"])
        _hash(task["variant_hash"])
        _require(task["variant_hash"] not in variants, "duplicate variant identity")
        variants.add(task["variant_hash"])
        _require(task["family"] in FAMILIES, "unknown task family")
        _require(task["kind"] in ("feature", "bugfix"), "unknown task kind")
        _number(task["budget_seconds"], positive=True)
        pairs = task["pair_ids"]
        _require(isinstance(pairs, list) and pairs, "pair_ids must be nonempty array")
        for pair in pairs:
            _id(pair)
        _require(len(set(pairs)) == len(pairs), "duplicate registered pair")
        if reg["phase"] == "confirmation":
            _require(len(pairs) >= 3, "confirmation requires at least three pairs per task")
            _require(task["variant_hash"] not in prior, "confirmation variant was previously exposed")
        family_counts[task["family"]] += 1
        tasks[task["task_id"]] = task
        expected.update((task["task_id"], pair, name) for pair in pairs for name in series)
    if reg["phase"] == "confirmation":
        _require(all(family_counts[f] >= 2 for f in FAMILIES), "confirmation requires two task clusters in each of six families")
    _require(isinstance(document["attempts"], list), "attempts must be array")
    seen, attempt_ids, participants = set(), set(), set()
    for attempt in document["attempts"]:
        _fields(attempt, ("task_id", "pair_id", "language", "attempt_id", "participant_id",
                          "registration_hash", "configuration_hash", "variant_hash", "started_at",
                          "ended_at", "status", "behavior_pass", "verification_pass", "review")
                + (() if arms is None else ("arm",)), ("telemetry", "clock"))
        for name in ("task_id", "pair_id", "attempt_id", "participant_id"):
            _id(attempt[name])
        _require(attempt["language"] in ("my", "python"), "invalid language")
        identity = (attempt["task_id"], attempt["pair_id"],
                    attempt["language"] if arms is None else attempt["arm"])
        _require(identity in expected, "unregistered task/pair/arm")
        if arms is not None:
            definition = next(a for a in arms.values() if a["label"] == attempt["arm"])
            _require(attempt["language"] == definition["language"], "attempt language differs from its arm")
        _require(identity not in seen, "duplicate attempt identity")
        seen.add(identity)
        _require(attempt["attempt_id"] not in attempt_ids, "duplicate attempt_id")
        attempt_ids.add(attempt["attempt_id"])
        _require(attempt["participant_id"] not in participants, "participant context reused")
        participants.add(attempt["participant_id"])
        _require(attempt["registration_hash"] == document["registration_hash"], "attempt registration mismatch")
        _require(attempt["configuration_hash"] == reg["configuration_hash"], "attempt configuration mismatch")
        _require(attempt["variant_hash"] == tasks[attempt["task_id"]]["variant_hash"], "attempt variant mismatch")
        start, end = _time(attempt["started_at"]), _time(attempt["ended_at"])
        _require(frozen <= start, "attempt precedes registration freeze")
        clock = attempt.get("clock")
        if clock is not None:
            _fields(clock, ("boot_id", "started_monotonic_ns", "ended_monotonic_ns"))
            _id(clock["boot_id"])
            for name in ("started_monotonic_ns", "ended_monotonic_ns"):
                _require(type(clock[name]) is int and 0 <= clock[name] <= 2**63 - 1, "invalid monotonic nanoseconds")
            _require(clock["started_monotonic_ns"] <= clock["ended_monotonic_ns"], "monotonic clock regressed")
        else:
            _require(reg["phase"] != "confirmation", "confirmation requires monotonic clock")
            _require(start <= end, "legacy UTC clock regressed")
        _require(attempt["status"] in ("sealed", "failed", "timed_out", "abandoned", "infrastructure_failure"), "invalid terminal status")
        _require(attempt["status"] != "sealed" or _elapsed(attempt) > 0, "sealed attempt duration must be positive")
        for name in ("behavior_pass", "verification_pass"):
            _require(type(attempt[name]) is bool, "quality checks must be explicit booleans")
        _require(attempt["review"] in ("approve", "approve_with_nits", "reject", "pending"), "invalid review")
        _require(attempt.get("telemetry") is None or isinstance(attempt["telemetry"], dict), "telemetry must be object or null")
    _require(seen == expected, "missing registered attempts: " + str(sorted(expected - seen)))
    return reg, tasks, arms


def _mean(values):
    return sum(values) / len(values) if values else None


def _elapsed(attempt):
    clock = attempt.get("clock")
    if clock is not None:
        return (clock["ended_monotonic_ns"] - clock["started_monotonic_ns"]) / 1_000_000_000
    return _time(attempt["ended_at"]) - _time(attempt["started_at"])


def _aggregate(families, prefixes=("my", "python")):
    # Equal tasks within each family; equal families irrespective of pair counts.
    return {key: _mean([_mean([row[key] for row in rows]) for rows in families.values()])
            for key in tuple(prefix + "_" + name for name in ("cost", "completion") for prefix in prefixes)}


def _ratio(values, prefixes=("my", "python")):
    return values[prefixes[0] + "_cost"] / values[prefixes[1] + "_cost"]


def analyze(document):
    """Validate a complete immutable cohort and return a JSON-serializable report."""
    reg, tasks, arms = _validate(document)
    # Legacy cohorts keep the literal my/python series; arm cohorts report roles.
    prefixes = ("my", "python") if arms is None else ("candidate", "comparator")
    labels = ("my", "python") if arms is None else tuple(arms[role]["label"] for role in prefixes)
    series = (lambda row: row["language"]) if arms is None else (lambda row: row["arm"])
    attempts, grouped = [], defaultdict(lambda: defaultdict(list))
    for raw in document["attempts"]:
        task = tasks[raw["task_id"]]
        elapsed = _elapsed(raw)
        qualified = (raw["status"] == "sealed" and elapsed <= task["budget_seconds"]
                     and raw["behavior_pass"] and raw["verification_pass"]
                     and raw["review"] in ("approve", "approve_with_nits"))
        row = dict(raw, telemetry=raw.get("telemetry"), elapsed_seconds=elapsed,
                   duration_source="monotonic_ns" if raw.get("clock") is not None else "legacy_utc",
                   utc_elapsed_seconds=_time(raw["ended_at"]) - _time(raw["started_at"]),
                   qualified=qualified, capped_cost_seconds=elapsed if qualified else task["budget_seconds"])
        attempts.append(row)
        grouped[raw["task_id"]][series(raw)].append(row)
    families = defaultdict(list)
    task_results = []
    for task_id in sorted(tasks):
        task, rows = tasks[task_id], grouped[task_id]
        result = {"task_id": task_id, "family": task["family"], "kind": task["kind"],
                  "pairs": len(task["pair_ids"]), "variant_hash": task["variant_hash"]}
        for prefix, label in zip(prefixes, labels):
            result[prefix + "_cost"] = _mean([r["capped_cost_seconds"] for r in rows[label]])
            result[prefix + "_completion"] = _mean([int(r["qualified"]) for r in rows[label]])
            result[prefix + "_qualified_count"] = sum(r["qualified"] for r in rows[label])
            result[prefix + "_successful_only_seconds"] = _mean([r["elapsed_seconds"] for r in rows[label] if r["qualified"]])
        task_results.append(result)
        families[task["family"]].append(result)
    families = dict(sorted(families.items()))
    aggregate = _aggregate(families, prefixes)
    rng = random.Random(reg["analysis"]["seed"])
    ratios = []
    for _ in range(reg["analysis"]["bootstrap_samples"]):
        sampled = {family: [rng.choice(rows) for _ in rows] for family, rows in families.items()}
        ratios.append(_ratio(_aggregate(sampled, prefixes), prefixes))
    ratios.sort()
    upper = ratios[min(len(ratios) - 1, math.ceil((1 - ALPHA_PER_GATE) * len(ratios)) - 1)]
    difference = aggregate[prefixes[0] + "_completion"] - aggregate[prefixes[1] + "_completion"]
    squared_weights = sum(1 / (len(families) ** 2 * len(rows)) for rows in families.values())
    # Each independent task-cluster completion difference is in [-1, 1].
    quality_lower = max(-1.0, difference - math.sqrt(2 * math.log(1 / ALPHA_PER_GATE) * squared_weights))
    all_candidate = all(row["qualified"] for row in attempts if series(row) == labels[0])
    empirical_quality = all_candidate and difference >= 0
    speed_met = upper <= 1.0
    confirmation = reg["phase"] == "confirmation"
    family_results = {family: dict(_aggregate({family: rows}, prefixes), task_count=len(rows)) for family, rows in families.items()}
    counts = {label: {"attempted": sum(series(row) == label for row in attempts),
                      "qualified": sum(series(row) == label and row["qualified"] for row in attempts),
                      "statuses": dict(Counter(row["status"] for row in attempts if series(row) == label))}
              for label in labels}
    return {
        **({} if arms is None else {"arms": arms}),
        "schema_version": 1, "analysis_version": version_for(reg["configuration"]),
        "registration_hash": document["registration_hash"], "configuration_hash": reg["configuration_hash"],
        "input_hash": canonical_hash(document), "study_id": reg["study_id"], "candidate_id": reg["candidate_id"],
        "phase": reg["phase"], "look": reg["look"], "attempts": sorted(attempts, key=lambda r: (r["task_id"], r["pair_id"], series(r))),
        "tasks": task_results, "families": family_results, "counts": counts,
        "aggregate": dict(aggregate, cost_ratio=_ratio(aggregate, prefixes), completion_difference=difference),
        "uncertainty": {"alpha_per_gate": ALPHA_PER_GATE, "planned_looks": LOOKS,
                        "bootstrap_seed": reg["analysis"]["seed"], "bootstrap_samples": len(ratios),
                        "cost_ratio_upper": upper, "quality_difference_lower": quality_lower,
                        "quality_method": "task-cluster weighted Hoeffding bound; independent clusters assumed",
                        "speed_method": "family-stratified paired task-cluster percentile bootstrap; approximate",
                        "small_sample_families": [family for family, rows in families.items() if len(rows) < 3]},
        "decision": {"speed_margin": 1.0, "quality_margin": 0.0,
                     "speed_criterion_met": speed_met, "empirical_quality_gate_met": empirical_quality,
                     "population_quality_noninferiority_demonstrated": confirmation and quality_lower >= 0,
                     "parity_criterion_met": confirmation and speed_met and empirical_quality,
                     "scope": "registered heldout corpus-level parity only; not equal population defect rates or global software parity",
                     "development_cannot_stop": not confirmation},
        "limitations": ["Task-cluster bootstrap is approximate, especially below three clusters per family.",
                        "Repeated participants within one task are not independent task samples.",
                        "Registration hashes establish content consistency, not external custody or honest timestamps.",
                        "Caller must enforce append-only look history, freeze provenance and heldout isolation.",
                        "Unknown telemetry is null; no model tokens, queue time or reasoning time are inferred."]}


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    report = analyze(json.loads(args.input.read_text(), object_pairs_hook=_unique_object))
    # Publication is append-only; never silently replace a previous analysis.
    with args.output.open("x") as handle:
        json.dump(report, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")


if __name__ == "__main__":
    main()
