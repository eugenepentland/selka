#!/usr/bin/env python3
"""Freeze exact-source S5 answers and validate Debug/ReleaseFast/verify with leaks.

Uses the existing S1 conformance verdicts and S2 strict process-status parser.
Run the complete command through build-slot.sh and the benchmark compile lock.
Every inner command has an immutable stdout/stderr/elapsed/affinity receipt.
"""
import argparse, concurrent.futures, datetime, hashlib, importlib.util, json
import os, re, subprocess, time
from pathlib import Path

PIN_SHA = "ec4d76d2b57a0de47eda656571952dab90cc1aa3ddea822a327b945d3c464d03"
BASE = "5a6b501d672f884336f5749fd6a191daacaac09b"
MODES = {"debug": [], "release": ["--release"], "verify": ["--release", "--verify-facts"]}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--oracle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--corpus-source", type=Path, help="read-only external worktree; default compiler source")
    parser.add_argument("--corpus", default="tests/lang", help="path relative to corpus source")
    parser.add_argument("--corpus-commit", help="required exact external source commit")
    parser.add_argument("--legacy", type=Path, help="optional existing conformance reference")
    parser.add_argument("--directory", action="store_true", help="also run the complete corpus directory in all modes")
    parser.add_argument("--expected-tests", type=int, help="required unique per-file and directory test count")
    parser.add_argument("--test-arg", action="append", default=[], help="repeat as --test-arg=--FLAG for corpus budgets")
    parser.add_argument("--configured-entry", nargs=2, action="append", default=[], metavar=("ENTRY", "CASES"),
                        help="also freeze ENTRY with its CASES file; paths relative to the corpus")
    args = parser.parse_args()
    source, oracle, output = args.source.resolve(), args.oracle.resolve(), args.output.resolve()
    corpus_source = args.corpus_source.resolve() if args.corpus_source else source
    corpus = (corpus_source / args.corpus).resolve()
    corpus.relative_to(corpus_source)
    if args.corpus_source and not args.corpus_commit:
        parser.error("--corpus-commit is required with an external worktree")
    corpus_commit = args.corpus_commit or BASE
    if output.exists():
        raise SystemExit("output exists; preserve it and choose a new output")
    output.mkdir(parents=True)
    if digest(oracle) != PIN_SHA:
        raise SystemExit("immutable S5 oracle digest mismatch")
    affinity = sorted(os.sched_getaffinity(0))
    if set(affinity) & {2, 3, 10, 11}:
        raise SystemExit("must run through build-slot.sh without reserved CPUs")

    def command(label, argv, env=None):
        folder = output / "commands" / label
        folder.parent.mkdir(parents=True, exist_ok=True)
        if folder.with_suffix(".json").exists():
            raise RuntimeError("receipt exists: " + label)
        # Sampling is a tool command too, so its own elapsed time is recorded.
        sample_start = time.monotonic()
        sample = subprocess.run(["ps", "-eo", "pid,ppid,psr,etimes,args"], capture_output=True, text=True)
        sample_time = time.monotonic() - sample_start
        heavy = [line for line in sample.stdout.splitlines() if any(part in line for part in
                 ("zig build", "zig cc", "fuzz_matrix.py", "run_units.py", "bench-newcore"))]
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        before = time.monotonic()
        timeout = False
        try:
            done = subprocess.run(argv, cwd=corpus_source, capture_output=True, text=True, env=env, timeout=600)
        except subprocess.TimeoutExpired as error:
            timeout = True
            stdout = error.stdout or b""
            stderr = error.stderr or b""
            if isinstance(stdout, bytes): stdout = stdout.decode(errors="replace")
            if isinstance(stderr, bytes): stderr = stderr.decode(errors="replace")
            done = subprocess.CompletedProcess(argv, 124, stdout, stderr)
        elapsed = time.monotonic() - before
        folder.with_suffix(".stdout").write_text(done.stdout)
        folder.with_suffix(".stderr").write_text(done.stderr)
        write(folder.with_suffix(".json"), {"command": argv, "cwd": str(corpus_source),
            "started_at": started, "elapsed_seconds": elapsed, "returncode": done.returncode,
            "cpu_affinity": sorted(os.sched_getaffinity(0)), "timeout": timeout,
            "other_build_heavy_processes": heavy,
            "process_sample": {"command": ["ps", "-eo", "pid,ppid,psr,etimes,args"],
                               "elapsed_seconds": sample_time, "returncode": sample.returncode},
            "stdout_sha256": digest(folder.with_suffix(".stdout")),
            "stderr_sha256": digest(folder.with_suffix(".stderr"))})
        return done, timeout, elapsed

    for label, worktree, expected in [("compiler", source, BASE), ("corpus", corpus_source, corpus_commit)]:
        commit, _, _ = command(label + "-commit", ["git", "-C", str(worktree), "rev-parse", "HEAD"])
        clean, _, _ = command(label + "-tracked-diff", ["git", "-C", str(worktree), "diff", "--exit-code", "HEAD", "--"])
        if commit.returncode or commit.stdout.strip() != expected or clean.returncode:
            raise SystemExit(label + " must be the exact, tracked-clean committed worktree")
    sweep = load("sweep", source / "experiments/new-core-s1-20261005/conformance.py")
    checked = load("checked", source / "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    sweep.LANG = str(corpus)
    sweep.ROOT = str(source)
    originals = {str(p.relative_to(corpus_source)): digest(p) for p in sorted(corpus.rglob("*")) if p.is_file()}
    paths = sorted(corpus.rglob("*.my"))
    oldpath = args.legacy
    if oldpath is None and corpus_source == source and args.corpus == "tests/lang":
        oldpath = source / "experiments/new-core-s5-20261007/references/conformance-v1.json"
    old = json.loads(oldpath.read_text()) if oldpath else {"files": {}}
    if oldpath:
        (output / "legacy-conformance-v1.json").write_bytes(oldpath.read_bytes())
    write(output / "source-manifest.json", {"commit": corpus_commit, "files": originals,
        "manifest_sha256": hashlib.sha256(json.dumps(originals, sort_keys=True).encode()).hexdigest()})
    write(output / "identity.json", {"commit": corpus_commit, "source_worktree": str(corpus_source),
        "compiler_commit": BASE, "compiler_source_worktree": str(source), "corpus": args.corpus,
        "collector": {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__))},
        "oracle": {"path": str(oracle), "sha256": PIN_SHA}, "cpu_affinity": affinity,
        "legacy_reference": {"original_path": str(oldpath), "sha256": digest(oldpath)} if oldpath else None,
        "leak_environment": {"MYL_CORE_LEAKCHECK": "1"},
        "test_force": True, "file_workers": args.jobs, "tests_per_worker": 1,
        "modes": MODES, "test_arguments": args.test_arg, "configured_entries": args.configured_entry,
        "source_manifest_sha256": digest(output / "source-manifest.json"),
        "tools": {str(p.relative_to(source)): digest(p) for p in [
            source / "experiments/new-core-s1-20261005/conformance.py",
            source / "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py"]}})
    args.cache.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MYL_CORE_LEAKCHECK="1")
    started = time.monotonic()

    def one(path, cases=None):
        name = str(path.relative_to(corpus))[:-3]
        entries, news = {}, {}
        for mode, flags in MODES.items():
            label = mode + ("/configured/" if cases else "/") + name.replace("/", "__")
            argv = [str(oracle), "test", str(path), "--json", "--force", "--jobs", "1",
                    "--cache-dir", str(args.cache), *flags, *args.test_arg]
            if cases:
                argv.extend(["--cases", str(cases)])
            done, timeout, elapsed = command(label, argv, env)
            report = checked.checked_report(sweep.parse, None if timeout else done, mode)
            if isinstance(report, str):
                entry = {"problem": report}
            else:
                names = [test["name"] for test in report["tests"]]
                if len(set(names)) != len(names):
                    entry = {"problem": "duplicate test names in pin report"}
                else:
                    entry = {"tests": [[test["name"], test["status"],
                        (re.match(r"(R_[A-Z_]+)", test.get("reason", "")) or [""])[0]]
                        for test in report["tests"]]}
            entry.update({"source_sha256": originals[str(path.relative_to(corpus_source))],
                          "receipt": "commands/" + label + ".json", "elapsed_seconds": elapsed})
            if cases:
                entry["cases"] = {"path": str(cases.relative_to(corpus_source)), "sha256": digest(cases)}
            entries[mode], news[mode] = entry, report
        debug = news["debug"]
        compared = sweep.compare(str(path), debug, news, True)
        return name, entries, compared

    # Warm the common runtime with a test-declaring file before concurrent files.
    warm = next((p for p in paths if re.search(r"public\s+def\s+test_", p.read_text())), paths[0] if paths else None)
    paths = ([warm] + [p for p in paths if p != warm]) if warm else []
    results = [one(paths[0])] if paths else []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for position, item in enumerate(pool.map(one, paths[1:]), 2):
            results.append(item)
            if position % 25 == 0:
                print(json.dumps({"completed_files": position, "total_files": len(paths),
                                  "elapsed_seconds": time.monotonic() - started}), flush=True)
    configured_results = [one(corpus / (entry if entry.endswith(".my") else entry + ".my"), corpus / cases)
                          for entry, cases in args.configured_entry]
    configured_tables = {mode: {name: entries[mode] for name, entries, _ in configured_results} for mode in MODES}
    for mode, files in configured_tables.items():
        if files:
            write(output / ("configured-" + mode + ".json"), {"version": "frontend-current-conformance-references-v1",
                "oracle": {"path": str(oracle), "sha256": PIN_SHA}, "source_commit": corpus_commit,
                "compiler_commit": BASE, "mode": mode, "leakcheck": True, "files": files})
    tables = {mode: {name: entries[mode] for name, entries, _ in results} for mode in MODES}
    for mode, files in tables.items():
        write(output / ("current-" + mode + ".json"), {"version": "frontend-current-conformance-references-v1",
            "oracle": {"path": str(oracle), "sha256": PIN_SHA}, "source_commit": corpus_commit, "compiler_commit": BASE,
            "mode": mode, "leakcheck": True, "files": files})
    current = {name: test for file in tables["debug"].values() for test in file.get("tests", []) for name in [test[0]]}
    legacy = {name: test for file in old["files"].values() for test in file.get("tests", []) for name in [test[0]]}
    changed = [{"name": name, "legacy": legacy[name], "current": current[name]}
               for name in sorted(set(current) & set(legacy)) if current[name] != legacy[name]]
    text, totals = sweep.table([item[2] for item in results], list(MODES), True)
    (output / "comparison.txt").write_text(text + "\n" + "\n".join(
        "PROBLEM " + result["file"] + ": " + problem for _, _, result in results for problem in result["problems"]) + "\n")
    directory = {}
    if args.directory:
        for mode, flags in MODES.items():
            argv = [str(oracle), "test", str(corpus), "--json", "--force", "--jobs", str(args.jobs),
                    "--cache-dir", str(args.cache), *flags, *args.test_arg]
            done, timeout, elapsed = command("directory-" + mode, argv, env)
            report = checked.checked_report(sweep.parse, None if timeout else done, "directory " + mode)
            if isinstance(report, str):
                directory[mode] = {"problem": report, "elapsed_seconds": elapsed}
            else:
                tests = report["tests"]
                directory[mode] = {"tests": [[test["name"], test["status"],
                    (re.match(r"(R_[A-Z_]+)", test.get("reason", "")) or [""])[0]] for test in tests],
                    "elapsed_seconds": elapsed, "reported_counts": {key: value for key, value in report.items()
                    if key not in ("tests", "sources")}, "receipt": "commands/directory-" + mode + ".json"}
                expected = {name: tuple(test[1:]) for name, test in current.items()}
                got = {test[0]: tuple(test[1:]) for test in directory[mode]["tests"]}
                directory[mode]["agrees_with_per_file"] = expected == got and len(got) == len(tests)
        write(output / "directory.json", directory)
    current_after = {str(p.relative_to(corpus_source)): digest(p) for p in sorted(corpus.rglob("*")) if p.is_file()}
    summary = {"elapsed_seconds": time.monotonic() - started, "current_files": len(paths),
        "current_unique_tests": len(current), "legacy_files": len(old["files"]), "legacy_unique_tests": len(legacy),
        "legacy_only_tests": sorted(set(legacy) - set(current)), "current_only_tests": sorted(set(current) - set(legacy)),
        "legacy_only_files": sorted(set(old["files"]) - set(tables["debug"])), "changed_legacy_answers": changed,
        "modes": {mode: {"files": len(files), "tests": sum(len(x.get("tests", [])) for x in files.values()),
                         "problems": {name: x["problem"] for name, x in files.items() if "problem" in x},
                         "statuses": {status: sum(t[1] == status for x in files.values() for t in x.get("tests", []))
                                      for status in sorted({t[1] for x in files.values() for t in x.get("tests", [])})}}
                  for mode, files in tables.items()}, "totals": totals,
        "sources_unchanged": originals == current_after,
        "configured": {mode: {"files": len(files), "tests": sum(len(x.get("tests", [])) for x in files.values()),
            "problems": {name: x["problem"] for name, x in files.items() if "problem" in x},
            "failed": sum(t[1] != "passed" for x in files.values() for t in x.get("tests", []))}
            for mode, files in configured_tables.items()},
        "configured_comparison_problems": [{"file": result["file"], "problems": result["problems"]}
            for _, _, result in configured_results if result["problems"]],
        "expected_unique_tests": args.expected_tests,
        "expected_count_matches": args.expected_tests is None or len(current) == args.expected_tests,
        "directory": {mode: {"tests": len(entry.get("tests", [])),
            "problem": entry.get("problem"), "agrees_with_per_file": entry.get("agrees_with_per_file", False),
            "counts": entry.get("reported_counts", {}), "elapsed_seconds": entry["elapsed_seconds"]}
            for mode, entry in directory.items()},
        "comparison_problems": [{"file": result["file"], "problems": result["problems"]}
                                for _, _, result in results if result["problems"]]}
    write(output / "coverage.json", summary)
    print(json.dumps(summary, sort_keys=True), flush=True)
    return int(not summary["sources_unchanged"] or not summary["expected_count_matches"] or
               any(not entry["agrees_with_per_file"] for entry in summary["directory"].values()) or
               bool(summary["comparison_problems"]) or bool(summary["configured_comparison_problems"]) or
               any(entry["failed"] or entry["problems"] for entry in summary["configured"].values()) or
               any(entry["statuses"].get("failed", 0) or entry["statuses"].get("unsupported", 0)
                   for entry in summary["modes"].values()) or
               any(totals[mode]["mismatch"] or totals[mode]["unsupported"] for mode in MODES))

if __name__ == "__main__":
    raise SystemExit(main())
