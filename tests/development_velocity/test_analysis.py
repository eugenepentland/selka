"""Boundary tests for reporting policy; these do not launch participants."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import unittest

from experiments.development_velocity.analysis import (
    ALPHA_PER_GATE, FAMILIES, VERSION, analyze, canonical_hash, registration_hash,
)


def stamp(seconds):
    return (datetime(2026, 9, 8, tzinfo=timezone.utc) + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def seal(document):
    reg = document["registration"]
    reg["configuration_hash"] = canonical_hash(reg["configuration"])
    document["registration_hash"] = registration_hash(reg)
    for attempt in document["attempts"]:
        attempt["registration_hash"] = document["registration_hash"]
        attempt["configuration_hash"] = reg["configuration_hash"]
    return document


def cohort(phase="development", my_seconds=10, python_seconds=20):
    tasks = []
    for index, family in enumerate(FAMILIES if phase == "confirmation" else FAMILIES[:1]):
        for variant in range(2 if phase == "confirmation" else 1):
            task_id = f"task-{index}-{variant}"
            tasks.append(dict(task_id=task_id, variant_hash=canonical_hash(task_id), family=family,
                              kind="feature", budget_seconds=100,
                              pair_ids=[str(i) for i in range(3 if phase == "confirmation" else 1)]))
    reg = dict(study_id="study", candidate_id="candidate", phase=phase,
               look=1 if phase == "confirmation" else 0, frozen_at=stamp(0),
               analysis=dict(version=VERSION, seed=871, bootstrap_samples=1000,
                             speed_margin=1.0, quality_margin=0.0),
               configuration={"model_id": None, "compiler_hash": canonical_hash("compiler")},
               configuration_hash="", tasks=tasks, prior_variant_hashes=[])
    attempts = []
    for task in tasks:
        for pair_id in task["pair_ids"]:
            for language, seconds in (("my", my_seconds), ("python", python_seconds)):
                identity = f'{task["task_id"]}-{pair_id}-{language}'
                attempts.append(dict(task_id=task["task_id"], pair_id=pair_id, language=language,
                                     attempt_id=identity, participant_id=identity,
                                     registration_hash="", configuration_hash="", variant_hash=task["variant_hash"],
                                     started_at=stamp(1), ended_at=stamp(1 + seconds), status="sealed",
                                     clock=dict(boot_id="test-boot", started_monotonic_ns=1000000000,
                                                ended_monotonic_ns=1000000000 + seconds * 1000000000),
                                     behavior_pass=True, verification_pass=True, review="approve"))
    return seal(dict(schema_version=1, registration=reg, registration_hash="", attempts=attempts))


class AnalysisTests(unittest.TestCase):
    def test_failed_fast_never_becomes_successful_speedup(self):
        data = cohort(my_seconds=1)
        data["attempts"][0]["status"] = "failed"
        report = analyze(data)
        self.assertEqual(report["aggregate"]["cost_ratio"], 5)
        self.assertEqual(report["tasks"][0]["my_qualified_count"], 0)
        self.assertIsNone(report["tasks"][0]["my_successful_only_seconds"])
        self.assertFalse(report["decision"]["parity_criterion_met"])

    def test_pending_review_and_false_checks_are_not_qualified(self):
        for key, value in (("review", "pending"), ("review", "reject"),
                           ("behavior_pass", False), ("verification_pass", False)):
            with self.subTest(key=key, value=value):
                data = cohort()
                data["attempts"][0][key] = value
                self.assertEqual(analyze(data)["tasks"][0]["my_cost"], 100)

    def test_missing_pair_member_rejects(self):
        data = cohort()
        data["attempts"].pop()
        with self.assertRaisesRegex(ValueError, "missing registered attempts"):
            analyze(data)

    def test_development_never_stops_even_if_both_observed_gates_pass(self):
        decision = analyze(cohort())["decision"]
        self.assertTrue(decision["speed_criterion_met"])
        self.assertTrue(decision["empirical_quality_gate_met"])
        self.assertFalse(decision["parity_criterion_met"])

    def test_confirmation_empirical_parity_is_not_population_equality(self):
        report = analyze(cohort("confirmation"))
        self.assertTrue(report["decision"]["parity_criterion_met"])
        self.assertFalse(report["decision"]["population_quality_noninferiority_demonstrated"])
        self.assertLess(report["uncertainty"]["quality_difference_lower"], 0)
        self.assertEqual(report["uncertainty"]["alpha_per_gate"], ALPHA_PER_GATE)
        self.assertEqual(set(report["uncertainty"]["small_sample_families"]), set(FAMILIES))

    def test_literal_speed_margin(self):
        self.assertTrue(analyze(cohort("confirmation", 20, 20))["decision"]["parity_criterion_met"])
        self.assertFalse(analyze(cohort("confirmation", 21, 20))["decision"]["parity_criterion_met"])

    def test_confirmation_quality_failure_cannot_stop_despite_lower_mean_cost(self):
        data = cohort("confirmation", 1, 80)
        data["attempts"][0]["status"] = "failed"
        report = analyze(data)
        self.assertLess(report["uncertainty"]["cost_ratio_upper"], 1)
        self.assertFalse(report["decision"]["parity_criterion_met"])

    def test_confirmation_requires_families_and_repetitions(self):
        for pair_shortage in (False, True):
            data = cohort()
            data["registration"].update(phase="confirmation", look=1)
            if not pair_shortage:
                data["registration"]["tasks"][0]["pair_ids"] = ["0", "1", "2"]
            seal(data)
            with self.assertRaisesRegex(ValueError, "three pairs|six families"):
                analyze(data)

    def test_registration_and_configuration_hash_drift(self):
        for where in ("registration", "attempt", "configuration", "variant"):
            data = cohort()
            if where == "registration":
                data["registration"]["candidate_id"] = "changed"
            elif where == "configuration":
                data["attempts"][0]["configuration_hash"] = "0" * 64
            elif where == "variant":
                data["attempts"][0]["variant_hash"] = "0" * 64
            else:
                data["attempts"][0]["registration_hash"] = "0" * 64
            with self.subTest(where=where), self.assertRaises(ValueError):
                analyze(data)

    def test_duplicate_attempts_and_context_reuse(self):
        data = cohort()
        data["attempts"].append(deepcopy(data["attempts"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate attempt"):
            analyze(data)
        data = cohort()
        data["attempts"][1]["participant_id"] = data["attempts"][0]["participant_id"]
        with self.assertRaisesRegex(ValueError, "context reused"):
            analyze(data)

    def test_freeze_must_precede_outcomes_and_variants_must_be_heldout(self):
        data = cohort()
        data["registration"]["frozen_at"] = stamp(2)
        with self.assertRaisesRegex(ValueError, "precedes registration"):
            analyze(seal(data))
        data = cohort("confirmation")
        data["registration"]["prior_variant_hashes"] = [data["registration"]["tasks"][0]["variant_hash"]]
        with self.assertRaisesRegex(ValueError, "previously exposed"):
            analyze(seal(data))

    def test_no_relaxed_margins_or_fifth_look(self):
        for key, value in (("speed_margin", 1.1), ("quality_margin", 0.01), ("speed_margin", True)):
            data = cohort()
            data["registration"]["analysis"][key] = value
            with self.assertRaises(ValueError):
                analyze(seal(data))
        data = cohort("confirmation")
        data["registration"]["look"] = 5
        with self.assertRaisesRegex(ValueError, "schedule"):
            analyze(seal(data))

    def test_deadline_and_infrastructure_failures_retained(self):
        data = cohort(my_seconds=100)
        self.assertEqual(analyze(data)["tasks"][0]["my_qualified_count"], 1)
        data["attempts"][0]["ended_at"] = stamp(102)
        data["attempts"][0]["clock"]["ended_monotonic_ns"] = 102000000000
        self.assertEqual(analyze(data)["tasks"][0]["my_qualified_count"], 0)
        data["attempts"][0].update(status="infrastructure_failure", ended_at=stamp(2))
        report = analyze(data)
        self.assertEqual(report["attempts"][0]["capped_cost_seconds"], 100)
        self.assertEqual(len(report["attempts"]), 2)

    def test_reproducible_and_unknown_telemetry_null(self):
        data = cohort("confirmation")
        data["attempts"][0]["ended_at"] = stamp(40)
        data["attempts"][0]["clock"]["ended_monotonic_ns"] = 40000000000
        first = analyze(data)
        self.assertEqual(first, analyze(deepcopy(data)))
        self.assertIsNone(first["attempts"][0]["telemetry"])
        self.assertGreaterEqual(first["uncertainty"]["cost_ratio_upper"], first["aggregate"]["cost_ratio"])

    def test_equal_family_weighting_not_attempt_pooling(self):
        data = cohort("confirmation")
        # One entire family has cost 70, the others 10: equal-family mean is 20.
        changed = {t["task_id"] for t in data["registration"]["tasks"] if t["family"] == FAMILIES[0]}
        for row in data["attempts"]:
            if row["task_id"] in changed and row["language"] == "my":
                row["ended_at"] = stamp(71)
                row["clock"] = dict(boot_id="test-boot", started_monotonic_ns=1000000000,
                                    ended_monotonic_ns=71000000000)
        # Add many pairs to just that family: its aggregate weight must stay 1/6.
        for task in data["registration"]["tasks"]:
            if task["task_id"] not in changed:
                continue
            originals = [a for a in data["attempts"] if a["task_id"] == task["task_id"] and a["pair_id"] == "0"]
            for pair in ("3", "4", "5"):
                task["pair_ids"].append(pair)
                for row in originals:
                    new = dict(row, pair_id=pair, attempt_id=row["attempt_id"] + pair,
                               participant_id=row["participant_id"] + pair)
                    data["attempts"].append(new)
        self.assertEqual(analyze(seal(data))["aggregate"]["my_cost"], 20)

    def test_monotonic_duration_is_authoritative_and_utc_remains_raw(self):
        data = cohort()
        data["attempts"][0]["ended_at"] = stamp(0)
        row = analyze(data)["attempts"][0]
        self.assertEqual(row["elapsed_seconds"], 10)
        self.assertEqual(row["utc_elapsed_seconds"], -1)
        self.assertEqual(row["duration_source"], "monotonic_ns")

    def test_legacy_clock_is_labeled_and_forbidden_in_confirmation(self):
        data = cohort()
        del data["attempts"][0]["clock"]
        self.assertEqual(analyze(data)["attempts"][0]["duration_source"], "legacy_utc")
        data = cohort("confirmation")
        data["attempts"][0]["clock"] = None
        with self.assertRaisesRegex(ValueError, "requires monotonic"):
            analyze(data)

    def test_monotonic_clock_types_and_order(self):
        for key, value in (("boot_id", ""), ("started_monotonic_ns", True),
                           ("started_monotonic_ns", -1), ("ended_monotonic_ns", 0),
                           ("ended_monotonic_ns", 1.5)):
            data = cohort()
            data["attempts"][0]["clock"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                analyze(data)


if __name__ == "__main__":
    unittest.main()
