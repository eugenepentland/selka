#!/usr/bin/env python3
"""FB1 exit: report/stats equality and unchanged bytes on the 46-row registry; P1."""
import argparse, hashlib, importlib.util, json, os, pathlib, re, subprocess, time
ROOT = pathlib.Path(__file__).resolve().parents[3]
AREA = pathlib.Path(__file__).resolve().parents[1]

def heavy():
    found = []
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdecimal(): continue
        try: command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except OSError: continue
        if any(word in command for word in ("zig build", "fuzz_matrix.py", "bench-newcore", "test-units")): found.append({"pid": int(entry.name), "command": command})
    return found

def run(label, argv, cwd=ROOT):
    directory = AREA / "commands"; directory.mkdir(exist_ok=True)
    path = directory / label
    if path.with_suffix(".json").exists(): raise RuntimeError(f"retained command exists: {label}")
    record = {"command": list(map(str, argv)), "cwd": str(cwd), "affinity": sorted(os.sched_getaffinity(0)), "other_heavy_processes": heavy()}
    started = time.monotonic()
    result = subprocess.run(record["command"], cwd=cwd, capture_output=True, text=True)
    record.update(seconds=time.monotonic()-started, status=result.returncode)
    path.with_suffix(".stdout").write_text(result.stdout); path.with_suffix(".stderr").write_text(result.stderr)
    path.with_suffix(".json").write_text(json.dumps(record, indent=2)+"\n")
    if result.returncode: raise RuntimeError(f"{label} failed: {result.stderr[-3000:]}")
    return result

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def counts(stderr):
    first = re.search(r"inlined (\d+) calls, unswitched (\d+) loops, versioned (\d+) loops, proved (\d+) checks, vectorized (\d+) loops", stderr)
    second = re.search(r"ownership: (\d+) updates in place, (\d+) tested, (\d+) copied; (\d+) retains, (\d+) releases \((\d+) pairs elided\); (\d+) lists on the stack", stderr)
    third = re.search(r"cost: (\d+) checks kept; (\d+) allocation sites \((\d+) unresolved calls\); (\d+) unknown loops", stderr)
    fourth = re.search(r"LLVM vectorized (unknown|\d+); (\d+) unknown loops; remarks (available|unavailable)", stderr)
    assert all((first, second, third, fourth)), stderr
    out = {}
    for match, keys in ((first, ("inlined_calls", "unswitched_loops", "versioned_loops", "checks_proved", "vector_plans")), (second, ("updates_in_place", "updates_tested", "updates_copied", "retains", "releases", "elided_pairs", "stack_lists")), (third, ("checks_kept", "allocations", "unresolved_allocation_calls", "loops_unknown"))):
        out.update(zip(keys, map(int, match.groups())))
    out["llvm_vectorized_loops"] = None if fourth[1] == "unknown" else int(fourth[1])
    assert out["loops_unknown"] == int(fourth[2])
    return out

def flatten(counts):
    result = {"inlined_calls": counts["inlined_calls"], "llvm_vectorized_loops": counts["llvm_vectorized_loops"]}
    mapping = {"checks": {"kept": "checks_kept", "proved": "checks_proved"}, "updates": {"in_place": "updates_in_place", "tested": "updates_tested", "copied": "updates_copied"}, "allocation": {"sites": "allocations", "unresolved_calls": "unresolved_allocation_calls"}, "rc": {name: name for name in ("retains", "releases", "elided_pairs", "stack_lists")}, "loops": {"unswitched": "unswitched_loops", "versioned": "versioned_loops", "vector_plans": "vector_plans", "unknown": "loops_unknown"}}
    for group, fields in mapping.items():
        result.update({name: counts[group][field] for field, name in fields.items()})
    return result

def summed(report):
    result = {key: 0 for key in flatten(report["totals"]) if key != "llvm_vectorized_loops"}
    result["llvm_vectorized_loops"] = None
    for function in report["functions"]:
        for key, value in flatten(function["counts"]).items():
            if key == "llvm_vectorized_loops":
                if value is not None: result[key] = (result[key] or 0) + value
            else: result[key] += value
    return result

def row_sources():
    path = ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py"
    spec = importlib.util.spec_from_file_location("fb1_rows", path); registry = importlib.util.module_from_spec(spec); spec.loader.exec_module(registry)
    assert len(registry.rows.UNITS) == 46
    result = {name: ROOT / "test/core" / (registry.rows.stem(name)+".my") for name in registry.rows.UNITS}
    assert all(path.is_file() for path in result.values())
    return result

