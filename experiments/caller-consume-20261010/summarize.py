#!/usr/bin/env python3
"""Write a compact before/after table without modifying the original census."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RC = ("retain", "release", "release_unique", "unique_test")
FIELDS = ("allocs", "alloc_bytes", "reallocs", "realloc_added_bytes", "realloc_moves",
          "realloc_moved_bytes", "runtime_retains", "runtime_releases", "list_copies",
          "list_copy_bytes", "dict_copies", "dict_copy_bytes", "buffer_copies",
          "buffer_copy_bytes", "text_copies", "text_copy_bytes", "list_grows",
          "list_grow_bytes", "dict_grows", "dict_grow_bytes", "buffer_grows",
          "buffer_grow_bytes", "text_grows", "text_grow_bytes")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def metrics(run):
    k = run["kernel"]
    return {"kernel": {**{key: k[key] for key in FIELDS},
                       "core_rc": {key: k["kinds"][key] for key in RC},
                       "unique_shared": k["unique_shared"],
                       "record_copy_events": k["kinds"]["record_copy"],
                       "record_copy_bytes": sum(s["bytes"] for s in run["rc_and_copy_sites"]
                                                if s["kind"] == "record_copy")},
            "whole_program": {key: run["whole_program"][key] for key in
                              ("allocs", "alloc_bytes", "peak_live_bytes", "live_bytes_at_exit")}}


def static(record):
    t = record["static"]["totals"]
    return {"allocation_sites": t["allocation"]["sites"], "rc": t["rc"],
            "inlined_calls": t["inlined_calls"]}


def pair(before, after):
    if before["source_sha256"] != after["source_sha256"]:
        raise ValueError("different source for comparison")
    result = {"source": before["source"], "source_sha256": before["source_sha256"],
              "static": {"baseline": static(before), "candidate": static(after)}, "runs": {}}
    if set(before["runs"]) != set(after["runs"]):
        raise ValueError("different input sets")
    for name, b in before["runs"].items():
        c = after["runs"][name]
        status = b.get("status", 0)
        if (b["stdout"] != c["stdout"] or status != c.get("status", 0)
                or b.get("argv", b.get("args")) != c.get("argv", c.get("args"))
                or b["qualified_modes"] != ["plain", "counted", "verify"]
                or c["qualified_modes"] != ["plain", "counted", "verify"]):
            raise ValueError("qualification/output parity failed")
        row = {"stdout": b["stdout"], "status": status}
        if status:
            if any("R_OVERFLOW" not in text for arm in (b, c) for text in arm["trap_stderr"].values()):
                raise ValueError("expected overflow trap missing")
            row["trap_diagnostics_equal"] = b["trap_stderr"] == c["trap_stderr"]
        else:
            row["baseline"] = metrics(b)
            row["candidate"] = metrics(c)
        result["runs"][name] = row
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    before = json.loads(args.baseline.read_text())
    after = json.loads(args.candidate.read_text())
    for arm in (before, after):
        if arm["failures"] or len(arm["cases"]) != 30 or arm.get("qualified_executions") != 230:
            raise ValueError("incomplete capture")
    if before["harness_sha256"] != after["harness_sha256"] or before["zig_sha256"] != after["zig_sha256"]:
        raise ValueError("harness or toolchain changed")
    args.output.mkdir(parents=True, exist_ok=True)
    result = {"version": "caller-consume-comparison-v1", "identity": {}, "census": {}, "targets": {},
              "metric_scope": {"kernel": "All emitted functions excluding outside startup/teardown.",
                "whole_program_peak": "Counter-reported peak managed live bytes, including startup; not RSS or C allocator scratch.",
                "traffic": "alloc_bytes and realloc_added_bytes are separate cumulative amounts; neither is peak memory.",
                "rc": "Core sites and runtime RC hooks remain separate because they can overlap.",
                "copies": "Hooked copies only; known text/buffer snapshot and runtime scratch blindspots remain."}}
    for label, arm, path in (("baseline", before, args.baseline), ("candidate", after, args.candidate)):
        result["identity"][label] = {key: arm[key] for key in ("compiler_sha256",
            "compiler_source_manifest_sha256", "compiler_base_revision", "installed_files", "harness_sha256", "zig_sha256")}
        result["identity"][label]["capture_sha256"] = sha(path)
        result["identity"][label]["qualified_executions"] = arm["qualified_executions"]
        result["identity"][label]["cache_parity"] = arm["cache_parity"]
    indexed = {case["id"]: case for case in after["cases"]}
    for case in before["cases"]:
        value = pair(case, indexed[case["id"]])
        value["source"] = "../rc-census-20261010/" + value["source"]
        result["census"][case["id"]] = value
    for name, record in before["targets"].items():
        result["targets"][name] = pair(record, after["targets"][name])
    (args.output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    with (args.output / "summary.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("case", "input", "compiler", "kernel_blocks", "kernel_alloc_bytes", "kernel_realloc_added_bytes",
                         "whole_program_managed_peak", "retains", "releases", "unique_frees", "uniqueness_tests",
                         "runtime_retains", "runtime_releases", "list_copies", "list_copy_bytes"))
        for group in (result["census"], result["targets"]):
            for name, case in group.items():
                for input_name, row in case["runs"].items():
                    if row["status"]:
                        continue
                    for label in ("baseline", "candidate"):
                        k = row[label]["kernel"]
                        writer.writerow((name, input_name, label, k["allocs"], k["alloc_bytes"], k["realloc_added_bytes"],
                                         row[label]["whole_program"]["peak_live_bytes"], *(k["core_rc"][key] for key in RC),
                                         k["runtime_retains"], k["runtime_releases"], k["list_copies"], k["list_copy_bytes"]))
    print(f"Compared 30 unchanged census samples and {len(result['targets'])} scaled workloads.")


if __name__ == "__main__":
    main()
