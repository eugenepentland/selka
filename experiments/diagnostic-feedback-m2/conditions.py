#!/usr/bin/env python3
"""The four treatments, as a compiler wrapper that also measures the invocation.

Canonical data first: the wrapper parses the compiler's stderr into diagnostic
records (code, message, path, line, column, snippet, notes) and computes a
semantic identity for each. Only then does it render — so `text`, `text_fix`,
`json` and `json_fix` differ in presentation alone, and the event log is identical
across arms. The suggestion is implemented once and rendered twice.

The wrapper also enforces the invocation limit and records source stability, so a
measurement never has to be reconstructed from a transcript afterwards.

    python3 experiments/diagnostic-feedback/conditions.py --show json_fix
    python3 experiments/diagnostic-feedback/conditions.py --list
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
COMPILER = REPO / "experiments" / "cascade" / "tools" / "bin" / "mylang"
CONDITIONS = ("text", "text_fix", "json", "json_fix")
REMEDY_ARMS = ("text_fix", "json_fix")
JSON_ARMS = ("json", "json_fix")

# Authored on the development cases only. Keyed by diagnostic code, then by a
# substring of the message where one code covers more than one situation.
REMEDIES: dict[str, list[tuple[str, str]]] = {
    "E_TYPE": [
        ("expected int, found bool",
         "mylang does not treat a boolean as an integer. Convert explicitly, for example "
         "`return 1 if condition else 0`, or declare the function `-> bool` if it returns a truth value."),
        ("found Result[",
         "the call returns a `Result`; unwrap it (`match parse(...): case Ok(value): ... "
         "case Err(problem): ...`) or propagate it with `?` from a function that itself returns a "
         "compatible `Result`."),
    ],
    "E_MODULE_NAME": [
        ("", "the `module` header must equal the file's path from the project root: a file "
             "`helper.my` at the root declares `module helper`."),
    ],
    "E_MODULE_READ": [
        ("", "imports are resolved from the project root: a module in `helper.my` at the root is "
             "`import helper as helper`, not through a folder that does not exist."),
    ],
    "E_OUTPUT_CAPABILITY": [
        ("", "printing goes through a stream: add `out: Stream` to this function, declare "
             "`effects(output)` on it, and pass `main`'s `out` at the call site."),
    ],
    "E_INCOMPLETE_MATCH": [
        ("", "add the arm the message names and bind its payload, for example "
             "`case Shape.square(side): return side * side`."),
    ],
    "E_UNKNOWN_NAME": [
        ("", "the name is not defined anywhere in scope. Assign it before the point of use, or "
             "correct the spelling to an existing binding."),
    ],
    "E_GENERIC_REQUIREMENT": [
        ("", "`Ordered` is not a requirement this compiler knows. Use one of `copy`, `equality`, "
             "`integer`, `codec`, `storable`, or declare a `constraint` naming the operations you need."),
    ],
}

WRAPPER = '''#!/usr/bin/env python3
"""Generated compiler wrapper: treatment {condition!r}, event logging, limits."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

sys.path.insert(0, {coordinator!r})
import events  # the coordinator's schema, parser and identity function

REAL = {compiler!r}
CONDITION = {condition!r}
JSON_ARMS = {json_arms!r}
REMEDY_ARMS = {remedy_arms!r}
REMEDIES = {remedies!r}


def remedy_for(code, message):
    for needle, remedy in REMEDIES.get(code, []):
        if needle in message:
            return remedy
    return None


def render(diagnostics, raw):
    if CONDITION == "text" or not diagnostics:
        return raw
    suggestions = {{}}
    for diagnostic in diagnostics:
        suggestions[id(diagnostic)] = remedy_for(diagnostic["code"], diagnostic["message"]) \\
            if CONDITION in REMEDY_ARMS else None
    if CONDITION in JSON_ARMS:
        payload = {{"version": "diagnostics-v1", "count": len(diagnostics), "diagnostics": []}}
        for diagnostic in diagnostics:
            rendered = {{key: diagnostic[key] for key in
                        ("code", "message", "path", "line", "column", "snippet", "notes")}}
            if suggestions[id(diagnostic)]:
                rendered["suggested_fix"] = suggestions[id(diagnostic)]
            payload["diagnostics"].append(rendered)
        return json.dumps(payload, indent=2) + "\\n"
    lines = [raw.rstrip("\\n")]
    for diagnostic in diagnostics:
        if suggestions[id(diagnostic)]:
            lines.append(f"{{diagnostic['path']}}:{{diagnostic['line']}}:{{diagnostic['column']}}: "
                         f"note: {{suggestions[id(diagnostic)]}}")
    return "\\n".join(lines) + "\\n"


