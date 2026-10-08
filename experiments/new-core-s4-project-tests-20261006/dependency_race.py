#!/usr/bin/env python3
"""Retain a directory replay race involving an imported source outside its subtree.

The suite first replays a cached success. While a second entry compiles, mutate
the suite's external dependency. A successful aggregate is the reduced defect;
the corrected parent must refuse it with SourceChanged. No gate is claimed here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--expect", choices=("defect", "refusal"), required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    if area.exists() or not area.is_relative_to(ROOT / "experiments"):
        parser.error("fresh evidence under experiments is required")
    area.mkdir(parents=True)
    project = area / "project"
    suites = project / "tests"
    suites.mkdir(parents=True)
    cache = ROOT / ".mylang-cache" / "s4-m" / area.name
    if cache.exists():
        raise RuntimeError("fresh reducer cache is required")
    (project / "mylang.json").write_text('{"version":1}\n')
    dependency = project / "dep.my"
    before = "module dep\n\npublic def value() -> int:\n    return 3\n"
    after = before.replace("return 3", "return 4")
    (area / "dependency-before.my").write_text(before)
    (area / "dependency-after.my").write_text(after)
    dependency.write_text(before)
    (suites / "suite_test.my").write_text(
        "module tests.suite_test\nimport dep\n\npublic def test_dependency() -> bool:\n"
        "    return dep.value() == 3\n")
    slow = suites / "slow_test.my"
    slow.write_text("module tests.slow_test\n\npublic def test_slow() -> bool:\n    return True\n")
    core = args.core.resolve()
    with core.open("rb") as stream:
        core_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    manifest = {"core": str(core), "sha256": core_digest, "cache": str(cache),
                "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "qualified": False, "expect": args.expect, "mutated_after_cached_report": False}
    manifest["untracked_helpers"] = {name: hashlib.sha256((ROOT / "src/core" / name).read_bytes()).hexdigest()
                                     for name in ("tool_identity.zig", "tool_ticket.zig")}
    (area / "source.diff").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    command = [str(ROOT / "scripts/build-slot.sh"), "build", str(core), "test", str(suites),
               "--json", "--jobs", "2", "--cache-dir", str(cache)]
    (area / "command.txt").write_text(shlex.join(command) + "\n")
    cold = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
    (area / "cold.stdout").write_text(cold.stdout)
    (area / "cold.stderr").write_text(cold.stderr)
    if cold.returncode or json.loads(cold.stdout).get("passed") != 2:
        raise RuntimeError("cold setup did not execute both tests")
    slow.write_text(slow.read_text().replace("test_slow()", "test_slow_changed()"))
    stdout = (area / "race.stdout").open("w")
    stderr = (area / "race.stderr").open("w")
    child = subprocess.Popen(command, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
    started = time.monotonic()
    try:
        while child.poll() is None and time.monotonic() - started < 90:
            for path in (cache / "tests").glob("directory-*/*.json"):
                try:
                    report = json.loads(path.read_text())
                except (OSError, ValueError):
                    continue
                tests = report.get("tests", [])
                if any(item.get("name") == "tests.suite_test::test_dependency" and item.get("status") == "cached" for item in tests):
                    (area / "cached-child.json").write_text(json.dumps(report, indent=2) + "\n")
                    dependency.write_text(after)
                    manifest["mutated_after_cached_report"] = True
                    break
            if manifest["mutated_after_cached_report"]:
                break
            time.sleep(0.001)
        code = child.wait(timeout=max(1, 90 - (time.monotonic() - started)))
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        stdout.close()
        stderr.close()
    result = json.loads((area / "race.stdout").read_text())
    manifest.update(status=code, seconds=time.monotonic() - started, report=result)
    defect = code == 0 and result.get("failed") == 0
    refusal = code == 1 and any("SourceChanged" in item.get("reason", "") for item in result.get("tests", []))
    matched = manifest["mutated_after_cached_report"] and (defect if args.expect == "defect" else refusal)
    manifest["expected_observed"] = matched
    (area / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({key: manifest[key] for key in ("status", "seconds", "mutated_after_cached_report", "expected_observed")}))
    return 0 if matched else 1


if __name__ == "__main__":
    raise SystemExit(main())
