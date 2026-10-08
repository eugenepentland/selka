#!/usr/bin/env python3
"""Verify frozen oracle source/output hashes and raw-report/triple correspondence."""
import argparse, collections, hashlib, importlib.util, json, re, subprocess
from pathlib import Path

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def triples(report):
    return [[t["name"], t["status"], (re.match(r"(R_[A-Z_]+)", t.get("reason", "")) or [""])[0]]
            for t in report["tests"]]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("directory", type=Path)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    root = args.directory.resolve()
    if args.output.exists():
        p.error("output exists; preserve it and choose a new path")
    identity = json.loads((root / "identity.json").read_text())
    source = Path(identity["source_worktree"])
    compiler_source = Path(identity.get("compiler_source_worktree", str(source)))
    corpus = identity.get("corpus", "tests/lang")
    sweep = load("sweep", compiler_source / "experiments/new-core-s1-20261005/conformance.py")
    checked = load("checked", compiler_source / "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    assert digest(Path(identity["oracle"]["path"])) == identity["oracle"]["sha256"]
    manifest = json.loads((root / "source-manifest.json").read_text())
    assert digest(root / "source-manifest.json") == identity["source_manifest_sha256"]
    for path, sha in manifest["files"].items():
        assert digest(source / path) == sha, "source hash mismatch: " + path
    reports, times = {}, {}
    for path in sorted((root / "commands").rglob("*.json")):
        receipt = json.loads(path.read_text())
        assert not set(receipt["cpu_affinity"]) & {2, 3, 10, 11}, "reserved CPU"
        for suffix in ("stdout", "stderr"):
            assert digest(path.with_suffix("." + suffix)) == receipt[suffix + "_sha256"], str(path)
        if "test" not in receipt["command"]:
            continue
        done = subprocess.CompletedProcess(receipt["command"], receipt["returncode"],
            path.with_suffix(".stdout").read_text(), path.with_suffix(".stderr").read_text())
        key = str(path.relative_to(root))
        reports[key] = checked.checked_report(sweep.parse, None if receipt["timeout"] else done, key)
        times[key] = receipt["elapsed_seconds"]
    result = {"source_commit": identity["commit"], "oracle_sha256": identity["oracle"]["sha256"],
              "verified_command_reports": len(reports), "categories": {},
              "slowest_commands": sorted(times.items(), key=lambda item: item[1], reverse=True)[:10]}
    for category in ("current", "configured"):
        for mode in ("debug", "release", "verify"):
            path = root / (category + "-" + mode + ".json")
            if not path.exists():
                continue
            document = json.loads(path.read_text())
            groups = collections.defaultdict(list)
            problems = {}
            for name, entry in document["files"].items():
                assert digest(source / corpus / (name + ".my")) == entry["source_sha256"]
                if "cases" in entry:
                    assert digest(source / entry["cases"]["path"]) == entry["cases"]["sha256"]
                report = reports[entry["receipt"]]
                if isinstance(report, str):
                    assert entry["problem"] == report
                    problems[name] = report
                    continue
                assert triples(report) == entry["tests"], "raw verdict differs from table: " + name
                for test in entry["tests"]:
                    groups[test[0]].append({"file": name, "status": test[1], "trap": test[2]})
            result["categories"][category + "-" + mode] = {
                "files": len(document["files"]), "entries": sum(len(items) for items in groups.values()),
                "unique_tests": len(groups), "duplicate_origins": {k:v for k,v in groups.items() if len(v)>1},
                "nonpassing": {k:v for k,v in groups.items() if any(t["status"] != "passed" for t in v)},
                "problems": problems}
    if (root / "directory.json").exists():
        directories = json.loads((root / "directory.json").read_text())
        for mode, entry in directories.items():
            report = reports[entry.get("receipt", "commands/directory-" + mode + ".json")]
            if isinstance(report, str):
                assert entry["problem"] == report
            else:
                assert triples(report) == entry["tests"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"verified_command_reports": len(reports), "counts": {
        key: {k:v[k] for k in ("files", "entries", "unique_tests")} for key,v in result["categories"].items()}}))

if __name__ == "__main__":
    main()
