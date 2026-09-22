#!/usr/bin/env python3
"""Add the `mut` call-site markers the compiler asks for.

The checker's `E_MUTATION_MARKER` message for a missing marker carries the paste
("`f` writes `x`; write `f(mut x)`") and the diagnostic's byte span is exactly the
argument expression, so the fix is one insertion per diagnostic. The compiler is
re-run after each round because adding a marker can expose the next one.

Usage: python3 scripts/fix_mut_markers.py [--compiler PATH] FILE.my [FILE.my ...]
"""

import json
import subprocess
import sys

DEFAULT_COMPILER = "zig-out/bin/mylang"


def diagnostics(compiler, path):
    """Every `E_MUTATION_MARKER` diagnostic the compiler reports for one file."""
    result = subprocess.run(
        [compiler, "check", "--diagnostics=json", path],
        capture_output=True,
        text=True,
    )
    found = []
    for line in result.stdout.splitlines() + result.stderr.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            diagnostic = json.loads(line)["diagnostic"]
        except (KeyError, ValueError):
            continue
        if diagnostic["code"] != "E_MUTATION_MARKER":
            continue
        span = diagnostic["location"].get("bytes")
        if span is None:
            continue
        found.append((span["start"], diagnostic["message"]))
    return found


def missing_marker(message):
    """Whether one message asks for a marker on an argument."""
    return "; write `" in message and "(mut " in message


def fix(path, compiler, rounds=8):
    """Insert every requested marker, re-checking after each round."""
    added = 0
    for _ in range(rounds):
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        wanted = sorted({entry for entry in diagnostics(compiler, path) if missing_marker(entry[1])}, key=lambda entry: entry[0])
        if not wanted:
            break
        for start, _ in reversed(wanted):
            if text[max(0, start - 4) : start] == "mut ":
                continue
            text = text[:start] + "mut " + text[start:]
            added += 1
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
    return added


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
        added = fix(path, compiler)
        if added:
            print(f"{path}: {added} marker(s)")
        total += added
    print(f"{total} marker(s) added")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
