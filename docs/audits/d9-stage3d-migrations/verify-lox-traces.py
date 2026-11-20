#!/usr/bin/env python3
"""Compare VM error traces before/after a Lox port change, with Lox GC stress.

Usage: verify-lox-traces.py REFERENCE CANDIDATE WORK_DIRECTORY
Both inputs are compiled Lox executables. Scratch and raw results stay in WORK.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


CASES = {
    "get_global": "print missing;",
    "set_global": "missing = 2;",
    "get_property": "print 1.missing;",
    "set_property": "var a = 1; a.field = 2;",
    "missing_property": "class A {} var a = A(); print a.missing;",
    "greater": "print 1 > nil;",
    "less": "print 1 < nil;",
    "subtract": "print 1 - nil;",
    "multiply": "print 1 * nil;",
    "divide": "print 1 / nil;",
    "add": "print 1 + nil;",
    "negate": "print -nil;",
    "inherit": "var Parent = 1; class Child < Parent {}",
    "call_value": "var a = 1; a();",
    "call_arity": "fun a(x) {} a();",
    "invoke_value": "var a = 1; a.method();",
    "invoke_missing": "class A {} A().missing();",
    "invoke_arity": "class A { method(x) {} } A().method();",
    "init_arity": "class A { init(x) {} } A();",
    "get_super": "class A {} class B < A { method() { return super.missing; } } B().method();",
    "invoke_super": "class A {} class B < A { method() { super.missing(); } } B().method();",
    "invoke_super_arity": "class A { method(x) {} } class B < A { other() { super.method(); } } B().other();",
    "stack_overflow": "fun recurse() { recurse(); } recurse();",
}


def observe(binary: Path, source: Path, stress: bool) -> dict:
    command = [str(binary), "--engine=vm"]
    if stress:
        command.append("--gc-stress")
    result = subprocess.run(
        command + [str(source)], capture_output=True, timeout=60, check=False
    )
    return {
        "exit": result.returncode,
        "stdout": result.stdout.decode(),
        "stderr": result.stderr.decode(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    reference, candidate, work = (
        args.reference.resolve(), args.candidate.resolve(), args.work.resolve()
    )
    work.mkdir(parents=True, exist_ok=True)
    evidence = {
        "reference_sha256": hashlib.sha256(reference.read_bytes()).hexdigest(),
        "candidate_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
        "runtime_options": os.environ.get("MYLANG_OPTIONS", ""),
        "cases": [],
    }
    for name, body in CASES.items():
        source = work / f"{name}.lox"
        # Harmless instructions/jumps precede each failure; both a caller's
        # post-call IP and the active instruction's IP must remain accurate.
        source.write_text(
            "fun failure() {\n"
            "  var i = 0; while (i < 3) { i = i + 1; }\n"
            f"  {body}\n"
            "}\nfun caller() { failure(); }\ncaller();\n"
        )
        for stress in (False, True):
            expected = observe(reference, source, stress)
            actual = observe(candidate, source, stress)
            passed = (
                expected["exit"] == 70
                and "[line " in expected["stderr"]
                and actual == expected
            )
            evidence["cases"].append(
                {
                    "name": name,
                    "lox_gc_stress": stress,
                    "source": source.read_text(),
                    "expected": expected,
                    "actual": actual,
                    "passed": passed,
                }
            )
    (work / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    failures = [row for row in evidence["cases"] if not row["passed"]]
    for row in failures:
        print(json.dumps(row, indent=2))
    total = len(evidence["cases"])
    print(f"{total - len(failures)}/{total} VM error traces match")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