def main():
    log_path = os.environ.get("MYLANG_EVENT_LOG", "")
    project = os.environ.get("MYLANG_PROJECT", "project")
    limit = int(os.environ.get("MYLANG_LIMIT", "0") or 0)
    cohort = os.environ.get("MYLANG_COHORT", "")
    attempt = os.environ.get("MYLANG_ATTEMPT", "")
    initial = os.environ.get("MYLANG_INITIAL_HASH", "")
    argv = sys.argv[1:]
    command = argv[0] if argv else ""

    written = 0
    if log_path and os.path.isfile(log_path):
        with open(log_path) as handle:
            written = sum(1 for line in handle if line.strip())
    invocation = uuid.uuid4().hex
    if limit and written >= limit:
        event = {{"schema": events.SCHEMA, "cohort_id": cohort, "attempt_id": attempt,
                  "invocation_id": invocation, "command": command, "argv": argv,
                  "cwd": os.getcwd(), "source_sha256": events.inventory(Path(project))[0],
                  "compiler_sha256": {compiler_hash!r}, "started_monotonic_ns": time.monotonic_ns(),
                  "finished_monotonic_ns": time.monotonic_ns(), "exit_code": 66,
                  "outcome": "limit_reached", "diagnostic_codes": [],
                  "diagnostic_identities": [], "source_stable": True,
                  "initial_source_sha256": initial, "stdout_sha256": "", "stderr_sha256": ""}}
        if log_path:
            _append(log_path, event)
        sys.stderr.write("mylang: invocation limit reached for this attempt\\n")
        sys.exit(66)

    before = events.inventory(Path(project))[0] if os.path.isdir(project) else ""
    started = time.monotonic_ns()
    completed = subprocess.run([REAL] + argv, capture_output=True)
    finished = time.monotonic_ns()
    after = events.inventory(Path(project))[0] if os.path.isdir(project) else ""

    stderr = completed.stderr.decode(errors="replace")
    diagnostics = events.parse_diagnostics(stderr)
    outcome = events.classify(completed.returncode, stderr, diagnostics, command)
    event = {{"schema": events.SCHEMA, "cohort_id": cohort, "attempt_id": attempt,
              "invocation_id": invocation, "command": command, "argv": argv, "cwd": os.getcwd(),
              "source_sha256": before, "compiler_sha256": {compiler_hash!r},
              "started_monotonic_ns": started, "finished_monotonic_ns": finished,
              "exit_code": completed.returncode, "outcome": outcome,
              "diagnostic_codes": [diagnostic["code"] for diagnostic in diagnostics],
              "diagnostic_identities": [events.identity(diagnostic) for diagnostic in diagnostics],
              "source_stable": before == after, "initial_source_sha256": initial,
              "stdout_sha256": hashlib.sha256(completed.stdout).hexdigest(),
              "stderr_sha256": hashlib.sha256(completed.stderr).hexdigest()}}
    if log_path:
        _append(log_path, event)

    sys.stdout.buffer.write(completed.stdout)
    sys.stdout.flush()
    sys.stderr.write(render(diagnostics, stderr))
    sys.exit(completed.returncode)


def _append(path, event):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as handle:
        handle.write(json.dumps(event) + "\\n")
        handle.flush()
        os.fsync(handle.fileno())


if __name__ == "__main__":
    main()
'''


def wrapper_source(condition: str, compiler: Path | None = None) -> str:
    """The wrapper for one arm; `compiler` exists so tests can substitute a fake."""
    if condition not in CONDITIONS:
        raise SystemExit(f"unknown condition {condition!r}; expected one of {', '.join(CONDITIONS)}")
    remedies = REMEDIES if condition in REMEDY_ARMS else {}
    target = COMPILER if compiler is None else compiler
    return WRAPPER.format(condition=condition, compiler=str(target), coordinator=str(HERE),
                          compiler_hash=hashlib.sha256(target.read_bytes()).hexdigest(),
                          remedies=remedies, json_arms=JSON_ARMS, remedy_arms=REMEDY_ARMS)


def install(bin_directory: Path, condition: str, compiler: Path | None = None) -> Path:
    bin_directory.mkdir(parents=True, exist_ok=True)
    path = bin_directory / "mylang"
    path.write_text(wrapper_source(condition, compiler))
    path.chmod(0o755)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--show", choices=CONDITIONS, help="print the wrapper for one condition")
    parser.add_argument("--list", action="store_true", help="list the conditions")
    args = parser.parse_args()
    if args.list:
        print("\n".join(CONDITIONS))
    if args.show:
        print(wrapper_source(args.show))
    return 0


if __name__ == "__main__":
    sys.exit(main())
