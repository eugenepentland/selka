#!/usr/bin/env python3
"""Attribute existing allocation profiles; never launch or modify benchmarks."""

import gzip
import hashlib
import json
from pathlib import Path
import tarfile


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FRESH = ROOT / "experiments/lox-eda-rerun-20261012"
OLD = ROOT / "experiments/lox-eda-zero-rc-20261012"
ARM = "mylang-zero-rc"
INPUTS = {}


def remember(path, data):
    INPUTS[str(path.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
    return data


def read(path):
    data = remember(path, path.read_bytes())
    return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)


def fresh_counter():
    member = "counted/tree-equality.mylang-zero-rc.counters.json"
    manifest = read(FRESH / "raw-evidence-manifest.json")
    path = FRESH / member
    if path.exists():
        data = path.read_bytes()
    else:
        with tarfile.open(FRESH / manifest["archive"], "r:gz") as archive:
            data = archive.extractfile(member).read()
    assert hashlib.sha256(data).hexdigest() == manifest["files"][member]
    return json.loads(remember(path, data))


def traffic(row):
    return row["alloc_bytes"] + row["realloc_added_bytes"]


def summarize(profiles, missing=()):
    functions = {}
    cases = {}
    for case, profile in sorted(profiles.items()):
        totals = profile["totals"]
        assert sum(traffic(f) for f in profile["functions"]) == traffic(totals), case
        assert totals["live_bytes_at_exit"] == 0, case
        cases[case] = {
            "allocation_traffic_bytes": traffic(totals),
            "allocations": totals["allocs"],
            "reallocations": totals["reallocs"],
            "peak_live_managed_bytes": totals["peak_live_bytes"],
            "exit_live_managed_bytes": totals["live_bytes_at_exit"],
        }
        for function in profile["functions"]:
            dest = functions.setdefault(function["name"], {
                "allocation_traffic_bytes": 0, "allocations": 0,
                "calls": 0, "cases_with_traffic": 0,
            })
            dest["allocation_traffic_bytes"] += traffic(function)
            dest["allocations"] += function["allocs"]
            dest["calls"] += function["calls"]
            dest["cases_with_traffic"] += int(traffic(function) > 0)
    total = sum(c["allocation_traffic_bytes"] for c in cases.values())
    for function in functions.values():
        function["traffic_share_percent"] = 100 * function["allocation_traffic_bytes"] / total
    functions = dict(sorted(functions.items(), key=lambda item: (
        -item[1]["allocation_traffic_bytes"], item[0])))
    return {
        "completed_cases": len(cases), "total_cases": len(cases) + len(missing),
        "missing_cases": sorted(missing), "cases": cases,
        "allocation_traffic_bytes": total,
        "largest_per_case_peak_live_managed_bytes": max(
            c["peak_live_managed_bytes"] for c in cases.values()),
        "functions": functions,
    }


def selected(dataset, names):
    amount = sum(dataset["functions"][name]["allocation_traffic_bytes"] for name in names)
    return {"functions": names, "allocation_traffic_bytes": amount,
            "traffic_share_percent": 100 * amount / dataset["allocation_traffic_bytes"]}


def main():
    results = read(FRESH / "results.json")
    fresh = fresh_counter()
    complete = []
    censored = []
    for case, cell in sorted(results["cells"].items()):
        arm = cell["arms"][ARM]
        if arm["complete"]:
            complete.append(case)
        else:
            assert arm["failures"] and not arm["wall_samples"], case
            assert all(f["status"] == "relative_timeout" and f["phase"] == "warmup"
                       for f in arm["failures"]), case
            censored.append(case)
    assert complete == ["lox/tree/equality"] and len(censored) == 59

    old_tree, old_vm, missing_vm = {}, {}, []
    paths = sorted((OLD / "lox/full-size-counters").glob("*.counted.spec.summary.json.gz"))
    assert len(paths) == 26
    for path in paths:
        summary = read(path)
        case, arm = summary["cell"], summary["arms"][ARM]
        if "counters" not in arm:
            assert case.startswith("lox/vm/") and arm["status"]["status"] == "timeout"
            missing_vm.append(case)
        else:
            dest = old_tree if case.startswith("lox/tree/") else old_vm
            dest[case] = arm["counters"]
    assert (len(old_tree), len(old_vm), len(missing_vm)) == (13, 7, 6)
    old_eda = {}
    for path in sorted((OLD / "bench/results/eda-counted").glob("*.mylang-zero-rc.counters.json.gz")):
        case = "eda/" + path.name.removesuffix(".mylang-zero-rc.counters.json.gz").removeprefix("eda-")
        old_eda[case] = read(path)
    assert len(old_eda) == 34

    datasets = {
        "fresh_tree_equality": summarize({"lox/tree/equality": fresh}),
        "historical_tree": summarize(old_tree),
        "historical_vm": summarize(old_vm, missing_vm),
        "historical_vm_fib": summarize({"lox/vm/fib": old_vm["lox/vm/fib"]}),
        "historical_eda": summarize(old_eda),
        "historical_eda_rds3_flat": summarize({"eda/rds3+flat": old_eda["eda/rds3+flat"]}),
    }
    selections = {
        "P1_vm_dispatch": ("historical_vm_fib", ["vm::run"]),
        "P2_tree_evaluation": ("fresh_tree_equality", ["interpreter::evaluate"]),
        "P2_tree_evaluation_and_statements": ("fresh_tree_equality", [
            "interpreter::evaluate", "interpreter::execute", "interpreter::run_block"]),
        "P3_object_reads": ("historical_tree", [
            "heap::class_obj", "interpreter::instance_of", "heap::env_obj", "heap::string_obj"]),
        "P4_eda_ast": ("historical_eda", ["sexpr_ast::as_list", "sexpr_ast::node_list"]),
        "P5_overlap_all_eda": ("historical_eda", ["kicad_sch_textbox::overlaps_of"]),
        "P5_overlap_rds3_flat": ("historical_eda_rds3_flat", ["kicad_sch_textbox::overlaps_of"]),
    }
    targets = {key: {"dataset": dataset, **selected(datasets[dataset], names)}
               for key, (dataset, names) in selections.items()}

    # Pin inspected source and provenance without modifying historical evidence.
    sources = [OLD / "lox/migrated" / (name + ".my")
               for name in ("heap", "interpreter", "vm", "object", "output")]
    sources += [OLD / "eda/source/src" / (name + ".my") for name in (
        "sexpr_ast", "sexpr_parser", "kicad_sch_textbox", "kicad_sch_verify", "support_sort")]
    sources += [ROOT / path for path in (
        "src/core/build_list_methods.zig", "src/core/single_owner_copy.zig",
        "src/core/single_owner.zig", "docs/tooling/ownership.md")]
    sources += [OLD / "README.md", OLD / "lox/full-size-counters/README.md",
                OLD / "bench/full-final/COMPARISON.md",
                ROOT / "experiments/text-gaps-20261012/README.md", HERE / "audit.py"]
    for path in sources:
        remember(path, path.read_bytes())
    old_readme = (OLD / "README.md").read_text()
    historical_commit = "e2893d2707cbe057a09abf94e04c4b12d16b7b8b"
    historical_compiler = "6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d"
    assert historical_commit in old_readme and historical_compiler in old_readme
    output = {
        "schema_version": 1,
        "scope": "Existing allocation profiles and source audit; no new benchmark executions",
        "traffic_definition": "alloc_bytes + realloc_added_bytes; exclusive function totals verified",
        "limitations": [
            "Allocation attribution is not CPU-time attribution or a speedup forecast.",
            "Historical and fresh datasets use different compiler binaries; never pooled.",
            "Per-function totals include legitimate allocations as well as avoidable copies.",
            "Source copy-event byte counts can overlap; they are not added to traffic.",
            "Corpus traffic shares weight the frozen workloads by allocated bytes, not equally.",
            "Peak managed memory and process RSS are not cumulative allocation traffic.",
            "59 fresh checked cases timed out during warmup; exact current ratios are unavailable.",
        ],
        "compiler_identities": {
            "fresh": {"source_commit": results["compiler_source_commit"], "sha256": results["compiler_sha256"]},
            "historical": {"source_commit": historical_commit, "sha256": historical_compiler},
        },
        "fresh_runtime_coverage": {"total_cases": 60, "completed_cases": complete,
                                   "censored_cases": censored, "counter_coverage": results["counter_coverage"]},
        "fresh_tree_equality_runtime": results["cells"]["lox/tree/equality"]["arms"][ARM],
        "targets": targets, "datasets": datasets, "input_sha256": dict(sorted(INPUTS.items())),
        "validation": {"function_traffic_matches_totals": True,
                       "completed_profiles_have_zero_exit_live_bytes": True,
                       "historical_unique_completed_profiles": 54,
                       "fresh_unique_completed_profiles": 1},
    }
    (HERE / "attribution.json").write_text(json.dumps(output, indent=2) + "\n")
    for name, target in targets.items():
        print(f"{name}: {target['allocation_traffic_bytes']:,} bytes; {target['traffic_share_percent']:.2f}% ({target['dataset']})")
    print("Validated 55 completed profiles, six historical missing VM profiles, and all 60 fresh runtime statuses.")


if __name__ == "__main__":
    main()
