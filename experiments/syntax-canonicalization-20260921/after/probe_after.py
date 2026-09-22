#!/usr/bin/env python3
"""Capture post-implementation evidence without modifying the audit baseline."""
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASE = HERE.parent
COMPILER = Path(os.environ.get(
    "MYLANG_CANONICAL_AFTER_COMPILER", ROOT / "zig-out/focus/mylang"
)).resolve()


def load_probe():
    spec = importlib.util.spec_from_file_location("canonical_probe", BASE / "probe.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load_probe()
probe.ROOT = ROOT
probe.HERE = HERE
probe.COMPILER = COMPILER
probe.CASES = dict(probe.CASES)
probe.CASES.update({
    "format_single_text_noalloc": (
        "def identity(value: str) -> str noalloc:\n"
        "    return f\"{value}\"\n"
    ),
    "library_float_noalloc": (
        "import strings\n\n"
        "def parse(s: str) -> Option[float] noalloc:\n"
        "    return strings.to_float(s)\n"
    ),
    "string_compare_noalloc": (
        "import sort\n\n"
        "def compare(left: str, right: str) -> int noalloc:\n"
        "    return sort.compare_strs(left, right)\n"
    ),
    "sort_keyed": (
        "record Item:\n"
        "    key: int\n"
        "    position: int\n\n"
        "def item_key(item: Item) -> int effects():\n"
        "    return item.key\n\n"
        "def order(items: list[Item]) -> list[Item]:\n"
        "    return sorted(items, key=item_key)\n"
    ),
    "sort_text_in_place": (
        "def order(items: list[str]):\n"
        "    items.sort()\n"
    ),
    "range_list": (
        "def materialize(start: int, end: int) -> list[int]:\n"
        "    return list(range(start, end))\n"
    ),
    "dict_items_stored": (
        "def total(d: dict[str, int]) -> int noalloc:\n"
        "    items = d.items()\n"
        "    result = 0\n"
        "    for key, value in items:\n"
        "        result += len(key) + value\n"
        "    return result\n"
    ),
    "dict_values_stored": (
        "def total(d: dict[str, int]) -> int noalloc:\n"
        "    values = d.values()\n"
        "    result = 0\n"
        "    for value in values:\n"
        "        result += value\n"
        "    return result\n"
    ),
})
probe.RUNTIME = '''import strings

def main(out: Stream) -> int:
    out.print(float(" 1.5 "))
    out.print(strings.to_float(" 1.5 "))
    out.print(float("1_000.5"))
    out.print(strings.to_float("1_000.5"))
    out.print(float("inf"))
    out.print(strings.to_float("inf"))
    d = {"a": 10, "b": 20}
    items = d.items()
    item_total = 0
    for key, value in items:
        item_total += len(key) + value
    out.print(item_total)
    values = d.values()
    value_total = 0
    for value in values:
        value_total += value
    out.print(value_total)
    return 0
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(args):
    result = subprocess.run(
        [str(COMPILER), *args], cwd=ROOT, text=True,
        capture_output=True, timeout=120,
    )
    return {
        "command": [str(COMPILER.relative_to(ROOT)), *args],
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


probe.invoke = invoke


def metrics(path):
    if not path.exists():
        return None
    text = path.read_text()
    calls = Counter(re.findall(r"call \$(myl_native_[A-Za-z0-9_]+)", text))
    return {
        "ir_bytes": len(text.encode()),
        "runtime_call_sites": dict(sorted(calls.items())),
        "text_concat_sites": calls["myl_native_text_concat"],
        "text_compare_sites": calls["myl_native_text_compare"],
        "text_encode_sites": calls["myl_native_bytes_encode"],
        "list_new_sites": calls["myl_native_list_new"],
        "list_append_sites": calls["myl_native_list_append"],
        "list_clear_sites": calls["myl_native_list_clear"],
        "list_sort_sites": calls["myl_native_list_sort"],
        "list_new_zero_capacity_sites": len(re.findall(
            r"call \$myl_native_list_new\([^\n]*, l 0\)", text
        )),
        "bytes_slice_sites": calls["myl_native_bytes_slice"],
        "bytes_view_sites": calls["myl_native_bytes_view"],
        "bytes_range_sites": calls["myl_native_bytes_range"],
    }


def numeric_delta(before, after):
    if before is None or after is None:
        return None
    keys = sorted((set(before) & set(after)) - {"runtime_call_sites"})
    return {key: after[key] - before[key] for key in keys}


def call_site_delta(before, after):
    if before is None or after is None:
        return None
    before_calls = before["runtime_call_sites"]
    after_calls = after["runtime_call_sites"]
    names = sorted(set(before_calls) | set(after_calls))
    return {
        name: after_calls.get(name, 0) - before_calls.get(name, 0)
        for name in names
        if after_calls.get(name, 0) != before_calls.get(name, 0)
    }


def enrich():
    evidence_path = HERE / "evidence.json"
    evidence = json.loads(evidence_path.read_text())
    baseline = json.loads((BASE / "evidence.json").read_text())
    evidence["capture"] = {
        "compiler_path": str(COMPILER.relative_to(ROOT)),
        "compiler_realpath": str(COMPILER.resolve()),
        "compiler_sha256": digest(COMPILER),
        "compiler_size_bytes": COMPILER.stat().st_size,
        "baseline_evidence_sha256": digest(BASE / "evidence.json"),
        "baseline_probe_sha256": digest(BASE / "probe.py"),
        "scope": "static checks, emitted QBE, and one native behavior run; no timing benchmark",
    }
    evidence["fixes"] = {
        "1_sorting": [
            "sort_in_place", "sort_copy", "sort_text", "sort_text_in_place",
            "sort_keyed",
        ],
        "2_numeric_parser": ["prelude_float_noalloc", "library_float", "library_float_noalloc"],
        "3_immediate_ranges": ["bytes_slice_noalloc", "bytes_view_noalloc", "bytes_range_noalloc"],
        "4_f_strings": ["format", "format_single_text_noalloc"],
        "5_text_comparison": ["minimum_text_noalloc", "minimum_text", "string_compare_noalloc"],
        "6_known_capacity": ["comprehension", "range_comprehension", "range_list"],
        "7_dictionary_views": ["dict_items_direct", "dict_values_direct", "dict_items_stored", "dict_values_stored"],
    }
    comparisons = {}
    for name, row in evidence["cases"].items():
        after_metrics = metrics(HERE / "ir" / (name + ".ssa"))
        before_metrics = metrics(BASE / "ir" / (name + ".ssa"))
        before_row = baseline["cases"].get(name)
        comparisons[name] = {
            "baseline_check_exit": None if before_row is None else before_row["check"]["exit_code"],
            "after_check_exit": row["check"]["exit_code"],
            "baseline_metrics": before_metrics,
            "after_metrics": after_metrics,
            "numeric_delta_after_minus_baseline": numeric_delta(before_metrics, after_metrics),
            "runtime_call_site_delta_after_minus_baseline": call_site_delta(
                before_metrics, after_metrics
            ),
        }
    evidence["comparisons"] = comparisons
    evidence["behavior_comparison"] = {
        "baseline": baseline["behavior"],
        "after": evidence["behavior"],
        "note": (
            "The after probe prints sums obtained by iterating stored dictionary "
            "views; the baseline printed the eagerly materialized items list."
        ),
    }
    expected_failure = {"removed_float_intrinsic"}
    unexpected_checks = {
        name: row["check"]["exit_code"]
        for name, row in evidence["cases"].items()
        if (row["check"]["exit_code"] != 0) != (name in expected_failure)
    }
    evidence["verification"] = {
        "compiler_unchanged_during_capture": (
            evidence["compiler_sha256_before"] == evidence["compiler_sha256_after"]
        ),
        "expected_rejection_cases": sorted(expected_failure),
        "unexpected_check_results": unexpected_checks,
        "behavior_exit_zero": evidence["behavior"]["exit_code"] == 0,
        "behavior_stdout_matches": evidence["behavior"]["stdout"] == (
            "Some(1.5)\nSome(1.5)\nSome(1000.5)\nSome(1000.5)\n"
            "Some(inf)\nSome(inf)\n32\n30\n"
        ),
        "static_ir_observations": {
            "non_key_sort_routes_to_native_sort": (
                comparisons["sort_copy"]["after_metrics"]["list_sort_sites"] == 1
                and comparisons["sort_text"]["after_metrics"]["list_sort_sites"] == 1
                and comparisons["sort_text_in_place"]["after_metrics"]["list_sort_sites"] == 1
            ),
            "text_min_uses_compare_without_encode": (
                comparisons["minimum_text"]["after_metrics"]["text_compare_sites"] == 1
                and comparisons["minimum_text"]["after_metrics"]["text_encode_sites"] == 0
            ),
            "immediate_slice_and_view_use_range": all(
                comparisons[name]["after_metrics"]["bytes_range_sites"] == 1
                for name in ("bytes_slice_noalloc", "bytes_view_noalloc")
            ),
            "multi_piece_format_uses_one_join_without_concat": (
                comparisons["format"]["after_metrics"]["text_concat_sites"] == 0
                and comparisons["format"]["after_metrics"]["runtime_call_sites"].get(
                    "myl_native_text_join", 0
                ) == 1
            ),
            "known_size_lists_do_not_pass_literal_zero_capacity": all(
                comparisons[name]["after_metrics"]["list_new_zero_capacity_sites"] == 0
                for name in ("comprehension", "range_comprehension", "range_list")
            ),
            "stored_dictionary_views_materialize_no_list": all(
                comparisons[name]["after_metrics"]["list_new_sites"] == 0
                for name in ("dict_items_stored", "dict_values_stored")
            ),
        },
    }
    tracked = [
        "src/sema.zig", "src/prelude_builtins.zig", "src/collection_lower.zig",
        "src/generic_bodies.zig", "src/buffer_operations.zig", "src/qbe_text.zig",
        "src/qbe_managed.zig", "src/native_collections.c", "src/native_text.c",
        "src/native_bytes.c", "src/stdlib/strings.my", "src/stdlib/sort.my",
    ]
    evidence["source_sha256_after"].update(
        {path: digest(ROOT / path) for path in tracked}
    )
    evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")


def main():
    if not COMPILER.is_file():
        raise SystemExit(f"missing focused compiler: {COMPILER}")
    probe.main()
    enrich()


if __name__ == "__main__":
    main()
