#!/usr/bin/env python3
"""Rerun a gate's failing tests once, alone, as the gate ran them (lane DL-4, item 4d; the user's decision D5).

    python3 scripts/verification_rerun.py --plan PLAN.json --results RESULTS.json   # run by verify_cache.py, admitted
    python3 scripts/verification_rerun.py --log [PATH]                              # the flaky log, grouped by test

Every launcher of a gate test step records how it was started, in the gate's telemetry directory
(`verification_telemetry.record_rerun`): the native
proxy (`verification_native_telemetry.py`) its runner command, the Python launcher (`verification_telemetry.py`) its
own command line, the guest suite driver (`test_lang.py`) its compiler and arguments; each with its working directory
and environment (inside the build's projected environment where the launcher runs there). `plan` turns one record and
one failing test into the same command for that test alone (a Zig root's `--test-list`, a Python test's
qualified name, a guest file's `selka test FILE --filter NAME`), with the same binary, compiler and environment and
the test's own deadline. `run_plan` runs the steps one after another and writes what each did.

The flaky log is a JSON-lines file in the per-user cache (`flaky_log_path`): one line for each test that failed in a
gate and passed alone.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verification_telemetry  # noqa: E402  (`record_rerun` writes the records this module reads)

FORMAT = verification_telemetry.RERUN_FORMAT
DEFAULT_DEADLINE_SECONDS = 900.0  # the native proxy's per-test default (`SELKA_TEST_DEADLINE_SECONDS`)
GUEST_DEADLINE_SECONDS = 600.0  # one guest file's run, its 60 s per-test timeout included
OUTPUT_TAIL = 4000


def flaky_log_path() -> Path:
    """`<XDG_CACHE_HOME or ~/.cache>/selka/flaky-tests/flaky.jsonl`, beside the other per-user stores."""
    base = os.environ.get("XDG_CACHE_HOME", "")
    root = Path(base) if base and os.path.isabs(base) else Path.home() / ".cache"
    return root / "selka" / "flaky-tests" / "flaky.jsonl"


def load(directory) -> dict:
    """Every record in a telemetry directory, by (action, member)."""
    found = {}
    try:
        names = sorted(Path(directory).glob("rerun.*.member.*.json"))
    except OSError:
        return found
    for path in names:
        try:
            value = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(value, dict) and value.get("format") == FORMAT:
            found[(value.get("action"), value.get("member"))] = value
    return found


DEFAULT_IDLE_SECONDS = 300.0  # the native proxy's per-test idle default (`SELKA_TEST_IDLE_SECONDS`)


def seconds_from(env, name, default) -> float:
    try:
        value = float((env or {}).get(name, default))
    except ValueError:
        return default
    return value if value > 0 else default


def deadline(env) -> float:
    return seconds_from(env, "SELKA_TEST_DEADLINE_SECONDS", DEFAULT_DEADLINE_SECONDS)


def native_bound(env) -> float:
    """One test alone reports once, so the proxy's idle bound (no result for that long) is its bound too."""
    return min(deadline(env), seconds_from(env, "SELKA_TEST_IDLE_SECONDS", DEFAULT_IDLE_SECONDS))


def plan(value: dict, test_id: str, scratch: Path) -> dict | None:
    """One step that runs `test_id` alone as its record ran it, or None when the record cannot select one test."""
    env = dict(value["env"])
    kind = value["kind"]
    if kind == "native":
        name = test_id.split("::", 1)[1] if "::" in test_id else test_id
        listing = scratch / ("list-%d.txt" % abs(hash((value["action"], value["member"], test_id))))
        listing.write_text(name + "\n")
        argv, skip = [], False
        for word in value["argv"]:
            if skip:
                skip = False
                continue
            if word == "--listen=-":
                argv += ["--test-list=" + str(listing), "--cache-dir=" + str(scratch / "fuzz-cache")]
            elif word.startswith(("--test-shard=", "--test-filter=", "--test-announce-filter=")):
                continue
            elif word == "--test-shard-plan":
                skip = True
            else:
                argv.append(word)
        if "--listen=-" not in value["argv"]:
            return None
        return {"argv": argv, "cwd": value["cwd"], "env": env, "timeout": native_bound(env),
                "expect": {"kind": "native"}}
    if kind == "python":
        argv = list(value["argv"])
        modules = value.get("tests") or []
        if not modules or argv[-len(modules):] != modules:
            return None
        env[value.get("telemetry_env", "SELKA_VERIFICATION_TELEMETRY_DIR")] = str(scratch)
        safe = str(value["action"]).replace("/", "_").replace("\\", "_")
        return {"argv": argv[:-len(modules)] + [test_id], "cwd": value["cwd"], "env": env, "timeout": deadline(env),
                "expect": {"kind": "python", "test": test_id,
                           "document": str(scratch / ("%s.member.%d.json" % (safe, value["member"])))}}
    if kind == "guest":
        if "::" not in test_id:
            return None
        area, name = test_id.split("::", 1)
        suite = Path(value["cwd"]) / value["suite"]
        files = sorted(suite.rglob(area + ".selka"))
        if len(files) != 1:
            return None
        arguments, skip = [], False
        for word in value.get("arguments", []):
            if skip:
                skip = False
                continue
            if word in ("--emit-certificates", "--cache-dir"):
                # No certificates (the gate's proofs already read them), and a private cache: a stored record of the
                # gate's run must not answer for the rerun.
                skip = True
            elif word not in ("--force", "--json"):
                arguments.append(word)
        argv = [value["compiler"], "test", str(files[0].relative_to(value["cwd"])), "--filter", name, *arguments,
                "--force", "--cache-dir", str(scratch / "guest-cache"), "--json"]
        return {"argv": argv, "cwd": value["cwd"], "env": env, "timeout": GUEST_DEADLINE_SECONDS,
                "expect": {"kind": "guest", "test": test_id}}
    return None


