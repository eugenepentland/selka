#!/usr/bin/env python3
"""Verify retained predictions, output oracles and result arithmetic; no guests run."""
import argparse
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("ir_evaluation", Path(__file__).with_name("evaluate.py"))
evaluation = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = evaluation
spec.loader.exec_module(evaluation)
bench = evaluation.bench


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path, help="extracted evidence root")
    args = parser.parse_args()
    root = args.evidence
    ir = (root / "optimized-core.ir").read_text()
    for run, suite_name in (("run01", "suite.json"), ("run02", "suite-longer.json")):
        directory = root / run
        suite = bench.read(root / suite_name)
        method = bench.read(directory / "method.json")
        retained = {"kernels": None, "mylang": None,
                    "juice_ir_estimate.py": "estimator-measured.py"}
        for original, digest in method["hashes"].items():
            name = Path(original).name
            payload = retained.get(name, name)
            if payload is not None:
                assert bench.digest(root / payload) == digest, original
        predictions = bench.read(directory / "predictions.json")
        assert bench.digest(directory / "predictions.json") == method["predictions_sha256"]
        for prediction in predictions.values():
            replay = evaluation.estimator.estimate(ir, prediction["function"],
                                                  {int(k): v for k,v in prediction["parameters"].items()})
            assert replay == prediction, prediction["function"]
        for prediction in bench.read(directory / "abstentions.json").values():
            assert evaluation.estimator.estimate(ir, prediction["function"],
                {int(k): v for k,v in prediction["parameters"].items()}) == prediction
        arms = suite["calibration"] + [c[a] for c in suite["cases"] for a in ("base", "candidate")]
        expected = {evaluation.identity(a): evaluation.oracle(a) for a in arms}
        assert expected == bench.read(directory / "oracles.json")
        def check(record, label):
            for suffix in ("stdout", "stderr"):
                assert bench.digest(directory / f"{label}.{suffix}") == record["command"][suffix + "_sha256"]
            fields = (directory / f"{label}.stdout").read_text().split()
            assert [int(x) for x in fields] == [expected[record["arm"]], record["kernel_ns"]]
            assert record["command"]["exit_code"] == 0
        samples = bench.read(directory / "samples.json")
        calibration = bench.read(directory / "calibration.json")
        for row in samples:
            for side in ("base", "candidate"):
                check(row[side], f"{row['case']}-{row['pair']}-{side}")
        for index, row in enumerate(calibration):
            check(row, f"cal-{row['arm'].split('-')[0]}-{index // len(suite['calibration']) + 1}")
        assert evaluation.summarize(suite, predictions, calibration, samples) == bench.read(directory / "results.json")
        print(f"{run}: predictions, oracles, {len(samples)*2 + len(calibration)} measured outputs and results match")


if __name__ == "__main__":
    main()
