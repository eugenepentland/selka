#!/usr/bin/env python3
"""Check whether dictionary fact repair affects the already qualified rebinding200.

This is a frontend-only replay: no guest builds or executions. It regenerates
the inherited S1 sequence with one RNG, then compares complete dump-ir --facts
output from the two frozen installed compilers.
"""
import argparse
import difflib
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import shlex
import subprocess
import sys
import time


BASE = "090dabd5a6932a7c3beaec68248f9a35d4c637d7"
D_TREE = "69bd18dfbbf741cfb5cee7af40e11d4540278643"
FEATURES = ["mut", "records", "alias"]
EXCLUDED_CPUS = {2, 3, 10, 11}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=True)
    return result.stdout


def binary_stat(path):
    info = path.stat()
    return {"path": str(path), "inode": info.st_ino, "size": info.st_size, "mtime_ns": info.st_mtime_ns}


def compiler_changes(root):
    return [path for path in git(root, "diff", "--name-only", BASE, "--", "src/core").splitlines()
            if path.endswith(".zig") and not path.endswith("_test.zig")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--after-root", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.root = args.root.resolve()
    args.after_root = args.after_root.resolve()
    args.scratch = args.scratch.resolve()
    args.evidence = args.evidence.resolve()
    args.evidence.mkdir(parents=True, exist_ok=True)
    source_dir = args.scratch / "sources"
    output_dir = args.scratch / "ir"
    source_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    before = args.root / "zig-out/bin/mylang-core"
    after = args.after_root / "zig-out/bin/mylang-core"
    started = time.monotonic()
    original_path = args.evidence / "fuzz-200/rebinding/summary.json"
    original = json.loads(original_path.read_text())
    report = {
        "command": shlex.join([sys.executable, *sys.argv]),
        "baseline_source_commit": BASE,
        "repaired_staged_source_tree": D_TREE,
        "before_root": str(args.root), "after_root": str(args.after_root),
        "original_qualification": str(original_path),
        "original_qualified": original["qualified"],
        "original_cases": original["cases_seen"],
        "original_comparisons": original["harness"]["compared"],
        "original_native_runs": original["native_runs"],
        "seed": 2204, "features": FEATURES, "cases_requested": 200,
        "generation": "wave-a/fuzz_rebinding.install(s1); one random.Random(2204); 200 consecutive s1.Gen(rng, ['mut','records','alias']).program() calls, with no other RNG use",
        "affinity": sorted(os.sched_getaffinity(0)),
        "nice": os.getpriority(os.PRIO_PROCESS, 0),
        "scratch": str(args.scratch), "native_builds": 0, "native_runs": 0,
        "cases": [], "complete": False, "reuse_justified": False, "error": None,
    }

    def save():
        report["elapsed_seconds"] = time.monotonic() - started
        report["cases_compared"] = len(report["cases"])
        report["identical_cases"] = sum(case["identical"] for case in report["cases"])
        report["differing_cases"] = [case["case"] for case in report["cases"] if not case["identical"]]
        (args.evidence / "rebinding-reuse.json").write_text(json.dumps(report, indent=2) + "\n")
        lines = [
            "Rebinding200 dictionary-fact repair reuse proof",
            "Command: " + report["command"],
            "Before source: " + BASE + " (" + str(args.root) + ")",
            "After base: " + BASE + "; repaired staged source tree: " + D_TREE,
            "After worktree: " + str(args.after_root),
            "Generator: " + report["generation"],
            "Original qualification: " + str(original_path),
            "Original: qualified200/200, 3000 comparisons, 4000 native runs, no mismatch/fact/crash/refusal.",
            "Frontend command for each source: BEFORE_OR_AFTER/mylang-core dump-ir SOURCE --facts",
            "Exact case commands, exit statuses and timings: rebinding-reuse.json",
            "Private generated sources and complete stdout/stderr: " + str(args.scratch),
            "Affinity: " + str(report["affinity"]) + "; nice: " + str(report["nice"]),
            "Compiler changes: " + str(report.get("after_compiler_changes")),
            "No guest dict/set constructs: " + str(report.get("no_guest_dict_or_set")),
            "No dictionary IR operations: " + str(report.get("no_dictionary_ir")),
            "Complete IR/facts identical: %d/%d" % (report["identical_cases"], report["cases_requested"]),
            "Complete: " + str(report["complete"]) + "; reuse justified: " + str(report["reuse_justified"]),
            "Differences: " + str(report["differing_cases"]),
            "Elapsed seconds: %.3f" % report["elapsed_seconds"],
            "Native builds/runs during proof: 0/0",
        ]
        if report["error"]:
            lines.append("Error: " + report["error"])
        if report["reuse_justified"]:
            lines.append("Wave B affected-check justification: the sole compiler-source change is dictionary transfer in facts.zig; all exact 200 guest sources contain no dict/set constructs or dictionary IR, and their complete optimized IR and printed facts are byte-identical. The completed source090 rebinding200 qualification can therefore be reused without a native fuzz replay.")
        (args.evidence / "rebinding-reuse.txt").write_text("\n".join(lines) + "\n")

    try:
        assert original["qualified"] and original["kind"] == "rebinding"
        assert original["cases_requested"] == original["cases_seen"] == 200 and original["seed"] == 2204
        assert original["harness"]["compared"] == 3000 and original["native_runs"] == 4000
        assert not (set(report["affinity"]) & EXCLUDED_CPUS) and report["nice"] >= 10
        report["before_head"] = git(args.root, "rev-parse", "HEAD").strip()
        report["after_head"] = git(args.after_root, "rev-parse", "HEAD").strip()
        assert report["before_head"] == report["after_head"] == BASE
        report["before_compiler_changes"] = compiler_changes(args.root)
        report["after_compiler_changes"] = compiler_changes(args.after_root)
        assert report["before_compiler_changes"] == []
        assert report["after_compiler_changes"] == ["src/core/facts.zig"]
        report["repair_tree_paths"] = git(args.after_root, "diff", "--name-only", BASE, D_TREE).splitlines()
        report["repair_tree_compiler_paths"] = [path for path in report["repair_tree_paths"]
                                               if path.startswith("src/core/") and path.endswith(".zig") and not path.endswith("_test.zig")]
        assert report["repair_tree_compiler_paths"] == ["src/core/facts.zig"]
        assert git(args.after_root, "diff", D_TREE, "--", "src/core/facts.zig") == ""
        report["generator_paths"] = ["experiments/new-core-s1-20261005/fuzz.py",
                                     "experiments/new-core-s0-20261005/fuzz.py",
                                     "experiments/new-core-s2-20261005/wave-a/fuzz_rebinding.py"]
        assert git(args.root, "diff", BASE, "--", *report["generator_paths"]) == ""
        (args.evidence / "rebinding-reuse-facts.diff").write_text(git(args.after_root, "diff", BASE, "--", "src/core/facts.zig"))
        report["binary_stats_before"] = [binary_stat(before), binary_stat(after)]
        s1 = load_module("rebinding_reuse_s1", args.root / report["generator_paths"][0])
        rebinding = load_module("rebinding_reuse_install", args.root / report["generator_paths"][2])
        rebinding.install(s1)
        rng = random.Random(2204)
        guest_hits = []
        for case in range(200):
            source = s1.Gen(rng, FEATURES).program()
            path = source_dir / ("mut_records_alias%d.my" % case)
            path.write_text(source)
            # These generators have no braced literals; reject any dictionary/set
            # name or braced literal rather than infer types from generator flags.
            if re.search(r"\b(?:dict|set)\b|[{}]", source):
                guest_hits.append(case)
        report["guest_dict_or_set_cases"] = guest_hits
        report["no_guest_dict_or_set"] = not guest_hits
        assert not guest_hits, "guest dictionary/set construct encountered"
        report["no_dictionary_ir"] = True
        save()
        for case in range(200):
            path = source_dir / ("mut_records_alias%d.my" % case)
            row = {"case": case, "source": str(path), "runs": []}
            dumps = []
            for label, binary in (("before", before), ("after", after)):
                command = [str(binary), "dump-ir", str(path), "--facts"]
                case_started = time.monotonic()
                done = subprocess.run(command, capture_output=True, timeout=60)
                elapsed = time.monotonic() - case_started
                out_path = output_dir / ("%03d.%s.ir" % (case, label))
                err_path = output_dir / ("%03d.%s.err" % (case, label))
                out_path.write_bytes(done.stdout)
                err_path.write_bytes(done.stderr)
                row["runs"].append({"label": label, "command": command, "status": done.returncode,
                                     "elapsed_seconds": elapsed, "stdout_bytes": len(done.stdout),
                                     "stderr_bytes": len(done.stderr), "stdout": str(out_path), "stderr": str(err_path)})
                dumps.append((done.returncode, done.stdout, done.stderr))
                if done.returncode != 0:
                    row["identical"] = False
                    report["cases"].append(row)
                    raise RuntimeError("case%d %s dump-ir failed with status%d" % (case, label, done.returncode))
                if re.search(rb"\bdict_[a-z_]+\b", done.stdout):
                    report["no_dictionary_ir"] = False
                    raise RuntimeError("dictionary IR encountered in case%d" % case)
            row["identical"] = dumps[0] == dumps[1]
            report["cases"].append(row)
            if not row["identical"]:
                diff_path = args.evidence / ("rebinding-reuse-case%03d.diff" % case)
                diff_path.write_text("".join(difflib.unified_diff(dumps[0][1].decode(errors="replace").splitlines(True), dumps[1][1].decode(errors="replace").splitlines(True), fromfile="before090", tofile="afterDictionaryRepair")))
                row["difference"] = str(diff_path)
            if (case + 1) % 25 == 0:
                save()
                print("Compared %d/200: %d identical" % (case + 1, sum(item["identical"] for item in report["cases"])), flush=True)
        report["binary_stats_after"] = [binary_stat(before), binary_stat(after)]
        assert report["binary_stats_before"] == report["binary_stats_after"], "installed compiler changed during proof"
        assert compiler_changes(args.root) == report["before_compiler_changes"]
        assert compiler_changes(args.after_root) == report["after_compiler_changes"]
        assert git(args.after_root, "diff", D_TREE, "--", "src/core/facts.zig") == ""
        report["complete"] = True
        report["reuse_justified"] = all(case["identical"] for case in report["cases"])
    except Exception as error:
        report["error"] = "%s: %s" % (type(error).__name__, error)
    save()
    print("complete=%s identical=%d/200 reuse_justified=%s error=%s" % (report["complete"], report["identical_cases"], report["reuse_justified"], report["error"]), flush=True)
    return 0 if report["reuse_justified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
