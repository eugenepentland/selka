#!/usr/bin/env python3
"""Measure explicit sharing against eager copies, then check snapshot-free controls."""
import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FOLLOWUP = HERE.parent / "single-owner-followup-20261011"
spec = importlib.util.spec_from_file_location("followup", FOLLOWUP / "compare.py")
followup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(followup)
previous = followup.previous


def capture(source, flags, configs, answers, raw, env, args, result):
    record = followup.capture(source, args.compiler, flags, configs, answers,
                              raw, env, args, result)
    for n, run in record["configs"]["release"].items():
        counts = json.loads((raw / "release" / f"counts-{n}.json").read_text())
        summary = previous.census.summarize(counts)
        run["functions"] = summary["functions"]
        run["rc_and_copy_sites"] = summary["rc_and_copy_sites"]
    return record


def answers_for(name, baseline):
    if name in ("nested_copy", "snapshot", "unused_snapshot"):
        return {str(n): previous.expected(name, n) for n in (4, 11)}
    if name == "mixed_families":
        return {str(n): f"{n * 100} {n * 100 + 1} {n * 100 + 1} {n * 100 + 1}\n" for n in (4, 11)}
    if name == "both_versions":
        return {str(n): "3 2 1 2\n" for n in (4, 11)}
    return baseline["census"][name]["single_owner_after"]["configs"]["release"]


def summarize(result):
    with (HERE / "summary.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("sample", "n", "mode", "peak_managed_bytes", "allocations", "reallocations",
                         "list_copies", "copied_bytes", "retains", "releases", "direct_frees",
                         "uniqueness_tests", "runtime_retains", "runtime_releases"))
        for name, lanes in result["samples"].items():
            for mode, record in lanes.items():
                for n, run in record["configs"]["release"].items():
                    k = run["kernel"]
                    writer.writerow((name, n, mode, run["whole_program"]["peak_live_bytes"],
                                     *(k[key] for key in ("allocs", "reallocs", "list_copies", "list_copy_bytes")),
                                     *(k["kinds"][key] for key in ("retain", "release", "release_unique", "unique_test")),
                                     k["runtime_retains"], k["runtime_releases"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    for name in ("compiler", "zig", "output"):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    env.pop("MYLANG_COUNTERS", None)
    baseline_path = FOLLOWUP / "results.json"
    baseline = json.loads(baseline_path.read_text())
    result = {"executions": 0, "samples": {}, "controls": {}, "unsupported": {},
              "compiler": str(args.compiler), "compiler_sha256": previous.digest(args.compiler),
              "zig_sha256": previous.digest(args.zig), "harness_sha256": previous.digest(__file__),
              "baseline_sha256": previous.digest(baseline_path),
              "helper_sha256": {str(path.relative_to(ROOT)): previous.digest(path) for path in
                                 (FOLLOWUP / "compare.py", previous.HERE / "compare.py", previous.CENSUS / "census.py")}}

    def checkpoint():
        (args.output / "partial-results.json").write_text(json.dumps(result, indent=2) + "\n")

    for source in sorted((HERE / "samples").glob("*.my")):
        name = source.stem
        answers = answers_for(name, baseline)
        answers = {n: run["stdout"] if isinstance(run, dict) else run for n, run in answers.items()}
        eager = HERE / "eager" / source.name
        if eager.read_text() != source.read_text().replace(".snapshot()", ".copy()"):
            raise RuntimeError(f"unpaired sources: {name}")
        raw = args.output / name
        result["samples"][name] = {
            "eager": capture(eager, [previous.FLAG], previous.CONFIGS, answers,
                             raw / "eager", env, args, result),
            "snapshot": capture(source, [previous.FLAG], previous.CONFIGS, answers,
                                raw / "snapshot", env, args, result),
            "default": capture(source, [], ["release", "verify"], answers,
                               raw / "default", env, args, result),
        }
        print("pass sample", name, flush=True)
        checkpoint()

    # Keep prior source and results intact: a no-snapshot control uses exactly
    # the previous source bytes, across the same five build configurations.
    for group in ("census", "focused"):
        for name, lanes in baseline[group].items():
            before = lanes["single_owner_after"]
            source = ROOT / before["source"]
            if previous.digest(source) != before["source_sha256"]:
                raise RuntimeError(f"baseline source changed: {name}")
            answers = {n: run["stdout"] for n, run in before["configs"]["release"].items()}
            label = f"{group}/{name}"
            after = capture(source, [previous.FLAG], previous.CONFIGS, answers,
                            args.output / "controls" / group / name, env, args, result)
            for n, run in after["configs"]["release"].items():
                for metric in ("kernel", "whole_program"):
                    if run[metric] != before["configs"]["release"][n][metric]:
                        raise RuntimeError(f"snapshot-free memory/RC changed: {label}/{n}/{metric}")
            result["controls"][label] = after
            print("pass control", label, flush=True)
            checkpoint()

    for name in baseline["unsupported"]:
        source = previous.CENSUS / "samples" / (name + ".my")
        checked = previous.command([args.compiler, "check", source, previous.FLAG],
                                   args.output / "unsupported" / name, env)
        if checked.returncode != 1 or b"E_SINGLE_OWNER_UNSUPPORTED" not in checked.stderr:
            raise RuntimeError(f"dictionary admission changed: {name}")
        result["unsupported"][name] = checked.stderr.decode()
    if previous.digest(args.compiler) != result["compiler_sha256"]:
        raise RuntimeError("compiler changed during measurement")
    (HERE / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    summarize(result)
    print("qualified", result["executions"], "executions;",
          len(result["samples"]), "paired samples;", len(result["controls"]), "unchanged controls", flush=True)


if __name__ == "__main__":
    main()
