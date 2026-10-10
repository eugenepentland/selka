#!/usr/bin/env python3
"""Replay all predictions and validation arithmetic without LLVM tools or guests."""
import argparse
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


model = module("machine_replay_model", ROOT / "scripts/juice_machine_estimate.py")
evaluation = module("machine_replay_evaluation", Path(__file__).with_name("evaluate.py"))
bench = evaluation.bench


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    root = parser.parse_args().evidence
    mapping = bench.read(root / "regions.json")
    ir = (root / "optimized-core.ir").read_text()
    suite = bench.read(root / "suite-longer.json")
    arms = suite["calibration"] + [c[a] for c in suite["cases"] for a in ("base", "candidate")]
    frozen = {}
    for run, name in (("model01", "llvm_stock"), ("model02", "llvm_latency_profile")):
        directory = root / run
        method = bench.read(directory / "method.json")
        assert bench.digest(directory / "predictions.json") == method["predictions_sha256"]
        predictions, models = bench.read(directory / "predictions.json"), bench.read(directory / "models.json")
        instructions = model.disassemble((directory / "disassembly.txt").read_text())
        for row in models.values():
            reports = []
            for count, call in zip((200,400,800), row["calls"], strict=True):
                path = directory / f"{row['region']['name']}-{count}.json"
                assert bench.digest(path) == call["output_sha256"]
                assert not path.with_suffix(".stderr").read_text()
                reports.append(bench.read(path))
            score, slopes = model.fit_cycles(reports)
            assert score == row["cycles_per_machine_iteration"] and slopes == row["convergence_slopes"]
        for arm in arms:
            old, regions = model.prepare(ir, arm["function"], {0:arm["n"],1:arm["seed"]}, mapping, instructions)
            contributions = []
            for region in regions:
                region["assembly"] = model.apply_profile(region["assembly"], method.get("latency_profile"))
                record = models[region["name"]]
                assert region == record["region"]
                assert (directory / (region["name"] + ".s")).read_text() == region["assembly"]
                contributions.append(dict(region=region["name"], machine_iterations=region["machine_iterations"],
                    score=region["machine_iterations"] * record["cycles_per_machine_iteration"]))
            expected = dict(status="estimated", function=arm["function"], parameters=old["parameters"],
                            cycle_score=sum(r["score"] for r in contributions), core_cycle_score=old["cycle_score"]["value"],
                            core_weighted_work=old["weighted_work"]["value"], regions=contributions)
            assert expected == predictions[evaluation.old.identity(arm)]
        frozen[name] = predictions
        print(f"{run}: all {len(models)} region costs and {len(predictions)} predictions replay exactly")
    timing = root / "timing01"
    frozen["core"] = {key:dict(cycle_score=p["core_cycle_score"]) for key,p in frozen["llvm_stock"].items()}
    assert frozen == bench.read(timing / "predictions.json")
    assert bench.digest(timing / "predictions.json") == bench.read(timing / "method.json")["predictions_sha256"]
    expected = {evaluation.old.identity(a):evaluation.old.oracle(a) for a in arms}
    assert expected == bench.read(timing / "oracles.json")
    samples = bench.read(timing / "samples.json")
    records = bench.read(timing / "calibration.json") + bench.read(timing / "warmups.json")
    records += [row[a] for row in samples for a in ("base", "candidate")]
    for row in records:
        label = row["label"]
        for suffix in ("stdout", "stderr"):
            assert bench.digest(timing / (label + "." + suffix)) == row["command"][suffix + "_sha256"]
        assert row["command"]["exit_code"] == 0
        assert [int(x) for x in (timing / (label + ".stdout")).read_text().split()] == [expected[row["arm"]], row["kernel_ns"]]
        perf = timing / (label + ".perf")
        assert bench.digest(perf) == row["perf_sha256"]
        assert evaluation.counters(perf.read_text()) == {k:row[k] for k in ("cycles", "reference_cycles")}
    assert evaluation.summarize(suite, frozen, samples) == bench.read(timing / "results.json")
    print(f"timing01: {len(records)} outputs, oracles, full-running counters and all result statistics match")


if __name__ == "__main__":
    main()
