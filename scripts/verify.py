#!/usr/bin/env python3
"""Run a declared verification manifest; report selected execution, never inferred coverage."""
import argparse
import base64
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

KINDS = {"build", "format", "check", "test", "parity", "mutation", "spec", "benchmark", "advisory"}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate(data):
    if not isinstance(data, dict) or set(data) != {"version", "steps"} or type(data["version"]) is not int or data["version"] != 1:
        raise ValueError("manifest requires version 1 and steps")
    if not isinstance(data["steps"], list) or not data["steps"]:
        raise ValueError("steps must be a nonempty list")
    known = set()
    for step in data["steps"]:
        allowed = {"id", "kind", "depends_on", "commands", "timeout", "max_output_bytes", "expect_exit", "expect_stdout", "expect_stderr_contains", "path", "contains", "repeats"}
        if not isinstance(step, dict) or set(step) - allowed:
            raise ValueError("unknown step fields")
        name = step.get("id")
        kind = step.get("kind")
        if not isinstance(name, str) or not name or name in known or not isinstance(kind, str) or kind not in KINDS:
            raise ValueError("steps require unique nonempty IDs and known kinds")
        dependencies = step.get("depends_on", [])
        if not isinstance(dependencies, list) or any(not isinstance(d, str) or d not in known for d in dependencies) or len(set(dependencies)) != len(dependencies):
            raise ValueError("dependencies must be distinct earlier step IDs")
        known.add(name)
        if kind == "spec":
            if not isinstance(step.get("path"), str) or not step["path"] or not isinstance(step.get("contains"), str) or not step["contains"]:
                raise ValueError("spec steps require path and nonempty contains marker")
            if set(step) - {"id", "kind", "depends_on", "path", "contains"}:
                raise ValueError("spec steps cannot execute commands")
            continue
        if "path" in step or "contains" in step:
            raise ValueError("path/contains belong to spec steps")
        commands = step.get("commands")
        if not isinstance(commands, list) or not commands or any(not isinstance(c, list) or not c or any(not isinstance(a, str) or not a or '\0' in a for a in c) for c in commands):
            raise ValueError("commands must be nonempty argument arrays")
        if kind == "parity" and len(commands) < 2:
            raise ValueError("parity requires at least two commands")
        if kind != "benchmark" and "repeats" in step:
            raise ValueError("only benchmarks accept repeats")
        for key, default in (("max_output_bytes", 1048576), ("repeats", 1)):
            if type(step.get(key, default)) is not int or step.get(key, default) <= 0:
                raise ValueError(f"{key} must be a positive integer")
        timeout = step.get("timeout", 60)
        if type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("timeout must be finite and positive")
        if type(step.get("expect_exit", 0)) is not int or not 0 <= step.get("expect_exit", 0) <= 255:
            raise ValueError("expect_exit must be an exit status from 0 to 255")
        for key in ("expect_stdout", "expect_stderr_contains"):
            if key in step and not isinstance(step[key], str):
                raise ValueError(f"{key} must be text")
        if kind == "mutation" and (step.get("expect_exit", 0) == 0 or not step.get("expect_stderr_contains")):
            raise ValueError("mutation rejection requires a nonzero exit and diagnostic marker")
    return data["steps"]


def select(steps, patterns):
    requested = {s["id"] for s in steps if not patterns or any(fnmatch.fnmatchcase(s["id"], p) for p in patterns)}
    for pattern in patterns:
        if not any(fnmatch.fnmatchcase(s["id"], pattern) for s in steps):
            raise ValueError(f"selector matched no steps: {pattern}")
    selected = set(requested)
    for step in reversed(steps):
        if step["id"] in selected:
            selected.update(step.get("depends_on", []))
    return requested, selected


def command(argv, root, step, env=None):
    start = time.monotonic()
    outcome = {"argv": argv, "cwd": str(root), "executed": False, "timed_out": False}
    limit = step.get("max_output_bytes", 1048576)
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            process = subprocess.Popen(argv, cwd=root, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr, start_new_session=True, env=env)
        except OSError as error:
            outcome.update(error=str(error), elapsed_seconds=time.monotonic() - start, passed=False)
            return outcome
        outcome["executed"] = True
        try:
            deadline = start + step.get("timeout", 60)
            while True:
                try:
                    from verification.scheduler import current_cancelled
                    cancelled = current_cancelled()
                except ImportError:
                    cancelled = False
                if cancelled:
                    outcome["cancelled"] = True
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(argv, step.get("timeout", 60))
                try:
                    process.wait(timeout=min(0.1, remaining))
                    break
                except subprocess.TimeoutExpired:
                    continue
        except subprocess.TimeoutExpired:
            outcome["timed_out"] = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
        finally:
            # A command owns its process group, including surviving descendants.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        outcome["exit"] = process.returncode
        outcome["elapsed_seconds"] = time.monotonic() - start
        truncated = False
        for name, stream in (("stdout", stdout), ("stderr", stderr)):
            stream.seek(0)
            content = stream.read(limit + 1)
            truncated |= len(content) > limit
            outcome[name + "_base64"] = base64.b64encode(content[:limit]).decode("ascii")
            outcome[name + "_sha256"] = hashlib.sha256(content[:limit]).hexdigest()
            outcome[name] = content[:limit].decode("utf-8", errors="replace")
        outcome["output_truncated"] = truncated
    outcome["passed"] = not outcome["timed_out"] and not outcome.get("cancelled", False) and not truncated and outcome["exit"] == step.get("expect_exit", 0)
    if "expect_stdout" in step:
        outcome["passed"] &= outcome["stdout_base64"] == base64.b64encode(step["expect_stdout"].encode()).decode("ascii")
    if "expect_stderr_contains" in step:
        outcome["passed"] &= step["expect_stderr_contains"].encode() in base64.b64decode(outcome["stderr_base64"])
    return outcome


