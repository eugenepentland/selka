#!/usr/bin/env python3
"""Run file-based stdin/stdout contracts with bounded, isolated child processes."""
import argparse
import base64
from datetime import datetime, timezone
from decimal import Decimal, DecimalException
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time

from verify import unique_object


def reject_constant(value):
    raise ValueError(f"non-JSON constant: {value}")


def parse_json(raw):
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object,
                           parse_constant=reject_constant, parse_float=Decimal)
        pending = [(value, 0)]
        while pending:
            item, depth = pending.pop()
            if depth > 128:
                raise ValueError("JSON nesting exceeds 128 levels")
            if isinstance(item, dict):
                pending.extend((child, depth + 1) for child in item.values())
            elif isinstance(item, list):
                pending.extend((child, depth + 1) for child in item)
        return value
    except (DecimalException, RecursionError) as error:
        raise ValueError("JSON number or nesting exceeds supported limits") from error


def json_equal(left, right):
    # Python's bool is an int; JSON booleans must not equal numeric values.
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(json_equal(left[k], right[k]) for k in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(json_equal(left[i], right[i]) for i in range(len(left)))
    return left == right


def load_cases(path, patterns):
    raw = path.read_bytes()
    data = parse_json(raw)
    if not isinstance(data, dict) or set(data) != {"version", "cases"} or type(data["version"]) is not int or data["version"] != 1:
        raise ValueError("fixtures require version 1 and cases")
    if not isinstance(data["cases"], list) or not data["cases"]:
        raise ValueError("cases must be a nonempty list")
    seen, cases = set(), []
    for case in data["cases"]:
        if not isinstance(case, dict) or set(case) - {"id", "input", "expected", "compare", "expect_exit", "expected_stderr"}:
            raise ValueError("unknown case fields")
        name = case.get("id")
        if not isinstance(name, str) or not name or name in seen:
            raise ValueError("cases require unique nonempty IDs")
        seen.add(name)
        if case.get("compare", "json") not in ("json", "bytes"):
            raise ValueError(f"{name}: compare must be json or bytes")
        if type(case.get("expect_exit", 0)) is not int or not 0 <= case.get("expect_exit", 0) <= 255:
            raise ValueError(f"{name}: expect_exit must be 0..255")
        row = dict(case)
        for field in ("input", "expected", "expected_stderr"):
            if field == "expected_stderr" and field not in case:
                continue
            if not isinstance(case.get(field), str) or not case[field]:
                raise ValueError(f"{name}: {field} must name a fixture file")
            row[field + "_bytes"] = (path.parent / case[field]).read_bytes()
        if case.get("compare", "json") == "json":
            row["expected_json"] = parse_json(row["expected_bytes"])
        cases.append(row)
    for pattern in patterns:
        if not any(fnmatch.fnmatchcase(c["id"], pattern) for c in cases):
            raise ValueError(f"selector matched no cases: {pattern}")
    return raw, [c for c in cases if not patterns or any(fnmatch.fnmatchcase(c["id"], p) for p in patterns)], len(cases)


def execute(argv, cwd, payload, timeout, limit):
    start = time.monotonic()
    row = {"executed": False, "timed_out": False, "output_limit_exceeded": False}
    captured = {"stdout": bytearray(), "stderr": bytearray()}
    # A file avoids pipe deadlocks when the child writes before consuming stdin.
    with tempfile.TemporaryFile() as source, selectors.DefaultSelector() as selector:
        source.write(payload)
        source.seek(0)
        try:
            child = subprocess.Popen(argv, cwd=cwd, stdin=source, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, start_new_session=True)
        except OSError as error:
            row["error"] = str(error)
            return row, b"", b""
        row["executed"] = True
        for name in captured:
            stream = getattr(child, name)
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        try:
            while selector.get_map() or child.poll() is None:
                remaining = timeout - (time.monotonic() - start)
                if remaining <= 0:
                    row["timed_out"] = True
                    break
                for key, _ in selector.select(min(remaining, 0.05)):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    room = limit - len(captured[key.data])
                    captured[key.data].extend(chunk[:room])
                    if len(chunk) > room:
                        row["output_limit_exceeded"] = True
                if row["output_limit_exceeded"]:
                    break
                if child.poll() is not None:
                    # Stop descendants that inherited the output pipes, then drain.
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
        finally:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
            child.stdout.close()
            child.stderr.close()
        row.update(exit=child.returncode, elapsed_seconds=time.monotonic() - start)
    return row, bytes(captured["stdout"]), bytes(captured["stderr"])


def evidence(raw):
    return {"base64": base64.b64encode(raw).decode("ascii"),
            "text": raw.decode("utf-8", errors="replace"),
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def run(args):
    raw, cases, total = load_cases(args.fixtures, args.case)
    report = {"version": 1, "fixtures": str(args.fixtures.resolve()),
              "fixtures_sha256": hashlib.sha256(raw).hexdigest(),
              "captured_utc": datetime.now(timezone.utc).isoformat(),
              "argv": args.command, "cwd": str(args.cwd.resolve()),
              "timeout_seconds": args.timeout, "max_output_bytes_per_stream": args.max_output_bytes,
              "total": total, "selected": len(cases), "cases": []}
    for case in cases:
        row, actual, stderr = execute(args.command, args.cwd, case["input_bytes"], args.timeout, args.max_output_bytes)
        errors = []
        if not row["executed"]:
            errors.append("could not start command: " + row["error"])
        elif row["exit"] != case.get("expect_exit", 0):
            errors.append(f"exit: expected {case.get('expect_exit', 0)}, actual {row['exit']}")
        if row["timed_out"]:
            errors.append("case timed out")
        if row["output_limit_exceeded"]:
            errors.append("child output exceeded limit; retained output is a prefix")
        mode = case.get("compare", "json")
        try:
            matches = json_equal(parse_json(actual), case["expected_json"]) if mode == "json" else actual == case["expected_bytes"]
            if not matches:
                errors.append(f"stdout {mode} mismatch (see expected and actual in report)")
        except (ValueError, UnicodeError, RecursionError) as error:
            errors.append(f"stdout is not strict UTF-8 JSON: {error}")
        if "expected_stderr_bytes" in case and stderr != case["expected_stderr_bytes"]:
            errors.append("stderr byte mismatch")
        row.update(id=case["id"], compare=mode, expect_exit=case.get("expect_exit", 0),
                   input=evidence(case["input_bytes"]), expected=evidence(case["expected_bytes"]),
                   actual=evidence(actual), stderr=evidence(stderr), errors=errors,
                   status="failed" if errors else "passed")
        if "expected_stderr_bytes" in case:
            row["expected_stderr"] = evidence(case["expected_stderr_bytes"])
        report["cases"].append(row)
    report["executed"] = sum(c["executed"] for c in report["cases"])
    report["passed"] = sum(c["status"] == "passed" for c in report["cases"])
    report["failed"] = len(cases) - report["passed"]
    report["status"] = "passed" if report["failed"] == 0 and cases else "failed"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--case", action="append", default=[], help="case ID glob; repeatable")
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--max-output-bytes", type=int, default=1048576)
    parser.add_argument("command", nargs=argparse.REMAINDER, help="-- executable [arguments...]")
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if args.report is not None and args.report.exists():
        print("contract: report already exists; choose a new report path", file=sys.stderr)
        return 2
    try:
        if not args.command or any("\0" in a for a in args.command):
            raise ValueError("supply command argv after --")
        if not math.isfinite(args.timeout) or args.timeout <= 0 or args.max_output_bytes <= 0:
            raise ValueError("timeout and max-output-bytes must be positive and finite")
        report = run(args)
        exit_code = 0 if report["status"] == "passed" else 1
        if any(not c["executed"] for c in report["cases"]):
            exit_code = 2
    except (OSError, ValueError) as error:
        report = {"version": 1, "status": "error", "error": str(error)}
        exit_code = 2
    try:
        if args.report is None:
            fd, name = tempfile.mkstemp(prefix="contract-report-", suffix=".json")
            os.close(fd)
            args.report = Path(name)
            args.report.unlink()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open("x") as output:
            output.write(json.dumps(report, indent=2, ensure_ascii=True) + "\n")
    except OSError as error:
        print(f"contract: cannot retain report: {error}", file=sys.stderr)
        return 2
    print(f"contract: {report['status']} passed={report.get('passed', 0)} selected={report.get('selected', 0)} total={report.get('total', 0)} report={args.report.resolve()}")
    if "error" in report:
        message = report["error"]
        print(message[:500] + ("… [see full report]" if len(message) > 500 else ""), file=sys.stderr)
    failures = [case for case in report.get("cases", []) if case["errors"]]
    for case in failures[:5]:
        print(f"{case['id'][:100]}: {'; '.join(case['errors'])[:500]}", file=sys.stderr)
    if len(failures) > 5:
        print(f"{len(failures) - 5} additional failures in report", file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
