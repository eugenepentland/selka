#!/usr/bin/env python3
"""Recheck reviewed bytes and coverage without building or running a guest."""
import gzip
import hashlib
import io
import json
from collections import Counter
from pathlib import Path
import re
import subprocess
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    data = path.read_bytes()
    return gzip.decompress(data) if path.suffix == ".gz" else data


here = Path(__file__).resolve().parent
review = json.loads((here / "review.json").read_text())
for name, expected in review["payloads"].items():
    assert digest(read(here / name)) == expected, name

freeze = json.loads(read(here / "frozen-source.json"))
author = Path(review["author_worktree"])
source = Path(review["selected_ast_source"])
for name, expected in freeze["core"].items():
    assert digest((author / name).read_bytes()) == expected, name
for name, expected in freeze["source37"].items():
    assert digest((source / name).read_bytes()) == expected, name

archive = subprocess.run(
    ["git", "archive", freeze["base"], "SPEC.md", "build.zig", "build.zig.zon", "src", "tests/lang"],
    cwd=author, check=True, capture_output=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
    baseline = {item.name: digest(stream.extractfile(item).read())
                for item in stream if item.isfile()}
changed = {name for name, expected in freeze["core"].items()
           if baseline.get(name) != expected}
assert changed == set(review["changed_core"])

guests = json.loads(read(here / "builds-qualified.json"))
fixture = json.loads(read(here / "fixture-qualified.json"))
assert guests["verified_after"] is True and fixture["verified_after"] is True
assert guests["source37"] == freeze["source37"]
assert len(guests["runs"]) == 4
assert {(row["backend"], row["runtime"]) for row in guests["runs"]} == {
    (backend, runtime) for backend in ["llvm", "qbe"] for runtime in ["rc", "gc"]}
assert len(fixture["builds"]) == 12
assert {(row["backend"], row["mode"], row["arm"]) for row in fixture["builds"]} == {
    (backend, mode, arm) for backend in ["llvm", "qbe"]
    for mode in ["rc", "counts", "gc"] for arm in ["control", "candidate"]}

artifacts = {}
for row in guests["runs"] + fixture["builds"]:
    assert row["status"] == 0
    argv = row["argv"]
    if row["backend"] == "llvm":
        assert "--qbe" not in argv
        assert argv[argv.index("--llvm-opt") + 1] == "3"
        assert "--lto" in argv
    else:
        assert "--qbe" in argv
    for name, expected in row["artifacts_sha256"].items():
        assert digest(Path(name).read_bytes()) == expected, name
        assert artifacts.get(name, expected) == expected
        artifacts[name] = expected
        if name.endswith(".qbe-manifest.json"):
            manifest = json.loads(Path(name).read_text())
            assert manifest["backend"] == row["backend"]
            assert manifest["runtime_object"] in row["artifacts_sha256"]
            if row["backend"] == "llvm":
                assert manifest["optimization"] == "3"
                assert manifest["lto"] is True and manifest["thin_lto"] is False
for key in ["compiler", "qbe"]:
    assert digest(Path(guests[key]).read_bytes()) == guests[key + "_sha256"]
for name, expected in fixture["tools_sha256"].items():
    assert digest(Path(name).read_bytes()) == expected, name
assert digest(Path(fixture["source"]).read_bytes()) == fixture["source_sha256"]

assert len(fixture["pairs"]) == 8 and len(fixture["names"]) == 7
assert {(row["backend"], row["mode"], row["native_gc_stress"])
        for row in fixture["pairs"]} == {
    (backend, mode, stress) for backend in ["llvm", "qbe"]
    for mode, stress in [("rc", False), ("counts", False), ("gc", False), ("gc", True)]}
for row in fixture["pairs"]:
    actual = row["observations"]["candidate"]
    control = row["observations"]["control"]
    assert all(actual[key] == control[key] for key in ["status", "stdout", "stderr"])
    assert actual["status"] == 0 and actual["stdout"] == "True\n" * 7
    if row["mode"] == "counts":
        events = json.loads(actual["stderr"].removeprefix("MYLANG_RC_COUNTS "))
        assert events == review["counting_snapshot"]
    else:
        assert actual["stderr"] == ""
    assert (row["environment"].get("MYLANG_OPTIONS") == "--gc-stress") == row["native_gc_stress"]
    for arm, observation in row["observations"].items():
        binary = observation["argv"][0]
        matching = [item for item in fixture["builds"] if item["backend"] == row["backend"]
                    and item["mode"] == row["mode"] and item["arm"] == arm]
        assert len(matching) == 1 and binary in matching[0]["artifacts_sha256"]

for name in review["failed_command_receipts"]:
    assert json.loads(read(here / name))["status"] != 0
for name in review["successful_command_receipts"]:
    assert json.loads(read(here / name))["status"] == 0
old_guests = json.loads(read(here / "builds-partial-failed.json"))
assert old_guests["verified_after"] is False and len(old_guests["runs"]) == 2
assert [row["status"] for row in old_guests["runs"]] == [0, 2]

public = json.loads(read(here / "public-qualified.json"))
assert public["verified_after"] is True and public["source37"] == freeze["source37"]
assert len(public["runs"]) == 8
assert {(row["target"], row["backend"], row["runtime"]) for row in public["runs"]} == {
    (target, backend, runtime) for target in ["ast", "fixture"]
    for backend in ["qbe", "llvm"] for runtime in ["rc", "gc-stress"]}


def observations(node):
    if isinstance(node, dict):
        for item in node.get("tests", []):
            if isinstance(item, dict) and "name" in item and "status" in item:
                yield item
        for key, value in node.items():
            if key != "tests":
                yield from observations(value)
    elif isinstance(node, list):
        for item in node:
            yield from observations(item)


for row in public["runs"]:
    count = 84 if row["target"] == "ast" else 7
    inputs = list(source.glob("*.my")) if row["target"] == "ast" else [author / "tests/lang/zeroed_variant_words.my"]
    names = {path.stem + "::" + name for path in inputs
             for name in re.findall(r"^public def (test_\w+)\(", path.read_text(), re.M)}
    assert len(names) == count and set(row["names"]) == names
    assert row["status"] == 0
    name = "public-" + "-".join(row[key] for key in ["target", "backend", "runtime"])
    data = read(here / (name + ".json.gz"))
    assert digest(data) == row["stdout_sha256"]
    assert digest(read(here / (name + ".stderr.gz"))) == row["stderr_sha256"]
    document = json.loads(data)
    tests = list(observations(document))
    assert len(tests) == count and {item["name"] for item in tests} == names
    assert all(item["status"] == "passed" for item in tests)
    assert document["passed"] == document["executed"] == count
    assert document["failed"] == document["skipped"] == document["cached"] == 0
    assert row["summary"] == {key: document[key] for key in ["passed", "failed", "skipped", "cached", "executed"]}
    argv = row["argv"]
    assert "--force" in argv and "--cases" not in argv
    assert argv[argv.index("--max-steps") + 1] == "1000000000"
    assert argv[argv.index("--timeout-ms") + 1] == "120000"
    if row["backend"] == "llvm":
        assert "--release" in argv
    else:
        assert argv[argv.index("--mode") + 1] == "Debug"
    assert ("--gc-stress" in argv) == (row["runtime"] == "gc-stress")

native = json.loads(read(here / "native-completed.json.gz"))
assert native["verified_after"] is True and native["before"] == native["after"]
assert native["before"]["core869"] == freeze["core"]
assert native["before"]["source37"] == freeze["source37"]
for name, expected in native["before"]["artifacts_sha256"].items():
    assert digest(Path(name).read_bytes()) == expected, name
for name, expected in native["receipt_sha256"].items():
    assert digest(read(here / ("native-" + name + ".gz"))) == expected, name
bounded = json.loads(read(here / "native-observations.json.gz"))
focused = json.loads(read(here / "native-focused-observations.json.gz"))
refusals = json.loads(read(here / "native-rc-native-stress-refusals.json.gz"))
bins = json.loads(read(here / "native-binaries.json.gz"))["binaries"]
assert bounded["verified_after"] is True
assert len(bounded["samples"]) == 1168 and len(focused["samples"]) == 96
assert len(refusals["comparisons"]) == 8
assert bounded["unrun"] == native["native_smoke_unrun"] and len(bounded["unrun"]) == 80
for name, expected in bounded["binary_sha256"].items():
    assert digest(Path(bins[name]).read_bytes()) == expected, name
for row in bounded["samples"] + focused["samples"]:
    assert row["actual"] == row["expected"], row["name"]
    argv = row.get("command", row.get("argv"))
    assert digest(Path(argv[-1]).read_bytes()) == row["source_sha256"]
    assert argv[0] == bins[row["arm"]] and "--stats" in argv
    assert ("--gc-stress" in argv) == row["lox_gc_stress"]
    if "environment" in row:
        assert (row["environment"].get("MYLANG_OPTIONS") == "--gc-stress") == row["native_gc_stress"]
for row in refusals["comparisons"]:
    assert row["actual"] == row["expected"]
    assert row["actual"] == {"status": 2, "stdout": "", "stderr":
        "mylang: --gc-stress needs a program built with --gc-runtime; this one uses reference counting\n"}
    assert row["environment"] == {"MYLANG_OPTIONS": "--gc-stress"}
assert {(row["backend"], row["engine"], row["lox_gc_stress"])
        for row in refusals["comparisons"]} == {
    (backend, engine, stress) for backend in ["llvm", "qbe"]
    for engine in ["vm", "tree"] for stress in [False, True]}


def cell(row):
    return (row["name"], row["engine"], row["arm"], row["lox_gc_stress"], row["native_gc_stress"])


arms = {row["arm"] for row in bounded["samples"]}
names = {(row["name"], row["tier"]) for row in bounded["samples"]}
actual = set(map(cell, bounded["samples"]))
omitted = set(map(cell, bounded["unrun"]))
assert len(arms) == 6 and len(actual) == 1168 and len(omitted) == 80 and not (actual & omitted)
assert Counter(tier for name, tier in names) == {"smoke": 13, "regression": 16, "error": 23}
assert actual | omitted == {(name, engine, arm, stress, "-gc-" in arm)
    for name, tier in names for engine in ["vm", "tree"] for arm in arms for stress in [False, True]}
assert all(row["tier"] == "smoke" and row["native_gc_stress"] and row["unrun_reason"] for row in bounded["unrun"])
focused_names = {row["name"] for row in focused["samples"]}
assert len(focused_names) == 4 and len(set(map(cell, focused["samples"]))) == 96
assert set(map(cell, focused["samples"])) == {(name, engine, arm, stress, "-gc-" in arm)
    for name in focused_names for engine in ["vm", "tree"] for arm in arms for stress in [False, True]}
mode_counts = Counter("native_gc_stress" if row["native_gc_stress"] else
    "rc" if "-rc-" in row["arm"] else "ordinary_gc" for row in bounded["samples"])
assert dict(mode_counts) == native["mode_counts"] == {"rc": 416, "ordinary_gc": 416, "native_gc_stress": 336}
print(json.dumps({"core_files_verified": len(freeze["core"]),
                  "selected_AST_files": len(freeze["source37"]),
                  "changed_core_files": len(changed), "guest_builds": 4,
                  "fixture_builds": 12, "fixture_pairs": 8,
                  "fresh_accounted_AST_tests": 336, "fresh_accounted_constructor_tests": 28,
                  "native_Lox_pairs": 1168, "native_AST_pairs": 96,
                  "RC_native_stress_refusals": 8, "native_smoke_unrun": 80,
                  "checks_per_pair": 7, "distinct_artifacts_verified": len(artifacts),
                  "qualification_rerun": False, "performance_claim": False}, sort_keys=True))