def run(manifest, patterns=()):
    raw = manifest.read_bytes()
    steps = validate(json.loads(raw, object_pairs_hook=unique_object))
    requested, selected = select(steps, patterns)
    root = manifest.parent.resolve()
    report = {"version": 1, "manifest": str(manifest.resolve()), "manifest_sha256": hashlib.sha256(raw).hexdigest(),
              "captured_utc": datetime.now(timezone.utc).isoformat(), "requested": [s["id"] for s in steps if s["id"] in requested],
              "selected": [s["id"] for s in steps if s["id"] in selected], "runtime_coverage": "not measured", "steps": []}
    states = {}
    for step in steps:
        row = {"id": step["id"], "kind": step["kind"], "selected": step["id"] in selected, "executed": False, "definition": step}
        if step["id"] not in selected:
            row.update(status="unselected", note="not run; no compilation or test result claimed")
        elif any(states[d] != "passed" for d in step.get("depends_on", [])):
            row.update(status="blocked", note="a declared dependency did not pass")
        elif step["kind"] == "spec":
            path = root / step["path"]
            try:
                content = path.read_bytes()
                row.update(executed=True, path=str(path), sha256=hashlib.sha256(content).hexdigest(), status="passed" if step["contains"].encode() in content else "failed")
            except OSError as error:
                row.update(status="failed", error=str(error))
        else:
            print(f"verify: {step['id']}", file=sys.stderr, flush=True)
            results = [command(argv, root, step) for _ in range(step.get("repeats", 1)) for argv in step["commands"]]
            passed = all(r["passed"] for r in results)
            if step["kind"] == "parity" and passed:
                passed = all((r["exit"], r["stdout_base64"]) == (results[0]["exit"], results[0]["stdout_base64"]) for r in results[1:])
            row.update(executed=any(r["executed"] for r in results), commands=results, status="passed" if passed else "failed")
            if step["kind"] == "benchmark":
                row["timing_policy"] = "observations only; no elapsed-time pass/fail threshold"
        states[step["id"]] = row["status"]
        report["steps"].append(row)
    report["selected_passed"] = all(states[name] == "passed" for name in selected)
    report["full_manifest_passed"] = len(selected) == len(steps) and report["selected_passed"]
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--only", action="append", default=[], help="step ID glob; dependencies are included explicitly in the report")
    parser.add_argument("--report", type=Path, help="also save the JSON report")
    parser.add_argument("--cache-dir", type=Path, default=Path.home() / ".cache" / "selka-verification")
    parser.add_argument("--cache-max-bytes", type=int, default=512 * 1024 * 1024)
    parser.add_argument("--previous", type=Path, help="previous v2 report for affected inventory comparison")
    parser.add_argument("--mode", choices=("full", "affected", "shadow"), default="full")
    from verification.scheduler import add_arguments, executor_from_args
    add_arguments(parser)
    args = parser.parse_args()
    try:
        from verification.core import run_manifest, collect_cache
        if args.cache_max_bytes < 0:
            raise ValueError("cache-max-bytes must be nonnegative")
        previous = json.loads(args.previous.read_text()) if args.previous else None
        executor = executor_from_args(args)
        report = run_manifest(args.manifest.resolve(), cache_dir=args.cache_dir, previous=previous, mode=args.mode, patterns=args.only, executor=executor)
        if report["version"] == 2:
            report["cache_gc"] = collect_cache(args.cache_dir, args.cache_max_bytes)
        text = json.dumps(report, indent=2) + "\n"
        if args.report:
            args.report.write_text(text)
        sys.stdout.write(text)
    except (OSError, ValueError, TypeError) as error:
        print(f"verify: {error}", file=sys.stderr)
        return 2
    return 0 if report["selected_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