def compare(core, label, path, mode, cache):
    cost_flags = {"release": [], "debug": ["--debug"], "verify": ["--verify-facts"], "off": ["--no-facts"]}[mode]
    build_flags = {"release": ["--release"], "debug": [], "verify": ["--release", "--verify-facts"], "off": ["--release", "--no-facts"]}[mode]
    directory = cache / label; directory.mkdir(parents=True, exist_ok=True)
    report = json.loads(run(label+"-cost", [core, "cost", path, "--json", *cost_flags]).stdout)
    assert summed(report) == flatten(report["totals"])
    common = [core, "build", path, *build_flags, "--cache-dir", directory / "cache", "--link", ROOT / "benchmarks/runtime/ports/native_clock.c"]
    stats = run(label+"-stats", [*common, "-o", directory / "with", "--stats", "--emit-llvm", directory / "with.ll"])
    observed = counts(stats.stderr)
    assert flatten(report["totals"]) == observed, (label, report["totals"], observed)
    run(label+"-plain", [*common, "-o", directory / "plain", "--emit-llvm", directory / "plain.ll"])
    assert digest(directory / "with.ll") == digest(directory / "plain.ll"), label+" LLVM changed"
    assert digest(directory / "with") == digest(directory / "plain"), label+" executable changed"
    return {"source": str(path.relative_to(ROOT)), "mode": mode, "totals": observed, "llvm_sha256": digest(directory/"with.ll"), "executable_sha256": digest(directory/"with"), "equal": True}

def p1(core, corpus, path, output):
    report = json.loads(run(output.name+"-"+corpus+"-cost", [core, "cost", path, "--json"]).stdout)
    assert summed(report) == flatten(report["totals"])
    (output / (corpus+".json")).write_text(json.dumps(report, indent=2)+"\n")
    top = sorted(report["functions"], key=lambda item: (-item["counts"]["updates"]["copied"], -item["counts"]["updates"]["tested"], item["name"]))[:20]
    lines = ["# "+corpus+" application cost", "", "Static release-pass sites reachable from main; cloned work belongs to its emitted caller.", "", "Totals: "+json.dumps(report["totals"], sort_keys=True), "", "## The 20 functions with most copies", "", "| Function | In place | Tested | Copied |", "|---|---:|---:|---:|"]
    lines += [f"| `{item['name']}` | {item['counts']['updates']['in_place']} | {item['counts']['updates']['tested']} | {item['counts']['updates']['copied']} |" for item in top]
    lines += ["", "## Every emitted function", "", "| Function | In place | Tested | Copied |", "|---|---:|---:|---:|"]
    lines += [f"| `{item['name']}` | {item['counts']['updates']['in_place']} | {item['counts']['updates']['tested']} | {item['counts']['updates']['copied']} |" for item in report["functions"]]
    (output / (corpus+".md")).write_text("\n".join(lines)+"\n")
    return {"entry": str(path), "entry_sha256": digest(path), "functions": len(report["functions"]), "totals": report["totals"], "top20": top}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=pathlib.Path, required=True)
    parser.add_argument("--rows", help="comma-separated subset, only for fixture smoke runs")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--p1", action="store_true")
    args = parser.parse_args(); core = args.core.resolve()
    cache = ROOT / ".mylang-cache/frontend-fb1" / args.run_id
    output = AREA / args.run_id; output.mkdir()
    results = {}
    if args.p1:
        entries = {"lox": pathlib.Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-fp2-lox/benchmarks/lox/ports/mylang/main.my"), "eda": pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/codex-frontend-fp2-eda/mylang/src/main.my")}
        for name, path in entries.items(): results[name] = p1(core, name, path, output)
    else:
        selected = row_sources()
        if args.rows: selected = {name: selected[name] for name in args.rows.split(",")}
        for name, path in selected.items():
            for mode in ("debug", "release", "verify", "off"):
                label = args.run_id+"-"+name+"-"+mode
                results[label] = compare(core, label, path, mode, cache)
            print(name+": all four modes matched stats; LLVM and executable hashes identical", flush=True)
    summary = {"core": str(core), "core_sha256": digest(core), "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "affinity": sorted(os.sched_getaffinity(0)), "rows": len(results), "results": results}
    (output/"summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(json.dumps({"output": str(output), "rows": len(results), "passed": True}))

if __name__ == "__main__": main()
