#!/usr/bin/env python3
"""Compare exact frozen per-file, directory and configured tests without oracle runs.

Run with an outer bench-compile.lock, then scripts/build-slot.sh. Examples:
  --source CANDIDATE_WORKTREE --compiler BINARY --against FROZEN_REF_DIR
  --output FRESH_RESULTS --cache OWNED_CACHE [--corpus-source MIGRATED_WORKTREE]

Only compiler/cache arguments change in the saved commands. Relocating a corpus
requires --normalize-source-paths: recorded changes are confined to JSON sources
and at fields plus diagnostic source filenames; line/column/verdict bytes remain.
All modes, force, leak checking, jobs, timeouts and budgets come from the references.
"""
import argparse
import concurrent.futures
import datetime
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import types

ORACLE_SHA = "ec4d76d2b57a0de47eda656571952dab90cc1aa3ddea822a327b945d3c464d03"
MODES = ("debug", "release", "verify")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def production_manifest(source):
    paths = [path for name in ("src", "std", "stdlib")
             for path in (source / name).rglob("*") if path.is_file()]
    paths += [source / name for name in ("build.zig", "build.zig.zon")
              if (source / name).is_file()]
    return {str(path.relative_to(source)): digest(path) for path in sorted(paths)}


def load(name, path):
    result = types.ModuleType(name)
    result.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), "exec"), result.__dict__)
    return result


def triples(report):
    return [[test["name"], test["status"],
             (re.match(r"(R_[A-Z_]+)", test.get("reason", "")) or [""])[0]]
            for test in report["tests"]]


def timed_git(source, arguments, output, label):
    command = ["git", "-C", str(source), *arguments]
    sample_start = time.monotonic()
    sample = subprocess.run(["ps", "-eo", "pid,ppid,psr,etimes,args"], capture_output=True, text=True)
    sample_seconds = time.monotonic() - sample_start
    started = time.monotonic()
    done = subprocess.run(command, capture_output=True, timeout=600)
    elapsed = time.monotonic() - started
    path = output / "commands" / label
    path.parent.mkdir(parents=True, exist_ok=True)
    path.with_suffix(".stdout").write_bytes(done.stdout)
    path.with_suffix(".stderr").write_bytes(done.stderr)
    write(path.with_suffix(".json"), {"command": command, "returncode": done.returncode,
        "elapsed_seconds": elapsed, "cpu_affinity": sorted(os.sched_getaffinity(0)),
        "stdout_sha256": digest(path.with_suffix(".stdout")),
        "stderr_sha256": digest(path.with_suffix(".stderr")),
        "other_build_heavy_processes": [line for line in sample.stdout.splitlines() if any(
            item in line for item in ("zig build", "zig cc", "fuzz_matrix.py", "bench-newcore"))],
        "process_sample": {"command": ["ps", "-eo", "pid,ppid,psr,etimes,args"],
            "elapsed_seconds": sample_seconds, "returncode": sample.returncode}})
    assert done.returncode == 0, "source identity command failed"
    return done.stdout.decode()


