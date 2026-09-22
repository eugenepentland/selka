#!/usr/bin/env python3
"""Migrate module files that have no entry point of their own.

`mylang check src/stdlib/json.my` stops at `E_MAIN`, so a module's own mutation
errors are never reported. This copies each module into a scratch project beside a
generated `main.my` that imports it, runs the real checker there, and writes the
requested `mut` edits back into the original module. A module the scratch entry
cannot import (it needs a capability, or imports a neighbour) is skipped and
reported.

Usage: python3 scripts/fix_mut_modules.py [--compiler PATH] FILE.my [...]
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_COMPILER = str(Path(__file__).resolve().parent.parent / "zig-out/bin/mylang")
SCRATCH = ".mylang-mut-modules"
ENTRY = "module main\nimport %s\n\n\ndef main() -> int:\n    return 0\n"


def check(compiler, directory, module):
    """Diagnostics one scratch project reports for the imported module."""
    result = subprocess.run([compiler, "check", "--diagnostics=json", "main.my"], cwd=directory, capture_output=True, text=True)
    found = []
    for line in result.stdout.splitlines() + result.stderr.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            found.append(json.loads(line)["diagnostic"])
        except (KeyError, ValueError):
            continue
    return found


def edits_for(diagnostic):
    """What one marker message asks for, or None."""
    message = diagnostic["message"]
    if "; remove `mut`: `" in message:
        return "undeclare"
    if "remove `mut`" in message:
        return "unmark"
    if "; write `" in message and "(mut " in message:
        return "mark"
    if "reachable from the caller; declare " in message:
        return "declare"
    return None


def offset_of(text, line, column):
    """Byte offset of a one-based line and column in `text`."""
    at = 0
    for _ in range(line - 1):
        newline = text.find(b"\n", at)
        if newline < 0:
            return None
        at = newline + 1
    end = text.find(b"\n", at)
    if end < 0:
        end = len(text)
    target = at + column - 1
    return target if target <= end else None


def paste_names(message):
    """The `name: mut T` fragments one declaration message asks for."""
    paste = message.split("reachable from the caller; declare ", 1)[1].strip().strip("`")
    found = []
    for fragment in paste.split("`, `"):
        name, separator, declared = fragment.partition(": mut ")
        if separator and declared:
            found.append(name.strip())
    return found


def parameter_list(text, at):
    """The `(start, end)` of the parameter list whose `(` follows offset `at`."""
    open_at = text.find(b"(", at, at + 200)
    if open_at < 0:
        return None
    depth = 0
    for index in range(open_at, min(len(text), open_at + 1024)):
        if text[index : index + 1] == b"(":
            depth += 1
        elif text[index : index + 1] == b")":
            depth -= 1
            if depth == 0:
                return (open_at, index)
    return None


def argument_offset(text, at, message):
    """Where `mut ` belongs inside the callee's first argument.

    The reported column points at the callee for a nested call and at the
    argument for a direct one, so the argument is found by parsing the call: the
    message names the callee, its `(` follows on the same line, and the first
    argument starts at the first non-space byte after it.
    """
    callee = message.split("` writes `", 1)[0].lstrip("`")
    line_start = text.rfind(b"\n", 0, at) + 1
    line_end = text.find(b"\n", at)
    line_end = len(text) if line_end < 0 else line_end
    if text[line_start:line_end].find(callee.encode()) < 0:
        return at
    call = text.rfind(callee.encode(), line_start, at + len(callee))
    open_at = text.find(b"(", call, line_end)
    if open_at < 0:
        return at
    start = open_at + 1
    while start < line_end and text[start : start + 1] == b" ":
        start += 1
    return min(start, line_end)


def apply(path, requests):
    """Apply one module's collected edits, bottom-up so offsets stay valid."""
    with open(path, "rb") as handle:
        original = handle.read()
    text = original
    added = 0
    for kind, at, message in sorted(requests, key=lambda entry: entry[1], reverse=True):
        if kind == "mark":
            at = argument_offset(text, at, message)
            if text[at : at + 4] == b"mut ":
                continue
            text = text[:at] + b"mut " + text[at:]
            added += 1
            continue
        if kind == "unmark":
            if text[at : at + 4] == b"mut ":
                text = text[:at] + text[at + 4 :]
                added += 1
            continue
        head = text.rfind(b"def ", 0, at)
        if head < 0:
            continue
        bounds = parameter_list(text, head)
        if bounds is None:
            continue
        start, end = bounds
        if kind == "declare":
            for name in paste_names(message):
                token = name.encode()
                found = text.find(token, start, end)
                if found < 0:
                    continue
                colon = text.find(b":", found + len(token), end)
                if colon < 0 or text[colon + 1 : colon + 6] == b" mut ":
                    continue
                text = text[: colon + 1] + b" mut " + text[colon + 2 :]
                end += 4
                added += 1
            continue
        marker = text.rfind(b"mut ", start, at + 1)
        if marker < 0:
            continue
        text = text[:marker] + text[marker + 4 :]
        added += 1
    if text != original:
        with open(path, "wb") as handle:
            handle.write(text)
    return added


def migrate(path, compiler, scratch, rounds=10):
    """Migrate one module through a scratch project it owns.

    The edits are applied to the scratch copy the diagnostics describe -- never to
    the original -- so a round can only move a position the compiler has just
    reported. The scratch copy is copied back once it checks clean.
    """
    module = Path(path).stem
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir()
    target = scratch / f"{module}.my"
    shutil.copy(path, target)
    (scratch / "main.my").write_text(ENTRY % module)
    total = 0
    for _ in range(rounds):
        with open(target, "rb") as handle:
            text = handle.read()
        requests = []
        for diagnostic in check(compiler, scratch, module):
            if diagnostic["code"] != "E_MUTATION_MARKER":
                continue
            kind = edits_for(diagnostic)
            if kind is None:
                continue
            start_at = diagnostic["location"]["start"]
            at = offset_of(text, start_at["line"], start_at["column"])
            if at is None:
                continue
            requests.append((kind, at, diagnostic["message"]))
        if not requests:
            break
        count = apply(target, requests)
        if count == 0:
            break
        total += count
    shutil.copy(target, path)
    return total


def main(argv):
    compiler = DEFAULT_COMPILER
    paths = []
    index = 1
    while index < len(argv):
        if argv[index] == "--compiler":
            index += 1
            compiler = argv[index]
        else:
            paths.append(argv[index])
        index += 1
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    total = 0
    for path in paths:
        count = migrate(path, compiler, Path(SCRATCH))
        if count:
            print(f"{path}: {count} edit(s)")
        total += count
    print(f"{total} edit(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
