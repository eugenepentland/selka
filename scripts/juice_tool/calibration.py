"""Optional, held-out calibration of instruction-work ratios for CPU-bound cases.

Timing observations must be supplied explicitly. Capture wall time is diagnostic
and is never silently used as training data on a shared machine.
"""
from __future__ import annotations

import math
from pathlib import Path
import statistics

from .common import JuiceError, digest, file_hash, read_json


def fit(dataset_path):
    path = Path(dataset_path).resolve()
    dataset = read_json(path)
    if dataset.get("version") != "juice-calibration-data-v1":
        raise JuiceError("expected juice-calibration-data-v1 dataset")
    points, context = [], None
    seen = set()
    for point in dataset.get("points", []):
        comparison_path = path.parent / point["comparison"]
        comparison = read_json(comparison_path)
        if comparison.get("version") != "juice-comparison-v1":
            raise JuiceError("calibration needs comparison reports")
        if context is not None and context != comparison["context_id"]:
            raise JuiceError("calibration cannot mix measurement contexts")
        context = comparison["context_id"]
        cell = comparison["workloads"][point["workload"]]
        if not cell["repeatable"] or cell["risks"]:
            raise JuiceError("calibration requires repeatable cases without unresolved cost risks")
        evidence_path = path.parent / point["timing_evidence"]
        timing = read_json(evidence_path)
        if timing.get("version") != "juice-timing-evidence-v1" or not timing.get("method"):
            raise JuiceError("timing evidence needs a version and a description of the measurement method")
        for key in ("base_id", "candidate_id", "context_id"):
            if timing.get(key) != comparison[key]:
                raise JuiceError(f"timing evidence {key} does not match the compared builds/context")
        if timing.get("workload") != point["workload"]:
            raise JuiceError("timing evidence names a different workload")
        pairs = timing.get("pairs", [])
        if len(pairs) < 5 or any(not isinstance(p, list) or len(p) != 2 or
                                any(isinstance(v, bool) or not isinstance(v, (int, float)) or
                                    not math.isfinite(v) or v <= 0 for v in p) for p in pairs):
            raise JuiceError("timing evidence requires at least five positive [base_seconds, candidate_seconds] pairs")
        ratios = [b / a for a, b in pairs]
        timing_ratio = statistics.median(ratios)
        if (max(ratios) - min(ratios)) / timing_ratio > 0.03:
            raise JuiceError("timing ratios vary by more than 3%; unsuitable calibration evidence")
        split = point["split"]
        if split not in ("train", "validation"):
            raise JuiceError("calibration split must be train or validation")
        identity = (comparison["base_id"], comparison["candidate_id"], point["workload"])
        if identity in seen:
            raise JuiceError("duplicate calibration observation")
        seen.add(identity)
        points.append({"family": cell["family"], "split": split, "work": cell["instruction_ratio"],
                       "time": timing_ratio, "comparison_sha256": file_hash(comparison_path),
                       "timing_sha256": file_hash(evidence_path)})
    train = [p for p in points if p["split"] == "train"]
    validation = [p for p in points if p["split"] == "validation"]
    train_families = {p["family"] for p in train}
    validation_families = {p["family"] for p in validation}
    if len(train) < 6 or len(validation) < 3 or len(train_families) < 2 or not validation_families:
        raise JuiceError("need six training observations across two families and three held-out observations")
    if train_families & validation_families:
        raise JuiceError("training and validation families must be disjoint")
    denominator = sum(math.log(p["work"]) ** 2 for p in train)
    if denominator < 0.001:
        raise JuiceError("training changes are too small to identify a useful model")
    exponent = sum(math.log(p["work"]) * math.log(p["time"]) for p in train) / denominator
    if not 0 < exponent <= 3:
        raise JuiceError("instruction work has no plausible positive relationship to supplied timings")
    errors = [abs(p["work"] ** exponent / p["time"] - 1) for p in validation]
    directional = [p for p in validation if abs(p["time"] - 1) > 0.03]
    accuracy = sum((p["work"] - 1) * (p["time"] - 1) > 0 for p in directional) / len(directional) if directional else 0
    if max(errors) > 0.10 or accuracy < 0.8:
        raise JuiceError("model failed held-out validation (max error >10% or direction accuracy <80%)")
    return {"version": "juice-model-v1", "context_id": context, "exponent": exponent,
            "meaning": "runtime ratio = instruction ratio ** exponent; CPU-bound trend only",
            "families": sorted(train_families | validation_families),
            "work_range": [min(p["work"] for p in points), max(p["work"] for p in points)],
            "validation": {"max_relative_error": max(errors), "median_relative_error": statistics.median(errors),
                           "direction_accuracy": accuracy, "observations": len(validation)},
            "points": points, "dataset_sha256": file_hash(path)}


def predict(report, model):
    if model.get("version") != "juice-model-v1" or report["context_id"] != model.get("context_id"):
        raise JuiceError("model version or measurement context does not match")
    result = {"status": "calibrated estimates where applicable", "model_id": digest(model), "workloads": {}}
    for name, cell in report["workloads"].items():
        reason = None
        if cell["family"] not in model["families"]:
            reason = "workload family outside calibration"
        elif not cell["repeatable"] or cell["risks"]:
            reason = "unstable observations or unresolved cost risks"
        elif not model["work_range"][0] <= cell["instruction_ratio"] <= model["work_range"][1]:
            reason = "change outside calibrated range"
        result["workloads"][name] = ({"reason": reason} if reason else
            {"ratio": cell["instruction_ratio"] ** model["exponent"],
             "validation_max_error": model["validation"]["max_relative_error"],
             "scope": "model estimate; held-out error is not a confidence bound"})
    report["runtime_prediction"] = result
