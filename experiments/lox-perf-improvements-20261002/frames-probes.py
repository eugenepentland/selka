#!/usr/bin/env python3
"""Check suspended Lox frames against an unchanged port on both engines.

Native GC stress requires both binaries to have been built with --gc-runtime.
Lox collector stress is always tested independently of native stress.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


PROBES = {
    "native_and_empty_constructor": (
        "class Empty {} fun f() { var x = 11; clock(); Empty(); clock(); "
        "return x + 2; } print f(); print f();",
        "13\n13\n",
    ),
    "different_closure_upvalues": (
        "fun make(n) { fun get() { return n; } return get; } "
        "var a = make(7); var b = make(19); "
        "fun combine() { var x = a(); var y = b(); return x + y + a(); } "
        "print combine(); print combine();",
        "33\n33\n",
    ),
    "closed_upvalue_after_return": (
        "fun outer() { var n = 40; fun bump() { n = n + 1; return n; } "
        "bump(); return bump; } var f = outer(); print f(); print f();",
        "42\n43\n",
    ),
    "suspended_open_upvalue": (
        "fun outer() { var n = 10; fun change() { n = n + 3; } "
        "fun nested() { change(); change(); } nested(); print n; "
        "change(); return n; } print outer();",
        "16\n19\n",
    ),
    "replace_running_closure_root": (
        "var f; fun churn() { f = nil; var i = 0; "
        "while (i < 50) { class T {} T(); i = i + 1; } } "
        "fun make(n) { fun running() { churn(); return n + 5; } "
        "return running; } f = make(37); print f();",
        "42\n",
    ),
    "bound_method_and_super": (
        "class A { init(n) { this.n = n; } read() { return this.n; } } "
        "class B < A { read() { var f = super.read; "
        "return f() + super.read(); } } var b = B(21); "
        "fun invoke(f) { return f(); } print invoke(b.read);",
        "42\n",
    ),
    "reuse_frame_slots_after_deep_return": (
        "fun depth(n) { if (n == 0) return 1; return depth(n - 1) + 1; } "
        "print depth(60); print depth(60); print depth(3);",
        "61\n61\n4\n",
    ),
    "receiver_mutation_across_call": (
        "class Box { init(n) { this.n = n; } "
        "change() { this.n = this.n + 10; return 2; } "
        "read() { return this.n; } } var b = Box(1); "
        "fun test() { b.n = b.change() + b.read(); return b.read(); } "
        "print test(); print test();",
        "13\n25\n",
    ),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("--native-gc-stress", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    env = {key: val for key, val in os.environ.items() if not key.startswith("MYLANG_")}
    if args.native_gc_stress:
        env["MYLANG_OPTIONS"] = "--gc-stress"
    binaries = {"reference": args.reference.resolve(), "candidate": args.candidate.resolve()}
    evidence = {
        "binary_sha256": {arm: digest(path) for arm, path in binaries.items()},
        "native_gc_stress": args.native_gc_stress,
        "runs": [],
    }
    for name, (program, expected) in PROBES.items():
        source = work / f"{name}.lox"
        source.write_text(program + "\n")
        for engine in ("vm", "tree"):
            for lox_stress in (False, True):
                for arm, binary in binaries.items():
                    command = [str(binary), f"--engine={engine}"]
                    if lox_stress:
                        command.append("--gc-stress")
                    command.append(str(source))
                    result = subprocess.run(command, env=env, capture_output=True, timeout=60)
                    passed = result.returncode == 0 and result.stdout == expected.encode() and not result.stderr
                    evidence["runs"].append({
                        "case": name, "engine": engine, "arm": arm,
                        "lox_gc_stress": lox_stress, "command": command,
                        "source_sha256": digest(source), "source": program,
                        "status": result.returncode, "stdout": result.stdout.decode(),
                        "stderr": result.stderr.decode(), "expected": expected,
                        "passed": passed,
                    })
                    (work / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    assert evidence["binary_sha256"] == {arm: digest(path) for arm, path in binaries.items()}
    failures = [row for row in evidence["runs"] if not row["passed"]]
    for row in failures:
        print(json.dumps(row, indent=2))
    total = len(evidence["runs"])
    print(f"{total - len(failures)}/{total} suspended-frame runs passed")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