def normalize_sources(report, stdout, stderr, root, manifest, enabled):
    """Map only known source fields/diagnostic paths, with exact byte receipts."""
    if not enabled or not isinstance(report, dict):
        return report, stdout, stderr, []
    result = copy.deepcopy(report)
    mappings = {str(root / name): "<source>/" + name for name in manifest if name.endswith(".my")}
    changes, substitutions = [], []
    string_token = rb'"(?:[^"\\]|\\.)*"'

    def field(value, location, begin, end):
        path = value.split(":", 1)[0]
        if path not in mappings:
            return value
        replacement = mappings[path] + value[len(path):]
        substitutions.append((begin, end, json.dumps(replacement, ensure_ascii=False).encode()))
        changes.append({"stream": "stdout", "field": location, "original": value,
            "replacement": replacement, "occurrences": 1})
        return replacement

    if "sources" in result:
        pattern = rb'(?<!\\)"sources"\s*:\s*\[(?P<items>\s*(?:' + string_token + rb'\s*(?:,\s*)?)*)\]'
        matches = list(re.finditer(pattern, stdout))
        assert len(matches) == 1, "ambiguous sources field in raw report"
        match = matches[0]
        tokens = list(re.finditer(string_token, match.group("items")))
        assert [json.loads(token.group()) for token in tokens] == report["sources"]
        result["sources"] = [field(value, "sources[" + str(index) + "]",
            match.start("items") + token.start(), match.start("items") + token.end())
            for index, (value, token) in enumerate(zip(report["sources"], tokens))]
    at_fields = [(index, test["at"]) for index, test in enumerate(report["tests"])
                 if isinstance(test.get("at"), str)]
    at_matches = list(re.finditer(rb'(?<!\\)"at"\s*:\s*(?P<value>' + string_token + rb')', stdout))
    assert len(at_fields) == len(at_matches), "ambiguous at field in raw report"
    for (index, value), match in zip(at_fields, at_matches):
        assert json.loads(match.group("value")) == value
        result["tests"][index]["at"] = field(value, "tests[" + str(index) + "].at",
            match.start("value"), match.end("value"))
    for begin, end, replacement in sorted(substitutions, reverse=True):
        stdout = stdout[:begin] + replacement + stdout[end:]
    for original, replacement in mappings.items():
        # Match diagnostic locations only; preserve line/column, code and text.
        pattern = re.compile(re.escape(original.encode()) + rb"(?=:[0-9]+(?::[0-9]+)?(?=[:)\s]|$))")
        stderr, count = pattern.subn(replacement.encode(), stderr)
        if count:
            changes.append({"stream": "stderr", "original": original,
                "replacement": replacement, "occurrences": count,
                "condition": "known .my filename immediately followed by a diagnostic line/column"})
    return result, stdout, stderr, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--against", "--reference", dest="reference", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True, help="candidate compiler source worktree")
    parser.add_argument("--corpus-source", type=Path, help="candidate corpus worktree; default frozen external source or --source for internal tests")
    parser.add_argument("--compiler-sha256", help="optional independently recorded candidate binary hash")
    parser.add_argument("--source-commit", help="optional independently recorded candidate source HEAD")
    parser.add_argument("--against-identity-sha256", help="optional independently recorded frozen identity hash")
    parser.add_argument("--normalize-source-paths", action="store_true", help="audit exact source-path relocation; preserve every other field/byte")
    parser.add_argument("--settings-context", type=Path, help="audited original keyed environment and immutable compiler/tool identities for configured provider fingerprints")
    parser.add_argument("--settings-hasher", type=Path, help="independently built frontend_settings_hash.zig witness; required with --settings-context")
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--jobs", type=int, help="file workers; default frozen collector count")
    parser.add_argument("--expected-tests", type=int, help="optional frozen unique test count assertion")
    args = parser.parse_args()
    reference, compiler, output, cache = (path.resolve() for path in
        (args.reference, args.compiler, args.output, args.cache))
    assert not output.exists(), "output must be fresh"
    compiler_sha = digest(compiler)
    if args.compiler_sha256:
        assert compiler_sha == args.compiler_sha256, "candidate compiler hash mismatch"
    assert not set(os.sched_getaffinity(0)) & {2, 3, 10, 11}, "reserved CPU"
    output.mkdir(parents=True)
    cache.mkdir(parents=True, exist_ok=True)
    if args.against_identity_sha256:
        assert digest(reference / "identity.json") == args.against_identity_sha256, "frozen identity hash mismatch"
    identity = json.loads((reference / "identity.json").read_text())
    assert identity["oracle"]["sha256"] == ORACLE_SHA, "reference does not name the immutable S5 pin"
    assert identity["test_force"] and identity["leak_environment"] == {"MYL_CORE_LEAKCHECK": "1"}
    assert identity["modes"] == {"debug": [], "release": ["--release"], "verify": ["--release", "--verify-facts"]}
    reference_source = Path(identity["source_worktree"])
    frozen_compiler_source = Path(identity["compiler_source_worktree"])
    compiler_source = args.source.resolve()
    corpus_source = args.corpus_source.resolve() if args.corpus_source else (
        compiler_source if reference_source == frozen_compiler_source else reference_source)
    corpus = corpus_source / identity["corpus"]
    if corpus_source != reference_source:
        assert args.normalize_source_paths, "relocated corpus requires audited source path normalization"
    source_commit = timed_git(compiler_source, ["rev-parse", "HEAD"], output, "source-commit").strip()
    if args.source_commit:
        assert source_commit == args.source_commit, "candidate source commit mismatch"
    timed_git(compiler_source, ["ls-files", "-z", "--", "src", "std", "stdlib", "build.zig", "build.zig.zon"], output, "source-files")
    compiler_sources = production_manifest(compiler_source)
    corpus_commit = timed_git(corpus_source, ["rev-parse", "HEAD"], output, "corpus-commit").strip()
    reference_files = {str(path.relative_to(reference)): digest(path) for path in reference.rglob("*") if path.is_file()}
    assert digest(Path(identity["oracle"]["path"])) == identity["oracle"]["sha256"]
    for name, sha in identity["tools"].items():
        assert digest(frozen_compiler_source / name) == sha, "frozen parser hash changed"
    sweep = load("sweep", frozen_compiler_source / "experiments/new-core-s1-20261005/conformance.py")
    checked = load("checked", frozen_compiler_source / "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    manifest = json.loads((reference / "source-manifest.json").read_text())
    assert digest(reference / "source-manifest.json") == identity["source_manifest_sha256"]
    originals = manifest["files"]
    assert all(digest(reference_source / path) == sha for path, sha in originals.items()), "frozen sources changed"
    candidate_originals = {str(path.relative_to(corpus_source)): digest(path) for path in corpus.rglob("*") if path.is_file()}
    write(output / "source-manifest.json", {"commit": corpus_commit, "files": candidate_originals})
    write(output / "reference-manifest.json", {"reference": str(reference), "files": reference_files})
    write(output / "compiler-source-manifest.json", {"source": str(compiler_source), "commit": source_commit, "files": compiler_sources})
    categories = {}
    for category in ("current", "configured"):
        for mode in MODES:
            path = reference / (category + "-" + mode + ".json")
            if path.exists():
                categories[category, mode] = json.loads(path.read_text())
                assert categories[category, mode]["mode"] == mode
                assert categories[category, mode]["oracle"]["sha256"] == ORACLE_SHA
                assert categories[category, mode]["leakcheck"] is True
    for category in ("current", "configured"):
        if (category, "debug") in categories:
            names = set(categories[category, "debug"]["files"])
            assert all(set(categories[category, mode]["files"]) == names for mode in MODES), "mode membership differs"
    paths = sorted(categories["current", "debug"]["files"])
    actual_paths = sorted(str(path.relative_to(corpus))[:-3] for path in corpus.rglob("*.my"))
    assert paths == actual_paths, "source membership changed"
    frozen_tests = {test[0] for entry in categories["current", "debug"]["files"].values() for test in entry.get("tests", [])}
    expected_tests = len(frozen_tests)
    if args.expected_tests is not None:
        assert args.expected_tests == expected_tests, "provided count differs from frozen references"
    jobs = args.jobs or identity["file_workers"]
    comparisons = {}
    env = dict(os.environ, MYL_CORE_LEAKCHECK="1", PYTHONDONTWRITEBYTECODE="1")
    settings_context, settings_helper = None, None
    settings_context_sha = digest(args.settings_context) if args.settings_context else None
    assert bool(args.settings_context) == bool(args.settings_hasher), "settings context and witness must be paired"
    if args.settings_context:
        settings_helper = load("settings_helper", Path(__file__).with_name("frontend_compare_settings.py"))
        settings_context = json.loads(args.settings_context.read_text())
        settings_helper.validate_context(settings_context, Path(identity["oracle"]["path"]), compiler,
            frozen_compiler_source, compiler_source)
        assert digest(args.settings_hasher) == settings_context["hasher_sha256"], "settings witness hash mismatch"
        env = settings_helper.launch_environment(settings_context, env)
        write(output / "settings-context.json", {"path": str(args.settings_context.resolve()),
            "sha256": digest(args.settings_context), "context": settings_context})
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
            "timeout": timeout, "timeout_seconds": 600, "cpu_affinity": sorted(os.sched_getaffinity(0)),
            "leak_environment": {"MYL_CORE_LEAKCHECK": "1"},
            "keyed_environment": settings_helper.keyed_environment(env) if settings_helper else None,
            "expected_cli_added_keyed_environment": {"MYLANG_HOST_LIMIT_CHECKPOINT": settings_context["environment"]["MYLANG_HOST_LIMIT_CHECKPOINT"]} if settings_context else None,
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
        mode = label.split("/", 1)[0].removeprefix("directory-")
        assert ("--release" in argv) == (mode != "debug")
        assert ("--verify-facts" in argv) == (mode == "verify")
        assert "--no-facts" not in argv
        argv[0] = str(compiler)
        cache_index = argv.index("--cache-dir") + 1
        argv[cache_index] = str(cache)
        for index, value in enumerate(argv[2:], 2):
            if value.startswith(str(reference_source) + "/"):
                argv[index] = str(corpus_source) + value[len(str(reference_source)):]
        expected_out = receipt_path.with_suffix(".stdout")
        expected_err = receipt_path.with_suffix(".stderr")
        assert digest(expected_out) == receipt["stdout_sha256"]
        assert digest(expected_err) == receipt["stderr_sha256"]
        old = subprocess.CompletedProcess(receipt["command"], receipt["returncode"],
            expected_out.read_text(), expected_err.read_text())
        expected_report = checked.checked_report(sweep.parse, None if receipt["timeout"] else old, label)
        if not isinstance(expected_report, str):
            assert triples(expected_report) == saved["tests"], "frozen table/raw verdict mismatch"
        else:
            assert expected_report == saved.get("problem"), "frozen table/raw problem mismatch"
        cwd = str(corpus_source) if receipt["cwd"] == str(reference_source) else receipt["cwd"]
        done, timeout, elapsed, folder = command(label, argv, cwd)
        actual = subprocess.CompletedProcess(argv, done.returncode,
            done.stdout.decode(errors="replace"), done.stderr.decode(errors="replace"))
        report = checked.checked_report(sweep.parse, None if timeout else actual, label)
        old_report, old_stdout, old_stderr, old_changes = normalize_sources(
            expected_report, expected_out.read_bytes(), expected_err.read_bytes(),
            reference_source, originals, args.normalize_source_paths)
        new_report, new_stdout, new_stderr, new_changes = normalize_sources(
            report, done.stdout, done.stderr, corpus_source, candidate_originals, args.normalize_source_paths)
        if settings_context and "/configured/" in label:
            old_fields = settings_helper.fields(receipt["command"], settings_context,
                settings_context["reference"]["compiler_identity"])
            new_fields = settings_helper.fields(argv, settings_context,
                settings_context["candidate"]["compiler_identity"])
            assert old_fields[:1] + old_fields[2:] == new_fields[:1] + new_fields[2:], "settings inputs differ beyond compiler identity"
            canonical = old_fields.copy()
            canonical[1] = b"<compiler-identity>"
            proof_path = output / "settings" / (label + ".preimages.json")
            write(proof_path, [settings_helper.preimage(fields).hex() for fields in (old_fields, new_fields, canonical)])
            hashed, hash_timeout, _, hash_folder = command("settings/" + label,
                [str(args.settings_hasher.resolve()), str(proof_path)], str(compiler_source))
            assert hashed.returncode == 0 and not hash_timeout, "settings witness failed"
            hashes = hashed.stdout.decode().splitlines()
            assert len(hashes) == 3 and all(re.fullmatch("[0-9a-f]{64}", value) for value in hashes)
            replacement = hashes[2]
            old_report, old_stdout, changes = settings_helper.normalize(old_report, old_stdout, hashes[0], replacement)
            old_changes += changes
            new_report, new_stdout, changes = settings_helper.normalize(new_report, new_stdout, hashes[1], replacement)
            new_changes += changes
            write(output / "settings" / (label + ".proof.json"), {
                "reference_fields": [field.hex() for field in old_fields],
                "candidate_fields": [field.hex() for field in new_fields],
                "all_other_inputs_byte_equal": True, "reference_fingerprint": hashes[0],
                "candidate_fingerprint": hashes[1], "canonical_fingerprint": replacement,
                "witness_receipt": str(hash_folder.with_suffix(".json").relative_to(output))})
        problems = []
        if done.returncode != receipt["returncode"] or timeout != receipt["timeout"]:
            problems.append("process status or timeout differs")
        if new_report != old_report:
            problems.append("complete parsed JSON report differs")
        if new_stdout != old_stdout:
            problems.append("stdout bytes differ")
        if new_stderr != old_stderr:
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
            "argv_changes": [{"index": index, "reference": old_arg, "candidate": new_arg}
                for index, (old_arg, new_arg) in enumerate(zip(receipt["command"], argv)) if old_arg != new_arg],
            "cwd_change": {"reference": receipt["cwd"], "candidate": cwd},
            "complete_report_identical": new_report == old_report,
            "normalizations": {"reference": old_changes, "candidate": new_changes},
            "stdout_normalized_identical": new_stdout == old_stdout,
            "stderr_normalized_identical": new_stderr == old_stderr,
            "stdout_identical": done.stdout == expected_out.read_bytes(),
            "stderr_identical": done.stderr == expected_err.read_bytes()}
        return entry

    def one(name, category="current"):
        result = {}
        for mode in MODES:
            saved = categories[category, mode]["files"][name]
            assert digest(reference_source / identity["corpus"] / (name + ".my")) == saved["source_sha256"]
            label = mode + ("/configured/" if category == "configured" else "/") + name.replace("/", "__")
            entry = compare(label, saved)
            entry["source_sha256"] = digest(corpus / (name + ".my"))
            entry["reference_source_sha256"] = saved["source_sha256"]
            if "cases" in saved:
                assert digest(reference_source / saved["cases"]["path"]) == saved["cases"]["sha256"]
                entry["cases"] = {"path": saved["cases"]["path"], "sha256": digest(corpus_source / saved["cases"]["path"])}
            result[mode] = entry
        return name, result

    # Match the frozen collector's runtime warm-up before file concurrency.
    warm = next((name for name in paths if re.search(r"public\s+def\s+test_", (corpus / (name + ".my")).read_text())), paths[0])
    results = [one(warm)]
    remaining = [name for name in paths if name != warm]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as workers:
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
                "oracle": {"path": str(compiler), "sha256": compiler_sha},
                "source_commit": corpus_commit, "compiler_commit": source_commit,
                "mode": mode, "leakcheck": True, "files": files})
            tests = [test for entry in files.values() for test in entry.get("tests", [])]
            totals[category + "-" + mode] = {"files": len(files), "tests": len(tests),
                "unique_tests": len({test[0] for test in tests}),
                "failed": sum(test[1] != "passed" for test in tests)}
            if category == "current":
                assert len(tests) == expected_tests == totals[category + "-" + mode]["unique_tests"]
    directory = {}
    saved_directory = json.loads((reference / "directory.json").read_text())
    for mode in MODES:
        directory[mode] = compare("directory-" + mode, saved_directory[mode])
        assert len(directory[mode].get("tests", [])) == expected_tests
    write(output / "directory.json", directory)
    write(output / "comparisons.json", comparisons)
    new_identity = {**identity, "commit": corpus_commit, "file_workers": jobs, "command_timeout_seconds": 600, "oracle": {"path": str(compiler), "sha256": compiler_sha},
        "compiler_commit": source_commit, "compiler_source_worktree": str(compiler_source),
        "source_worktree": str(corpus_source),
        "reference": str(reference),
        "reference_identity_sha256": digest(reference / "identity.json"),
        "source_manifest_sha256": digest(output / "source-manifest.json"),
        "collector": {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__))}}
    write(output / "identity.json", new_identity)
    summary = {"elapsed_seconds": time.monotonic() - started, "totals": totals,
        "directory_counts": {mode: len(entry.get("tests", [])) for mode, entry in directory.items()},
        "commands": len(comparisons),
        "mismatches": {name: value["problems"] for name, value in comparisons.items() if value["problems"]},
        "source_manifest_unchanged": candidate_originals == {str(path.relative_to(corpus_source)): digest(path) for path in corpus.rglob("*") if path.is_file()},
        "reference_sources_unchanged": all(digest(reference_source / path) == sha for path, sha in originals.items()),
        "reference_files_unchanged": reference_files == {str(path.relative_to(reference)): digest(path) for path in reference.rglob("*") if path.is_file()},
        "compiler_sources_unchanged": compiler_sources == production_manifest(compiler_source),
        "compiler_unchanged": digest(compiler) == compiler_sha,
        "settings_context_unchanged": not settings_context or digest(args.settings_context) == settings_context_sha,
        "settings_witness_unchanged": not settings_context or digest(args.settings_hasher) == settings_context["hasher_sha256"]}
    write(output / "summary.json", summary)
    print(json.dumps(summary, sort_keys=True), flush=True)
    return int(bool(summary["mismatches"]) or not summary["source_manifest_unchanged"] or not summary["compiler_unchanged"] or not summary["reference_sources_unchanged"] or not summary["reference_files_unchanged"] or not summary["compiler_sources_unchanged"] or not summary["settings_context_unchanged"] or not summary["settings_witness_unchanged"])


if __name__ == "__main__":
    raise SystemExit(main())
