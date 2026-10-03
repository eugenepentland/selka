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
    if not path.exists():
        path = path.with_suffix("") if path.suffix == ".gz" else Path(str(path) + ".gz")
    data = path.read_bytes()
    return gzip.decompress(data) if path.suffix == ".gz" else data


here = Path(__file__).resolve().parent
review = json.loads((here / "review.json").read_text())
for name, expected in review["payloads"].items():
    assert digest(read(here / name)) == expected, name
for name, expected in review["original_payloads"].items():
    assert digest(Path(name).read_bytes()) == expected, name

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

guests = json.loads(read(here / "builds-stable.json"))
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
    inputs = list(source.glob("*.my")) if row["target"] == "ast" else [author / "tests/lang/zeroed_number_tag.my"]
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


def prefix_map(root):
    root = Path(root)
    return {str(path.relative_to(root)): digest(path.read_bytes())
            for folder in [root / "bin", root / "lib"] if folder.is_dir()
            for path in folder.rglob("*") if path.is_file()}


expected_prefixes = guests["immutable_prefixes_before"]
assert expected_prefixes == guests["immutable_prefixes_after"]
assert sorted(map(len, expected_prefixes.values())) == [2, 16]
for prefix, items in expected_prefixes.items():
    assert prefix_map(prefix) == items
for name in ["public-prefix-audit.json", "fixture-prefix-audit.json", "native-prefix-audit.json"]:
    audit = json.loads(read(here / name))
    assert audit["status"] == 0 and audit["unchanged"] is True
    assert audit["before"] == audit["after"] == expected_prefixes
    assert digest(Path(audit["argv"][1]).read_bytes()) == audit["script_sha256"]
owned = json.loads(read(here / "acceptance-owned-layout.json"))
assert owned["before"] == owned["after"] == expected_prefixes
assert owned["verified_unchanged"] is True and owned["prior_gate_completed_before_stop"] is True
assert "no pre-gate full lib map claim" in owned["prefix_window_scope"]
for folder in [author / "zig-out/bin", author / "zig-out/lib"]:
    assert folder.is_dir() and not folder.is_symlink()
    assert all(not path.is_symlink() for path in folder.rglob("*"))
assert prefix_map(author / "zig-out") == owned["owned_zig_out"]
assert json.loads(read(here / "acceptance-suspended.json"))["processes"] == {}

provisional = json.loads(read(here / "builds-provisional.json"))
assert provisional["verified_after"] is True
old_bytes = {(row["backend"], row["runtime"]): row["artifacts_sha256"][row["binary"]]
             for row in provisional["runs"]}
new_bytes = {(row["backend"], row["runtime"]): row["artifacts_sha256"][row["binary"]]
             for row in guests["runs"]}
assert old_bytes == new_bytes
for row in public["runs"]:
    assert row["argv"][2] == guests["compiler"]
    if row["backend"] == "qbe":
        assert row["argv"][row["argv"].index("--qbe") + 1] == guests["qbe"]

for name in review["failed_command_receipts"] + review["successful_command_receipts"]:
    command = json.loads(read(here / name))
    prefix = name.removesuffix(".json")
    for stream in ["stdout", "stderr"]:
        assert digest(read(here / (prefix + "." + stream))) == command[stream + "_sha256"]
focus = read(here / "command-focused-style-corrected.stderr").decode()
assert {"passed": 25, "failed": 0, "skipped": 0} in [
    json.loads(value) for value in re.findall(r"guardian/test: RESULT (\{[^\n]*\})", focus)]
shards = read(here / "command-unit-shards.stderr").decode()
units = [json.loads(value) for value in re.findall(r"guardian/test: RESULT (\{[^\n]*\})", shards)]
assert len(units) == 8 and sum(row["passed"] for row in units) == 2493
assert all(row["failed"] == row["skipped"] == 0 for row in units)
assert "declared RSS limit" not in shards
corrected = read(here / "command-qbe-acceptance-layout-corrected.stderr").decode()
fresh = [json.loads(value) for value in re.findall(r"guardian/test: RESULT (\{[^\n]*\})", corrected)]
assert sorted(row["passed"] for row in fresh) == [4, 139, 255]
assert all(row["failed"] == row["skipped"] == 0 for row in fresh)
assert "cached" in read(here / "command-qbe-acceptance-owned.stderr").decode()

static = json.loads(read(here / "static-summary.json"))
widths = json.loads(read(here / "static-width-difference.json"))
assert len(widths["functions"]) == 6
changes = 0
for name, row in widths["functions"].items():
    slug = name.replace("::", "-")
    before = read(here / ("static-control-" + slug + ".ssa")).decode().splitlines()
    after = read(here / ("static-candidate-" + slug + ".ssa")).decode().splitlines()
    assert len(before) == len(after)
    delta = [[old, new] for old, new in zip(before, after) if old != new]
    assert delta == row["tag_store_pairs"] and row["ssa_only_changes_are_tag_widths"] is True
    for old, new in delta:
        assert re.fullmatch(r" storew [23], %v\d+", old)
        assert old.replace("storew", "storel", 1) == new
        pointer = old.split(", ")[1]
        assert " storel 0, " + pointer in before[:before.index(old)]
    changes += len(delta)
    assert row["qbe_control_instructions_calls"] == row["qbe_candidate_instructions_calls"]
    for arm in ["control", "candidate"]:
        function = static["arms"][arm]["functions"][name]
        assert digest(read(here / ("static-" + arm + "-" + slug + ".ssa"))) == function["ssa_sha256"]
        assembly = read(here / ("static-" + arm + "-" + slug + ".asm"))
        assert digest(assembly) == function["asm_sha256"]
        ops = re.findall(r"^\s*[0-9a-f]+:\s+([a-z][a-z0-9]*)", assembly.decode(), re.M)
        assert [len(ops), ops.count("call")] == row["qbe_" + arm + "_instructions_calls"]
assert changes == 9
for arm in ["control", "candidate"]:
    llvm = static["arms"][arm]["llvm_run"]
    assembly = read(here / ("static-" + arm + "-llvm-vm-run.asm"))
    assert digest(assembly) == llvm["asm_sha256"]
    ops = re.findall(r"^\s*[0-9a-f]+:\s+([a-z][a-z0-9]*)", assembly.decode(), re.M)
    assert [len(ops), ops.count("call")] == [5586, 486]
print(json.dumps({"core_files_verified": len(freeze["core"]),
                  "selected_AST_files": len(freeze["source37"]),
                  "changed_core_files": len(changed), "guest_builds": 4,
                  "fixture_builds": 12, "fixture_pairs": 8,
                  "fresh_accounted_AST_tests": 336, "fresh_accounted_constructor_tests": 28,
                  "native_Lox_pairs": 1168, "native_AST_pairs": 96,
                  "RC_native_stress_refusals": 8, "native_smoke_unrun": 80,
                  "checks_per_pair": 7, "distinct_artifacts_verified": len(artifacts),
                  "complete_prefix_maps": [2, 16], "selected_static_functions": 6, "only_tag_width_changes": changes,
                  "qualification_rerun": False, "performance_claim": False}, sort_keys=True))
