#!/usr/bin/env python3
"""Bounded direct native-test probe for the C4 selective-lowering evidence.

Complements `scripts/profile_large_project.py`, whose `forced_tests` state does
not request `--report` and therefore cannot show lowering/emission/link
counters or warm/unchanged and helper-edit states.  This driver reuses the
harness generators so the sources are byte-identical in shape, then invokes the
real `mylang test` CLI and records the complete child/folded `work-report-v1`,
`native-tests-v1`, cache file inventory and wall/RSS for each state.

It intentionally does not modify the versioned v3 harness; the frozen
generator_sha256 of that harness is recorded by the matrix runs.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
import profile_large_project as harness  # noqa: E402

MIB = 1024 * 1024


def parse_final_test_report(stderr: str):
    records = harness.extract_protocol_records(stderr, "work-report-v1")
    for record in reversed(records):
        if record.get("command") == "test":
            return record
    return None


def stage(report, name):
    value = (report or {}).get(name)
    return value if isinstance(value, dict) else {}


def counter(report, name, field):
    value = stage(report, name).get(field)
    return value if isinstance(value, int) else None


def cache_inventory(cache_dir: Path):
    inventory = {"graphs": 0, "results": 0, "objects": 0, "other": 0, "total": 0}
    if not cache_dir.exists():
        return inventory
    for path in cache_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(cache_dir)
        head = rel.parts[0] if rel.parts else "other"
        key = head if head in ("graphs", "results", "objects") else "other"
        inventory[key] += 1
        inventory["total"] += 1
    return inventory


def one_run(compiler, entry, cache_dir, args, env, timeout, trace_path):
    """Run one `mylang test` child, returning the folded counters and inventory."""
    argv = [compiler, "test", entry, "--json", "--report", "--cache-dir=" + str(cache_dir)]
    argv += list(args)
    if trace_path is not None:
        try:
            trace_path.write_text("")
        except OSError:
            pass
    before = cache_inventory(cache_dir)
    result = harness.run_measured(argv, timeout=timeout, env=env)
    after = cache_inventory(cache_dir)
    native = harness.extract_native_tests(result["stdout"])
    report = parse_final_test_report(result["stderr"])
    children = harness.extract_protocol_records(result["stderr"], "work-report-v1")
    test_entries = (native or {}).get("tests") or []
    sample = {
        "wall_ms": result["wall_ms"],
        "peak_rss_kb": result["peak_rss_kb"],
        "exit": result["exit"],
        "timed_out": result["timed_out"],
        "success": (not result["timed_out"] and result["exit"] == 0 and report is not None),
        "statuses": [item.get("status") for item in test_entries],
        "native": {key: (native or {}).get(key) for key in ("passed", "failed", "skipped", "cached", "executed")},
        "reused_results": (report or {}).get("reused_results"),
        "counters": {
            key: {
                "status": stage(report, key).get("status"),
                "performed": counter(report, key, "performed"),
                "reused": counter(report, key, "reused"),
            }
            for key in (
                "parsed_modules", "checked_bodies", "instantiated_specializations",
                "lowered_functions", "emitted_fragments", "links", "executed_tests",
                "symbolic_templates", "specialization_bodies",
            )
        },
        "semantic_cache": (report or {}).get("semantic_cache"),
        "bypassed": (report or {}).get("bypassed"),
        "child_commands": [child.get("command") for child in children],
        "child_reports": [
            {
                "command": child.get("command"),
                "stages": {
                    key: {field: stage(child, key).get(field) for field in ("status", "performed", "reused")}
                    for key in ("parsed_modules", "checked_bodies", "instantiated_specializations",
                                "lowered_functions", "emitted_fragments", "links", "executed_tests",
                                "symbolic_templates", "specialization_bodies")
                },
            }
            for child in children
        ],
        "cache_before": before,
        "cache_after": after,
        "cache_files_delta": after["total"] - before["total"],
        "select_file": None,
        "diagnostic": result["stderr"][:800] if result["exit"] != 0 else "",
    }
    if trace_path is not None and trace_path.exists():
        lines = [line for line in trace_path.read_text().splitlines() if line.strip()]
        sample["select_file"] = next(
            (line for line in lines if "--select-file=" in line), None)
        sample["select_file_count"] = sum(1 for line in lines if "--select-file=" in line)
    return sample


def summarize(samples):
    good = [s["wall_ms"] for s in samples if s["success"]]
    good_rss = [s["peak_rss_kb"] for s in samples if s["success"] and s.get("peak_rss_kb")]
    import math

    def pct(values, fraction):
        if not values:
            return None
        ordered = sorted(values)
        return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]

    return {
        "n": len(good),
        "failed": len(samples) - len(good),
        "p50_ms": (sorted(good)[len(good) // 2] if good else None),
        "p95_ms": pct(good, 0.95),
        "min_ms": min(good) if good else None,
        "max_ms": max(good) if good else None,
        "peak_rss_kb": max(good_rss) if good_rss else None,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--workdir", default="/tmp/s1-final-native")
    parser.add_argument("--sizes", default="10000,100000")
    parser.add_argument("--families", default="ordinary,managed")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--first-builds", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()

    compiler = str(Path(args.compiler).resolve())
    workdir = Path(args.workdir)
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True, exist_ok=True)
    # One fixed environment for every run: the receipt/graph key fingerprints
    # the whole environment, so a varying value would defeat warm reuse.
    env = dict(os.environ)
    trace_path = workdir / "test-trace.log"
    env["MYLANG_TEST_TRACE"] = str(trace_path)
    target_sizes = [int(item) for item in args.sizes.split(",")]
    families = args.families.split(",")

    document = {
        "version": "s1-final-native-probe-v1",
        "compiler": compiler,
        "compiler_sha256": harness.sha256_file(compiler),
        "harness_path": str(Path(harness.__file__).resolve()),
        "generator_sha256": harness.sha256_file(harness.__file__),
        "probe_sha256": harness.sha256_file(__file__),
        "host_load_before": Path("/proc/loadavg").read_text().strip(),
        "workdir": str(workdir),
        "method": "direct `mylang test --json --report` with a fixed environment; work-report-v1 folded counters",
        "workloads": [],
    }
    for family in families:
        for target in target_sizes:
            label = f"{family}-{target // 1000}k"
            root = workdir / "sources" / label
            if family == "ordinary":
                modules = 64
                functions_hint = max(1, target // (3 * modules))
                functions, lines, total_bytes = harness.size_ordinary(root, target, modules, functions_hint)
                entry, paths = harness.generate_ordinary_modules(root, modules, functions)
                used_edit = lambda token: harness.apply_ordinary_edit(paths, "implementation_edit", token)
                unused_target = root / "m001.my"

                def unused_edit(token):
                    text = unused_target.read_text()
                    text = text.replace("    return base(x) + 1", f"    return base(x) + {token}")
                    unused_target.write_text(text)
                    return unused_target
                provider_edit = None
                pristine_paths = [root / "m000.my", root / "m001.my", root / "conf.my", root / "main.my"]
            elif family == "managed":
                providers = 64
                functions_hint = max(1, target // (3 * providers))
                functions, lines, total_bytes = harness.size_managed(root, target, providers, functions_hint)
                entry, paths = harness.generate_managed(root, providers, functions)
                pricing = root / "pricing.my"
                original_apply = "    return P.price(policy, subtotal) + P.tag(policy)"

                def managed_used_edit(token, pricing=pricing, original=original_apply):
                    text = pricing.read_text()
                    text = text.replace(original, f"{original} + {token}")
                    pricing.write_text(text)
                    return pricing
                used_edit = managed_used_edit
                provider_target = root / "provider000.my"
                original_size = "    return size(Node.leaf(x)) + 1"

                def managed_unused_edit(token, target=provider_target, original=original_size):
                    text = target.read_text()
                    text = text.replace(original, f"    return size(Node.leaf(x)) + {token}")
                    target.write_text(text)
                    return target
                unused_edit = managed_unused_edit
                provider_edit = (lambda token: harness.apply_managed_edit(paths, "provider_edit", token, paths["providers"]))
                pristine_paths = [root / "provider000.my", root / "pricing.my", root / "conf.my", root / "main.my"]
            else:
                raise SystemExit(f"unknown family {family}")
            pristine = {path: path.read_text() for path in pristine_paths}

            def restore():
                for path, text in pristine.items():
                    path.write_text(text)

            restore()
            workload = {
                "label": label,
                "family": family,
                "target_lines": target,
                "generated_lines": lines,
                "generated_bytes": total_bytes,
                "entry": str(entry),
                "states": [],
            }
            cache = workdir / "caches" / label

            def loadavg():
                try:
                    return Path("/proc/loadavg").read_text().strip()
                except OSError:
                    return None

            def record(state_name, cache_dir, extra_args=(), rerun=None):
                runs = []
                load_start = loadavg()
                for index in range(rerun if rerun is not None else args.repeats):
                    if extra_args == ("FIRST_BUILD",):
                        shutil.rmtree(cache_dir, ignore_errors=True)
                        cache_dir.mkdir(parents=True, exist_ok=True)
                        argv = ()
                    else:
                        argv = extra_args
                    sample = one_run(compiler, str(entry), cache_dir, argv, env, args.timeout, trace_path)
                    sample["sample"] = index
                    runs.append(sample)
                entry_out = {"state": state_name, "summary": summarize(runs),
                             "load_start": load_start, "load_end": loadavg(), "samples": runs}
                workload["states"].append(entry_out)
                return entry_out

            first = record("first_build_cold_cache", cache, ("FIRST_BUILD",), args.first_builds)
            warm = record("warm_unchanged_cached", cache)
            forced = record("forced_run", cache, ("--force",))
            # used helper edit
            restore()
            used_runs = []
            for index in range(args.repeats):
                restore()
                used_edit(1000 + index)
                sample = one_run(compiler, str(entry), cache, (), env, args.timeout, trace_path)
                sample["sample"] = index
                used_runs.append(sample)
            restore()
            workload["states"].append({"state": "used_helper_edit", "summary": summarize(used_runs),
                                        "load_start": loadavg(), "load_end": loadavg(), "samples": used_runs})
            # unused helper edit
            unused_runs = []
            for index in range(args.repeats):
                restore()
                unused_edit(2000 + index)
                sample = one_run(compiler, str(entry), cache, (), env, args.timeout, trace_path)
                sample["sample"] = index
                unused_runs.append(sample)
            restore()
            workload["states"].append({"state": "unused_helper_edit", "summary": summarize(unused_runs),
                                        "load_start": loadavg(), "load_end": loadavg(), "samples": unused_runs})
            if provider_edit is not None:
                provider_runs = []
                for index in range(args.repeats):
                    restore()
                    provider_edit(1 + index)
                    sample = one_run(compiler, str(entry), cache, (), env, args.timeout, trace_path)
                    sample["sample"] = index
                    provider_runs.append(sample)
                restore()
                workload["states"].append({"state": "provider_edit", "summary": summarize(provider_runs),
                                        "load_start": loadavg(), "load_end": loadavg(), "samples": provider_runs})
            # no-cache control: no durable graph/receipt files may be written.
            nocache = workdir / "caches" / (label + "-nocache")
            shutil.rmtree(nocache, ignore_errors=True)
            nocache.mkdir(parents=True, exist_ok=True)
            nc_sample = one_run(compiler, str(entry), nocache, ("--no-cache",), env, args.timeout, None)
            nc_sample["files_after_no_cache"] = cache_inventory(nocache)
            nc_sample["no_cache_clean"] = all(
                (nocache / part).exists() is False or not any((nocache / part).rglob("*"))
                for part in ("graphs", "results", "objects"))
            workload["states"].append({"state": "no_cache_control", "summary": summarize([nc_sample]),
                                        "load_start": loadavg(), "load_end": loadavg(), "samples": [nc_sample]})
            document["workloads"].append(workload)
            print(f"[native] {label}: first={first['summary']['p50_ms']}ms warm={warm['summary']['p50_ms']}ms forced={forced['summary']['p50_ms']}ms", flush=True)
            Path(args.output).write_text(json.dumps(document, indent=2) + "\n")
    document["host_load_after"] = Path("/proc/loadavg").read_text().strip()
    Path(args.output).write_text(json.dumps(document, indent=2) + "\n")
    print(json.dumps({"output": args.output}, indent=2))


if __name__ == "__main__":
    main()
