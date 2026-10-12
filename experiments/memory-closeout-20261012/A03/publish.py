#!/usr/bin/env python3
"""Publish only A03 evidence from one completed, isolated census run."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent

# These classify source requirements/opportunities, not individual malloc calls.
REASONS = {
    "01_scalar": "scalar control",
    "02_local_list": "bounded local list; stack-eligible control",
    "03_borrowed_reader": "borrowed bounded list; stack-eligible control",
    "04_returned_list": "independent result storage; caller destination opportunity",
    "05_mut_destination": "caller destination; stack-eligible control",
    "06_dynamic_list": "independent list storage and growth",
    "07_large_list": "large list storage and growth",
    "08_snapshot_read": "two borrowed reads; stack-eligible control",
    "09_snapshot_mutate": "explicit independent copy and growth",
    "10_loop_snapshots": "explicit saved copies",
    "11_record_scalar": "scalar aggregate control",
    "12_record_list": "owned child storage and growth",
    "13_record_snapshot": "explicit aggregate/child copy and growth",
    "14_nested_lists": "independent child storage and outer growth",
    "15_managed_elements": "independent text/list children; formatting intermediates",
    "16_branch_alias": "explicit branch copy and growth",
    "17_indirect_reader": "list storage across indirect borrowed call; promotion opportunity",
    "18_recursive_reader": "list storage across recursive borrowed call; promotion opportunity",
    "19_return_field": "explicit independent returned-field copy",
    "20_loop_carried": "owned in-place growth; prior artificial sharing removed by migration",
    "21_dict_unique": "dictionary storage/growth; native side tables excluded",
    "22_dict_snapshot": "explicit dictionary copy/growth; native side tables excluded",
    "23_dict_managed": "dictionary/owned text storage; formatting/replacement intermediates",
    "24_text_builder": "owned text growth",
    "25_text_snapshot": "explicit text copy and growth",
    "26_text_slice": "owned text growth; returned view borrows without materialization",
    "27_buffer_builder": "buffer growth",
    "28_buffer_snapshot": "explicit independent bytes materialization and buffer growth",
    "29_list_filter": "source and independent filtered-result storage/growth",
    "30_sort_scratch": "list storage; native sort scratch excluded",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must be alphanumeric with hyphens/underscores")
    run = args.run.resolve()
    result_bytes = (run / "results.json").read_bytes()
    result = json.loads(result_bytes)
    destination = HERE / args.label
    destination.mkdir(exist_ok=False)
    with gzip.GzipFile(filename=str(destination / "results.json.gz"), mode="wb", mtime=0) as stream:
        stream.write(result_bytes)
    with tarfile.open(destination / "raw-json.tar.gz", "w:gz") as archive:
        for path in sorted((run / "raw").rglob("*.json")):
            archive.add(path, arcname=str(path.relative_to(run)))
    for name in ('manifest.json', 'census.py.snapshot'):
        if (run / name).exists():
            (destination / name).write_bytes((run / name).read_bytes())
    summary = result["summary"]
    compiler = result["identities"]["compiler"]
    lines = [f"# A03 {args.label} census", "", f"Compiler commit: `{compiler['commit']}`.",
             f"Compiler SHA-256: `{compiler['sha256']}`.",
             f"Ownership request: `{result['identities']['ownership']}`.", "",
             f"Executed {summary['executions']} guests; {summary['passed_executions']} passed output, exit, RC and managed-leak checks.",
             f"Observed RC in {summary['executions_with_rc']} runs; managed exit leaks in {summary['executions_with_managed_leaks']} runs.", ""]
    if summary['original_denominator']:
        lines += ["| Original 30, migrated workload | Allocate | Allocation-free | Execute RC | Refused | Failed | Unmeasured |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    else:
        lines += ["This supplemental manifest is separate from the original 30 and pinned 81-case matrix; its cases do not change either denominator.", ""]
    for count, row in summary["original_30"].items():
        lines.append(f"| n={count}; denominator 30 | {row['allocating']} | {row['allocation_free']} | {row['executed_rc']} | {row['refused']} | {row['failed']} | {row['unmeasured']} |")
    original = summary["original_source_checks"]
    if summary['original_denominator']:
        lines += ["", f"The original unmigrated source checks admitted {original['admitted']}, refused {original['refused']}, failed outside a source diagnostic {original.get('failed', 0)}, and left {original['unmeasured']} unmeasured.",
                  "These checks are a separate source-migration inventory; they are not counted as migrated execution successes.", ""]
    lines += ["| Configuration/status | Cases |", "| --- | ---: |"]
    for status, count in sorted(summary["case_status"].items()):
        lines.append(f"| {status} | {count} |")
    if summary['original_denominator']:
        lines += ["", "All following measurements are fresh release-mode input-11 observations. Workload totals exclude startup/teardown (`<outside>`).", "",
                  "| Original ID | Status | Workload blocks / reallocs | Workload cumulative bytes | Whole-program peak / exit-live bytes | Source cost classification |",
                  "| --- | --- | ---: | ---: | ---: | --- |"]
    for case_id, case in result["cases"].items():
        if not case_id.startswith("census/"):
            continue
        name = case["manifest"]["original_id"]
        lane = case["modes"].get("release", {})
        sample = lane.get("runs", {}).get("11", {})
        workload = sample.get("workload", {})
        memory = sample.get("whole_program", {})
        if workload:
            blocks = f"{workload['allocs']} / {workload['reallocs']}"
            traffic = workload["alloc_bytes"] + workload["realloc_added_bytes"]
            peak = f"{memory['peak_live_bytes']} / {memory['live_bytes_at_exit']}"
        else:
            blocks, traffic, peak = "unmeasured", "unmeasured", "unmeasured"
        lines.append(f"| {name} | {lane.get('status', 'unmeasured')} | {blocks} | {traffic} | {peak} | {REASONS[name]} |")
    lookup_rows = []
    for kind in ("array", "object"):
        for size in (1, 16, 128):
            for action in ("hit", "miss"):
                names = [f"batch/{kind}_{size}_{suffix}" for suffix in ("control", action)]
                samples = [result["cases"].get(name, {}).get("modes", {}).get("release", {}).get("runs", {}).get("0", {}) for name in names]
                if not all(sample.get("passed") for sample in samples):
                    continue
                control, active = [sample["whole_program"] for sample in samples]
                lookup_rows.append({"case": names[1], "allocations_per_lookup": (active["allocs"] - control["allocs"]) / 32,
                                    "reallocations_per_lookup": (active["reallocs"] - control["reallocs"]) / 32,
                                    "cumulative_bytes_per_lookup": (active["alloc_bytes"] + active["realloc_added_bytes"] - control["alloc_bytes"] - control["realloc_added_bytes"]) / 32})
    if lookup_rows:
        lines += ["", "## Fresh JSON lookup and field-transfer controls", "",
                  "Lookup traffic is the matched active case minus construction-only control, divided by 32 lookups. Peak memory is not subtracted.", "",
                  "| Lookup | Added allocations per lookup | Added reallocations per lookup | Added cumulative managed bytes per lookup |",
                  "| --- | ---: | ---: | ---: |"]
        for row in lookup_rows:
            lines.append(f"| {row['case']} | {row['allocations_per_lookup']:g} | {row['reallocations_per_lookup']:g} | {row['cumulative_bytes_per_lookup']:g} |")
    controls = {"json_lookup": lookup_rows, "record_source_variants": {}}
    for phase in ("before", "after"):
        sample = result["cases"].get("batch/record_" + phase, {}).get("modes", {}).get("release", {}).get("runs", {}).get("0", {})
        if sample.get("passed"):
            controls["record_source_variants"][phase] = sample["whole_program"]
    if len(controls["record_source_variants"]) == 2:
        copied, moved = (controls["record_source_variants"][phase] for phase in ("before", "after"))
        lines += ["", f"The explicit-copy record source allocates {copied['allocs']} whole-program blocks; the transferred-field source allocates {moved['allocs']} on the same compiler (1,000 unpacks).",
                  "This is a source-semantics comparison, not a compiler-only before/after result."]
    (destination / "controls.json").write_text(json.dumps(controls, indent=2) + "\n")
    lines += ["", "Classification describes storage required by source semantics and concrete optimization opportunities. It does not attribute every allocation to one category.",
              "Formatting/concatenation intermediates are actionable candidates only after an owner demonstrates a semantics-preserving removal.",
              "Explicit copies and independent return storage must retain their documented independence. Growth is legitimate allocation work.",
              "Task infrastructure is covered separately by the expanded task cases and A01's scheduler decomposition.", "",
              "For every admitted executable, machine-readable results preserve source/binary/LLVM hashes, output, workload and whole-program counters, and LLVM/linked-symbol audit results.",
              "`raw-json.tar.gz` contains the command receipts and complete counted reports. Full native binaries and LLVM remain in the recorded scratch run directory.",
              "Managed peak is never subtracted as traffic and is not process RSS. Native dictionaries, sort scratch, provider buffers, task stacks and allocator overhead lie outside these counters.",
              "Copy-traffic telemetry is distinct from allocation traffic: A09's 8ba337fd6 correction adds previously unrecorded recursive child-list copies without changing allocations, freed bytes, or managed peak. A C0/candidate difference in list-copy counts or bytes alone is not a new allocation cost.",
              "Admission receipts record queue wait separately for batched runs; command receipts mark whether wait is excluded. These are not compile-performance measurements. A09 owns runtime/RSS/compile timings.", ""]
    failures = [(name, mode, lane) for name, case in result["cases"].items() for mode, lane in case["modes"].items() if lane["status"] != "passed"]
    if failures:
        lines += ["## Failures and refusals", ""]
        for name, mode, lane in failures:
            detail = lane.get("error") or lane.get("build", {}).get("stderr", "")[:1000]
            lines += [f"- `{name}/{mode}`: {lane['status']}. `{detail.strip().replace(chr(10), ' ')}`"]
    (destination / "REPORT.md").write_text("\n".join(lines) + "\n")
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(destination.iterdir())}
    (destination / "sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
