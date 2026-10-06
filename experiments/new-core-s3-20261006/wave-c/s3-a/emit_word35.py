#!/usr/bin/env python3
"""Retain all 35 raw LLVM definition diffs for the authorized scalar dictionary stores."""
import argparse
from collections import Counter
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[4]


def imported(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def calls(function):
    return Counter(re.findall(r'\bcall[^\n]*?@("[^"]+"|[A-Za-z0-9_.]+)\(', function))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    rows = imported("word35_rows", Path(__file__).with_name("measure_all40.py"))
    audit = imported("word35_identity", ROOT / "experiments/new-core-s3-20261006/wave-b/s3-c/identity_audit.py")
    evidence = args.evidence.resolve()
    evidence.relative_to(ROOT)
    evidence.mkdir(parents=True, exist_ok=False)
    cache = ROOT / ".mylang-cache/s3-a" / evidence.name
    (cache / "before").mkdir(parents=True, exist_ok=False)
    (cache / "after").mkdir()
    summary = {"qualified": False, "baseline": str(args.baseline), "rows": [], "error": None}
    try:
        for row in rows.UNITS:
            if row in rows.APPLICATIONS:
                continue
            stem = rows.stem(row)
            before = cache / "before" / f"{stem}.ll"
            after = cache / "after" / f"{stem}.ll"
            shutil.copy2(args.baseline / before.name, before)
            command = [ROOT / "zig-out/bin/mylang-core", "build", ROOT / "test/core" / f"{stem}.my",
                       "-o", cache / f"{stem}_new", "--release", "--emit-llvm", after,
                       "--cache-dir", cache / "core-cache", "--link", ROOT / "benchmarks/runtime/ports/native_clock.c"]
            built = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            (evidence / f"{stem}.build.json").write_text(json.dumps({"command": list(map(str, command)), "status": built.returncode, "stdout": built.stdout, "stderr": built.stderr}, indent=2) + "\n")
            if built.returncode:
                raise RuntimeError(f"build failed {row}: {built.stderr}")
            original, current = before.read_text(), after.read_text()
            old_functions, new_functions = audit.functions(original), audit.functions(current)
            if old_functions.keys() != new_functions.keys():
                raise RuntimeError(f"definition set changed for {row}")
            (evidence / f"{stem}.raw.diff").write_text("".join(difflib.unified_diff(original.splitlines(True), current.splitlines(True), fromfile="qualified-C", tofile="word-scalar-store")))
            old_sites, new_sites = audit.sites(original), audit.sites(current)
            old_debug, new_debug = audit.debug(original), audit.debug(current)
            record = {"row": row, "before_sha256": hashlib.sha256(before.read_bytes()).hexdigest(), "after_sha256": hashlib.sha256(after.read_bytes()).hexdigest(), "changed_functions": [], "unexpected_functions": []}
            for name in old_functions:
                old = audit.normalize(old_functions[name], old_sites, old_debug)
                new = audit.normalize(new_functions[name], new_sites, new_debug)
                if old == new:
                    continue
                old_calls, new_calls = calls(old), calls(new)
                removed = old_calls["myl_core_dict_set"] - new_calls["myl_core_dict_set"]
                expected = old_calls.copy()
                expected["myl_core_dict_set"] -= removed
                allowed = removed > 0 and expected == new_calls
                record["changed_functions"].append({"function": name, "removed_scalar_set_calls": removed, "other_call_counts_unchanged": expected == new_calls,
                                                     "classification": "authorized scalar dictionary update emission" if allowed else "unexpected; inspect raw and definition diffs"})
                (evidence / f"{stem}.{len(record['changed_functions'])}.definition.diff").write_text("".join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile="qualified-C", tofile="word-scalar-store")))
                if not allowed:
                    record["unexpected_functions"].append(name)
            summary["rows"].append(record)
            print(f"{row}: {len(record['changed_functions'])} changed definitions; {len(record['unexpected_functions'])} unexpected", flush=True)
        summary["qualified"] = len(summary["rows"]) == 35 and not any(row["unexpected_functions"] for row in summary["rows"])
        summary["limit"] = "Raw/SSA-and-semantic-metadata-only diffs retained. Call classification bounds affected functions; exact address/store changes still require review. No instructions, traps, CFG labels or general runtime calls are removed by normalization."
        if not summary["qualified"]:
            raise RuntimeError("unexpected changed functions; retained diffs require review")
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
