#!/usr/bin/env python3
"""Strict generated project/test comparisons, plus traced unchanged receipts.

Run under core-qualification.lock, after the frozen source's full old gate.
Retains every source, command and output; a mismatch stops before any correction.
"""
import argparse
import ast
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import random
import re
import shlex
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import qualification_support as support
spec = importlib.util.spec_from_file_location("s4_project_report", Path(__file__).with_name("conformance_checked.py"))
reports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


identity = support.identity


def verdicts(result, forced=False):
    value = json.loads(result.stdout)
    counts = reports.validate_report(value, result.returncode, allow_cached=not forced)
    tests = value["tests"]
    normalized = sorted((test["name"], "passed" if test["status"] == "cached" else test["status"]) for test in tests)
    return normalized, counts


def execute(capture, argv, timeout):
    try:
        return capture.run(argv, capture_output=True, text=True, timeout=timeout), False
    except subprocess.TimeoutExpired as error:
        return subprocess.CompletedProcess(argv, 124, error.stdout.decode("utf-8", "replace"),
                                           error.stderr.decode("utf-8", "replace")), True


def trace_replay(path, compiler, directory):
    """Only the host compiler and its two directory workers may attempt exec."""
    executions = []
    for line in path.read_text().splitlines():
        found = re.search(r'execve\(("(?:[^"\\]|\\.)*")', line)
        if found:
            executions.append(ast.literal_eval(found[1]))
    allowed = [str(Path(compiler).resolve())] * (3 if directory else 1)
    if executions != allowed:
        raise ValueError("unchanged run attempted a guest/tool execution or wrong directory fanout")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--cases", type=int, default=50)
    parser.add_argument("--seed", type=int, default=4701)
    support.receipt_arguments(parser)
    args = parser.parse_args()
    if args.cases < 1 or git("status", "--porcelain", "--untracked-files=no"):
        parser.error("positive cases and clean frozen tracked source are required")
    area, cache = args.evidence.resolve(), args.cache.resolve()
    if area.exists() or cache.exists() or not area.is_relative_to(ROOT / "experiments"):
        parser.error("fresh evidence under experiments and fresh cache are required")
    area.mkdir(parents=True)
    cache.mkdir(parents=True)
    try:
        receipt = support.manifest(ROOT, args.old, args.core, args,
            [Path(__file__), Path(support.__file__), Path(reports.__file__)], ("strace",))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.error(str(error))
    oracles = receipt["oracles"]
    capture = support.Capture(area / "processes", ROOT)
    rng = random.Random(args.seed)
    manifest = {**receipt, "cases": args.cases, "seed": args.seed,
                "accepted": 0, "commands": [], "inputs": {}, "qualified": False}
    (area / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    command_lock = threading.Lock()
    next_command = [1]
    phases = {}

    def retain(folder, phase):
        value = support.snapshot(folder, area / "inputs" / folder.name / phase)
        manifest["inputs"].setdefault(folder.name, {})[phase] = value
        phases[folder.name] = phase

    def run(folder, engine, target, flags=(), traced=False, required_statuses=None):
        with command_lock:
            number = next_command[0]
            next_command[0] += 1
        stem = area / f"command-{number:04}"
        argv = [oracles[engine]["path"], "test", str(folder / target), "--json", "--jobs", "2",
                "--cache-dir", str(cache / folder.name / engine), *flags]
        if traced:
            argv = [receipt["tools"]["strace"]["path"], "-f", "-s", "65535", "-e", "trace=execve", "-o", str(stem.with_suffix(".trace")), *argv]
        started = time.monotonic()
        result, timed_out = execute(capture, argv, 120)
        stem.with_suffix(".stdout").write_text(result.stdout)
        stem.with_suffix(".stderr").write_text(result.stderr)
        item = {"argv": argv, "status": result.returncode, "seconds": time.monotonic() - started,
                "timed_out": timed_out, "input_phase": phases[folder.name],
                "stdout": str(stem.with_suffix(".stdout")), "stderr": str(stem.with_suffix(".stderr"))}
        with command_lock:
            manifest["commands"].append(item)
        stem.with_suffix(".command").write_text(shlex.join(argv) + "\n" + json.dumps(item) + "\n")
        if timed_out:
            raise ValueError("command timed out; partial outputs retained and process group terminated")
        normalized, counts = verdicts(result, forced="--force" in flags)
        statuses = {test["name"]: test["status"] for test in json.loads(result.stdout)["tests"]}
        if required_statuses is not None and statuses != required_statuses:
            raise ValueError(f"per-test reuse statuses differ: {statuses}")
        if traced:
            trace_replay(stem.with_suffix(".trace"), oracles[engine]["path"], target == ".")
            if counts["cached"] != len(normalized):
                raise ValueError("unchanged file run executed a child or did not reuse every success")
        return normalized

    try:
        for number in range(args.cases):
            folder = area / f"case-{number:03}"
            folder.mkdir()
            value, bound, offset = rng.randrange(1, 40), rng.randrange(2, 14), rng.randrange(0, 9)
            expected = value + bound * (bound - 1) // 2 + offset
            leaf = "module leaf\n\npublic def value() -> int:\n    return " + str(value) + "\n"
            dependency = ("module dep\nimport leaf\n\npublic def value() -> int:\n"
                          "    total = leaf.value()\n    for i in range(" + str(bound) + "):\n"
                          "        total += i\n    return total + " + str(offset) + "\n")
            app = ("module app\nimport dep\n\npublic def test_dependency() -> bool:\n"
                   "    return dep.value() == " + str(expected) + "\n\npublic def test_constant() -> bool:\n"
                   "    return True\n\ndef main() -> int:\n    return 0\n")
            for name, source in (("app", app), ("dep", dependency), ("leaf", leaf)):
                (folder / f"{name}.my").write_text(source)
            (folder / "orphan.my").write_text("module orphan\n\npublic def test_orphan() -> bool:\n    return True\n")
            (folder / "mylang.json").write_text('{"version":1}\n')
            retain(folder, "before")
            cold = run(folder, "old", ".")
            if cold != run(folder, "core", ".", ("--force",)):
                raise ValueError("cold directory comparison differs")
            if cold != [("app::test_constant", "passed"), ("app::test_dependency", "passed"), ("orphan::test_orphan", "passed")]:
                raise ValueError("cold directory did not account for the exact three expected tests")
            if run(folder, "core", ".", traced=True,
                   required_statuses={name: "cached" for name, _ in cold}) != cold:
                raise ValueError("unchanged directory dropped tests")
            if run(folder, "old", "app.my") != run(folder, "core", "app.my"):
                raise ValueError("file comparison differs")
            run(folder, "core", "app.my", traced=True,
                required_statuses={"app::test_constant": "cached", "app::test_dependency": "cached"})
            # Changed dependency: one test fails, the unaffected constant remains reusable.
            (folder / "leaf.my").write_text(leaf.replace(str(value) + "\n", str(value + 1) + "\n"))
            retain(folder, "changed-dependency")
            changed = run(folder, "old", "app.my")
            if changed != run(folder, "core", "app.my", required_statuses={"app::test_constant": "cached", "app::test_dependency": "failed"}) or changed != [("app::test_constant", "passed"), ("app::test_dependency", "failed")]:
                raise ValueError("changed dependency comparison differs")
            # Provider replacement restores the expected result with an unchanged signature.
            (folder / "app.cases.json").write_text(json.dumps({"app::test_dependency": {"providers": {"dep.my": dependency.replace(" + " + str(offset), " + " + str(offset - 1))}}}) + "\n")
            retain(folder, "provider")
            provider = run(folder, "old", "app.my", ("--filter", "test_dependency"))
            if provider != run(folder, "core", "app.my", ("--filter", "test_dependency")) or provider != [("app::test_dependency", "passed")]:
                raise ValueError("provider comparison differs")
            run(folder, "core", "app.my", ("--filter", "test_dependency"), traced=True,
                required_statuses={"app::test_dependency": "cached"})
            if number % 5 == 0:
                a = folder / "provider-a.json"
                b = folder / "provider-b.json"
                a.write_bytes((folder / "app.cases.json").read_bytes())
                b.write_text(json.dumps({"app::test_dependency": {"providers": {"dep.my": "module dep\n\npublic def value() -> int:\n    return " + str(expected + 1) + "\n"}, "expected": False}}) + "\n")
                retain(folder, "concurrent-providers")
                expected_results = [run(folder, "old", "app.my", ("--filter", "test_dependency", "--cases", str(cases))) for cases in (a, b)]
                with ThreadPoolExecutor(max_workers=2) as workers:
                    results = list(workers.map(lambda cases: run(folder, "core", "app.my", ("--force", "--filter", "test_dependency", "--cases", str(cases))), (a, b)))
                if results != expected_results or results != [[("app::test_dependency", "passed")]] * 2:
                    raise ValueError("concurrent provider selections shared an output or returned a wrong result")
            manifest["accepted"] += 1
            (area / "summary.json").write_text(json.dumps(manifest, indent=2) + "\n")
            print(f"project {number + 1}/{args.cases}: PASS", flush=True)
        manifest["source_unchanged"] = support.unchanged(ROOT, receipt)
        manifest["oracles_unchanged"] = all(identity(Path(item["path"])) == item for item in oracles.values())
        manifest["qualified"] = manifest["source_unchanged"] and manifest["oracles_unchanged"] and manifest["accepted"] == args.cases
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        manifest["error"] = str(error)
        print(f"STOP: {error}", flush=True)
    (area / "summary.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return 0 if manifest["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
