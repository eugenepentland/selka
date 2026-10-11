#!/usr/bin/env python3
"""Separate source migration costs from the nested-cleanup compiler change."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREVIOUS = HERE.parent / "single-owner-20261010"
spec = importlib.util.spec_from_file_location("previous", PREVIOUS / "compare.py")
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)


def capture(source, compiler, flags, configs, answers, raw, env, args, result):
    record = {"source": str(source.relative_to(ROOT)),
              "source_sha256": previous.digest(source), "configs": {}}
    for config in configs:
        directory = raw / config
        directory.mkdir(parents=True, exist_ok=True)
        binary = directory / "program"
        build = [compiler, "build", source, "-o", binary, "--zig", args.zig,
                 "--cache-dir", args.output / "cache", *flags,
                 *previous.CONFIGS[config]]
        if config == "release":
            build += ["--emit-llvm", directory / "program.ll"]
        previous.require(previous.command(build, directory / "build", env), str(directory))
        runs = {}
        for n, answer in answers.items():
            counts = directory / f"counts-{n}.json"
            run_env = dict(env)
            if config == "release":
                run_env["MYLANG_COUNTERS"] = str(counts)
            ran = previous.command([binary, *(["x"] * int(n))], directory / f"run-{n}", run_env)
            previous.require(ran, str(directory), answer)
            result["executions"] += 1
            run = {"stdout": ran.stdout.decode()}
            if config == "release":
                summary = previous.census.summarize(json.loads(counts.read_text()))
                run.update({key: summary[key] for key in ("kernel", "whole_program")})
            runs[n] = run
        record["configs"][config] = runs
    if record["source_sha256"] != previous.digest(source):
        raise RuntimeError(f"source changed during measurement: {source}")
    return record


def compare(source, migrated, answers, raw, env, args, result):
    lanes = {}
    lanes["default_original"] = capture(source, args.before, [], ["release"], answers,
                                         raw / "default_original", env, args, result)
    if migrated != source:
        lanes["default_migrated"] = capture(migrated, args.before, [], ["release"], answers,
                                             raw / "default_migrated", env, args, result)
    lanes["single_owner_before"] = capture(migrated, args.before, [previous.FLAG], ["release"],
                                            answers, raw / "single_owner_before", env, args, result)
    lanes["single_owner_after"] = capture(migrated, args.compiler, [previous.FLAG], previous.CONFIGS,
                                           answers, raw / "single_owner_after", env, args, result)
    return lanes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    for name in ("before", "compiler", "zig", "output"):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    env.pop("MYLANG_COUNTERS", None)
    result = {"executions": 0, "census": {}, "focused": {}, "unsupported": {},
              "compilers": {name: {"path": str(getattr(args, name)),
                                    "sha256": previous.digest(getattr(args, name))}
                            for name in ("before", "compiler")},
              "zig_sha256": previous.digest(args.zig), "harness_sha256": previous.digest(__file__)}
    baseline = json.loads((previous.CENSUS / "results.json").read_text())
    for case in baseline["cases"]:
        name = case["id"]
        source = previous.CENSUS / case["source"]
        migrated = HERE / "migrated" / source.name
        if not migrated.exists():
            migrated = source
        if name.startswith(("21_", "22_", "23_")):
            checked = previous.command([args.compiler, "check", source, previous.FLAG],
                                       args.output / name / "check", env)
            if checked.returncode != 1 or b"E_SINGLE_OWNER_UNSUPPORTED" not in checked.stderr:
                raise RuntimeError(f"dictionary admission unexpectedly changed: {name}")
            result["unsupported"][name] = checked.stderr.decode()
        else:
            result["census"][name] = compare(source, migrated, case["expected"], args.output / name,
                                             env, args, result)
            print("pass", name, flush=True)
        (args.output / "partial-results.json").write_text(json.dumps(result, indent=2) + "\n")
    for source in sorted((PREVIOUS / "samples").glob("*.my")):
        answers = {str(n): previous.expected(source.stem, n) for n in (4, 11)}
        result["focused"][source.stem] = compare(source, source, answers,
                                                  args.output / "focused" / source.stem, env, args, result)
        print("pass focused", source.stem, flush=True)
    for name, compiler in result["compilers"].items():
        if previous.digest(compiler["path"]) != compiler["sha256"]:
            raise RuntimeError(f"{name} compiler changed during measurement")
    for name, lanes in result["census"].items():
        if int(name[:2]) in (15, 24, 25, 26, 27, 28):
            continue  # These cases exercise shared strings or existing text/byte buffers.
        for run in lanes["single_owner_after"]["configs"]["release"].values():
            kernel = run["kernel"]
            if (kernel["runtime_retains"] or kernel["runtime_releases"] or
                    any(kernel["kinds"][kind] for kind in ("retain", "release", "unique_test"))):
                raise RuntimeError(f"unexpected numeric collection RC: {name}")
    for run in result["focused"]["nested_copy"]["single_owner_after"]["configs"]["release"].values():
        if run["kernel"]["runtime_releases"]:
            raise RuntimeError("nested copy still has runtime child RC")
    result["summary"] = {
        "total_census": 30, "supported": len(result["census"]), "migrated": 7,
        "unsupported": len(result["unsupported"]),
        "allocating": {n: sum(bool(lanes["single_owner_after"]["configs"]["release"][n]["kernel"]["allocs"] or
                                     lanes["single_owner_after"]["configs"]["release"][n]["kernel"]["reallocs"])
                              for lanes in result["census"].values()) for n in ("4", "11")},
    }
    (HERE / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print("qualified", result["executions"], "executions", result["summary"], flush=True)


if __name__ == "__main__":
    main()
