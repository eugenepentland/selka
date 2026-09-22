#!/usr/bin/env python3
"""Delete derived-effect clause diagnostics from Zig test fixtures.

Zig tests embed guest sources as runs of `\\\\`-prefixed lines. Item 2 makes three
diagnostics reachable in those fixtures:

  E_DERIVED_EFFECTS  a clause names an effect no parameter supplies
  W_DERIVED_EFFECTS  a clause restates the ceiling its parameters imply
  E_UNUSED_CAPABILITY  a capability parameter the body never reads

This rewrites the fixture text the compiler points at: the clause is deleted, and
the fixture is checked again until it is clean. Fixtures that need a *new*
parameter or call-site argument are reported instead of guessed at.

Usage: python3 scripts/migrate_zig_fixtures.py --compiler PATH [--apply] FILE.zig ...
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIAGNOSTIC = re.compile(r"^(.+?\.my):(\d+):(\d+): (error|warning)\[(\w+)\]: (.*)$")
CLAUSE = re.compile(r"[ \t]*effects\s*\([^)]*\)|[ \t]*\bnoalloc\b|[ \t]*\bnoio\b")


def fixture_runs(lines: list[str]):
    """Each maximal run of `\\\\`-prefixed lines as (start, end, prefix) indices."""
    runs = []
    index = 0
    while index < len(lines):
        match = re.match(r"^([ \t]*)\\\\", lines[index])
        if not match:
            index += 1
            continue
        start = index
        while index < len(lines) and re.match(r"^([ \t]*)\\\\", lines[index]):
            index += 1
        runs.append((start, index))
    return runs


def run_text(lines: list[str], start: int, end: int) -> str:
    parts = []
    for line in lines[start:end]:
        at = line.index("\\\\")
        parts.append(line[at + 2 :])
    return "\n".join(parts)


def write_run(lines: list[str], start: int, end: int, text: str) -> list[str]:
    parts = text.split("\n")
    if len(parts) != end - start:
        return lines
    replacement = [line[: line.index("\\\\")] + "\\\\" + part for line, part in zip(lines[start:end], parts)]
    return lines[:start] + replacement + lines[end:]


def check(compiler: Path, text: str, work: Path):
    """Check one fixture text. Returned lines are fixture-relative (1-based)."""
    path = work / "fixture.my"
    has_main = "\ndef main(" in text or text.startswith("def main(")
    body = text if has_main else text + "\n\ndef main() -> int:\n    return 0\n"
    path.write_text("module fixture\n" + body, encoding="utf-8")
    result = subprocess.run([str(compiler), "check", str(path)], capture_output=True, text=True, cwd=work, timeout=600)
    found = []
    for line in result.stderr.splitlines():
        match = DIAGNOSTIC.match(line.strip())
        if not match:
            continue
        found.append((int(match.group(2)) - 1, int(match.group(3)), match.group(5), match.group(6)))
    return found


def offset(text: str, line: int, column: int) -> int:
    return sum(len(part) + 1 for part in text.split("\n")[: line - 1]) + column - 1


DECLARE = re.compile(r"declare `([^`]+)`")
CALL_PASTE = re.compile(r"write `(\([^`]*\))`")


def apply_marker(text: str, at: int, message: str):
    """Apply one `E_MUTATION_MARKER` paste at `at`. Returns the new text or None."""
    declared = DECLARE.search(message)
    if declared:
        replacement = declared.group(1)
        name = replacement.split(":", 1)[0].strip()
        start = text.rfind(name + ":", 0, at)
        if start < 0:
            return None
        end = text.find(",", start)
        close = text.find(")", start)
        if end < 0 or (close >= 0 and close < end):
            end = close
        if end < 0:
            end = len(text)
        return text[:start] + replacement + text[end:]
    call = CALL_PASTE.search(message)
    if call and text[at] == "(":
        end = match_close(text, at)
        if end < 0:
            return None
        return text[:at] + call.group(1) + text[end + 1 :]
    return None


def clean_run(compiler: Path, text: str, work: Path, report: list):
    """Apply the compiler's own pastes to one fixture. Returns the new text."""
    for _ in range(12):
        diagnostics = check(compiler, text, work)
        fixable = [
            (l, c, code, message)
            for l, c, code, message in diagnostics
            if code in ("E_DERIVED_EFFECTS", "W_DERIVED_EFFECTS") or (code == "E_MUTATION_MARKER" and ("declare `" in message or "write `(" in message))
        ]
        if not fixable:
            return text, diagnostics
        before = text
        for line, column, code, message in sorted(fixable, reverse=True):
            at = offset(text, line, column)
            if code in ("E_DERIVED_EFFECTS", "W_DERIVED_EFFECTS"):
                match = CLAUSE.match(text, at)
                if not match:
                    continue
                text = text[:at] + text[match.end() :]
                continue
            updated = apply_marker(text, at, message)
            if updated is not None:
                text = updated
        if text == before:
            return text, diagnostics
    return text, check(compiler, text, work)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("files", nargs="+")
    arguments = parser.parse_args(argv[1:])
    work = Path.home() / ".cache" / "mylang" / "fixture-migration"
    work.mkdir(parents=True, exist_ok=True)
    for name in arguments.files:
        path = Path(name)
        lines = path.read_text(encoding="utf-8").split("\n")
        edits = 0
        leftover = []
        for start, end in reversed(fixture_runs(lines)):
            text = run_text(lines, start, end)
            cleaned, diagnostics = clean_run(arguments.compiler, text, work, leftover)
            for line, column, code, message in diagnostics:
                leftover.append(f"{path}:{start + line}: {code}: {message}")
            if cleaned == text:
                continue
            edits += 1
            if arguments.apply:
                lines = write_run(lines, start, end, cleaned)
        print(f"{path}: {edits} fixture(s) cleaned")
        if arguments.apply and edits:
            path.write_text("\n".join(lines), encoding="utf-8")
        for item in leftover:
            print(f"  leftover: {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
