#!/usr/bin/env python3
"""Qualify small lifetime probes and preserve static and executed memory evidence."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GROUPS = ("lists.json", "composites.json", "containers.json")
RC_KINDS = ("retain", "release", "release_unique", "unique_test")
COPY_KINDS = ("list_copy", "dict_copy", "buffer_copy", "text_copy", "record_copy")
FUNCTION_METRICS = (
    "allocs", "alloc_bytes", "frees", "free_bytes", "reallocs",
    "realloc_added_bytes", "realloc_moves", "realloc_moved_bytes",
    "runtime_retains", "runtime_releases", "list_grows", "list_grow_bytes",
    "dict_grows", "dict_grow_bytes", "buffer_grows", "buffer_grow_bytes",
    "text_grows", "text_grow_bytes", "list_copies", "list_copy_bytes",
    "dict_copies", "dict_copy_bytes", "buffer_copies", "buffer_copy_bytes",
    "text_copies", "text_copy_bytes",
)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def invoke(argv, prefix, env, expected=None):
    argv = [str(x) for x in argv]
    ran = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, timeout=300)
    prefix.with_suffix(".stdout").write_bytes(ran.stdout)
    prefix.with_suffix(".stderr").write_bytes(ran.stderr)
    write_json(prefix.with_suffix(".command.json"), {"argv": argv, "status": ran.returncode})
    if ran.returncode:
        raise RuntimeError(f"{prefix.name}: exit {ran.returncode}: {ran.stderr.decode(errors='replace')[:1500]}")
    if expected is not None:
        if ran.stdout != expected.encode() or ran.stderr:
            raise RuntimeError(f"{prefix.name}: wanted {expected!r}; stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    return ran.stdout


def summarize(document):
    if document["version"] != "mylang-counters-v1":
        raise ValueError("unknown counters schema")
    if document["totals"]["live_bytes_at_exit"] != 0:
        raise ValueError("managed memory remains live at exit")
    functions = [row for row in document["functions"] if row["name"] != "<outside>"]
    kernel = {key: sum(row.get(key, 0) for row in functions) for key in FUNCTION_METRICS}
    kernel["kinds"] = {kind: sum(site["count"] for site in document["sites"]
                                if site["kind"] == kind and site["function"] != "<outside>")
                       for kind in RC_KINDS + COPY_KINDS}
    kernel["unique_shared"] = sum(site["count"] - site["extra"] for site in document["sites"]
                                  if site["kind"] == "unique_test" and site["function"] != "<outside>")
    kernel["copies"] = sum(kernel[key] for key in
                           ("list_copies", "dict_copies", "buffer_copies", "text_copies"))
    # Inline sites and out-of-line runtime releases can describe the same release.
    # Preserve them separately; never add these columns into one RC operation total.
    kernel["classification"] = (
        "sharing RC" if kernel["kinds"]["retain"] or kernel["runtime_retains"] else
        "heap + cleanup/count checks" if kernel["allocs"] or kernel["reallocs"] else
        "count operations without observed managed allocation" if any(kernel["kinds"][k] for k in RC_KINDS)
        or kernel["runtime_releases"] else "no observed managed heap/RC"
    )
    return {"kernel": kernel, "whole_program": document["totals"],
            "outside": [r for r in document["functions"] if r["name"] == "<outside>"],
            "functions": functions,
            "rc_and_copy_sites": [s for s in document["sites"] if s["kind"] in RC_KINDS + COPY_KINDS]}


def capture_case(case, args, env):
    source = HERE / case["source"]
    raw = args.output / case["id"]
    completed = raw / "result.json"
    source_hash = digest(source)
    if args.resume and completed.exists():
        old = json.loads(completed.read_text())
        if (old["source_sha256"] == source_hash and old["compiler_sha256"] == digest(args.compiler)
                and old.get("harness_sha256") == args.harness_sha256 and old.get("zig_sha256") == args.zig_sha256):
            if old["expected"] == case["expected"]:
                print(f"reuse {case['id']}", flush=True)
                return old
    raw.mkdir(parents=True, exist_ok=True)
    record = dict(case, source_sha256=source_hash, compiler_sha256=digest(args.compiler),
                  harness_sha256=args.harness_sha256, zig_sha256=args.zig_sha256, runs={}, binaries={})
    record["static"] = json.loads(invoke([args.compiler, "cost", source, "--json"], raw / "cost", env))
    ir = invoke([args.compiler, "dump-ir", source, "--facts"], raw / "core", env)
    (raw / "core.ir").write_bytes(ir)
    for mode, flags in (("plain", []), ("counted", ["--counters"]), ("verify", ["--verify-facts"])):
        binary = raw / mode
        command = [args.compiler, "build", source, "--release", "--zig", args.zig,
                   "--cache-dir", args.output / "cache", "-o", binary] + flags
        if mode == "plain":
            command += ["--emit-llvm", raw / "plain.ll"]
        invoke(command, raw / ("build-" + mode), env)
        record["binaries"][mode] = {"sha256": digest(binary), "path": str(binary)}
        for n in (4, 11):
            run_env = dict(env, MYL_CORE_LEAKCHECK="1")
            count_path = raw / f"counts-n{n}.json"
            if mode == "counted":
                run_env["MYLANG_COUNTERS"] = str(count_path)
            invoke([binary] + ["x"] * n, raw / f"{mode}-n{n}", run_env, case["expected"][str(n)])
            run = record["runs"].setdefault(str(n), {"args": ["x"] * n, "stdout": case["expected"][str(n)], "qualified_modes": []})
            run["qualified_modes"].append(mode)
            if mode == "counted":
                run.update(summarize(json.loads(count_path.read_text())))
    if digest(source) != source_hash:
        raise RuntimeError("sample source changed during qualification")
    write_json(completed, record)
    print(f"pass {case['id']}: n=11 heap={record['runs']['11']['kernel']['allocs']} "
          f"retain={record['runs']['11']['kernel']['kinds']['retain']}", flush=True)
    return record


def publish(result, output):
    evidence = HERE / "evidence"
    evidence.mkdir(exist_ok=True)
    for case in result["cases"]:
        raw = output / case["id"]
        dest = evidence / case["id"]
        dest.mkdir(exist_ok=True)
        for name in ("core.ir", "counts-n4.json", "counts-n11.json"):
            shutil.copyfile(raw / name, dest / name)
        write_json(dest / "cost.json", case["static"])
        case["evidence_sha256"] = {p.name: digest(p) for p in sorted(dest.iterdir()) if p.is_file()}
    write_json(HERE / "results.json", result)
    shutil.copyfile(output / "compiler-sources.json", HERE / "compiler-sources.json")
    with (HERE / "summary.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("case", "n", "managed_allocs", "alloc_bytes", "reallocs", "core_retains", "core_releases",
                         "unique_frees", "unique_tests", "runtime_retains", "runtime_releases", "collection_copies", "stack_lists"))
        for case in result["cases"]:
            for n, run in case["runs"].items():
                k = run["kernel"]
                writer.writerow((case["id"], n, k["allocs"], k["alloc_bytes"], k["reallocs"],
                                 *(k["kinds"][key] for key in RC_KINDS),
                                 k["runtime_retains"], k["runtime_releases"], k["copies"],
                                 case["static"]["totals"]["rc"]["stack_lists"]))
    write_details(result)


def source_link(case, line=1):
    return f"[{case['id']}:{line}]({case['source']}#L{line})"


def site_link(case, site):
    path = Path(site["path"])
    if not path.is_absolute():
        path = ROOT / path
    target = os.path.relpath(path, HERE)
    label = case["id"] if path.resolve() == (HERE / case["source"]).resolve() else path.name
    return f"[{label}:{site['line']}]({target}#L{site['line']})"


def write_details(result):
    lines = ["# Per-program evidence", "", "Generated by `census.py`. Both inputs passed ordinary, counted, and fact-verification builds.",
             "Counts below exclude `<outside>` startup/teardown. Full counts and optimized Core IR are linked per case.",
             "Core release sites and runtime releases overlap; do not sum them. Unique frees are listed separately from decrements.",
             "Collection copies count runtime list/dictionary/buffer/text copies; aggregate record copies appear in the source-site tables separately.",
             "Heap numbers cover managed blocks; C allocator scratch is not included. Static allocation sites are potential sites, not executions.", ""]
    for case in result["cases"]:
        lines += [f"## {case['id']}: {case['title']}", "", case["intent"], "", f"Source: {source_link(case)}. {case['focus']}",
                  "", f"Expected-output derivation: {case['oracle']}", "",
                  "| Input n | Output | Managed blocks | Allocated bytes | Reallocs | Retains | Releases | Unique frees | Uniqueness tests | Runtime retain/release | Collection copies |",
                  "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
        for n, run in case["runs"].items():
            k = run["kernel"]; s = k["kinds"]
            lines.append(f"| {n} | {run['stdout'].strip()} | {k['allocs']} | {k['alloc_bytes']} | {k['reallocs']} | "
                         f"{s['retain']} | {s['release']} | {s['release_unique']} | {s['unique_test']} | "
                         f"{k['runtime_retains']}/{k['runtime_releases']} | {k['copies']} |")
        totals = case["static"]["totals"]
        evidence = "evidence/" + case["id"]
        lines += ["", f"Static: {totals['allocation']['sites']} potential allocation sites; "
                  f"{totals['rc']['stack_lists']} promoted lists; {totals['inlined_calls']} Core inlined calls. "
                  f"[Cost]({evidence}/cost.json), [optimized IR]({evidence}/core.ir), "
                  f"[n=4 counters]({evidence}/counts-n4.json), [n=11 counters]({evidence}/counts-n11.json).", "",
                  "Allocation and runtime count activity by emitted function at n=11:", "",
                  "| Function | Blocks | Bytes | Runtime retain/release | Collection copies |",
                  "| --- | ---: | ---: | ---: | ---: |"]
        for row in case["runs"]["11"]["functions"]:
            if any(row.get(k, 0) for k in ("allocs", "reallocs", "runtime_retains", "runtime_releases")):
                copies = sum(row.get(k, 0) for k in ("list_copies", "dict_copies", "buffer_copies", "text_copies"))
                lines.append(f"| `{row['name']}` | {row['allocs']} | {row['alloc_bytes']} | "
                             f"{row['runtime_retains']}/{row['runtime_releases']} | {copies} |")
        sites = case["runs"]["11"]["rc_and_copy_sites"]
        if sites:
            lines += ["", "Executed RC/copy sites at n=11 (source locations survive Core inlining):", "",
                      "| Source | Operation | Count | Bytes | Source function → emitted function |",
                      "| --- | --- | ---: | ---: | --- |"]
            for site in sites:
                lines.append(f"| {site_link(case, site)} | `{site['kind']}` / `{site['detail']}` | "
                             f"{site['count']} | {site['bytes']} | `{site['origin']}` → `{site['function']}` |")
        else:
            lines += ["", "No executed Core RC/copy sites at n=11."]
        lines += [""]
    (HERE / "DETAILS.md").write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--zig", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    args.compiler = args.compiler.resolve(); args.zig = args.zig.resolve(); args.output = args.output.resolve()
    args.harness_sha256 = digest(__file__)
    args.zig_sha256 = digest(args.zig)
    args.output.mkdir(parents=True, exist_ok=args.resume)
    cases = sorted((case for group in GROUPS if (HERE / group).exists()
                    for case in json.loads((HERE / group).read_text())), key=lambda c: c["id"])
    if len({c["id"] for c in cases}) != len(cases) or (not args.case and len(cases) != 30):
        raise ValueError("expected 30 distinct cases")
    if args.case:
        cases = [c for c in cases if c["id"] in args.case]
        if len(cases) != len(set(args.case)):
            raise ValueError("unknown case")
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    for key in ("MYLANG_COUNTERS", "MYL_CORE_LEAKCHECK"):
        env.pop(key, None)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    manifest = {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / "src").rglob("*"))
                if p.is_file() and not p.name.endswith("_test.zig")}
    write_json(args.output / "compiler-sources.json", manifest)
    result = {"version": "rc-census-v1", "compiler": str(args.compiler), "compiler_sha256": digest(args.compiler),
              "compiler_base_revision": revision, "compiler_source_manifest_sha256": digest(args.output / "compiler-sources.json"),
              "zig": str(args.zig), "zig_sha256": args.zig_sha256, "harness_sha256": args.harness_sha256,
              "build_mode": "--release", "inputs": [4, 11], "cases": [], "failures": []}
    for case in cases:
        try:
            result["cases"].append(capture_case(case, args, env))
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            result["failures"].append({"case": case["id"], "error": str(error)})
            print(f"FAIL {case['id']}: {error}", flush=True)
        write_json(args.output / "results.json", result)
    if result["failures"]:
        return 1
    result["qualified_executions"] = len(result["cases"]) * 6
    write_json(args.output / "results.json", result)
    if args.publish:
        if len(result["cases"]) != 30:
            raise ValueError("publish requires the complete suite")
        publish(result, args.output)
    print(f"qualified {len(result['cases'])} programs / {result['qualified_executions']} executions", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
