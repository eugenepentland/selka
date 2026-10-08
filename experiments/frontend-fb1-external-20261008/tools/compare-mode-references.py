#!/usr/bin/env python3
"""Run the exact frozen external test commands with FB1; never rerun the oracle."""
import argparse
import concurrent.futures
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time

COMPILER_SHA = "5ddab7ce39d576615f55676886252e4dbfff863d0d253cc003886a769c7b1a55"
SOURCE_COMMIT = "061f46aba144c00bf2094fcdada9a2c682696105"
MODES = ("debug", "release", "verify")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def triples(report):
    return [[test["name"], test["status"],
             (re.match(r"(R_[A-Z_]+)", test.get("reason", "")) or [""])[0]]
            for test in report["tests"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--expected-tests", type=int, required=True)
    args = parser.parse_args()
    reference, compiler, output, cache = (path.resolve() for path in
        (args.reference, args.compiler, args.output, args.cache))
    assert not output.exists(), "output must be fresh"
    assert digest(compiler) == COMPILER_SHA, "immutable compiler hash mismatch"
    assert not set(os.sched_getaffinity(0)) & {2, 3, 10, 11}, "reserved CPU"
    output.mkdir(parents=True)
    cache.mkdir(parents=True, exist_ok=True)
    identity = json.loads((reference / "identity.json").read_text())
    corpus_source = Path(identity["source_worktree"])
    corpus = corpus_source / identity["corpus"]
    compiler_source = Path(identity["compiler_source_worktree"])
    for name, sha in identity["tools"].items():
        assert digest(compiler_source / name) == sha, "frozen parser hash changed"
    sweep = load("sweep", compiler_source / "experiments/new-core-s1-20261005/conformance.py")
    checked = load("checked", compiler_source / "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    manifest = json.loads((reference / "source-manifest.json").read_text())
    assert digest(reference / "source-manifest.json") == identity["source_manifest_sha256"]
    originals = manifest["files"]
    assert all(digest(corpus_source / path) == sha for path, sha in originals.items())
    (output / "source-manifest.json").write_bytes((reference / "source-manifest.json").read_bytes())
    categories = {}
    for category in ("current", "configured"):
        for mode in MODES:
            path = reference / (category + "-" + mode + ".json")
            if path.exists():
                categories[category, mode] = json.loads(path.read_text())
    paths = sorted(categories["current", "debug"]["files"])
    actual_paths = sorted(str(path.relative_to(corpus))[:-3] for path in corpus.rglob("*.my"))
    assert paths == actual_paths, "source membership changed"
    comparisons = {}
    env = dict(os.environ, MYL_CORE_LEAKCHECK="1", PYTHONDONTWRITEBYTECODE="1")
    started = time.monotonic()

    def command(label, argv, cwd):
        folder = output / "commands" / label
        folder.parent.mkdir(parents=True, exist_ok=True)
        assert not folder.with_suffix(".json").exists(), "receipt exists"
        sample_started = time.monotonic()
        sample = subprocess.run(["ps", "-eo", "pid,ppid,psr,etimes,args"], capture_output=True, text=True)
        sample_elapsed = time.monotonic() - sample_started
        heavy = [line for line in sample.stdout.splitlines() if any(part in line for part in
            ("zig build", "zig cc", "fuzz_matrix.py", "run_units.py", "bench-newcore"))]
        before = time.monotonic()
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        timeout = False
        try:
            done = subprocess.run(argv, cwd=cwd, capture_output=True, env=env, timeout=600)
        except subprocess.TimeoutExpired as error:
            timeout = True
            done = subprocess.CompletedProcess(argv, 124, error.stdout or b"", error.stderr or b"")
        elapsed = time.monotonic() - before
        folder.with_suffix(".stdout").write_bytes(done.stdout)
        folder.with_suffix(".stderr").write_bytes(done.stderr)
        write(folder.with_suffix(".json"), {
            "command": argv, "cwd": cwd, "started_at": timestamp,
            "elapsed_seconds": elapsed, "returncode": done.returncode,
            "timeout": timeout, "cpu_affinity": sorted(os.sched_getaffinity(0)),
            "leak_environment": {"MYL_CORE_LEAKCHECK": "1"},
            "other_build_heavy_processes": heavy,
            "process_sample": {"command": ["ps", "-eo", "pid,ppid,psr,etimes,args"],
                "elapsed_seconds": sample_elapsed, "returncode": sample.returncode},
            "stdout_sha256": digest(folder.with_suffix(".stdout")),
            "stderr_sha256": digest(folder.with_suffix(".stderr"))})
        return done, timeout, elapsed, folder

    def compare(label, saved):
        receipt_path = reference / saved["receipt"]
        receipt = json.loads(receipt_path.read_text())
        argv = receipt["command"].copy()
        assert argv[0] == identity["oracle"]["path"]
        assert argv[1] == "test" and "--force" in argv and "--json" in argv
        argv[0] = str(compiler)
        cache_index = argv.index("--cache-dir") + 1
        argv[cache_index] = str(cache)
        done, timeout, elapsed, folder = command(label, argv, receipt["cwd"])
        expected_out = receipt_path.with_suffix(".stdout")
        expected_err = receipt_path.with_suffix(".stderr")
        assert digest(expected_out) == receipt["stdout_sha256"]
        assert digest(expected_err) == receipt["stderr_sha256"]
        old = subprocess.CompletedProcess(receipt["command"], receipt["returncode"],
            expected_out.read_text(), expected_err.read_text())
        actual = subprocess.CompletedProcess(argv, done.returncode,
            done.stdout.decode(errors="replace"), done.stderr.decode(errors="replace"))
        expected_report = checked.checked_report(sweep.parse, None if receipt["timeout"] else old, label)
        report = checked.checked_report(sweep.parse, None if timeout else actual, label)
        problems = []
        if done.returncode != receipt["returncode"] or timeout != receipt["timeout"]:
            problems.append("process status or timeout differs")
        if report != expected_report:
            problems.append("complete parsed JSON report differs")
        if done.stdout != expected_out.read_bytes():
            problems.append("stdout bytes differ")
        if done.stderr != expected_err.read_bytes():
            problems.append("stderr bytes differ")
        if isinstance(report, str):
            problems.append("invalid report: " + report)
            entry = {"problem": report}
        else:
            entry = {"tests": triples(report)}
            if any(test[1] != "passed" for test in entry["tests"]):
                problems.append("nonpassing test")
            if triples(report) != saved["tests"]:
                problems.append("frozen triples differ")
            if any(report[key] != 0 for key in ("failed", "skipped", "cached", "unsupported")):
                problems.append("nonzero failed/skipped/cached/unsupported count")
        entry.update({"receipt": str(folder.with_suffix(".json").relative_to(output)),
            "elapsed_seconds": elapsed})
        comparisons[label] = {"reference_receipt": str(receipt_path),
            "reference_receipt_sha256": digest(receipt_path), "problems": problems,
            "complete_report_identical": report == expected_report,
            "stdout_identical": done.stdout == expected_out.read_bytes(),
            "stderr_identical": done.stderr == expected_err.read_bytes()}
        return entry

    def one(name, category="current"):
        result = {}
        for mode in MODES:
            saved = categories[category, mode]["files"][name]
            assert digest(corpus / (name + ".my")) == saved["source_sha256"]
            label = mode + ("/configured/" if category == "configured" else "/") + name.replace("/", "__")
            entry = compare(label, saved)
            entry["source_sha256"] = saved["source_sha256"]
            if "cases" in saved:
                assert digest(corpus_source / saved["cases"]["path"]) == saved["cases"]["sha256"]
                entry["cases"] = saved["cases"]
            result[mode] = entry
        return name, result

    # Match the frozen collector's runtime warm-up before file concurrency.
    warm = next((name for name in paths if re.search(r"public\s+def\s+test_", (corpus / (name + ".my")).read_text())), paths[0])
    results = [one(warm)]
    remaining = [name for name in paths if name != warm]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as workers:
        for position, item in enumerate(workers.map(one, remaining), 2):
            results.append(item)
            if position % 25 == 0:
                print(json.dumps({"completed_files": position, "total_files": len(paths),
                    "elapsed_seconds": time.monotonic() - started}), flush=True)
    configured = [one(name, "configured") for name in categories.get(("configured", "debug"), {}).get("files", {})]
    totals = {}
    for category, groups in (("current", results), ("configured", configured)):
        for mode in MODES:
            files = {name: entries[mode] for name, entries in groups}
            if not files:
                continue
            write(output / (category + "-" + mode + ".json"), {
                "version": "frontend-current-conformance-references-v1",
                "oracle": {"path": str(compiler), "sha256": COMPILER_SHA},
                "source_commit": identity["commit"], "compiler_commit": SOURCE_COMMIT,
                "mode": mode, "leakcheck": True, "files": files})
            tests = [test for entry in files.values() for test in entry.get("tests", [])]
            totals[category + "-" + mode] = {"files": len(files), "tests": len(tests),
                "unique_tests": len({test[0] for test in tests}),
                "failed": sum(test[1] != "passed" for test in tests)}
            if category == "current":
                assert len(tests) == args.expected_tests == totals[category + "-" + mode]["unique_tests"]
    directory = {}
    saved_directory = json.loads((reference / "directory.json").read_text())
    for mode in MODES:
        directory[mode] = compare("directory-" + mode, saved_directory[mode])
        assert len(directory[mode].get("tests", [])) == args.expected_tests
    write(output / "directory.json", directory)
    write(output / "comparisons.json", comparisons)
    new_identity = {**identity, "oracle": {"path": str(compiler), "sha256": COMPILER_SHA},
        "compiler_commit": SOURCE_COMMIT, "compiler_source_worktree": str(compiler.parents[2]),
        "reference": str(reference),
        "reference_identity_sha256": digest(reference / "identity.json"),
        "source_manifest_sha256": digest(output / "source-manifest.json"),
        "collector": {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__))}}
    write(output / "identity.json", new_identity)
    summary = {"elapsed_seconds": time.monotonic() - started, "totals": totals,
        "directory_counts": {mode: len(entry.get("tests", [])) for mode, entry in directory.items()},
        "commands": len(comparisons),
        "mismatches": {name: value["problems"] for name, value in comparisons.items() if value["problems"]},
        "source_manifest_unchanged": all(digest(corpus_source / path) == sha for path, sha in originals.items()),
        "compiler_unchanged": digest(compiler) == COMPILER_SHA}
    write(output / "summary.json", summary)
    print(json.dumps(summary, sort_keys=True), flush=True)
    return int(bool(summary["mismatches"]) or not summary["source_manifest_unchanged"] or not summary["compiler_unchanged"])


if __name__ == "__main__":
    raise SystemExit(main())