def end_group(process) -> None:
    for signum in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, signum)
        except (ProcessLookupError, PermissionError):
            return
        try:
            process.wait(timeout=5)
            return
        except subprocess.TimeoutExpired:
            continue


def run_step(step: dict) -> dict:
    """Run one planned step in its own process group, bounded by its deadline: whether it passed, its seconds and the
    end of its output."""
    began = time.monotonic()
    with tempfile.TemporaryFile() as output:
        try:
            process = subprocess.Popen(step["argv"], cwd=step["cwd"], env=step["env"], stdin=subprocess.DEVNULL,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as error:
            return {"passed": False, "seconds": 0.0, "status": None, "output": "cannot start: %s" % error}
        try:
            status = process.wait(timeout=step["timeout"])
            timed_out = False
        except subprocess.TimeoutExpired:
            end_group(process)
            status, timed_out = None, True
        output.seek(0)
        whole = output.read().decode("utf-8", "replace")
    passed, evidence = ran_and_passed(step, status, whole)
    return {"passed": passed, "evidence": evidence, "seconds": round(time.monotonic() - began, 3), "status": status,
            "timed_out": timed_out, "output": whole[-OUTPUT_TAIL:]}


GUARDIAN_RESULT = re.compile(r'test: RESULT (\{.*\})')


def ran_and_passed(step: dict, status, text: str) -> tuple[bool, str]:
    """Whether the one test ran and passed, from what its runner reports, not only its exit status: a test that
    skipped, was answered from a stored record, or was not selected did not pass (item 4d)."""
    if status != 0:
        return False, "exited %s" % status
    expect = step.get("expect") or {}
    kind = expect.get("kind")
    if kind == "native":
        found = GUARDIAN_RESULT.findall(text)
        try:
            counts = json.loads(found[-1]) if found else {}
        except ValueError:
            counts = {}
        ok = counts.get("passed") == 1 and counts.get("failed", 0) == 0 and counts.get("skipped", 0) == 0
        return ok, "runner result %s" % (found[-1] if found else "missing")
    if kind == "python":
        try:
            rows = json.loads(Path(expect["document"]).read_text()).get("tests", [])
        except (OSError, ValueError):
            return False, "no telemetry document"
        states = [row.get("state") for row in rows if row.get("test_id") == expect["test"]]
        return states == ["passed"] and len(rows) == 1, "telemetry %s" % states
    if kind == "guest":
        for line in text.splitlines():
            if line.startswith("{") and "native-tests-v1" in line:
                try:
                    tests = json.loads(line).get("tests", [])
                except ValueError:
                    continue
                states = [test.get("status") for test in tests if test.get("name") == expect["test"]]
                others = [test.get("status") for test in tests if test.get("name") != expect["test"]]
                return states == ["passed"] and "failed" not in others, "report %s" % states
        return False, "no test report"
    return False, "no expectation"


def run_plan(steps: list[dict]) -> list[dict]:
    return [dict(run_step(step), test=step.get("test"), action=step.get("action")) for step in steps]


def print_log(path: Path) -> int:
    """The flaky log grouped by test: how often, last seen, and how many carried the F22 signature."""
    groups = {}
    try:
        lines = path.read_text().splitlines()
    except OSError:
        print("flaky log: none at %s" % path)
        return 0
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        key = (entry.get("action"), entry.get("test"))
        group = groups.setdefault(key, {"count": 0, "last": "", "f22": 0, "heads": set()})
        group["count"] += 1
        group["last"] = max(group["last"], entry.get("time", ""))
        group["f22"] += bool(entry.get("f22"))
        group["heads"].add(str(entry.get("head", ""))[:10])
    for (action, test), group in sorted(groups.items(), key=lambda item: (-item[1]["count"], item[0])):
        print("%3d  %s  %s  last %s  F22 %d  heads %s" % (group["count"], action, test, group["last"], group["f22"],
                                                        ", ".join(sorted(group["heads"]))))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--results", type=Path)
    parser.add_argument("--log", nargs="?", const="", default=None, help="print the flaky log (default: the per-user one)")
    args = parser.parse_args(argv)
    if args.log is not None:
        return print_log(Path(args.log) if args.log else flaky_log_path())
    if args.plan is None or args.results is None:
        parser.error("give --plan and --results, or --log")
    steps = json.loads(args.plan.read_text())
    results = run_plan(steps)
    args.results.write_text(json.dumps(results))
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
