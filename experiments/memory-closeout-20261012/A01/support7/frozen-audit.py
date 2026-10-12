#!/usr/bin/env python3
"""Audit whole-program RC counters; this is execution evidence, not a static proof."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SITE_RC = ("retain", "release", "unique_test")
RUNTIME_RC = ("runtime_retains", "runtime_releases", "shared_retains",
              "shared_releases", "share_marks")
MEMORY = ("allocs", "alloc_bytes", "frees", "reallocs", "peak_live_bytes",
          "live_bytes_at_exit")


def label(path):
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def natural(value):
    if type(value) is not int or value < 0:
        raise ValueError("counter must be a nonnegative integer")
    return value


def audit(path):
    raw = path.read_bytes()
    data = json.loads(raw)
    if data["version"] != "mylang-counters-v1":
        raise ValueError("unsupported counter schema")
    totals, kinds = data["totals"], data["kinds"]
    # Require every field: an incomplete or incompatible report must not pass.
    runtime = {key: natural(totals[key]) for key in RUNTIME_RC}
    emitted = {key: natural(kinds[key]["count"]) for key in SITE_RC}
    memory = {key: natural(totals[key]) for key in MEMORY}
    direct_frees = natural(kinds["release_unique"]["count"])
    # Retain the locations of executed RC sites and runtime calls, including main
    # and <outside>. Never add the emitted and runtime counters: they can overlap.
    sites = []
    site_totals = dict.fromkeys(SITE_RC, 0)
    for site in data["sites"]:
        if site["kind"] not in SITE_RC:
            continue
        count = natural(site["count"])
        site_totals[site["kind"]] += count
        if count:
            sites.append({key: site[key] for key in
                          ("function", "origin", "path", "line", "column", "kind", "count")})
    if site_totals != emitted:
        raise ValueError("RC site counts do not match kind totals")
    functions = []
    runtime_totals = dict.fromkeys(RUNTIME_RC, 0)
    for function in data["functions"]:
        counts = {key: natural(function[key]) for key in RUNTIME_RC}
        for key, count in counts.items():
            runtime_totals[key] += count
        if any(counts.values()):
            functions.append({"function": function["name"], **counts})
    if runtime_totals != runtime:
        raise ValueError("function RC counts do not match runtime totals")
    return {
        "counter_file": label(path),
        "counter_sha256": hashlib.sha256(raw).hexdigest(),
        "observed_rc_free": not any((*runtime.values(), *emitted.values())),
        "managed_leak_free": memory["live_bytes_at_exit"] == 0,
        "emitted_rc": emitted,
        "runtime_rc": runtime,
        "direct_frees": direct_frees,
        "memory": memory,
        "executed_rc_sites": sites,
        "runtime_rc_functions": functions,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path,
                        help="counter JSON files, or directories containing counts-*.json")
    parser.add_argument("--output", type=Path, help="write the report here instead of stdout")
    parser.add_argument("--require-zero", action="store_true",
                        help="exit 1 if any run records RC or live managed bytes at exit")
    args = parser.parse_args()
    try:
        paths = set()
        for given in args.inputs:
            path = given.resolve()
            if path.is_dir():
                found = set(path.rglob("counts-*.json"))
                if not found:
                    raise ValueError(f"no counter reports in {path}")
                paths.update(found)
            elif path.is_file():
                paths.add(path)
            else:
                raise ValueError(f"missing input: {path}")
        runs = []
        for path in sorted(paths):
            try:
                runs.append(audit(path))
            except (OSError, ValueError, KeyError, TypeError) as error:
                raise ValueError(f"{path}: invalid counter report: {error}") from error
        report = {
            "schema": "mylang-zero-rc-audit-v1",
            "audit_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "scope": "Whole execution, including main and startup/teardown (<outside>).",
            "limitations": [
                "Existing counters do not cover every runtime reference-count read or check.",
                "Zero observed events does not prove that unexecuted paths contain no RC.",
                "Emitted and runtime RC columns can overlap; do not sum them.",
                "Memory measures managed blocks, not RSS or all allocator storage.",
            ],
            "summary": {
                "runs": len(runs),
                "observed_rc_free_runs": sum(run["observed_rc_free"] for run in runs),
                "managed_leak_free_runs": sum(run["managed_leak_free"] for run in runs),
            },
            "runs": runs,
        }
        rendered = json.dumps(report, indent=2) + "\n"
        if args.output:
            args.output.write_text(rendered)
        else:
            sys.stdout.write(rendered)
        summary = report["summary"]
        print(f"{len(runs)} runs: {summary['observed_rc_free_runs']} with no observed RC; "
              f"{summary['managed_leak_free_runs']} with no managed leaks", file=sys.stderr)
        failed = any(not run["observed_rc_free"] or not run["managed_leak_free"] for run in runs)
        return 1 if args.require_zero and failed else 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"audit: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
